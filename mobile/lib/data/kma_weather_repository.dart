import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../domain/contracts.dart';
import 'http_support.dart';

class KmaGrid {
  const KmaGrid(this.x, this.y);
  final int x;
  final int y;

  /// KMA Lambert conformal conic projection, 5 km grid.
  factory KmaGrid.fromPoint(GeoPoint point) {
    const radians = math.pi / 180;
    const re = 6371.00877 / 5;
    const slat1 = 30 * radians;
    const slat2 = 60 * radians;
    final sn =
        math.log(math.cos(slat1) / math.cos(slat2)) /
        math.log(
          math.tan(math.pi * .25 + slat2 * .5) /
              math.tan(math.pi * .25 + slat1 * .5),
        );
    final sf =
        math.pow(math.tan(math.pi * .25 + slat1 * .5), sn) *
        math.cos(slat1) /
        sn;
    final ro =
        re * sf / math.pow(math.tan(math.pi * .25 + 38 * radians * .5), sn);
    final ra =
        re *
        sf /
        math.pow(math.tan(math.pi * .25 + point.latitude * radians * .5), sn);
    var theta = point.longitude * radians - 126 * radians;
    if (theta > math.pi) theta -= 2 * math.pi;
    if (theta < -math.pi) theta += 2 * math.pi;
    theta *= sn;
    return KmaGrid(
      (ra * math.sin(theta) + 43.5).floor(),
      (ro - ra * math.cos(theta) + 136.5).floor(),
    );
  }
}

/// Latest 02/05/08/11/14/17/20/23 KST run available after ten minutes.
DateTime latestWeatherBaseTime(DateTime now) {
  final available = koreanTime(now).subtract(const Duration(minutes: 10));
  final hour = ((available.hour - 2) / 3).floor() * 3 + 2;
  return DateTime.utc(
    available.year,
    available.month,
    available.day,
    hour,
  ).subtract(const Duration(hours: 9));
}

DateTime? parseKmaTime(Object? date, Object? time) {
  final text = '$date${time.toString().padLeft(4, '0')}';
  if (!RegExp(r'^\d{12}$').hasMatch(text)) return null;
  final year = int.parse(text.substring(0, 4));
  final month = int.parse(text.substring(4, 6));
  final day = int.parse(text.substring(6, 8));
  final hour = int.parse(text.substring(8, 10));
  final minute = int.parse(text.substring(10, 12));
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      hour > 23 ||
      minute > 59) {
    return null;
  }
  return DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
  ).subtract(const Duration(hours: 9));
}

WeatherSnapshot selectForecast({
  required List<dynamic> items,
  required GeoPoint point,
  required DateTime baseTime,
  required DateTime now,
}) {
  final byTime = <DateTime, Map<String, double>>{};
  const required = {'TMP', 'REH', 'SKY', 'PTY', 'WSD', 'VEC'};
  for (final row in items) {
    if (row is! Map) continue;
    final time = parseKmaTime(row['fcstDate'], row['fcstTime']);
    final value = double.tryParse('${row['fcstValue']}');
    final category = '${row['category']}';
    if (time == null ||
        time.isBefore(now) ||
        value == null ||
        !value.isFinite ||
        !required.contains(category)) {
      continue;
    }
    byTime.putIfAbsent(time, () => {})[category] = value;
  }
  final times = byTime.keys.toList()..sort();
  for (final time in times) {
    final values = byTime[time]!;
    if (!values.keys.toSet().containsAll(required)) continue;
    return WeatherSnapshot(
      point: point,
      forecastAt: time,
      baseTime: baseTime,
      temperatureC: values['TMP']!,
      humidityPercent: values['REH']!,
      skyCode: values['SKY']!.toInt(),
      precipitationCode: values['PTY']!.toInt(),
      windSpeedMetersPerSecond: values['WSD']!,
      windDirectionDegrees: values['VEC']!,
    );
  }
  throw const DataException('현재 이후 같은 예보시각의 날씨 항목을 찾지 못했습니다. 다시 시도해 주세요.');
}

class KmaWeatherRepository implements WeatherRepository {
  KmaWeatherRepository({
    required this.client,
    this.serviceKey = '',
    this.gatewayOrigin,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final http.Client client;
  final String serviceKey;
  final Uri? gatewayOrigin;
  final DateTime Function() clock;
  final _requests = <String, Future<List<dynamic>>>{};
  final _cache = <String, List<dynamic>>{};
  @override
  Future<WeatherSnapshot> fetchWeather(GeoPoint point) async {
    if (gatewayOrigin == null && serviceKey.trim().isEmpty) {
      throw const DataException('기상청 API 키를 설정하면 날씨를 볼 수 있습니다.');
    }
    final now = clock().toUtc();
    final grid = KmaGrid.fromPoint(point);
    final base = latestWeatherBaseTime(now);
    final items = await _fetch(grid, base);
    return selectForecast(items: items, point: point, baseTime: base, now: now);
  }

  Future<List<dynamic>> _fetch(KmaGrid grid, DateTime base) {
    final key = '${grid.x}/${grid.y}/${base.toIso8601String()}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _requests.putIfAbsent(
      key,
      () => _download(grid, base)
          .then((items) {
            if (_cache.length >= 30) _cache.remove(_cache.keys.first);
            _cache[key] = items;
            return items;
          })
          .whenComplete(() {
            _requests.remove(key);
          }),
    );
  }

  Future<List<dynamic>> _download(KmaGrid grid, DateTime base) async {
    final kst = koreanTime(base);
    String two(int n) => '$n'.padLeft(2, '0');
    // Accept both portal display variants while URI encodes the key once.
    var key = serviceKey.trim();
    if (key.contains('%')) {
      try {
        key = Uri.decodeComponent(key);
      } on FormatException {
        /* retain literal key */
      }
    }
    final query = {
      'base_date': '${kst.year}${two(kst.month)}${two(kst.day)}',
      'base_time': '${two(kst.hour)}00',
      'nx': '${grid.x}',
      'ny': '${grid.y}',
    };
    final uri = gatewayOrigin != null
        ? gatewayEndpoint(gatewayOrigin!, '/api/weather', query)
        : Uri.https(
            'apis.data.go.kr',
            '/1360000/VilageFcstInfoService_2.0/getVilageFcst',
            {
              ...query,
              'serviceKey': key,
              'pageNo': '1',
              'numOfRows': '1000',
              'dataType': 'JSON',
            },
          );
    final result = decodeObject(
      await getResponse(client, uri, gatewayOrigin: gatewayOrigin),
    );
    final response = result['response'];
    if (response is! Map) throw const DataException('기상청 응답 형식이 변경되었습니다.');
    final code = '${(response['header'] as Map?)?['resultCode']}';
    if (code != '00') {
      if (const ['20', '21', '22', '30', '31', '32'].contains(code)) {
        throw const DataException('기상청 인증 또는 호출 한도를 확인해 주세요.');
      }
      throw DataException('기상청에서 예보를 제공하지 못했습니다 ($code). 잠시 후 다시 시도해 주세요.');
    }
    final body = response['body'];
    final items = body is Map ? body['items'] : null;
    final rows = items is Map ? items['item'] : null;
    if (rows is! List) throw const DataException('해당 위치의 기상청 예보가 없습니다.');
    return rows;
  }
}
