import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_mountain_mobile/ui/app.dart';

import 'ui_controller_test.dart' as fixtures;

void main() {
  testWidgets(
    'small screen and 200 percent type keep tabs, history and filters usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = fixtures.makeController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(HappyMountainApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('지도 연결 설정이 필요합니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('경보 이력').last);
      await tester.pumpAndSettle();
      expect(find.text('실시간 위험정보가 아닙니다.'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('전체 지역'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('강원특별자치도').last);
      await tester.pumpAndSettle();
      expect(controller.filteredRecords, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('지도').last);
      await tester.pumpAndSettle();
      expect(find.text('지도 연결 설정이 필요합니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history network error provides retry and subsequently displays data',
    (tester) async {
      final history = fixtures.FakeHistory()..error = '연결을 확인해 주세요.';
      final controller = fixtures.makeController(history: history);
      addTearDown(controller.dispose);
      await tester.pumpWidget(HappyMountainApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('경보 이력').last);
      await tester.pumpAndSettle();
      expect(find.text('연결을 확인해 주세요.'), findsOneWidget);
      history.error = null;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('자료 최신일  2026.06.11'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('capture configured-layout previews for visual review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fonts = FontLoader('Environment')
      ..addFont(rootBundle.load('assets/fonts/environment_regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/environment_bold.ttf'));
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final controller = fixtures.makeController();
    controller.initialize(requestLocation: false);
    addTearDown(controller.dispose);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: HappyMountainApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = await Directory('build/qa').create(recursive: true);
        await File('${directory.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('map-missing-configuration');
    await tester.tap(find.text('경보 이력').last);
    await tester.pumpAndSettle();
    await capture('history-preview-fixtures');
    expect(tester.takeException(), isNull);
  });
}
