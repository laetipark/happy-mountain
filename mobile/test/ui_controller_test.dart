import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:happy_mountain_mobile/app/app_config.dart';
import 'package:happy_mountain_mobile/app/app_controller.dart';
import 'package:happy_mountain_mobile/domain/contracts.dart';

class FakePlaces implements PlaceRepository {
  final searches = <GeoPoint>[];
  final requests = <GeoPoint, Completer<List<MountainPlace>>>{};
  int geocodes = 0;
  bool delayed = false;
  bool missingCoordinates = false;
  @override
  Future<List<MountainPlace>> searchMountains(GeoPoint center) {
    searches.add(center);
    if (delayed) {
      return (requests[center] = Completer<List<MountainPlace>>()).future;
    }
    return Future.value([]);
  }

  @override
  Future<GeoPoint?> resolveAddress(String address) async {
    geocodes++;
    return missingCoordinates ? null : GeoPoint.seoul;
  }
}

class FakeWeather implements WeatherRepository {
  int calls = 0;
  @override
  Future<WeatherSnapshot> fetchWeather(GeoPoint point) async {
    calls++;
    return WeatherSnapshot(
      point: point,
      forecastAt: DateTime.utc(2026, 6, 11, 6),
      baseTime: DateTime.utc(2026, 6, 11, 5),
      temperatureC: 23.5,
      humidityPercent: 60,
      skyCode: 1,
      precipitationCode: 0,
      windSpeedMetersPerSecond: 2.3,
      windDirectionDegrees: 90,
    );
  }
}

class FakeHistory implements WarningHistoryRepository {
  FakeHistory({List<WarningRecord>? records})
    : records =
          records ??
          [
            WarningRecord(
              issuedAt: DateTime.utc(2026, 6, 11, 1),
              region: '강원도',
              district: '강릉시',
              town: '성산면',
              grade: '경계',
            ),
            WarningRecord(
              issuedAt: DateTime.utc(2026, 6, 10, 2),
              region: '경북',
              district: '안동시',
              town: '풍천면',
              grade: '주의',
            ),
          ];
  final List<WarningRecord> records;
  DateTime latestDate = DateTime.utc(2026, 6, 11);
  int loads = 0;
  String? error;
  @override
  Future<WarningDataset> load({bool forceRefresh = false}) async {
    loads++;
    if (error != null) throw DataException(error!);
    return WarningDataset(
      records: records,
      latestDate: latestDate,
      fetchedAt: DateTime.utc(2026, 9, 26, 4),
    );
  }
}

class FakeLocation implements LocationService {
  GeoPoint point = const GeoPoint(37.7, 127.1);
  LocationFailure? failure = LocationFailure.denied;
  int settingsOpened = 0;
  int positionRequests = 0;
  final stream = StreamController<GeoPoint>.broadcast();
  @override
  Future<GeoPoint> currentPosition() async {
    positionRequests++;
    if (failure != null) throw LocationException(failure!);
    return point;
  }

  @override
  Stream<GeoPoint> get changes => stream.stream;
  @override
  Future<void> openSettings() async {
    settingsOpened++;
  }
}

AppController makeController({
  AppConfig config = const AppConfig(
    kakaoNativeKey: '',
    kakaoRestKey: '',
    weatherKey: '',
  ),
  FakePlaces? places,
  FakeWeather? weather,
  FakeHistory? history,
  FakeLocation? location,
}) => AppController(
  config: config,
  places: places ?? FakePlaces(),
  weatherRepository: weather ?? FakeWeather(),
  historyRepository: history ?? FakeHistory(),
  location: location ?? FakeLocation(),
  debounceDuration: const Duration(milliseconds: 100),
);

void main() {
  testWidgets(
    'default dates follow newer data while custom dates remain fixed',
    (tester) async {
      final history = FakeHistory();
      final controller = makeController(history: history);
      addTearDown(controller.dispose);
      await controller.loadHistory();
      controller.setFilter(
        HistoryFilter(
          startDate: controller.filter!.startDate,
          endDate: controller.filter!.endDate,
          region: '강원',
        ),
      );
      history.latestDate = DateTime.utc(2026, 8, 31);
      await controller.loadHistory(forceRefresh: true);
      expect(controller.filter!.startDate, DateTime.utc(2026, 6, 30));
      expect(controller.filter!.endDate, DateTime.utc(2026, 8, 31));
      expect(controller.filter!.region, '강원특별자치도');
      controller.setFilter(
        HistoryFilter(
          startDate: DateTime.utc(2026, 7, 1),
          endDate: DateTime.utc(2026, 7, 10),
          region: '강원',
        ),
        useDefaultDates: false,
      );
      history.latestDate = DateTime.utc(2026, 9, 20);
      await controller.loadHistory(forceRefresh: true);
      expect(controller.filter!.startDate, DateTime.utc(2026, 7, 1));
      expect(controller.filter!.endDate, DateTime.utc(2026, 7, 10));
    },
  );

  testWidgets(
    'location stream error releases subscription and locate restarts tracking',
    (tester) async {
      final location = FakeLocation()..failure = null;
      final controller = makeController(location: location);
      addTearDown(controller.dispose);
      await controller.locate();
      location.stream.addError(const DataException('위치 연결 중단'));
      await tester.pump();
      expect(location.stream.hasListener, isFalse);
      expect(controller.locationError, '위치 연결 중단');
      await controller.locate();
      expect(location.stream.hasListener, isTrue);
      location.stream.add(const GeoPoint(36, 129));
      await tester.pump();
      expect(controller.myLocation, const GeoPoint(36, 129));
      expect(controller.locationError, isNull);
    },
  );

  testWidgets(
    'missing keys skips private services but public history remains available',
    (tester) async {
      final places = FakePlaces();
      final weather = FakeWeather();
      final controller = makeController(places: places, weather: weather);
      addTearDown(controller.dispose);
      controller.initialize(requestLocation: false);
      await tester.pump();
      expect(places.searches, isEmpty);
      expect(weather.calls, 0);
      expect(places.geocodes, 0);
      expect(controller.filteredRecords, hasLength(2));
      expect(controller.weatherError, contains('연결 설정'));
      expect(controller.center, GeoPoint.seoul);
    },
  );

  testWidgets(
    'new viewport invalidates old response before debounce completes',
    (tester) async {
      final places = FakePlaces()..delayed = true;
      final controller = makeController(
        config: const AppConfig(kakaoRestKey: 'test'),
        places: places,
      );
      addTearDown(controller.dispose);
      controller.refreshViewport();
      const target = GeoPoint(35.1, 129.1);
      controller.cameraIdle(target);
      places.requests[GeoPoint.seoul]!.complete([
        const MountainPlace(
          id: 'old',
          name: '이전 산',
          address: '',
          point: GeoPoint.seoul,
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 20));
      expect(controller.mountains, isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      places.requests[target]!.complete([
        const MountainPlace(id: 'new', name: '새 산', address: '', point: target),
      ]);
      await tester.pump();
      expect(controller.mountains.single.name, '새 산');
      controller.cameraIdle(target);
      await tester.pump(const Duration(milliseconds: 150));
      expect(places.searches, hasLength(2));
    },
  );

  testWidgets(
    'first permission grant centers immediately and stream never recenters',
    (tester) async {
      final location = FakeLocation();
      final controller = makeController(location: location);
      addTearDown(controller.dispose);
      await controller.locate();
      expect(controller.center, GeoPoint.seoul);
      expect(controller.locationError, contains('거부'));
      location.failure = null;
      await controller.locate();
      expect(controller.center, location.point);
      expect(controller.cameraRevision, 1);
      expect(location.stream.hasListener, isTrue);
      const manual = GeoPoint(35, 128);
      controller.cameraIdle(manual);
      location.stream.add(const GeoPoint(37.8, 127.2));
      await tester.pump();
      expect(controller.myLocation, const GeoPoint(37.8, 127.2));
      expect(controller.center, manual);
      expect(controller.cameraRevision, 1);
      controller.setForeground(false);
      await tester.pump();
      expect(location.stream.hasListener, isFalse);
      controller.setForeground(true);
      expect(location.stream.hasListener, isTrue);
      await tester.pump(const Duration(milliseconds: 150));
    },
  );

  testWidgets(
    'disabled service and permanent denial offer settings, then recover',
    (tester) async {
      final location = FakeLocation()
        ..failure = LocationFailure.serviceDisabled;
      final controller = makeController(location: location);
      addTearDown(controller.dispose);
      await controller.locate();
      expect(controller.needsLocationSettings, isTrue);
      expect(controller.locationError, contains('위치 서비스'));
      await controller.openLocationSettings();
      expect(location.settingsOpened, 1);
      location.failure = LocationFailure.deniedForever;
      await controller.locate();
      expect(controller.needsLocationSettings, isTrue);
      location.failure = null;
      await controller.locate();
      expect(controller.locationError, isNull);
      expect(controller.needsLocationSettings, isFalse);
    },
  );

  testWidgets(
    'history filters preserve failed geocodes and bound the startup batch',
    (tester) async {
      final records = List.generate(
        90,
        (i) => WarningRecord(
          issuedAt: DateTime.utc(2026, 6, 11),
          region: i.isEven ? '강원도' : '경북',
          district: '시$i',
          town: '읍',
          grade: '주의',
        ),
      );
      final places = FakePlaces()..missingCoordinates = true;
      final controller = makeController(
        config: const AppConfig(kakaoRestKey: 'test'),
        places: places,
        history: FakeHistory(records: records),
      );
      addTearDown(controller.dispose);
      await controller.loadHistory();
      await tester.pump();
      expect(places.geocodes, 60);
      expect(controller.filteredRecords, hasLength(90));
      expect(controller.displayedHistoryMarkers, 0);
      expect(
        controller.addressUnavailable(controller.filteredRecords.first),
        isTrue,
      );
      controller.setFilter(
        HistoryFilter(
          startDate: DateTime.utc(2026, 4, 11),
          endDate: DateTime.utc(2026, 6, 11),
          region: '강원',
        ),
      );
      await tester.pump();
      expect(controller.filteredRecords, hasLength(45));
      expect(
        controller.mapRecords.every(
          (record) => record.canonicalRegion == '강원특별자치도',
        ),
        isTrue,
      );
    },
  );
}
