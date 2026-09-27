import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Only the official public SDK surface is used here.
// https://apis.map.kakao.com/web/documentation/
@JS('kakao')
external JSObject? get _kakao;

@JS('kakao.maps.load')
external void _loadMaps(JSFunction callback);

@JS('kakao.maps.LatLng')
extension type KakaoLatLng._(JSObject _) implements JSObject {
  external KakaoLatLng(double latitude, double longitude);
  external double getLat();
  external double getLng();
}

extension type KakaoMapOptions._(JSObject _) implements JSObject {
  external KakaoMapOptions({
    required KakaoLatLng center,
    required int level,
    required bool draggable,
    required bool scrollwheel,
  });
}

@JS('kakao.maps.Map')
extension type KakaoJsMap._(JSObject _) implements JSObject {
  external KakaoJsMap(web.HTMLElement container, KakaoMapOptions options);
  external KakaoLatLng getCenter();
  external void setCenter(KakaoLatLng center);
  external int getLevel();
  external void setLevel(int level);
  external void relayout();
  external void setDraggable(bool enabled);
  external void setZoomable(bool enabled);
}

extension type KakaoOverlayOptions._(JSObject _) implements JSObject {
  external KakaoOverlayOptions({
    required KakaoJsMap map,
    required KakaoLatLng position,
    required web.HTMLElement content,
    required double xAnchor,
    required double yAnchor,
    required int zIndex,
    required bool clickable,
  });
}

@JS('kakao.maps.CustomOverlay')
extension type KakaoJsOverlay._(JSObject _) implements JSObject {
  external KakaoJsOverlay(KakaoOverlayOptions options);
  external void setMap(KakaoJsMap? map);
  external void setPosition(KakaoLatLng position);
}

@JS('kakao.maps.event.addListener')
external void addKakaoListener(
  JSObject target,
  String event,
  JSFunction handler,
);

@JS('kakao.maps.event.removeListener')
external void removeKakaoListener(
  JSObject target,
  String event,
  JSFunction handler,
);

@JS('kakao.maps.event.preventMap')
external void preventKakaoMapEvent();

/// The SDK is shared by all platform views and loaded once per page.
/// A failed script can be retried; changing an already loaded key needs a reload.
class KakaoWebSdk {
  static Future<void>? _pending;
  static String? _key;

  static Future<void> load(String key) {
    if (_pending != null) {
      if (_key != key) {
        return Future.error(
          const KakaoWebException('지도 설정이 변경되었습니다. 페이지를 새로고침해 주세요.'),
        );
      }
      return _pending!;
    }
    _key = key;
    final completion = Completer<void>();
    _pending = completion.future;
    final script = web.HTMLScriptElement()
      ..id = 'happy-mountain-kakao-sdk'
      ..async = true
      ..src = Uri.https('dapi.kakao.com', '/v2/maps/sdk.js', {
        'appkey': key,
        'autoload': 'false',
      }).toString();
    Timer? timeout;
    void finish([String? message]) {
      if (completion.isCompleted) return;
      timeout?.cancel();
      script.onload = null;
      script.onerror = null;
      if (message == null) {
        completion.complete();
      } else {
        script.remove();
        _pending = null;
        _key = null;
        completion.completeError(KakaoWebException(message));
      }
    }

    script.onload = ((web.Event event) {
      if (completion.isCompleted) return;
      try {
        if (_kakao == null) {
          finish('지도 인증에 실패했습니다. JavaScript 키와 등록된 웹 주소를 확인해 주세요.');
          return;
        }
        _loadMaps((() => finish()).toJS);
      } catch (_) {
        finish('지도 인증에 실패했습니다. JavaScript 키와 등록된 웹 주소를 확인해 주세요.');
      }
    }).toJS;
    script.onerror = ((web.Event event) {
      finish('지도를 연결하지 못했습니다. 인터넷 연결과 지도 키·웹 주소 등록을 확인해 주세요.');
    }).toJS;
    timeout = Timer(const Duration(seconds: 20), () {
      finish('지도 연결 시간이 초과되었습니다. 인터넷 연결과 지도 키·웹 주소 등록을 확인해 주세요.');
    });
    web.document.head!.appendChild(script);
    return completion.future;
  }
}

class KakaoWebException implements Exception {
  const KakaoWebException(this.message);
  final String message;
}
