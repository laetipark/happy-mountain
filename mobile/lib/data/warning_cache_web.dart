import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'warning_cache_contract.dart';

Future<WarningCache> createWarningCache() async => IndexedDbWarningCache();

/// IndexedDB handles the full archive without localStorage's small string quota.
/// Storage is lazy so denied/private storage never prevents application startup.
class IndexedDbWarningCache implements WarningCache {
  IndexedDbWarningCache({this.databaseName = 'happy-mountain-history-v1'});
  final String databaseName;
  static const _store = 'snapshots';
  static const _key = 'latest';
  static const _timeout = Duration(seconds: 5);

  Future<web.IDBDatabase> _open() {
    final result = Completer<web.IDBDatabase>();
    final timer = Timer(_timeout, () {
      if (!result.isCompleted) {
        result.completeError(TimeoutException('History storage unavailable'));
      }
    });
    try {
      final request = web.window.indexedDB.open(databaseName, 1);
      request.onupgradeneeded = ((web.Event _) {
        final database = request.result as web.IDBDatabase;
        if (!database.objectStoreNames.contains(_store)) {
          database.createObjectStore(_store);
        }
      }).toJS;
      request.onsuccess = ((web.Event _) {
        timer.cancel();
        final database = request.result as web.IDBDatabase;
        if (result.isCompleted) {
          database.close();
        } else {
          result.complete(database);
        }
      }).toJS;
      void fail(web.Event _) {
        timer.cancel();
        if (!result.isCompleted) {
          result.completeError(StateError('History storage unavailable'));
        }
      }

      request.onerror = fail.toJS;
      request.onblocked = fail.toJS;
    } catch (_) {
      timer.cancel();
      result.completeError(StateError('History storage unavailable'));
    }
    return result.future;
  }

  @override
  Future<String?> read() async {
    final database = await _open();
    try {
      final result = Completer<String?>();
      final transaction = database.transaction(_store.toJS, 'readonly');
      final request = transaction.objectStore(_store).get(_key.toJS);
      request.onsuccess = ((web.Event _) {
        if (!result.isCompleted) {
          final value = request.result;
          result.complete(
            value.isA<JSString>() ? (value as JSString).toDart : null,
          );
        }
      }).toJS;
      void fail(web.Event _) {
        if (!result.isCompleted) {
          result.completeError(StateError('History cache read failed'));
        }
      }

      request.onerror = fail.toJS;
      transaction.onabort = fail.toJS;
      return await result.future.timeout(_timeout);
    } finally {
      database.close();
    }
  }

  @override
  Future<void> write(String value) async {
    final database = await _open();
    try {
      final result = Completer<void>();
      final transaction = database.transaction(_store.toJS, 'readwrite');
      transaction.oncomplete = ((web.Event _) {
        if (!result.isCompleted) result.complete();
      }).toJS;
      void fail(web.Event _) {
        if (!result.isCompleted) {
          result.completeError(StateError('History cache write failed'));
        }
      }

      transaction.onerror = fail.toJS;
      transaction.onabort = fail.toJS;
      transaction.objectStore(_store).put(value.toJS, _key.toJS);
      await result.future.timeout(_timeout);
    } finally {
      database.close();
    }
  }
}
