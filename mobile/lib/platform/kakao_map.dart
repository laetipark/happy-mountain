import 'package:flutter/material.dart';

import 'kakao_map_native.dart'
    if (dart.library.js_interop) 'kakao_map_web.dart'
    as platform;
import 'map_types.dart';

export 'map_types.dart';

/// Fetching, filters and selection stay in Flutter on every platform.
class KakaoMap extends StatelessWidget {
  const KakaoMap({
    super.key,
    required this.nativeKey,
    this.javascriptKey = '',
    required this.center,
    required this.cameraRevision,
    required this.markers,
    required this.onCameraIdle,
    required this.onMarkerTap,
    this.myLocation,
    this.interactionEnabled = true,
  });

  final String nativeKey;
  final String javascriptKey;
  final MapPoint center;
  final int cameraRevision;
  final List<MapPin> markers;
  final MapPoint? myLocation;
  final ValueChanged<MapPoint> onCameraIdle;
  final ValueChanged<String> onMarkerTap;

  /// Disable while a modal route covers the embedded browser map.
  /// Flutter controls above the map must also use PointerInterceptor on web.
  final bool interactionEnabled;

  @override
  Widget build(BuildContext context) => platform.PlatformKakaoMap(
    nativeKey: nativeKey,
    javascriptKey: javascriptKey,
    center: center,
    cameraRevision: cameraRevision,
    markers: markers,
    myLocation: myLocation,
    onCameraIdle: onCameraIdle,
    onMarkerTap: onMarkerTap,
    interactionEnabled: interactionEnabled,
  );
}
