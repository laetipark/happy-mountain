# 산등성이 웹 실행 안내

Android·iOS와 같은 Flutter 화면과 자료 처리 로직을 사용합니다. 넓은 브라우저에서는 지도와 경보 이력을 함께 표시하고, 작은 화면에서는 두 탭으로 전환합니다. 웹에는 요청 중계용 Node.js 서버가 필요합니다.

## 로컬에서 실행

필요한 도구: Flutter 3.47.5 / Dart 3.13.4, Node.js 22.22.0 이상(22 계열 권장), Chrome 또는 Edge.

저장소 루트에서 PowerShell로 실행합니다.

```powershell
./mobile/scripts/build-web.ps1
./mobile/scripts/serve-web.ps1
```

[산등성이 로컬 웹](http://localhost:8080)을 엽니다. 서버를 종료하려면 실행한 터미널에서 Ctrl+C를 누릅니다. 다른 포트는 `serve-web.ps1 -Port 8081`로 지정합니다. 해당 주소도 카카오에 등록해야 합니다.

키 없이도 공개 경보 이력을 조회할 수 있습니다. 지도·산 검색·날씨에는 설정 안내가 표시됩니다. 웹 첫 방문에는 위치 권한을 요청하지 않으며, ‘내 위치로 이동’을 누를 때 요청합니다. 거부하면 서울 중심에서 탐색을 계속할 수 있습니다.

## 나중에 API 키 설정

`server/.env.example`을 `server/.env.local`로 복사하고 다음 세 값을 설정한 뒤 서버를 재시작합니다. `.env.local`은 Git과 배포 패키지에서 제외됩니다.

| 설정 | 사용처 |
| --- | --- |
| `KAKAO_JAVASCRIPT_APP_KEY` | 웹 지도. 브라우저에 공개되는 JavaScript 키 |
| `KAKAO_REST_API_KEY` | 서버의 산·주소 검색 |
| `WEATHER_API_KEY` | 서버의 기상청 단기예보 조회 |

카카오 개발자 콘솔에서 카카오맵 사용을 활성화하고 JavaScript SDK 도메인에 `http://localhost:8080`과 실제 배포 주소를 등록합니다. JavaScript 키는 모바일 네이티브 키와 다릅니다. [카카오 지도 공식 설정 안내](https://apis.map.kakao.com/web/guide/)

서버의 `/api/config`는 지도 JavaScript 키와 기능 사용 가능 여부만 반환합니다. REST·기상청 키를 Flutter 웹 빌드에 넣지 마세요. 모바일의 `config/local.json`은 Android·iOS 빌드에서만 사용합니다.

## 배포용 패키지

빌드 스크립트는 `.artifacts/sandeungseongi-web.zip`을 생성합니다. 압축을 풀면 `server`와 `mobile/build/web`이 포함됩니다. Flutter 설치 없이 Node.js만으로 실행할 수 있습니다.

```powershell
cd server
node --env-file-if-exists=.env.local src/index.mjs
```

외부 공개 시에는 HTTPS 리버스 프록시 뒤에 서버를 두고 사이트 루트(`/`)와 `/api/*`를 같은 출처로 연결합니다. 서버 기본 바인딩은 로컬 컴퓨터이며, 컨테이너 등에서 필요한 경우 `HOST`를 별도로 지정합니다. 이 작업에서는 공개 서버에 배포하지 않습니다.

정적 파일만 올리는 호스팅으로는 경보 이력을 조회할 수 없습니다. 서버가 공공데이터포털의 CSV 주소를 찾아 원본 바이트를 중계해야 합니다. 키나 개인 설정을 정적 파일 디렉터리에 복사하지 마세요.

기존 웹 배포를 교체할 때는 새 빌드 파일 전체를 함께 교체합니다. 서버 설정만 바뀌면 웹을 다시 빌드할 필요 없이 서버 재시작과 브라우저 새로고침으로 반영됩니다.

## 캐시·위치·지원 범위

- 경보 자료는 브라우저 IndexedDB에 저장하고 한국 날짜 기준 하루마다 또는 수동 새로고침으로 갱신합니다. 실패하면 기존 자료와 실패 상태를 표시합니다.
- 저장이 차단되거나 용량이 부족해도 현재 조회는 계속됩니다. 브라우저 데이터를 삭제하면 캐시도 지워집니다.
- 현위치는 HTTPS 또는 localhost에서 사용합니다. 다른 기기가 PC의 LAN 주소로 접속하는 일반 HTTP 환경에서는 위치 권한을 사용할 수 없습니다.
- PWA 설치와 오프라인 앱 실행은 제공하지 않습니다. 이미 열린 앱에서 갱신 실패 시 캐시를 표시하는 기능과 별개입니다.
- iPhone Safari와 실제 지도·날씨 연동은 기기와 API 키 준비 후 검증합니다. 자세한 결과는 검증 기록을 참고하세요.

## 자동 검사

`mobile`에서 `flutter analyze`, `flutter test`를 실행합니다. 브라우저 전용 검사는 Chrome을 설치하고 다음을 실행합니다.

```powershell
flutter test --platform chrome test/data_cache_web_test.dart test/data_gateway_test.dart test/data_history_test.dart test/data_places_test.dart test/data_weather_test.dart test/web_app_test.dart test/kakao_web_adapter_test.dart
```

서버 검사는 `server`에서 `npm test`로 실행합니다. 테스트의 모의 지도·위치·날씨 응답은 테스트에만 사용하며 배포 앱에는 넣지 않습니다.

Flutter 3.47.5의 Windows 브라우저 테스트 도구에서 CanvasKit 경로 구분자 문제를 확인했습니다. 이 환경에서는 SDK의 `packages/flutter_tools/lib/src/test/flutter_web_platform.dart` 안 `_localCanvasKitHandler`에서 `_fileSystem.path.fromUri(request.url)`을 `request.url.path`로 바꿔 해결했습니다. 이는 테스트 서버의 URL 경로 처리만 보정하며 앱 소스·배포 산출물에는 영향을 주지 않습니다. 원본 SDK 파일과 도구 캐시는 저장소의 `.tooling/flutter-test-workaround`에 보존했습니다. 새 Windows 환경에서도 동일한 404가 발생하면 이 보정 후 Flutter 도구 캐시를 재생성해야 합니다. Flutter SDK를 바꾸기보다 원인과 보정 내용을 확인하세요.
