# 산등성이 공통 앱

Flutter 3.47.5 / Dart 3.13.4 기반 Android·iOS·웹 공통 앱입니다. 기존 이름·로고·폰트를 사용하고 지도와 경보 이력을 제공합니다. 웹 실행과 서버 설정은 [웹 안내서](docs/web.md)를 참고하세요.

## 현재 제공 범위

- Android: ARM 기기용 개인 테스트 서명 APK
- 웹: 데스크톱·모바일 브라우저 화면, 같은 출처의 Node.js 중계 서버, 로컬 실행·배포용 패키지
- iOS: 프로젝트·지도 브리지·권한·아이콘·CocoaPods 설정. Windows에서는 Xcode 빌드와 실기기 동작을 검증할 수 없습니다.
- API 키가 없어도 공개 경보 이력을 조회합니다. 지도·산 검색·날씨는 키 설정 안내를 표시하며 가짜 자료로 대체하지 않습니다.
- 경보 이력은 과거에 발표한 예보 자료입니다. 자료 최신일을 표시하고 최신 기록 기준 두 달을 기본 선택합니다.

실제 검증 결과와 남은 실기기 항목은 [검증 기록](docs/verification.md)에 있습니다.

## API 키 설정

`config/example.json`을 `config/local.json`으로 복사하고 다음 값을 넣습니다. `local.json`은 Git에서 제외됩니다.

| 이름 | 값 |
|---|---|
| `KAKAO_NATIVE_APP_KEY` | 카카오 앱의 네이티브 앱 키: 지도 SDK |
| `KAKAO_REST_API_KEY` | 같은 앱의 REST API 키: 산·주소 검색 |
| `WEATHER_API_KEY` | 기상청 단기예보 조회서비스 활용 승인된 인증키 |

카카오 개발자 콘솔에서 카카오맵 사용을 활성화하고 플랫폼을 등록합니다.

- Android 패키지: `com.example.happy_mountain.mobile`
- Android 키 해시: APK 서명 인증서의 SHA-1을 Base64로 인코딩한 값. `scripts/show-key-hash.ps1`로 확인합니다.
- iOS 번들 ID: `com.example.happy-mountain.mobile`

iOS 번들 ID는 밑줄을 사용할 수 없어 Android 패키지와 표기가 다릅니다. 무료 Apple 계정에서 식별자 충돌로 Xcode의 번들 ID를 바꾸면 카카오 iOS 플랫폼 등록도 같은 값으로 갱신해야 합니다.

키는 빌드 시 주입되므로 값을 바꾼 뒤 APK를 다시 빌드해야 합니다. 키 파일을 Git에 넣지 않는 것은 소스 노출 방지이며 앱 바이너리에서 키를 숨기는 수단은 아닙니다. 개인 테스트용 계정·키를 사용하세요.

- [카카오 Android SDK 설정](https://apis.map.kakao.com/android_v2/docs/getting-started/)
- [카카오 iOS SDK 설정](https://apis.map.kakao.com/ios_v2/docs/getting-started/)
- [기상청 단기예보 조회서비스](https://www.data.go.kr/data/15084084/openapi.do)

## Windows에서 Android 빌드

필요한 도구는 Flutter 3.47.5, JDK 17 이상, Android SDK API 36 및 SDK 명령줄 도구입니다. NDK는 Flutter가 지정하는 `28.2.13676358`을 사용합니다. 기존 PC의 SDK 경로는 `D:\Android\Sdk`, JDK 경로는 `C:\Program Files\Android\Android Studio\jbr`입니다.

이번 작업에서 저장소 전용 Flutter를 루트 `.tooling/flutter`에 준비했습니다. 새 환경에서는 Flutter 3.47.5를 설치하거나 `.fvmrc`를 이용해 같은 버전을 선택하세요. `.tooling`과 `.artifacts`는 버전 관리하지 않습니다.

`mobile` 디렉터리에서 PowerShell로 실행합니다.

```powershell
.\scripts\build-android.ps1
```

다른 환경의 경로는 인수로 지정합니다.

```powershell
.\scripts\build-android.ps1 -Flutter 'C:\dev\flutter\bin\flutter.bat' -AndroidSdk 'C:\Android\Sdk' -JavaHome 'C:\Program Files\Java\jdk-17'
```

스크립트는 고정 SDK 버전과 잠금 파일을 확인하고, 처음 실행할 때 개인 테스트 서명키를 생성합니다. 키 설정이 없으면 `config/example.json`으로 빌드하고 명시적으로 알립니다.

결과:

- 저장소 루트 `.artifacts/sandeungseongi-android.apk`
- 원본 빌드 출력 `build/app/outputs/flutter-apk/app-release.apk`

`android/key.properties`와 `android/app/test-signing.jks`는 재빌드·업데이트 설치에 계속 사용하므로 함께 보관하세요. 두 파일은 Git에서 제외됩니다. 이 키는 스토어 출시용 키가 아닌 개인 테스트용입니다.

### Android 설치

Android 7 이상 ARM/ARM64 기기에 APK를 전송하고 설치합니다. 기존 Java 앱과 별도 패키지이므로 함께 설치됩니다. USB 디버깅을 허용한 기기에서는 다음 명령으로 설치할 수 있습니다.

```powershell
& 'D:\Android\Sdk\platform-tools\adb.exe' install -r '..\.artifacts\sandeungseongi-android.apk'
```

카카오 SDK는 ARM 아키텍처를 지원합니다. x86/x64 에뮬레이터는 지도 실기기 검증을 대신할 수 없습니다.

## Mac에서 iOS 준비 및 설치

1. Flutter 3.47.5, 해당 iPhone/iOS 버전을 지원하는 Xcode, CocoaPods를 준비하고 `flutter doctor`를 확인합니다.
2. 동일한 저장소에서 `mobile/config/local.json`을 설정합니다.
3. `mobile`에서 다음을 실행합니다.

```sh
flutter pub get --enforce-lockfile
flutter build ios --debug --no-codesign --dart-define-from-file=config/local.json
open ios/Runner.xcworkspace
```

프로젝트는 CocoaPods를 사용합니다. `pubspec.yaml`에서 Swift Package Manager를 끄고 카카오 SDK 버전을 `ios/Podfile`에 고정했습니다. 최초 Mac 설치 후 생성되는 `Podfile.lock`은 확인하여 함께 커밋하세요.

4. Xcode Settings > Accounts에서 Apple 계정에 로그인합니다. Runner > Signing & Capabilities에서 Personal Team과 자동 서명을 선택합니다. 최소 지원 버전은 iOS 15입니다.
5. iPhone을 연결하고 신뢰 및 Developer Mode를 활성화합니다. 연결한 iPhone을 실행 대상으로 선택합니다.
6. Flutter에서 실제 키가 들어간 앱을 실행합니다.

```sh
flutter run --release --dart-define-from-file=config/local.json
```

무료 Personal Team은 설치 앱 프로비저닝이 7일 후 만료되어 재빌드·재설치가 필요합니다. TestFlight·App Store 배포는 이번 범위에 포함하지 않습니다. [Apple 개인 기기 테스트 안내](https://developer.apple.com/help/account/basics/about-your-developer-account)

## 테스트

`mobile`에서 실행합니다. Windows의 저장소 전용 SDK를 쓸 때 `flutter` 대신 `..\.tooling\flutter\bin\flutter.bat`를 사용합니다.

```sh
flutter analyze
flutter test
```

공개 데이터 원본을 실제로 다운로드하는 검사는 별도 명령입니다. 단위 테스트는 네트워크를 사용하지 않습니다.

```sh
dart run tool/check_history.dart
```

화면, 데이터 계약과 캐시 정책은 [구조 설명](docs/architecture.md), 네이티브 지도 통신은 [지도 연동 설명](docs/native-map.md)을 참고하세요.
