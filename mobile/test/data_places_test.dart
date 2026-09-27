import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:happy_mountain_mobile/data/kakao_place_repository.dart';
import 'package:happy_mountain_mobile/domain/contracts.dart';

void main() {
  test(
    'mountains use 10km AT4 keyword search with pagination and unique IDs',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.queryParameters['query'], '산');
        expect(request.url.queryParameters['radius'], '10000');
        expect(request.url.queryParameters['category_group_code'], 'AT4');
        expect(request.headers['Authorization'], 'KakaoAK key');
        return http.Response(
          jsonEncode({
            'meta': {'is_end': calls == 2},
            'documents': [
              {
                'id': '$calls',
                'place_name': '산$calls',
                'address_name': '서울',
                'x': '126.97',
                'y': '37.56',
                'distance': '100',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final places = await KakaoPlaceRepository(
        client: client,
        restApiKey: 'key',
      ).searchMountains(GeoPoint.seoul);
      expect(places.length, 2);
      expect(places.first.point.latitude, 37.56);
    },
  );
  test('geocoding deduplicates in flight requests and caches both match and no match', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'documents': request.url.queryParameters['query'] == '미확인'
              ? []
              : [
                  {'x': '128', 'y': '38'},
                ],
        }),
        200,
      );
    });
    final repo = KakaoPlaceRepository(client: client, restApiKey: 'key');
    final points = await Future.wait([
      repo.resolveAddress('강원도 북면'),
      repo.resolveAddress('강원도  북면'),
    ]);
    expect(points.first, const GeoPoint(38, 128));
    expect(calls, 1);
    await repo.resolveAddress('강원도 북면');
    await repo.resolveAddress('미확인');
    await repo.resolveAddress('미확인');
    expect(calls, 2);
  });
  test(
    'geocoding concurrency is limited to three and failure is retriable',
    () async {
      var active = 0;
      var maximum = 0;
      var fail = false;
      final client = MockClient((request) async {
        active++;
        if (active > maximum) maximum = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return http.Response(
          fail ? 'error' : '{"documents":[]}',
          fail ? 500 : 200,
        );
      });
      final repo = KakaoPlaceRepository(client: client, restApiKey: 'key');
      await Future.wait(List.generate(10, (i) => repo.resolveAddress('주소$i')));
      expect(maximum, 3);
      fail = true;
      await expectLater(
        repo.resolveAddress('재시도'),
        throwsA(isA<DataException>()),
      );
      fail = false;
      expect(await repo.resolveAddress('재시도'), isNull);
    },
  );
}
