import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'map_types.dart';

/// Native map owns rendering only. Fetching, filters and selection stay in Dart.
class PlatformKakaoMap extends StatefulWidget {
  const PlatformKakaoMap({
    super.key,
    required this.nativeKey,
    required this.center,
    required this.cameraRevision,
    required this.markers,
    required this.onCameraIdle,
    required this.onMarkerTap,
    this.myLocation,
    this.javascriptKey = '',
    this.interactionEnabled = true,
  });

  final String nativeKey;
  final String javascriptKey;
  final bool interactionEnabled;
  final MapPoint center;
  final int cameraRevision;
  final List<MapPin> markers;
  final MapPoint? myLocation;
  final ValueChanged<MapPoint> onCameraIdle;
  final ValueChanged<String> onMarkerTap;

  @override
  State<PlatformKakaoMap> createState() => _PlatformKakaoMapState();
}

class _PlatformKakaoMapState extends State<PlatformKakaoMap> {
  MethodChannel? _channel;
  bool _ready = false;
  String? _error;
  int _generation = 0;

  void _disposeNative() {
    final channel = _channel;
    _channel = null;
    _ready = false;
    if (channel != null) {
      unawaited(
        channel.invokeMethod<void>('dispose').catchError((Object _) {}),
      );
      channel.setMethodCallHandler(null);
    }
  }

  Future<void> _send(String method, Object? arguments) async {
    if (!_ready || !mounted) return;
    try {
      await _channel?.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? '지도 연결에 실패했습니다.');
    } on MissingPluginException {
      if (mounted) setState(() => _error = '이 환경에서는 네이티브 지도를 사용할 수 없습니다.');
    }
  }

  Future<void> _synchronize({bool camera = false}) async {
    await _send('replaceMarkers', {
      'markers': widget.markers.map((marker) => marker.toMap()).toList(),
    });
    await _send('setMyLocation', widget.myLocation?.toMap());
    if (camera) {
      await _send('moveCamera', {...widget.center.toMap(), 'zoom': 13});
    }
  }

  void _created(int id) {
    _disposeNative();
    _channel = MethodChannel('happy_mountain/map/$id');
    _channel!.setMethodCallHandler((call) async {
      if (!mounted) return;
      final arguments = call.arguments;
      switch (call.method) {
        case 'onReady':
          setState(() {
            _ready = true;
            _error = null;
          });
          await _synchronize(camera: true);
        case 'onCameraIdle':
          if (arguments is Map &&
              arguments['latitude'] is num &&
              arguments['longitude'] is num) {
            widget.onCameraIdle(
              MapPoint(
                (arguments['latitude'] as num).toDouble(),
                (arguments['longitude'] as num).toDouble(),
              ),
            );
          }
        case 'onMarkerTap':
          if (arguments is Map && arguments['id'] is String) {
            widget.onMarkerTap(arguments['id'] as String);
          }
        case 'onError':
          setState(() {
            _error = arguments is Map
                ? arguments['message']?.toString() ?? '지도를 불러오지 못했습니다.'
                : '지도를 불러오지 못했습니다.';
          });
      }
    });
    _channel!.invokeMethod<void>('initialize').catchError((Object error) {
      if (mounted) setState(() => _error = '지도 초기화에 실패했습니다. 다시 연결해 주세요.');
    });
  }

  @override
  void didUpdateWidget(covariant PlatformKakaoMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nativeKey != widget.nativeKey) {
      _disposeNative();
      _error = null;
      _generation++;
    }
    if (_ready) {
      _synchronize(camera: oldWidget.cameraRevision != widget.cameraRevision);
    }
  }

  @override
  void dispose() {
    _disposeNative();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nativeKey.trim().isEmpty) {
      return const MapUnavailable(
        message: '지도 연결 설정이 필요합니다',
        detail: '앱 설치 안내에 따라 연결을 설정해 주세요.\n경보 이력은 아래 탭에서 확인할 수 있습니다.',
      );
    }
    final params = <String, Object>{
      'nativeKey': widget.nativeKey,
      ...widget.center.toMap(),
      'zoom': 13,
    };
    final Widget nativeMap;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      nativeMap = PlatformViewLink(
        key: ValueKey(_generation),
        viewType: 'happy_mountain/map',
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (creation) {
          // Kakao renders into a SurfaceView; hybrid composition preserves it.
          return PlatformViewsService.initExpensiveAndroidView(
              id: creation.id,
              viewType: creation.viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: params,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => creation.onFocusChanged(true),
            )
            ..addOnPlatformViewCreatedListener(creation.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener(_created)
            ..create();
        },
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      nativeMap = UiKitView(
        key: ValueKey(_generation),
        viewType: 'happy_mountain/map',
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
      );
    } else {
      return const MapUnavailable(
        message: '지도는 Android·iPhone에서 열립니다',
        detail: '실제 기기에서 앱을 실행해 주세요.',
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: nativeMap),
        if (!_ready && _error == null)
          const Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Color(0xDDEDF3E9),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        if (_error != null)
          Positioned.fill(
            child: MapUnavailable(
              message: '지도를 불러오지 못했습니다',
              detail: _error!,
              onRetry: () {
                setState(() {
                  _disposeNative();
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
