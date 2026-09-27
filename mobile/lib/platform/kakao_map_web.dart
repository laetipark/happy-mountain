import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'kakao_map_js.dart';
import 'map_types.dart';

class PlatformKakaoMap extends StatefulWidget {
  const PlatformKakaoMap({
    super.key,
    required this.nativeKey,
    required this.javascriptKey,
    required this.center,
    required this.cameraRevision,
    required this.markers,
    required this.onCameraIdle,
    required this.onMarkerTap,
    this.myLocation,
    this.interactionEnabled = true,
    this.sdkLoader = KakaoWebSdk.load,
  });

  final String nativeKey;
  final String javascriptKey;
  final MapPoint center;
  final int cameraRevision;
  final List<MapPin> markers;
  final MapPoint? myLocation;
  final ValueChanged<MapPoint> onCameraIdle;
  final ValueChanged<String> onMarkerTap;
  final bool interactionEnabled;

  @visibleForTesting
  final Future<void> Function(String key) sdkLoader;

  @override
  State<PlatformKakaoMap> createState() => _PlatformKakaoMapState();
}

class _PlatformKakaoMapState extends State<PlatformKakaoMap> {
  // Web levels grow when zooming out; 8 gives a useful city/mountain overview.
  static const _initialLevel = 8;
  web.HTMLDivElement? _element;
  web.ResizeObserver? _resizeObserver;
  KakaoJsMap? _map;
  JSFunction? _idleHandler;
  final Map<String, _WebPin> _pins = {};
  KakaoJsOverlay? _myLocation;
  MapPoint? _lastCameraPoint;
  int? _lastCameraLevel;
  bool _sdkReady = false;
  bool _ready = false;
  bool _updatingCamera = false;
  String? _error;
  int _generation = 0;
  int _epoch = 0;
  int _lastWidth = 0;
  int _lastHeight = 0;

  void _elementCreated(Object object, int generation) {
    if (!mounted || generation != _generation) return;
    final element = object as web.HTMLDivElement;
    _element = element;
    element
      ..setAttribute('role', 'region')
      ..setAttribute('aria-label', '주변 산과 경보 이력 지도')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = '#edf3e9';
    _syncInteraction();
    // HtmlElementView invokes this callback before attachment. Initialize only
    // once ResizeObserver confirms a connected, non-zero container.
    _resizeObserver = web.ResizeObserver(
      (JSArray<web.ResizeObserverEntry> entries, web.ResizeObserver observer) {
        if (mounted && identical(_element, element)) _layout();
      }.toJS,
    )..observe(element);
    final epoch = _epoch;
    unawaited(
      widget
          .sdkLoader(widget.javascriptKey.trim())
          .then(
            (_) {
              if (!mounted || epoch != _epoch) return;
              _sdkReady = true;
              _layout();
            },
            onError: (Object error) {
              if (!mounted || epoch != _epoch) return;
              _fail(
                error is KakaoWebException
                    ? error.message
                    : '지도를 연결하지 못했습니다. 다시 연결해 주세요.',
              );
            },
          ),
    );
  }

  void _layout() {
    final element = _element;
    if (!_sdkReady ||
        _error != null ||
        element == null ||
        !element.isConnected) {
      return;
    }
    final width = element.clientWidth;
    final height = element.clientHeight;
    if (width == 0 || height == 0) return;
    try {
      if (_map == null) {
        final map = KakaoJsMap(
          element,
          KakaoMapOptions(
            center: _coordinate(widget.center),
            level: _initialLevel,
            draggable: widget.interactionEnabled,
            scrollwheel: widget.interactionEnabled,
          ),
        );
        _map = map;
        _idleHandler = _cameraIdle.toJS;
        addKakaoListener(map, 'idle', _idleHandler!);
        _syncMarkers();
        _syncMyLocation();
        setState(() {
          _ready = true;
          _error = null;
        });
        _syncInteraction();
        _cameraIdle();
      } else if (_lastWidth != width || _lastHeight != height) {
        final map = _map!;
        final center = map.getCenter();
        final level = map.getLevel();
        _updatingCamera = true;
        try {
          map.relayout();
          map.setLevel(level);
          map.setCenter(center);
        } finally {
          _updatingCamera = false;
        }
        _cameraIdle();
      }
      _lastWidth = width;
      _lastHeight = height;
    } catch (_) {
      _fail('지도를 표시하지 못했습니다. 지도 키와 등록된 웹 주소를 확인해 주세요.');
    }
  }

  void _cameraIdle() {
    final map = _map;
    if (!mounted || map == null || !_ready || _updatingCamera) return;
    final center = map.getCenter();
    final point = MapPoint(center.getLat(), center.getLng());
    if (!_valid(point)) return;
    final level = map.getLevel();
    if (_samePoint(_lastCameraPoint, point) && _lastCameraLevel == level) {
      return;
    }
    _lastCameraPoint = point;
    _lastCameraLevel = level;
    final epoch = _epoch;
    // SDK setters may dispatch synchronously from didUpdateWidget. Notify
    // Flutter after that build and discard intermediate camera positions.
    scheduleMicrotask(() {
      if (mounted &&
          epoch == _epoch &&
          _samePoint(_lastCameraPoint, point) &&
          _lastCameraLevel == level) {
        widget.onCameraIdle(point);
      }
    });
  }

  void _syncInteraction() {
    final enabled = widget.interactionEnabled && _ready && _error == null;
    final element = _element;
    if (element != null) {
      // inert also blocks focus and descendants that explicitly use auto.
      element.inert = !enabled;
      element.style.pointerEvents = enabled ? 'auto' : 'none';
    }
    _map?.setDraggable(enabled);
    _map?.setZoomable(enabled);
  }

  void _syncMarkers() {
    final map = _map;
    if (map == null) return;
    final wanted = <String, MapPin>{
      for (final pin in widget.markers)
        if (_valid(pin.point)) pin.id: pin,
    };
    for (final id in _pins.keys.toList()) {
      final current = _pins[id]!;
      final replacement = wanted[id];
      if (replacement == null || !_samePin(current.pin, replacement)) {
        current.dispose();
        _pins.remove(id);
      }
    }
    for (final pin in wanted.values) {
      if (_pins.containsKey(pin.id)) continue;
      final button = web.HTMLButtonElement()
        ..type = 'button'
        ..title = pin.title
        ..setAttribute('aria-label', pin.title)
        ..style.cssText =
            'display:flex;align-items:center;flex-direction:column;gap:3px;'
            'background:none;border:0;padding:3px;cursor:pointer;'
            'font:600 12px sans-serif;line-height:1.3;color:#1d2b27;';
      final history = pin.kind == 'history';
      final symbol = web.HTMLSpanElement()
        ..textContent = history ? '!' : '▲'
        ..style.cssText =
            'display:flex;align-items:center;justify-content:center;'
            'width:27px;height:27px;border-radius:50% 50% 50% 4px;'
            'border:2px solid white;color:white;font-size:16px;'
            'box-shadow:0 2px 4px #0005;'
            'background:${history ? '#c53d42' : '#2679bf'};';
      final label = web.HTMLSpanElement()
        ..textContent = pin.title
        ..style.cssText =
            'max-width:145px;overflow:hidden;text-overflow:ellipsis;'
            'white-space:nowrap;padding:2px 5px;border-radius:5px;'
            'background:#fffffff0;box-shadow:0 1px 3px #0003;';
      button
        ..appendChild(symbol)
        ..appendChild(label);
      final click = ((web.Event event) {
        event.stopPropagation();
        preventKakaoMapEvent();
        if (mounted && widget.interactionEnabled) widget.onMarkerTap(pin.id);
      }).toJS;
      button.addEventListener('click', click);
      final overlay = KakaoJsOverlay(
        KakaoOverlayOptions(
          map: map,
          position: _coordinate(pin.point),
          content: button,
          xAnchor: 0.5,
          yAnchor: 1,
          zIndex: history ? 2 : 1,
          clickable: true,
        ),
      );
      _pins[pin.id] = _WebPin(pin, overlay, button, click);
    }
  }

  void _syncMyLocation() {
    final map = _map;
    if (map == null) return;
    final point = widget.myLocation;
    if (point == null || !_valid(point)) {
      _myLocation?.setMap(null);
      _myLocation = null;
      return;
    }
    if (_myLocation != null) {
      _myLocation!.setPosition(_coordinate(point));
      return;
    }
    final dot = web.HTMLDivElement()
      ..title = '현재 위치'
      ..setAttribute('role', 'img')
      ..setAttribute('aria-label', '현재 위치')
      ..style.cssText =
          'width:16px;height:16px;border-radius:50%;background:#17845c;'
          'border:3px solid white;box-shadow:0 0 0 7px #17845c40;'
          'pointer-events:none;';
    _myLocation = KakaoJsOverlay(
      KakaoOverlayOptions(
        map: map,
        position: _coordinate(point),
        content: dot,
        xAnchor: 0.5,
        yAnchor: 0.5,
        zIndex: 3,
        clickable: false,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant PlatformKakaoMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.javascriptKey != oldWidget.javascriptKey) {
      _disposeMap();
      _error = null;
      _generation++;
      return;
    }
    if (_map == null) return;
    try {
      _syncMarkers();
      _syncMyLocation();
      _syncInteraction();
      if (widget.cameraRevision != oldWidget.cameraRevision &&
          _valid(widget.center)) {
        _updatingCamera = true;
        try {
          _map!.setLevel(_initialLevel);
          _map!.setCenter(_coordinate(widget.center));
        } finally {
          _updatingCamera = false;
        }
        _cameraIdle();
      }
    } catch (_) {
      _fail('지도 정보를 반영하지 못했습니다. 다시 연결해 주세요.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    _syncInteraction();
  }

  void _disposeMap() {
    _epoch++;
    _resizeObserver?.disconnect();
    _resizeObserver = null;
    final map = _map;
    final idleHandler = _idleHandler;
    if (map != null && idleHandler != null) {
      removeKakaoListener(map, 'idle', idleHandler);
    }
    _idleHandler = null;
    for (final pin in _pins.values) {
      pin.dispose();
    }
    _pins.clear();
    _myLocation?.setMap(null);
    _myLocation = null;
    _map = null;
    // The SDK has no public destroy method. Remove our listeners, overlays and
    // DOM and release the instance so removed platform views can be collected.
    _element?.textContent = '';
    _element = null;
    _sdkReady = false;
    _ready = false;
    _lastWidth = 0;
    _lastHeight = 0;
    _lastCameraPoint = null;
    _lastCameraLevel = null;
  }

  @override
  void dispose() {
    _disposeMap();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.javascriptKey.trim().isEmpty) {
      return const MapUnavailable(
        message: '웹 지도 연결 설정이 필요합니다',
        detail: '웹 연결 설정에 카카오 JavaScript 키를 추가하고\n현재 주소를 카카오 웹 플랫폼에 등록해 주세요.\n경보 이력 화면에서 자료를 확인할 수 있습니다.',
      );
    }
    final generation = _generation;
    return Stack(
      children: [
        Positioned.fill(
          child: HtmlElementView.fromTagName(
            key: ValueKey(_generation),
            tagName: 'div',
            onElementCreated: (element) => _elementCreated(element, generation),
          ),
        ),
        if (!_ready && _error == null)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xDDEDF3E9),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_error != null)
          Positioned.fill(
            child: MapUnavailable(
              message: '지도를 불러오지 못했습니다',
              detail: _error!,
              onRetry: () {
                setState(() {
                  _disposeMap();
                  _error = null;
                  _generation++;
                });
              },
            ),
          ),
      ],
    );
  }
}

KakaoLatLng _coordinate(MapPoint point) =>
    KakaoLatLng(point.latitude, point.longitude);

bool _valid(MapPoint point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude >= -90 &&
    point.latitude <= 90 &&
    point.longitude >= -180 &&
    point.longitude <= 180;

bool _samePoint(MapPoint? a, MapPoint b) =>
    a != null && a.latitude == b.latitude && a.longitude == b.longitude;

bool _samePin(MapPin a, MapPin b) =>
    a.id == b.id &&
    _samePoint(a.point, b.point) &&
    a.title == b.title &&
    a.kind == b.kind;

class _WebPin {
  _WebPin(this.pin, this.overlay, this.button, this.click);
  final MapPin pin;
  final KakaoJsOverlay overlay;
  final web.HTMLButtonElement button;
  final JSFunction click;

  void dispose() {
    button.removeEventListener('click', click);
    overlay.setMap(null);
    button.remove();
  }
}
