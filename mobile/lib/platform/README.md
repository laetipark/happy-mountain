# Kakao 지도 공통 인터페이스

`kakao_map.dart`는 모델과 공통 위젯을 공개하며 `dart.library.js_interop` 조건으로 브라우저 구현을 선택한다. Android/iOS 구현과 브라우저 구현은 서로의 런타임 라이브러리를 가져오지 않는다.

- 기존 `nativeKey`, `center`, `cameraRevision`, `markers`, `myLocation`, `onCameraIdle`, `onMarkerTap` 계약을 유지한다.
- 웹에서는 `javascriptKey`를 사용한다. JavaScript 키는 공개 클라이언트 식별자이며 REST 키를 여기에 전달하지 않는다. SDK는 HTTPS와 `autoload=false`로 페이지당 한 번 로드된다.
- `cameraRevision`이 바뀔 때만 명시적인 중심 이동을 적용한다. 단순한 데이터/날씨 갱신은 사용자가 이동한 카메라를 되돌리지 않는다. 웹의 초기 확대 수준은 8이다.
- 산은 파란 표식, 경보 이력은 빨간 표식, 현위치는 녹색 원으로 표시한다. 표식 제목은 DOM `textContent`로 설정한다.
- `ResizeObserver`로 DOM 연결과 실제 크기를 확인한 뒤 지도를 만든다. 크기 변경 시 `relayout()` 전후 중심과 확대 수준을 보존한다.
- 웹에서는 지도를 덮는 Flutter 버튼과 패널을 `PointerInterceptor`로 감싼다. 상위 위젯의 `ModalRoute.isCurrentOf(context) ?? true`를 `interactionEnabled`로 전달하면 팝업/대화상자가 뜰 때 DOM 입력·포커스·지도 제스처를 함께 막는다.
- 제거 시 등록한 지도 이벤트, DOM 이벤트와 ResizeObserver를 해제하고 모든 표식을 제거한다. 공식 JavaScript SDK에는 map destroy API가 없으므로 지도 DOM과 Dart 참조도 해제한다.
- 잘못된 키/등록되지 않은 도메인은 스크립트 오류 또는 20초 로드 시간 초과 상태로 표시한다. 공식 SDK에 별도 인증 실패 이벤트는 없다. 로드가 성공한 뒤 키를 바꿨다면 페이지를 새로고침해야 한다.

웹 진입점에는 서비스 워커 등록이나 설치용 manifest가 없다. `flutter_bootstrap.js`는 기본 로더를 시작하고 시작 화면만 제거한다.

공식 근거: [Kakao SDK load·Map·CustomOverlay·event](https://apis.map.kakao.com/web/documentation/), [지도 크기 변경](https://apis.map.kakao.com/web/sample/mapRelayout/), [Flutter HtmlElementView 수명과 포인터 처리](https://api.flutter.dev/flutter/widgets/HtmlElementView-class.html).
