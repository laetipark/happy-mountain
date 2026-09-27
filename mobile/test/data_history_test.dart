import 'dart:convert';
import 'dart:typed_data';

import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:happy_mountain_mobile/data/warning_history_repository.dart';
import 'package:happy_mountain_mobile/domain/contracts.dart';

const sampleCsv =
    '예보일시,시도명,시군구명,읍면동명,실효습도,풍속,등급\r\n2026-06-11 15:00,강원도,인제군,북면,34.6,7.3,주의보\r\n2026-04-11 12:00,강원,인제군,북면,31.2,12.3,경보\r\n2026-04-10 12:00,서울,중구,명동,32,8,주의보\r\n';
String metadata({String url = 'https://www.data.go.kr/download.csv'}) =>
    '<script type="application/ld+json">${jsonEncode({
      '@type': 'Dataset',
      'dateModified': '2026-09-03',
      'distribution': [
        {'encodingFormat': 'CSV', 'contentUrl': url},
      ],
    })}</script>';

class MemoryCache implements WarningCache {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async {
    if (failWrite) throw StateError('disk full');
    value = text;
  }
}

void main() {
  test('CP949 decodes Korean, parses timestamp and newest-first ordering', () {
    final parsed = parseWarningBytes(cp949.encode(sampleCsv));
    expect(parsed.records.length, 3);
    expect(parsed.records.first.region, '강원도');
    expect(parsed.records.first.canonicalRegion, '강원특별자치도');
    expect(parsed.records.first.date, DateTime.utc(2026, 6, 11));
    expect(parsed.records.first.effectiveHumidity, 34.6);
  });
  test('header names drive reordered CSV with quoted comma, quote and newline', () {
    const text =
        '등급,풍속,예보일시,시군구명,시도명,실효습도,읍면동명\n주의보,7.3,20260611150000,"인제,군",알수없는도,34,"북""면\n마을"\n';
    final parsed = parseWarningBytes(Uint8List.fromList(utf8.encode(text)));
    expect(parsed.records.single.district, '인제,군');
    expect(parsed.records.single.town, '북"면\n마을');
    expect(parsed.records.single.canonicalRegion, '알수없는도');
  });
  test('invalid calendar dates and wrong row width skipped, missing header rejected', () {
    final parsed = parseWarningBytes(
      cp949.encode(
        '${sampleCsv}2026-02-30 10:00,강원도,인제군,북면,34,7,주의보\nnot,a,row\n',
      ),
    );
    expect(parsed.skippedRows, 2);
    expect(parsed.records.length, 3);
    expect(
      () => parseWarningBytes(
        Uint8List.fromList(utf8.encode('wrong,headers\n1,2')),
      ),
      throwsA(isA<DataException>()),
    );
    expect(() => parseCsv('"unterminated'), throwsA(isA<DataException>()));
  });
  test(
    'calendar two-month filter includes both boundaries and clamps short month',
    () {
      final records = parseWarningBytes(cp949.encode(sampleCsv)).records;
      final filter = HistoryFilter.latestTwoMonths(DateTime.utc(2026, 6, 11));
      expect(filter.startDate, DateTime.utc(2026, 4, 11));
      expect(filter.apply(records).length, 2);
      expect(filter.mapRecords(records).single.grade, '주의보');
      expect(
        HistoryFilter.latestTwoMonths(DateTime.utc(2026, 4, 30)).startDate,
        DateTime.utc(2026, 2, 28),
      );
      expect(
        HistoryFilter.latestTwoMonths(DateTime.utc(2024, 4, 30)).startDate,
        DateTime.utc(2024, 2, 29),
      );
      expect(
        HistoryFilter.latestTwoMonths(DateTime.utc(2026, 1, 31)).startDate,
        DateTime.utc(2025, 11, 30),
      );
    },
  );
  test('historical and short region names share filter while unknown names survive', () {
    final records = parseWarningBytes(cp949.encode(sampleCsv)).records;
    final filter = HistoryFilter(
      startDate: DateTime.utc(2017),
      endDate: DateTime.utc(2026, 12),
      region: '강원특별자치도',
    );
    expect(filter.apply(records).length, 2);
    expect(canonicalizeRegion('전북'), '전북특별자치도');
    expect(canonicalizeRegion('전라북도'), '전북특별자치도');
    expect(canonicalizeRegion('미등록도'), '미등록도');
  });
  test('JSON-LD discovers dynamic CSV, supports graph and disallows HTTP', () {
    expect(
      findWarningDownload(metadata(url: 'https://www.data.go.kr/new-file.csv'))
          .uri
          .path,
      '/new-file.csv',
    );
    expect(findWarningDownload(metadata()).modifiedAt, DateTime(2026, 9, 3));
    expect(
      () => findWarningDownload(
        metadata(url: 'http://www.data.go.kr/download.csv'),
      ),
      throwsA(isA<DataException>()),
    );
    expect(
      findWarningDownload(
        '<script type="application/ld+json">{"@graph":[{"distribution":{"encodingFormat":"text/csv","contentUrl":"https://example.com/current.csv"}}]}</script>',
      ).uri.path,
      '/current.csv',
    );
  });
  test(
    'cache serialization keeps timestamps, source spelling and metadata',
    () {
      final records = parseWarningBytes(cp949.encode(sampleCsv)).records;
      final dataset = WarningDataset(
        records: records,
        latestDate: records.first.date,
        fetchedAt: DateTime.utc(2026, 9, 26),
        modifiedAt: DateTime.utc(2026, 9, 3),
        skippedRows: 2,
      );
      final restored = decodeWarningCache(encodeWarningCache(dataset));
      expect(restored.latestDate, dataset.latestDate);
      expect(restored.records.first.issuedAt, records.first.issuedAt);
      expect(restored.records.first.region, '강원도');
      expect(restored.skippedRows, 2);
    },
  );
  test('daily cache, explicit refresh, next Korean day and offline restart fallback', () async {
    var now = DateTime.parse('2026-09-26T23:00:00+09:00');
    var calls = 0;
    var online = true;
    final cache = MemoryCache();
    final client = MockClient((request) async {
      calls++;
      if (!online) throw http.ClientException('offline');
      if (request.url.path.endsWith('.do')) {
        return http.Response(metadata(), 200);
      }
      return http.Response.bytes(cp949.encode(sampleCsv), 200);
    });
    final repo = PublicWarningHistoryRepository(
      client: client,
      cache: cache,
      clock: () => now,
    );
    final results = await Future.wait([repo.load(), repo.load()]);
    expect(results.first.records.length, 3);
    expect(calls, 2);
    await repo.load();
    expect(calls, 2);
    await repo.load(forceRefresh: true);
    expect(calls, 4);
    now = DateTime.parse('2026-09-27T00:01:00+09:00');
    await repo.load();
    expect(calls, 6);
    now = now.add(const Duration(days: 1));
    online = false;
    final restarted = PublicWarningHistoryRepository(
      client: client,
      cache: cache,
      clock: () => now,
    );
    final stale = await restarted.load();
    expect(stale.records.length, 3);
    expect(stale.isStale, isTrue);
    expect(stale.refreshWarning, contains('저장된 자료'));
  });
  test('corrupt cache gets repaired, failed write keeps fresh data, no cache fails explicitly', () async {
    final cache = MemoryCache()..value = '{bad json';
    final client = MockClient(
      (request) async => request.url.path.endsWith('.do')
          ? http.Response(metadata(), 200)
          : http.Response.bytes(cp949.encode(sampleCsv), 200),
    );
    final repo = PublicWarningHistoryRepository(client: client, cache: cache);
    expect((await repo.load()).isStale, isFalse);
    cache.failWrite = true;
    expect(
      (await repo.load(forceRefresh: true)).refreshWarning,
      contains('저장하지 못했습니다'),
    );
    await expectLater(
      PublicWarningHistoryRepository(
        client: MockClient((_) async => http.Response('error', 500)),
        cache: MemoryCache(),
      ).load(),
      throwsA(isA<DataException>()),
    );
  });
}
