import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_mountain_mobile/app/app_config.dart';
import 'package:happy_mountain_mobile/domain/contracts.dart';
import 'package:happy_mountain_mobile/ui/app.dart';

import 'ui_controller_test.dart' as fixtures;

AppConfig webConfig({bool enabled = false}) => AppConfig.fromGateway({
  'kakaoJavascriptKey': '',
  'placesEnabled': enabled,
  'weatherEnabled': enabled,
});

void main() {
  test(
    'resume checks history freshness and weather without recentering',
    () async {
      final history = fixtures.FakeHistory();
      final weather = fixtures.FakeWeather();
      final controller = fixtures.makeController(
        config: webConfig(enabled: true),
        history: history,
        weather: weather,
      );
      addTearDown(controller.dispose);
      controller.initialize();
      await Future<void>.delayed(Duration.zero);
      controller.center = const GeoPoint(35.1, 129.0);
      controller.setForeground(false);
      history.latestDate = DateTime.utc(2026, 7, 12);
      controller.setForeground(true);
      await Future<void>.delayed(Duration.zero);
      expect(history.loads, 2);
      expect(weather.calls, 2);
      expect(controller.center, const GeoPoint(35.1, 129.0));
      expect(controller.cameraRevision, 0);
      expect(controller.filter!.endDate, DateTime.utc(2026, 7, 12));
      controller.setForeground(true);
      await Future<void>.delayed(Duration.zero);
      expect(history.loads, 2);
    },
  );

  test('gateway capabilities enable services without client secrets', () async {
    final places = fixtures.FakePlaces();
    final weather = fixtures.FakeWeather();
    final config = webConfig(enabled: true);
    final controller = fixtures.makeController(
      config: config,
      places: places,
      weather: weather,
    );
    addTearDown(controller.dispose);
    expect(config.kakaoRestKey, isEmpty);
    expect(config.weatherKey, isEmpty);
    controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(places.searches, [GeoPoint.seoul]);
    expect(weather.calls, 1);
    expect(controller.weather, isNotNull);
    expect(places.geocodes, 2);
  });

  test('invalid public configuration cannot silently disable services', () {
    expect(
      () => AppConfig.fromGateway({'placesEnabled': 'true'}),
      throwsFormatException,
    );
  });

  testWidgets('web waits for location click; denial shows browser help', (
    tester,
  ) async {
    final location = fixtures.FakeLocation();
    final controller = fixtures.makeController(
      config: webConfig(),
      location: location,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(HappyMountainApp(controller: controller));
    await tester.pumpAndSettle();
    expect(location.positionRequests, 0);
    await tester.tap(find.byTooltip('내 위치로 이동'));
    await tester.pumpAndSettle();
    expect(location.positionRequests, 1);
    expect(controller.center, GeoPoint.seoul);
    await tester.tap(find.text('권한 안내'));
    await tester.pumpAndSettle();
    expect(find.text('브라우저 위치 권한'), findsOneWidget);
    expect(location.settingsOpened, 0);
    Navigator.of(tester.element(find.text('브라우저 위치 권한'))).pop();
    await tester.pumpAndSettle();
    location.failure = null;
    await tester.tap(find.byTooltip('내 위치로 이동'));
    await tester.pumpAndSettle();
    expect(controller.center, location.point);
    expect(controller.cameraRevision, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shows both panels; resize retains active filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = fixtures.makeController(config: webConfig());
    addTearDown(controller.dispose);
    await tester.pumpWidget(HappyMountainApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('desktop-layout')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('산불위험 경보 이력'), findsOneWidget);
    controller.setFilter(
      HistoryFilter(
        startDate: controller.filter!.startDate,
        endDate: controller.filter!.endDate,
        region: '강원',
      ),
    );
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('경보 이력').last);
    await tester.pumpAndSettle();
    expect(controller.filteredRecords, hasLength(1));
    expect(controller.filter!.region, '강원특별자치도');
    expect(tester.takeException(), isNull);
  });
}
