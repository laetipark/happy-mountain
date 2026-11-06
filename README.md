# 산등성이

![산등성이 아이콘과 프로젝트명을 배치한 소개 배너](docs/images/project-banner.png)

Flutter 공통 앱은 [`mobile/`](mobile/README.md)에 있습니다. Android 개인 테스트용 APK, iOS 프로젝트, 브라우저용 웹판을 함께 관리합니다.

구형 Java Android 프로젝트는 정리했습니다. 로고 원본과 API 참고 문서는 `docs/`에 보존했습니다. 앱은 `mobile/`에서 빌드하고 웹 데이터 중계 서버는 `server/`에서 실행합니다.

- 지도: 주변 산, 현재 위치, 기상청 예보
- 경보 이력: 산림청 대형산불위험예보 공개 이력, 기간·지역 필터
- 기본 지원: Android 7(API 24)+, iOS 15+
- 도구 버전: Flutter 3.47.5 / Dart 3.13.4

웹은 키 없이 공개 경보 이력을 조회할 수 있습니다. 로컬 실행은 저장소 루트에서 다음 순서로 진행합니다.

```powershell
./mobile/scripts/build-web.ps1
./mobile/scripts/serve-web.ps1
```

[로컬 웹 열기](http://localhost:8080) · [웹 실행·배포 안내](mobile/docs/web.md) · [모바일 설치·키 설정](mobile/README.md) · [검증 결과](mobile/docs/verification.md)
