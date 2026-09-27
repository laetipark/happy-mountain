# 네이티브 지도 연결

Flutter Platform View `happy_mountain/map`이 Android의 Kakao `MapView`와 iOS의 `KMViewContainer`를 직접 사용한다. 지도 로딩·인증은 네이티브 SDK가 담당하고, 장소 검색·경보 자료·위치 권한은 Dart 서비스가 담당한다.

## 고정 SDK와 앱 등록

- Android: `com.kakao.maps.open:android:2.15.2`, Maven 저장소 `https://devrepo.kakao.com/nexus/repository/kakaomap-releases/`. 최소 API 24. SDK가 ARM만 제공하므로 `armeabi-v7a`, `arm64-v8a`로 빌드한다. x86 에뮬레이터에서는 지도 검증을 하지 않는다.
- iOS: `pod 'KakaoMapsSDK', '2.12.19'`, `use_frameworks!`, deployment target iOS 15.0. `HappyMountainMapFactory.swift`를 Runner target의 Compile Sources에 포함한다. Windows에서는 iOS 컴파일·서명·실기기 동작을 검증할 수 없다.
- 카카오 개발자 콘솔에서 Android 패키지 `com.example.happy_mountain.mobile`와 APK 서명의 키 해시, iOS 번들 ID `com.example.happy-mountain.mobile`를 등록한다. iOS는 밑줄을 허용하지 않으므로 하이픈을 사용한다. 두 플랫폼에 지도 사용 권한이 활성화되어 있어야 한다.
- 지도 팩토리는 생성 인자의 `nativeKey`로 SDK를 초기화한다. AppDelegate나 Application에 별도 키를 하드코딩하지 않는다.
- Android 코드 축소를 적용할 경우 `-keep class com.kakao.vectormap.** { *; }`와 `-keep interface com.kakao.vectormap.**`를 유지한다.

## 등록 코드

Android `MainActivity.configureFlutterEngine`에서 `super.configureFlutterEngine(flutterEngine)` 다음에 등록한다.

```kotlin
flutterEngine.platformViewsController.registry.registerViewFactory(
    "happy_mountain/map",
    HappyMountainMapFactory(this, flutterEngine.dartExecutor.binaryMessenger),
)
```

iOS에서 Flutter plugin registrar를 얻어 다음과 같이 등록한다.

```swift
registrar.register(
    HappyMountainMapFactory(messenger: registrar.messenger()),
    withId: "happy_mountain/map"
)
```

## 채널 계약

생성 인자는 `{nativeKey, latitude, longitude, zoom}`이다. 기본 좌표는 서울 시청 `37.5665, 126.9780`, 기본 줌은 13이다. 줌은 SDK 공통 범위 6~21로 제한한다. View ID마다 독립적인 `happy_mountain/map/<id>` MethodChannel을 사용한다.

| Dart → Native | 인자 | 동작 |
|---|---|---|
| `initialize` | 없음 | Dart 이벤트 핸들러를 먼저 설치한 뒤 호출한다. SDK 초기화를 시작한다. |
| `moveCamera` | `{latitude, longitude, zoom?}` | 중심을 이동한다. 준비 전이면 최신 목표 좌표를 기억한다. |
| `setMyLocation` | `{latitude, longitude}` 또는 `null` | 초록 원형 현위치 표식을 표시하거나 지운다. 카메라는 이동하지 않는다. |
| `replaceMarkers` | `{markers: [{id, latitude, longitude, title, kind}]}` | 목록 전체를 교체한다. `history`는 빨강, 나머지는 파랑이다. |
| `dispose` | 없음 | 네이티브 자원을 즉시 해제한다. 플랫폼의 자체 해제에서도 같은 정리 로직을 실행한다. |

| Native → Dart | 인자 |
|---|---|
| `onReady` | `null` |
| `onCameraIdle` | `{latitude, longitude}` |
| `onMarkerTap` | `{id}` |
| `onError` | `{message}` |

`initialize`의 성공 응답은 시작 요청을 접수했다는 의미다. 지도 사용 가능 여부는 `onReady`, 인증·엔진 오류는 `onError`로 판단한다. 인증 실패 후 재시도는 Platform View를 새 키로 재생성한다. SDK 원문 오류에 인증 정보가 섞일 가능성을 피하기 위해 사용자 안내문과 iOS 오류 코드만 전달한다.

Android는 화면을 소유한 Activity의 resume/pause/destroy를 관찰하여 `resume`, `pause`, `finish`를 호출한다. iOS는 앱 활성화/비활성화 알림에서 `activateEngine`, `pauseEngine`을 호출하고 해제 시 `resetEngine`을 실행한다. 지도 표식과 현위치 표식은 서로 다른 레이어에 둬 한쪽 갱신이 다른 쪽을 지우지 않는다. 경보·산 표식의 제목이 지도에 표시된다.

## 검증 항목

실기기에서 올바른 등록 키로 지도 표시, 잘못된 키의 오류 안내, 각 색상 표식·제목 표시와 탭 이벤트, 현위치 이동, 빠른 표식 갱신, 홈 이동 후 복귀, 회전·크기 변경, 지도 화면 재생성을 확인한다. Android APK 컴파일 성공은 인증 성공이나 ARM 실기기 렌더링 성공을 대신하지 않는다. iOS는 Mac에서 `pod install` 후 Runner workspace를 빌드해야 컴파일 확인이 완료된다.

## 확인한 공식 문서

- [Android 시작·버전·생명주기](https://apis.map.kakao.com/android_v2/docs/getting-started/quickstart/)
- [Android SDK 요구사양](https://apis.map.kakao.com/android_v2/docs/getting-started/)
- [Android Label](https://apis.map.kakao.com/android_v2/docs/api-guide/label/label/)
- [iOS 배포 버전](https://apis.map.kakao.com/ios_v2/news/)
- [iOS 설치](https://apis.map.kakao.com/ios_v2/docs/getting-started/gettingstarted/)
- [iOS 생명주기](https://apis.map.kakao.com/ios_v2/docs/getting-started/basics/01_view/)
- [iOS 지도](https://apis.map.kakao.com/ios_v2/docs/map/01_kakaomap/)
- [iOS 카메라](https://apis.map.kakao.com/ios_v2/docs/map/03_camera/)
- [iOS 화면 중심 좌표 변환 예시](https://apis.map.kakao.com/ios_v2/docs/roadview/01_roadview/)
- [iOS 표식](https://apis.map.kakao.com/ios_v2/docs/map/04_label/02_poi/)
- [iOS 이벤트 시그니처](https://apis.map.kakao.com/ios_v2/references/Protocols/KakaoMapEventDelegate.html)
- [iOS 엔진 시그니처](https://apis.map.kakao.com/ios_v2/references/Classes/KMController.html)

Android 2.15.2 AAR의 `classes.jar`를 `javap`로 확인했다. 공식 레퍼런스의 일부 예시와 달리 `OnLabelClickListener`는 `Boolean`을 반환하며, `LabelOptions.setTexts`는 `LabelTextBuilder`를 받는다. 구현은 실제 배포 바이너리의 시그니처를 따른다.

공식 iOS API 레퍼런스의 머리말은 2.12.0이다. 2.12.19 릴리스 공지·변경 이력 및 공식 배포 `.swiftinterface`, `KMController.h`, `KMViewContainer.h`와 대조했다. 현재 바이너리의 `PoiTextStyle(textLineStyles:)`와 `textLayouts`를 사용한다. 확인한 인터페이스의 빌드 컴파일러는 Apple Swift 6.3.3이므로 Mac에서는 최신 호환 Xcode를 사용한다. 이 검토는 실제 iOS 컴파일·링크·실기기 검증을 대신하지 않는다.
