# 산등성이 웹 테스트 서버

Node.js 22.22.0 이상에서 실행하는 의존성 없는 서버입니다. `.node-version`에 검증한 버전을 기록했습니다. Flutter 웹 빌드와 API를 같은 origin에서 제공합니다. Android/iOS 앱의 직접 API 연결에는 이 서버가 필요하지 않습니다.

## 실행

먼저 `mobile/`에서 Flutter 웹 빌드를 만듭니다. 저장소 루트 기준 예시는 다음과 같습니다.

```powershell
Set-Location mobile
flutter build web --release --base-href /
Set-Location ../server
Copy-Item .env.example .env.local
# .env.local에 발급받은 키 입력
npm start
```

`npm install`은 필요하지 않습니다. 브라우저에서 `http://localhost:8080`을 엽니다. 명시적으로 실행하려면 `server/`에서 아래 명령을 사용합니다.

```powershell
node --env-file-if-exists=.env.local src/index.mjs
```

기본 수신 주소는 `127.0.0.1:8080`, 정적 파일 경로는 `../mobile/build/web`입니다. `HOST`, `PORT`, `STATIC_ROOT`로 변경할 수 있습니다. 상대 `STATIC_ROOT`는 항상 `server/` 기준입니다. 웹 앱은 도메인 루트(`/`)에 배치합니다.

## 키 설정

- `KAKAO_JAVASCRIPT_APP_KEY`: 지도 JavaScript 앱 키. 브라우저에 전달되는 공개 키이므로 Kakao 개발자 설정에 `http://localhost:8080` 등 실제 웹 도메인을 등록합니다.
- `KAKAO_REST_API_KEY`: 장소/주소 검색용 REST 키. 서버에만 보관합니다.
- `WEATHER_API_KEY`: 기상청 단기예보 서비스 키. 일반 키와 퍼센트 인코딩된 키를 모두 받습니다.

비공개 키를 Flutter 웹 빌드의 define이나 정적 JSON에 넣지 마세요. `.env.local`과 기타 `.env*`는 Git에서 제외하며 `.env.example`만 추적합니다. `/api/config`는 공개 지도 키와 기능 사용 가능 여부만 반환합니다. 키가 없는 장소/날씨 기능은 503 오류를 반환하고, 경보 이력은 키 없이 사용할 수 있습니다.

## API 계약

| GET 경로 | 요청 | 응답 |
| --- | --- | --- |
| `/api/config` | 없음 | `{kakaoJavascriptKey, placesEnabled, weatherEnabled}` |
| `/api/places/mountains` | `x`, `y`, `page=1..3`(기본 1) | Kakao 원본 JSON. 검색어 `산`, AT4, 반경 10km, 거리순, 15개 고정 |
| `/api/places/address` | `query`(최대 200자) | Kakao 주소 검색 원본 JSON |
| `/api/weather` | `nx`, `ny`, `base_date=yyyyMMdd`, `base_time=HHmm` | 기상청 단기예보 원본 JSON, 1페이지·1,000행 고정 |
| `/api/history` | 선택 `forceRefresh=true` | 원본 CSV bytes, 선택 `X-Data-Modified-At` ISO 시각 헤더 |

경보 CSV는 [공공데이터포털 상세 페이지](https://www.data.go.kr/data/15092027/fileData.do)의 JSON-LD에서 CSV 다운로드 주소를 찾습니다. 전송 헤더의 UTF-8 표기를 신뢰해 변환하지 않고 원본 바이트를 그대로 반환하므로 클라이언트에서 CP949/EUC-KR로 해석해야 합니다. 서버 메모리에 한국 시간(KST) 달력 날짜 단위로 캐시하고 동시 조회를 합칩니다. 자정을 넘으면 다음 조회에서 새로 다운로드합니다. 강제 새로고침은 캐시를 건너뛰되 진행 중 요청은 공유합니다. 실패한 갱신이 기존 캐시를 덮어쓰지는 않으며, 실패한 요청에는 이전 자료 대신 오류를 반환합니다.

오류 형식은 `{ "error": { "code": "…", "message": "한국어 안내" } }`입니다. 잘못된 입력 400, 인증 401, 권한 403, 미존재 404, 메서드 405, 조회 한도 429, 공급자 실패 502, 키 미설정 503, 25초 시간 초과 504를 구분합니다. upstream 원문 오류나 비공개 키, 검색 주소, 요청 URL은 로그/오류 응답에 넣지 않습니다. 정상 upstream JSON 자체의 기상청 결과코드는 클라이언트에서 해석합니다.

## 검증

```powershell
npm test
```

기본 테스트는 mock upstream만 사용해 외부 네트워크·실제 키 없이 실행됩니다. 설정 노출, 고정 upstream 인자, 입력 검증, CSV 원본 유지, JSON-LD 변경, 캐시/동시 요청, 인증/한도/timeout, redirect 호스트 제한, 정적 경로 탈출과 dotfile 차단을 확인합니다.

공공 CSV의 실제 다운로드는 선택적으로 실행합니다. 키가 필요하지 않으며 약 2.5MB 이상의 공개 데이터를 읽습니다.

```powershell
$env:RUN_LIVE_HISTORY_TEST='1'
npm run test:live
Remove-Item Env:RUN_LIVE_HISTORY_TEST
```

## 로컬/개인 테스트 운영

HTTPS 환경에서 사용할 때 reverse proxy가 도메인 루트의 `/`와 `/api/`를 모두 이 Node 서버로 전달하도록 설정합니다. API를 별도 공개 origin으로 분리할 필요가 없습니다. 필요한 도메인을 Kakao 웹 플랫폼 설정에 등록합니다. 이 변경은 서버나 도메인을 자동 배포하지 않으며 PWA 설치/서비스워커를 추가하지 않습니다.

이 서버는 접근 인증이나 사용자별 rate limit이 없는 개인 테스트용입니다. 인터넷에 공개하기 전에는 reverse proxy에서 접근 제어와 요청 한도를 설정해야 합니다. upstream은 고정 API 및 공공데이터포털 HTTPS 호스트로 제한하고 redirect도 검사하지만, 공개된 조회 경로는 API quota를 사용할 수 있습니다. API URL 쿼리에 위치가 포함되므로 reverse proxy access log에도 전체 요청 URI를 남기지 않는 구성을 사용합니다.

경보 자료는 월별 공개 **이력**입니다. 다운로드 성공이나 해당 기간 0건을 현재 산불 위험 없음으로 해석하지 마세요. 공개 파일의 자료 기준일과 실제 최신 예보일시를 앱에서 표시해야 합니다.
