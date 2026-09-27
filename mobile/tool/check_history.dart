import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:happy_mountain_mobile/data/warning_history_repository.dart';
import 'package:happy_mountain_mobile/data/warning_cache_io.dart';
import 'package:happy_mountain_mobile/domain/contracts.dart';

/// Explicit, online smoke check. Unit tests never depend on the live portal.
Future<void> main() async {
  final client = http.Client();
  final cache = FileWarningCache(Directory('.dart_tool/history-smoke'));
  try {
    final repository = PublicWarningHistoryRepository(
      client: client,
      cache: cache,
    );
    final dataset = await repository.load(forceRefresh: true);
    if (dataset.isStale) throw StateError(dataset.refreshWarning!);
    final filter = HistoryFilter.latestTwoMonths(dataset.latestDate);
    final offlineClient = MockClient(
      (_) => throw StateError('Cached read must not use network'),
    );
    final cached = await PublicWarningHistoryRepository(
      client: offlineClient,
      cache: cache,
    ).load();
    offlineClient.close();
    if (cached.isStale) throw StateError(cached.refreshWarning!);
    if (cached.records.length != dataset.records.length) {
      throw StateError('Cache read differs from the fetched dataset');
    }
    stdout.writeln(
      'records=${dataset.records.length}; skipped=${dataset.skippedRows}',
    );
    stdout.writeln(
      'latest=${dataset.latestDate.toIso8601String().substring(0, 10)}',
    );
    stdout.writeln(
      'defaultRange=${filter.startDate.toIso8601String().substring(0, 10)}..${filter.endDate.toIso8601String().substring(0, 10)}',
    );
    stdout.writeln(
      'filtered=${filter.apply(dataset.records).length}; regions=${dataset.regions.length}',
    );
    stdout.writeln(
      'HTTPS discovery, decoding, parsing and file-cache write: OK',
    );
  } finally {
    client.close();
  }
}
