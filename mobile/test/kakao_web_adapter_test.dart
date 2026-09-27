@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:happy_mountain_mobile/platform/kakao_map.dart';
import 'package:happy_mountain_mobile/platform/kakao_map_js.dart';
import 'package:happy_mountain_mobile/platform/kakao_map_web.dart';
import 'package:web/web.dart' as web;

@JS('happyMountainMapTest')
external _SdkFixture get _fixture;

extension type _SdkFixture._(JSObject _) implements JSObject {
  external JSArray<_TestMap> get maps;
  external JSArray<_TestOverlay> get overlays;
  external int get removedListeners;
}

extension type _TestMap._(JSObject _) implements JSObject {
  external web.HTMLDivElement get container;
  external bool get draggable;
  external bool get zoomable;
  external int get layouts;
  external KakaoLatLng getCenter();
  external void setCenter(KakaoLatLng point);
  external int getLevel();
  external void setLevel(int level);
  external void emit(String event);
}

extension type _TestOverlay._(JSObject _) implements JSObject {
  external _TestMap? get map;
  external web.HTMLElement get content;
}

Future<void> _loaded(String _) async {}

final _attachedElements = <web.HTMLElement>[];

/// Widget tests intercept platform channels; mirror Flutter's own
/// HtmlElementView test registry while retaining real DOM nodes and observers.
class _BrowserViewRegistry implements ui_web.PlatformViewRegistry {
  final _factories = <String, Function>{};
  final _views = <int, Object>{};

  @override
  Object getViewById(int viewId) => _views[viewId]!;

  @override
  bool registerViewFactory(
    String viewType,
    Function viewFactory, {
    bool isVisible = true,
  }) {
    if (_factories.containsKey(viewType)) return false;
    _factories[viewType] = viewFactory;
    return true;
  }

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'create') {
      final args = call.arguments as Map;
      final id = args['id'] as int;
      final params = args['params'];
      final factory = _factories[args['viewType']];
      _views[id] = factory == null
          ? web.document.createElement((params as Map)['tagName'] as String)
          : Function.apply(factory, [id], {#params: params}) as Object;
    } else if (call.method == 'dispose') {
      _views.remove(call.arguments as int);
    }
    return null;
  }
}

Future<void> _attachMapDom(WidgetTester tester, {double width = 500}) async {
  await _flushBrowser(tester);
  final surface = tester.widget<PlatformViewSurface>(
    find.byType(PlatformViewSurface),
  );
  final element = ui_web.platformViewRegistry.getViewById(
    surface.controller.viewId,
  ) as web.HTMLElement;
  // Automated widget tests do not submit platform views to the browser scene.
  // Attach the framework-created element so ResizeObserver can see layout.
  element.style.width = '${width}px';
  element.style.height = '400px';
  if (!element.isConnected) {
    web.document.body!.appendChild(element);
    _attachedElements.add(element);
  }
  await _flushBrowser(tester);
}

Future<void> _flushBrowser(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pump();
}

void main() {
  // Browser Flutter error details otherwise stay in the headless console.
  reportTestException = (details, description) {
    Zone.current.handleUncaughtError(
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };
  web.HTMLScriptElement? fixtureScript;

  setUp(() {
    final registry = _BrowserViewRegistry();
    ui_web.debugOverridePlatformViewRegistry(registry);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          registry.handle,
        );
    fixtureScript = web.HTMLScriptElement()
      ..textContent = r'''
globalThis.happyMountainMapTest = { maps: [], overlays: [], removedListeners: 0 };
globalThis.kakao = { maps: {
  LatLng: class {
    constructor(lat, lng) { this.lat = lat; this.lng = lng; }
    getLat() { return this.lat; }
    getLng() { return this.lng; }
  },
  Map: class {
    constructor(container, options) {
      this.container = container;
      this.center = options.center;
      this.level = options.level;
      this.draggable = options.draggable;
      this.zoomable = options.scrollwheel;
      this.listeners = {};
      this.layouts = 0;
      happyMountainMapTest.maps.push(this);
    }
    getCenter() { return this.center; }
    setCenter(value) { this.center = value; this.emit('idle'); }
    getLevel() { return this.level; }
    setLevel(value) { this.level = value; this.emit('idle'); }
    setDraggable(value) { this.draggable = value; }
    setZoomable(value) { this.zoomable = value; }
    relayout() {
      this.layouts++;
      this.center = new kakao.maps.LatLng(0, 0);
      this.level = 1;
    }
    emit(event) { this.listeners[event]?.(); }
  },
  CustomOverlay: class {
    constructor(options) {
      this.map = options.map;
      this.content = options.content;
      this.position = options.position;
      this.map.container.appendChild(this.content);
      happyMountainMapTest.overlays.push(this);
    }
    setMap(value) {
      this.map = value;
      if (value) value.container.appendChild(this.content);
      else this.content.remove();
    }
    setPosition(value) { this.position = value; }
  },
  event: {
    addListener(target, event, callback) { target.listeners[event] = callback; },
    removeListener(target, event, callback) {
      if (target.listeners[event] === callback) {
        delete target.listeners[event];
        happyMountainMapTest.removedListeners++;
      }
    },
    preventMap() {}
  }
}};
''';
    web.document.head!.appendChild(fixtureScript!);
  });

  tearDown(() {
    ui_web.debugOverridePlatformViewRegistry(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
    fixtureScript?.remove();
    for (final element in _attachedElements) {
      element.remove();
    }
    _attachedElements.clear();
  });

  testWidgets('facade without web key shows setup and makes no SDK request', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KakaoMap(
          nativeKey: 'native-key-is-not-a-web-key',
          center: const MapPoint(37.5665, 126.978),
          cameraRevision: 0,
          markers: const [],
          onCameraIdle: (_) {},
          onMarkerTap: (_) {},
        ),
      ),
    );
    expect(find.text('웹 지도 연결 설정이 필요합니다'), findsOneWidget);
    expect(web.document.getElementById('happy-mountain-kakao-sdk'), isNull);
    expect(_fixture.maps.toDart, isEmpty);
  });

  testWidgets('camera, markers, route interaction, resize and disposal', (
    tester,
  ) async {
    final centers = <MapPoint>[];
    final taps = <String>[];
    var width = 500.0;
    var revision = 0;
    var enabled = true;
    var center = const MapPoint(37.5665, 126.978);
    var pins = const [
      MapPin(
        id: 'mountain',
        point: MapPoint(37.58, 126.99),
        title: '<b>북한산</b>',
        kind: 'mountain',
      ),
      MapPin(
        id: 'history',
        point: MapPoint(37.55, 126.96),
        title: '서울 · 2026-09-01',
        kind: 'history',
      ),
    ];
    MapPoint? location = const MapPoint(37.56, 126.97);
    Future<void> render() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              height: 400,
              child: PlatformKakaoMap(
                nativeKey: '',
                javascriptKey: 'fixture',
                center: center,
                cameraRevision: revision,
                markers: pins,
                myLocation: location,
                onCameraIdle: centers.add,
                onMarkerTap: taps.add,
                interactionEnabled: enabled,
                sdkLoader: _loaded,
              ),
            ),
          ),
        ),
      );
      await _attachMapDom(tester, width: width);
    }

    await render();
    expect(_fixture.maps.toDart, hasLength(1));
    final map = _fixture.maps.toDart.single;
    expect(centers.last.latitude, 37.5665);
    expect(map.container.querySelectorAll('button').length, 2);
    expect(map.container.querySelector('b'), isNull);
    final mountain =
        map.container.querySelector('button') as web.HTMLButtonElement;
    mountain.click();
    expect(taps, ['mountain']);

    map.setCenter(KakaoLatLng(35.18, 129.07));
    map.setLevel(6);
    // Unrelated rebuilds keep the user's camera and unchanged overlay objects.
    final before = _fixture.overlays.toDart.length;
    await render();
    expect(map.getCenter().getLat(), 35.18);
    expect(_fixture.overlays.toDart.length, before);

    width = 320;
    await render();
    expect(map.layouts, greaterThan(0));
    expect(map.getCenter().getLat(), 35.18);
    expect(map.getCenter().getLng(), 129.07);
    expect(map.getLevel(), 6);

    enabled = false;
    await render();
    expect(map.container.inert, isTrue);
    expect(map.container.style.pointerEvents, 'none');
    expect(map.draggable, isFalse);
    expect(map.zoomable, isFalse);
    mountain.click();
    expect(taps, ['mountain']);

    enabled = true;
    center = const MapPoint(36.35, 127.38);
    revision++;
    pins = const [];
    location = null;
    await render();
    expect(map.container.inert, isFalse);
    expect(map.getCenter().getLat(), 36.35);
    expect(map.getLevel(), 8);
    expect(map.container.childElementCount, 0);
    expect(
      _fixture.overlays.toDart.every((overlay) => overlay.map == null),
      isTrue,
    );

    final count = centers.length;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(_fixture.removedListeners, 1);
    map.emit('idle');
    mountain.click();
    expect(centers, hasLength(count));
    expect(taps, ['mountain']);
  });

  testWidgets('SDK failure is visible and retry recreates the view', (
    tester,
  ) async {
    final pending = Completer<void>();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlatformKakaoMap(
          nativeKey: '',
          javascriptKey: 'fixture',
          center: const MapPoint(37.5665, 126.978),
          cameraRevision: 0,
          markers: const [],
          onCameraIdle: (_) {},
          onMarkerTap: (_) {},
          sdkLoader: (_) => ++attempts == 1 ? pending.future : Future.value(),
        ),
      ),
    );
    await _flushBrowser(tester);
    pending.completeError(const KakaoWebException('지도 인증 실패'));
    await tester.pump();
    expect(find.text('지도 인증 실패'), findsOneWidget);
    expect(find.text('지도 다시 연결'), findsOneWidget);
    expect(_fixture.maps.toDart, isEmpty);
    await tester.tap(find.text('지도 다시 연결'));
    await tester.pump();
    await _attachMapDom(tester);
    expect(_fixture.maps.toDart, hasLength(1));
    expect(find.text('지도 인증 실패'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late SDK completion after disposal cannot create a map', (
    tester,
  ) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: PlatformKakaoMap(
          nativeKey: '',
          javascriptKey: 'fixture',
          center: const MapPoint(37.5665, 126.978),
          cameraRevision: 0,
          markers: const [],
          onCameraIdle: (_) {},
          onMarkerTap: (_) {},
          sdkLoader: (_) => pending.future,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await _flushBrowser(tester);
    expect(_fixture.maps.toDart, isEmpty);
  });
}
