import 'dart:convert';

import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:happy_mountain_mobile/data/http_support.dart';
import 'package:happy_mountain_mobile/data/kakao_place_repository.dart';
import 'package:happy_mountain_mobile/data/kma_weather_repository.dart';
import 'package:happy_mountain_mobile/data/warning_history_repository.dart';
import 'package:happy_mountain_mobile/domain/contracts.dart';

class _Cache implements WarningCache {
  String? value;
  bool denied = false;
  @override
  Future<String?> read() async {
    if (denied) throw StateError('Storage denied');
    return value;
  }

  @override
  Future<void> write(String data) async {
    if (denied) throw StateError('Storage denied');
    value = data;
  }
}

const _csv =
    '예보일시,시도명,시군구명,읍면동명,실효습도,풍속,등급\n2026-06-11 15:00,강원도,인제군,북면,34.6,7.3,주의보\n';

void main() {
  final origin = Uri.parse('http://localhost:8080/app/index.html');
  test(
    'places use fixed same-origin routes without transmitting REST key',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.url.origin, origin.origin);
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.url.toString(), isNot(contains('private-key')));
        if (request.url.path == '/api/places/mountains') {
          expect(request.url.queryParameters.keys.toSet(), {'x', 'y', 'page'});
          expect(
            request.url.queryParameters['x'],
            '${GeoPoint.seoul.longitude}',
          );
          return http.Response('{"meta":{"is_end":true},"documents":[]}', 200);
        }
        expect(request.url.queryParameters, {'query': '강원특별자치도 인제군 북면'});
        return http.Response('{"documents":[{"x":"128","y":"38"}]}', 200);
      });
      final repository = KakaoPlaceRepository(
        client: client,
        restApiKey: 'private-key',
        gatewayOrigin: origin,
      );
      expect(await repository.searchMountains(GeoPoint.seoul), isEmpty);
      expect(
        await repository.resolveAddress('강원특별자치도 인제군 북면'),
        const GeoPoint(38, 128),
      );
      expect(paths, ['/api/places/mountains', '/api/places/address']);
    },
  );

  test(
    'weather shares grid and forecast selection while gateway holds its key',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/weather');
        expect(request.url.queryParameters, {
          'nx': '60',
          'ny': '127',
          'base_date': '20260926',
          'base_time': '0800',
        });
        expect(request.url.toString(), isNot(contains('secret-weather-key')));
        return http.Response(
          jsonEncode({
            'response': {
              'header': {'resultCode': '00'},
              'body': {
                'items': {
                  'item': [
                    for (final entry in {
                      'TMP': '24',
                      'REH': '50',
                      'SKY': '1',
                      'PTY': '0',
                      'WSD': '2',
                      'VEC': '0',
                    }.entries)
                      {
                        'fcstDate': '20260926',
                        'fcstTime': '0900',
                        'category': entry.key,
                        'fcstValue': entry.value,
                      },
                  ],
                },
              },
            },
          }),
          200,
        );
      });
      final repository = KmaWeatherRepository(
        client: client,
        serviceKey: 'secret-weather-key',
        gatewayOrigin: origin,
        clock: () => DateTime.parse('2026-09-26T08:30:00+09:00'),
      );
      final weather = await repository.fetchWeather(GeoPoint.seoul);
      expect(weather.temperatureC, 24);
      expect(weather.forecastAt, DateTime.parse('2026-09-26T09:00:00+09:00'));
    },
  );

  test('history fetches raw gateway bytes once, reads metadata and preserves offline cache', () async {
    var calls = 0;
    var online = true;
    var now = DateTime.utc(2026, 9, 26);
    final cache = _Cache();
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/api/history');
      expect(
        request.url.queryParameters,
        calls == 2 ? {'forceRefresh': 'true'} : isEmpty,
      );
      if (!online) throw http.ClientException('offline');
      return http.Response.bytes(
        cp949.encode(_csv),
        200,
        headers: {
          'x-data-modified-at': '2026-09-03T00:00:00Z',
          'content-type': 'application/octet-stream; charset=UTF-8',
        },
      );
    });
    final repository = PublicWarningHistoryRepository(
      client: client,
      cache: cache,
      gatewayOrigin: origin,
      clock: () => now,
    );
    final result = await repository.load();
    expect(result.records.single.region, '강원도');
    expect(result.latestDate, DateTime.utc(2026, 6, 11));
    expect(result.modifiedAt, DateTime.utc(2026, 9, 3));
    await repository.load();
    expect(calls, 1);
    await repository.load(forceRefresh: true);
    expect(calls, 2);
    now = now.add(const Duration(days: 1));
    online = false;
    final restarted = PublicWarningHistoryRepository(
      client: client,
      cache: cache,
      gatewayOrigin: origin,
      clock: () => now,
    );
    expect((await restarted.load()).refreshWarning, contains('저장된 자료'));
  });

  test(
    'denied browser storage keeps the fresh archive available with warning',
    () async {
      final repository = PublicWarningHistoryRepository(
        client: MockClient(
          (_) async => http.Response.bytes(cp949.encode(_csv), 200),
        ),
        cache: _Cache()..denied = true,
        gatewayOrigin: origin,
      );
      final result = await repository.load();
      expect(result.records.single.town, '북면');
      expect(result.refreshWarning, contains('저장하지 못했습니다'));
    },
  );

  test(
    'HTTP exception is limited to matching local gateway API origin',
    () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('ok', 200);
      });
      await getResponse(
        client,
        Uri.parse('https://www.data.go.kr/file'),
        gatewayOrigin: null,
      );
      await getResponse(
        client,
        Uri.parse('http://localhost:8080/api/config'),
        gatewayOrigin: origin,
      );
      for (final target in [
        'http://example.com/api/history',
        'http://localhost:8081/api/history',
        'http://localhost:8080/not-api',
        'https://other.example/api/history',
      ]) {
        await expectLater(
          getResponse(client, Uri.parse(target), gatewayOrigin: origin),
          throwsA(isA<DataException>()),
        );
      }
      await expectLater(
        getResponse(client, Uri.parse('http://localhost:8080/api/history')),
        throwsA(isA<DataException>()),
      );
      expect(calls, 2);
    },
  );
}
