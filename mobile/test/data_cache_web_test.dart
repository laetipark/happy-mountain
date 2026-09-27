@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:happy_mountain_mobile/data/warning_cache.dart'
    show createWarningCache;
import 'package:happy_mountain_mobile/data/warning_cache_web.dart'
    show IndexedDbWarningCache;

void main() {
  test('IndexedDB persists a large snapshot across cache instances and replaces it', () async {
    final name = 'happy-mountain-test-${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() async {
      final completion = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => completion.complete()).toJS;
      request.onerror = ((web.Event _) => completion.completeError(
        StateError('cleanup failed'),
      )).toJS;
      await completion.future;
    });
    final cache = IndexedDbWarningCache(databaseName: name);
    expect(await cache.read(), isNull);
    final archive = '경보 이력\n' * 900000;
    await cache.write(archive);
    expect(await IndexedDbWarningCache(databaseName: name).read(), archive);
    await cache.write('updated');
    expect(await IndexedDbWarningCache(databaseName: name).read(), 'updated');
  });

  test('web cache factory starts without accessing filesystem APIs', () async {
    expect(await createWarningCache(), isA<IndexedDbWarningCache>());
  });
}
