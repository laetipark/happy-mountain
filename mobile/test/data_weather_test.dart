import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:happy_mountain_mobile/data/kma_weather_repository.dart';
import 'package:happy_mountain_mobile/domain/contracts.dart';

List<Map<String, String>> forecast(
  String date,
  String time, {
  String temperature = '24',
  bool complete = true,
}) => [
  for (final entry in <String, String>{
    'TMP': temperature,
    'REH': '70',
    'SKY': '3',
    'PTY': '0',
    'WSD': '2.4',
    if (complete) 'VEC': '350',
  }.entries)
    {
      'fcstDate': date,
      'fcstTime': time,
      'category': entry.key,
      'fcstValue': entry.value,
    },
];

void main() {
  test('KMA projection agrees with Seoul and Busan reference grid', () {
    final seoul = KmaGrid.fromPoint(GeoPoint.seoul);
    final busan = KmaGrid.fromPoint(const GeoPoint(35.1796, 129.0756));
    expect((seoul.x, seoul.y), (60, 127));
    expect((busan.x, busan.y), (98, 76));
  });
  test('publication boundary uses previous run until 02:10 KST', () {
    expect(
      latestWeatherBaseTime(DateTime.parse('2026-09-26T02:09:59+09:00')),
      DateTime.parse('2026-09-25T23:00:00+09:00'),
    );
    expect(
      latestWeatherBaseTime(DateTime.parse('2026-09-26T02:10:00+09:00')),
      DateTime.parse('2026-09-26T02:00:00+09:00'),
    );
    expect(
      latestWeatherBaseTime(DateTime.parse('2026-09-26T23:09:00+09:00')),
      DateTime.parse('2026-09-26T20:00:00+09:00'),
    );
    expect(
      latestWeatherBaseTime(DateTime.parse('2026-09-26T23:10:00+09:00')),
      DateTime.parse('2026-09-26T23:00:00+09:00'),
    );
  });
  test('midnight, year rollover and timezone-independent clock', () {
    expect(
      latestWeatherBaseTime(DateTime.parse('2026-01-01T00:00:00+09:00')),
      DateTime.parse('2025-12-31T23:00:00+09:00'),
    );
    expect(
      latestWeatherBaseTime(DateTime.parse('2026-09-25T17:10:00Z')),
      DateTime.parse('2026-09-26T02:00:00+09:00'),
    );
  });
  test('selects nearest future complete timestamp without mixing values', () {
    final now = DateTime.parse('2026-09-26T08:35:00+09:00');
    final result = selectForecast(
      items: [
        ...forecast('20260926', '0800', temperature: '10'),
        ...forecast('20260926', '0900', temperature: '20', complete: false),
        ...forecast('20260926', '1000', temperature: '30'),
        ...forecast('20260926', '1100', temperature: '40'),
      ],
      point: GeoPoint.seoul,
      baseTime: latestWeatherBaseTime(now),
      now: now,
    );
    expect(result.forecastAt, DateTime.parse('2026-09-26T10:00:00+09:00'));
    expect(result.temperatureC, 30);
    expect(result.humidityPercent, 70);
    expect(result.windDirectionLabel, '북');
  });
  test(
    'no complete future timestamp reports failure rather than stale weather',
    () {
      final now = DateTime.parse('2026-09-26T08:35:00+09:00');
      expect(
        () => selectForecast(
          items: forecast('20260926', '0800'),
          point: GeoPoint.seoul,
          baseTime: latestWeatherBaseTime(now),
          now: now,
        ),
        throwsA(isA<DataException>()),
      );
      expect(parseKmaTime('20260230', '1000'), isNull);
    },
  );
  test('HTTPS request uses grid, KST base date and exactly once encoded key; shared grid reuses data', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.scheme, 'https');
      expect(request.url.queryParameters['serviceKey'], 'test+key=');
      expect(request.url.queryParameters['base_date'], '20260926');
      expect(request.url.queryParameters['base_time'], '0800');
      expect(request.url.queryParameters['nx'], '60');
      expect(request.url.queryParameters['ny'], '127');
      return http.Response(
        jsonEncode({
          'response': {
            'header': {'resultCode': '00'},
            'body': {
              'items': {'item': forecast('20260926', '0900')},
            },
          },
        }),
        200,
      );
    });
    final repo = KmaWeatherRepository(
      client: client,
      serviceKey: 'test%2Bkey%3D',
      clock: () => DateTime.parse('2026-09-26T08:30:00+09:00'),
    );
    await Future.wait([
      repo.fetchWeather(GeoPoint.seoul),
      repo.fetchWeather(GeoPoint.seoul),
    ]);
    await repo.fetchWeather(GeoPoint.seoul);
    expect(calls, 1);
  });
  test(
    'missing key and authorization error are actionable without exposing keys',
    () async {
      final client = MockClient((_) async => http.Response('forbidden', 403));
      await expectLater(
        KmaWeatherRepository(
          client: client,
          serviceKey: '',
        ).fetchWeather(GeoPoint.seoul),
        throwsA(isA<DataException>()),
      );
      await expectLater(
        KmaWeatherRepository(
          client: client,
          serviceKey: 'private-key',
        ).fetchWeather(GeoPoint.seoul),
        throwsA(
          isA<DataException>().having(
            (e) => e.message,
            'message',
            isNot(contains('private-key')),
          ),
        ),
      );
    },
  );
}
