/// Geographic coordinates in WGS84.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
  static const seoul = GeoPoint(37.5665, 126.9780);
  Map<String, double> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;
  @override
  int get hashCode => Object.hash(latitude, longitude);
}

class MountainPlace {
  const MountainPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.point,
    this.distanceMeters,
  });
  final String id;
  final String name;
  final String address;
  final GeoPoint point;
  final int? distanceMeters;
}

/// Timestamps are UTC instants. Use [koreanTime] before displaying their fields.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.point,
    required this.forecastAt,
    required this.baseTime,
    required this.temperatureC,
    required this.humidityPercent,
    required this.skyCode,
    required this.precipitationCode,
    required this.windSpeedMetersPerSecond,
    required this.windDirectionDegrees,
  });
  final GeoPoint point;
  final DateTime forecastAt;
  final DateTime baseTime;
  final double temperatureC;
  final double humidityPercent;
  final int skyCode;
  final int precipitationCode;
  final double windSpeedMetersPerSecond;
  final double windDirectionDegrees;
  String get skyLabel => switch (skyCode) {
    1 => '맑음',
    3 => '구름 많음',
    4 => '흐림',
    _ => '알 수 없음',
  };
  String get precipitationLabel => switch (precipitationCode) {
    0 => '없음',
    1 => '비',
    2 => '비/눈',
    3 => '눈',
    4 => '소나기',
    _ => '알 수 없음',
  };
  String get windDirectionLabel => const [
    '북',
    '북동',
    '동',
    '남동',
    '남',
    '남서',
    '서',
    '북서',
  ][((windDirectionDegrees % 360) / 45).round() % 8];
}

class WarningRecord {
  const WarningRecord({
    required this.issuedAt,
    required this.region,
    required this.district,
    required this.town,
    required this.grade,
    this.effectiveHumidity,
    this.windSpeed,
  });
  final DateTime issuedAt;

  /// Original source spelling, retained for traceability.
  final String region;
  final String district;
  final String town;
  final String grade;
  final double? effectiveHumidity;
  final double? windSpeed;
  String get canonicalRegion => canonicalizeRegion(region);
  String get address =>
      [canonicalRegion, district, town].where((s) => s.isNotEmpty).join(' ');
  String get id => '${issuedAt.toIso8601String()}|$address|$grade';
  DateTime get date => calendarDate(koreanTime(issuedAt));
}

class WarningDataset {
  const WarningDataset({
    required this.records,
    required this.latestDate,
    required this.fetchedAt,
    this.modifiedAt,
    this.refreshWarning,
    this.skippedRows = 0,
  });
  final List<WarningRecord> records;

  /// Calendar date in Korea, represented by UTC midnight for date arithmetic.
  final DateTime latestDate;
  final DateTime fetchedAt;
  final DateTime? modifiedAt;
  final String? refreshWarning;
  final int skippedRows;
  bool get isStale => refreshWarning != null;
  List<String> get regions =>
      (records.map((r) => r.canonicalRegion).toSet().toList()..sort());
  WarningDataset withWarning(String warning) => WarningDataset(
    records: records,
    latestDate: latestDate,
    fetchedAt: fetchedAt,
    modifiedAt: modifiedAt,
    refreshWarning: warning,
    skippedRows: skippedRows,
  );
}

class HistoryFilter {
  HistoryFilter({
    required DateTime startDate,
    required DateTime endDate,
    String? region,
  }) : startDate = calendarDate(startDate),
       endDate = calendarDate(endDate),
       region = region == null || region.isEmpty
           ? null
           : canonicalizeRegion(region);
  factory HistoryFilter.latestTwoMonths(DateTime latestDate) {
    final end = calendarDate(latestDate);
    final targetMonth = DateTime.utc(end.year, end.month - 2, 1);
    final maxDay = DateTime.utc(targetMonth.year, targetMonth.month + 1, 0).day;
    return HistoryFilter(
      startDate: DateTime.utc(
        targetMonth.year,
        targetMonth.month,
        end.day > maxDay ? maxDay : end.day,
      ),
      endDate: end,
    );
  }
  final DateTime startDate;
  final DateTime endDate;
  final String? region;
  List<WarningRecord> apply(Iterable<WarningRecord> records) =>
      records
          .where(
            (r) =>
                !r.date.isBefore(startDate) &&
                !r.date.isAfter(endDate) &&
                (region == null || r.canonicalRegion == region),
          )
          .toList()
        ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));

  /// Only the map deduplicates by address; the history list retains all records.
  List<WarningRecord> mapRecords(Iterable<WarningRecord> records) {
    final latestByAddress = <String, WarningRecord>{};
    for (final record in apply(records)) {
      latestByAddress.putIfAbsent(record.address, () => record);
    }
    return latestByAddress.values.toList();
  }
}

DateTime koreanTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9));
DateTime calendarDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String canonicalizeRegion(String region) {
  final value = region.trim();
  const aliases = <String, String>{
    '서울': '서울특별시',
    '서울시': '서울특별시',
    '부산': '부산광역시',
    '부산시': '부산광역시',
    '대구': '대구광역시',
    '대구시': '대구광역시',
    '인천': '인천광역시',
    '인천시': '인천광역시',
    '광주': '광주광역시',
    '광주시': '광주광역시',
    '대전': '대전광역시',
    '대전시': '대전광역시',
    '울산': '울산광역시',
    '울산시': '울산광역시',
    '세종': '세종특별자치시',
    '세종시': '세종특별자치시',
    '경기': '경기도',
    '강원': '강원특별자치도',
    '강원도': '강원특별자치도',
    '충북': '충청북도',
    '충남': '충청남도',
    '전북': '전북특별자치도',
    '전라북도': '전북특별자치도',
    '전남': '전라남도',
    '경북': '경상북도',
    '경남': '경상남도',
    '제주': '제주특별자치도',
    '제주도': '제주특별자치도',
  };
  return aliases[value] ?? value;
}

enum LocationFailure { denied, deniedForever, serviceDisabled, unavailable }

class LocationException implements Exception {
  const LocationException(this.reason);
  final LocationFailure reason;
  @override
  String toString() => switch (reason) {
    LocationFailure.denied => '위치 권한이 거부되었습니다. 지도를 직접 이동할 수 있습니다.',
    LocationFailure.deniedForever => '설정에서 위치 권한을 허용해 주세요.',
    LocationFailure.serviceDisabled => '기기의 위치 서비스를 켜 주세요.',
    LocationFailure.unavailable => '현재 위치를 확인하지 못했습니다. 다시 시도해 주세요.',
  };
}

class DataException implements Exception {
  const DataException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class LocationService {
  Stream<GeoPoint> get changes;
  Future<GeoPoint> currentPosition();
  Future<void> openSettings();
}

abstract interface class PlaceRepository {
  Future<List<MountainPlace>> searchMountains(GeoPoint center);
  Future<GeoPoint?> resolveAddress(String address);
}

abstract interface class WeatherRepository {
  Future<WeatherSnapshot> fetchWeather(GeoPoint point);
}

abstract interface class WarningHistoryRepository {
  Future<WarningDataset> load({bool forceRefresh = false});
}
