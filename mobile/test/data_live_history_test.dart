import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:happy_mountain_mobile/data/warning_history_repository.dart';
import 'package:happy_mountain_mobile/domain/contracts.dart';

class _TemporaryCache implements WarningCache {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    value = data;
  }
}

void main() {
  test(
    'official metadata and live CP949 archive parse successfully',
    () async {
      final client = http.Client();
      addTearDown(client.close);
      final repository = PublicWarningHistoryRepository(
        client: client,
        cache: _TemporaryCache(),
      );
      final dataset = await repository.load();
      expect(dataset.records, isNotEmpty);
      expect(dataset.isStale, isFalse);
      expect(dataset.modifiedAt, isNotNull);
      final filtered = HistoryFilter.latestTwoMonths(dataset.latestDate)
          .apply(dataset.records);
      expect(filtered, isNotEmpty);
      // Useful evidence when deliberately running against the changing public source.
      // ignore: avoid_print
      print(
        'Official archive: records=${dataset.records.length}, latest=${dataset.latestDate.toIso8601String()}, modified=${dataset.modifiedAt}, skipped=${dataset.skippedRows}, two-month records=${filtered.length}',
      );
    },
    skip: !const bool.fromEnvironment('LIVE_DATA_CHECK'),
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
