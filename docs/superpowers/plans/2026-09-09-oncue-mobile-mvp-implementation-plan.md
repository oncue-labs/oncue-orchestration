# OnCue 모바일 MVP 구현 계획

> **에이전트 작업자 필수 안내:** 이 계획을 작업별로 실행할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 작업 단계는 추적할 수 있도록 체크박스(`- [ ]`)로 작성되어 있다.

**목표:** 사용자가 제공된 통화 조합 카드를 선택하고 예약하며, 시스템과 비슷한 수신 전화 화면으로 전화를 받고, 인증된 WebRTC 대화를 시작할 수 있는 iOS 우선 Flutter 앱을 구축한다.

**아키텍처:** Flutter UI, 애플리케이션 상태, API client는 플랫폼 공통으로 유지한다. PushKit과 CallKit은 iOS native adapter 뒤에 두고, 나중에 Android가 같은 통화 상태 계약을 구현할 수 있도록 플랫폼 인터페이스를 만든다.

**기술 스택:** Flutter stable, Dart, iOS Swift, CallKit, PushKit, `flutter_webrtc`, HTTPS REST, APNs VoIP Push, unit/widget/integration test.

**사양:** `docs/superpowers/specs/2026-09-08-oncue-mvp-design.md`, `docs/superpowers/specs/2026-09-09-oncue-mvp-api-data-contract.md`

## 전체 제약 조건

- iOS를 먼저 지원하고 Android는 나중에 같은 Dart 도메인 계약 뒤에 구현한다.
- 하드코딩된 MVP 통화 카드에는 DB 숫자 ID가 아니라 `personaKey`와 `scenarioKey`를 사용한다.
- 네 개의 MVP 선택 카드와 로컬 이미지·음성 미리듣기 asset을 사용하며, 관리자 편집 화면과 동적 음성 설정은 만들지 않는다.
- iOS 수신 전화 경험은 CallKit과 PushKit을 사용한다.
- 음성은 WebRTC로 전달하고 백엔드를 거치지 않는다. WebSocket은 WebRTC 시그널링에만 사용한다.
- 백엔드 API에는 사용자 access token을, 보이스 시그널링에는 1회성 연결 토큰을 사용한다.
- 시나리오 컨텍스트 placeholder 하나와 통화 목표 placeholder 하나만 표시한다.
- 예약 시각은 정확한 보장이 아니라 예상 시각으로 표시한다.
- Android UI, 반복 예약, 임의 전화번호 수신자, 사용자 직접 페르소나 생성은 추가하지 않는다.

---

### 작업 1: Flutter 프로젝트 구조와 플랫폼 계약 만들기

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-mobile/pubspec.yaml`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/lib/main.dart`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/lib/common/config/app_config.dart`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/lib/common/auth/auth_session.dart`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/lib/common/call/native_call_platform.dart`
- 테스트: `/Users/yeonny0723/orca/oncue-mobile/test/common/call/native_call_platform_test.dart`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/ios/Runner/OnCueCallKitBridge.swift`

**인터페이스:**
- `NativeCallPlatform.reportIncomingCall(CallPresentation): Future<void>`
- `NativeCallPlatform.endCall(String callId): Future<void>`
- `NativeCallPlatform.onAnswer: Stream<String>`
- `NativeCallPlatform.onEnd: Stream<String>`

- [ ] **단계 1: 플랫폼 계약 테스트 작성**

Dart interface에 answer/end stream이 있고 fake 구현을 widget test에 주입할 수 있는지 검증한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/common/call/native_call_platform_test.dart`

예상 결과: Flutter 프로젝트와 계약이 없으므로 실패한다.

- [ ] **단계 3: Flutter 프로젝트와 플랫폼 interface 생성**

선택한 Flutter stable release와 CallKit/PushKit 구현이 지원하는 최소 iOS 배포 버전을 설정한다. Android 파일은 생성된 stub만 유지한다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `flutter test test/common/call/native_call_platform_test.dart`

예상 결과: 통과한다.

### 작업 2: 인증과 타입이 지정된 백엔드 API client 구현

**파일:**
- 생성: `lib/auth/data/auth_api_client.dart`
- 생성: `lib/auth/application/auth_service.dart`
- 생성: `lib/auth/presentation/login_page.dart`
- 생성: `lib/common/network/api_client.dart`
- 생성: `lib/common/network/api_error.dart`
- 테스트: `test/auth/application/auth_service_test.dart`

**인터페이스:**
- `AuthApiClient.login(String provider, String authorizationCode): Future<AuthSession>`
- `ApiClient.request<T>(ApiRequest<T> request): Future<T>`
- `AuthService.loginWithKakao(): Future<void>`
- `AuthService.loginWithX(): Future<void>`

- [ ] **단계 1: 인증 서비스 테스트 작성**

Kakao/X 로그인 성공, access token 저장, 만료 token 처리, 401 logout, `code`, `message`, `requestId`, `createdAt`을 포함한 공통 오류 해석을 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/auth/application/auth_service_test.dart`

예상 결과: 인증 client와 세션 저장 기능이 없으므로 실패한다.

- [ ] **단계 3: provider 공통 인증과 API transport 구현**

Kakao/X provider 세부 사항은 auth adapter 안에 둔다. 백엔드 access token을 `Authorization: Bearer`에 넣고 보이스 시그널링 요청에는 넣지 않는다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `flutter test test/auth/application/auth_service_test.dart`

예상 결과: 통과한다.

### 작업 3: 하드코딩 MVP 통화 카드와 미리듣기 asset 추가

**파일:**
- 생성: `lib/combination/model/call_combination_card.dart`
- 생성: `lib/combination/data/mvp_call_combinations.dart`
- 생성: `lib/combination/presentation/combination_list_page.dart`
- 생성: `lib/combination/presentation/combination_detail_page.dart`
- 생성: `assets/images/personas/`
- 생성: `assets/audio/previews/`
- 수정: `pubspec.yaml`
- 테스트: `test/combination/presentation/combination_list_page_test.dart`

**인터페이스:**
- `MvpCallCombinations.all: List<CallCombinationCard>`
- 각 카드는 `personaKey`, `scenarioKey`, 제목, 이미지 asset, 미리듣기 음성 asset, 입력 placeholder를 가진다.

- [ ] **단계 1: 네 개 통화 카드 widget test 작성**

네 개 카드가 보이고, 각 카드가 persona key 하나와 scenario key 하나를 가지며, 상세 화면에 시나리오 컨텍스트 placeholder 하나와 통화 목표 placeholder 하나만 있는지 검증한다.

- [ ] **단계 2: widget test 실행 및 실패 확인**

실행: `flutter test test/combination/presentation/combination_list_page_test.dart`

예상 결과: 카드 model과 화면이 없으므로 실패한다.

- [ ] **단계 3: 정적 카드 정의와 asset 추가**

`santa`, `princess`, `friend`, `child-roleplay`, `go-home`, `travel-friend-introduction` 같은 안정적인 key를 사용한다. 이미지는 제품 소유자가 제공한 local asset으로 넣는다.

- [ ] **단계 4: widget test 실행 및 통과 확인**

실행: `flutter test test/combination/presentation/combination_list_page_test.dart`

예상 결과: 통과한다.

### 작업 4: 예약 화면과 API 호출 구현

**파일:**
- 생성: `lib/reservation/model/reservation.dart`
- 생성: `lib/reservation/data/reservation_api_client.dart`
- 생성: `lib/reservation/application/reservation_service.dart`
- 생성: `lib/reservation/presentation/reservation_form_page.dart`
- 생성: `lib/reservation/presentation/reservation_list_page.dart`
- 테스트: `test/reservation/application/reservation_service_test.dart`
- 테스트: `test/reservation/presentation/reservation_form_page_test.dart`

**인터페이스:**
- `ReservationApiClient.create(CreateReservationRequest): Future<Reservation>`
- `ReservationApiClient.update(String reservationId, UpdateReservationRequest): Future<Reservation>`
- `ReservationApiClient.cancel(String reservationId): Future<Reservation>`
- `ReservationService.createFromCard(CallCombinationCard, String context, String goal, DateTime localTime, String timeZone): Future<Reservation>`

- [ ] **단계 1: 요청 매핑과 form 규칙 테스트 작성**

선택 카드가 `personaKey`와 `scenarioKey`로 매핑되는지, 현지 시각과 time zone이 전송되는지, placeholder가 한 번만 표시되는지, 백엔드 안전·마감 오류가 입력값을 지우지 않고 표시되는지 검증한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/reservation/application/reservation_service_test.dart test/reservation/presentation/reservation_form_page_test.dart`

예상 결과: 예약 코드가 없으므로 실패한다.

- [ ] **단계 3: 타입이 지정된 예약 요청과 화면 구현**

기기 time zone과 locale을 사용한다. 예약 시각 근처에 예상 시각 안내를 표시한다. client에서 시나리오 적합성 LLM 검사를 실행하지 않는다.

- [ ] **단계 4: 목록·수정·취소 흐름 구현**

백엔드가 5분 전 마감을 보고하면 수정·취소를 비활성화하고, `reservationStatus`, `callStatus`, `callOutcome`을 서로 구분해 표시한다. `callOutcome`이 비어 있으면 통화 진행 중이고, 값이 있으면 종료된 것으로 표시한다.

- [ ] **단계 5: 테스트 실행 및 통과 확인**

실행: `flutter test test/reservation/application/reservation_service_test.dart test/reservation/presentation/reservation_form_page_test.dart`

예상 결과: 통과한다.

### 작업 5: PushKit과 CallKit 수신 전화 처리 구현

**파일:**
- 수정: `ios/Runner/OnCueCallKitBridge.swift`
- 생성: `ios/Runner/OnCueVoIPPushHandler.swift`
- 생성: `ios/Runner/OnCueCallKitProvider.swift`
- 수정: `ios/Runner/AppDelegate.swift`
- 생성: `lib/call/application/incoming_call_service.dart`
- 테스트: `test/call/application/incoming_call_service_test.dart`

**인터페이스:**
- `IncomingCallService.handleVoipPayload(Map<String, dynamic>): Future<void>`
- Push payload에는 opaque `sessionId` 또는 통화 식별자만 넣고 컨텍스트, 목표, 장기 token은 넣지 않는다.

- [ ] **단계 1: 수신 전화 서비스 테스트 작성**

정상 opaque payload, 잘못된 payload, 중복 Push, CallKit 보고 실패, answer callback, end callback을 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/call/application/incoming_call_service_test.dart`

예상 결과: PushKit과 CallKit bridge가 없으므로 실패한다.

- [ ] **단계 3: native PushKit 등록과 CallKit 보고 구현**

VoIP push entitlement를 설정하고 device token을 등록한다. 수신 전화를 지체 없이 보고하며 선택된 페르소나가 보이는 이름과 일치시킨다.

- [ ] **단계 4: answer/end callback을 Dart로 전달**

opaque session ID를 Dart로 내보낸다. 사용자가 응답하기 전에는 연결 token을 요청하지 않는다.

- [ ] **단계 5: 테스트와 iOS simulator smoke check 실행**

실행: `flutter test test/call/application/incoming_call_service_test.dart` 및 `flutter build ios --no-codesign`

예상 결과: 테스트와 iOS build가 통과한다.

### 작업 6: 연결 token 조회와 WebRTC client 구현

**파일:**
- 생성: `lib/call/data/call_session_api_client.dart`
- 생성: `lib/call/application/call_connection_service.dart`
- 생성: `lib/call/data/webrtc_client.dart`
- 생성: `lib/call/presentation/in_call_page.dart`
- 테스트: `test/call/application/call_connection_service_test.dart`
- 테스트: `test/call/data/webrtc_client_test.dart`

**인터페이스:**
- `CallSessionApiClient.issueConnectionToken(String callSessionId): Future<ConnectionToken>`
- `WebRtcClient.connect(ConnectionToken token): Future<void>`는 token의 `signalingUrl`과 `iceServers`를 사용해 WebSocket 시그널링 후 WebRTC 음성 연결을 시작한다.
- `WebRtcClient.close(String reason): Future<void>`

- [ ] **단계 1: 연결 흐름 테스트 작성**

answer → token 요청 → token 만료 → WebSocket signaling offer → answer/ICE candidate 교환 → WebRTC connected 상태, 잘못된 token, WebRTC 실패를 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/call/application/call_connection_service_test.dart test/call/data/webrtc_client_test.dart`

예상 결과: 연결과 WebRTC 코드가 없으므로 실패한다.

- [ ] **단계 3: token 조회와 ICE 설정 구현**

token 요청에는 백엔드 access token만 사용한다. 반환된 1회성 연결 token, `signalingUrl`, STUN/TURN 설정을 `flutter_webrtc`와 WebSocket signaling에 전달한다. WebSocket으로 음성 데이터를 전송하지 않는다.

- [ ] **단계 4: 통화 화면 구현**

페르소나 식별 정보, 경과 시간, 통화 종료, 연결 실패를 표시한다. transcript는 표시하거나 저장하지 않는다.

- [ ] **단계 5: 테스트와 실제 기기 WebRTC 확인**

실행: `flutter test test/call/application/call_connection_service_test.dart test/call/data/webrtc_client_test.dart` 및 TURN 설정이 있는 iPhone에서 테스트한다.

예상 결과: 인증된 음성 연결이 `oncue-voice`에 연결된다.

### 작업 7: 상태 기반 화면 전환·다국어·최종 검증 추가

**파일:**
- 생성: `lib/call/model/call_state.dart`
- 생성: `lib/call/application/call_state_controller.dart`
- 생성: `lib/l10n/app_ko.arb`
- 생성: `lib/l10n/app_en.arb`
- 테스트: `test/call/application/call_state_controller_test.dart`
- 생성: `integration_test/oncue_mvp_flow_test.dart`

**인터페이스:**
- `CallStateController#apply(CallEvent): CallState`
- `CallState`는 `callStatus`와 `callOutcome`을 제공한다. 통화 종료 뒤에도 `callStatus`에는 마지막 진행 단계를 유지한다.

- [ ] **단계 1: 상태 controller 테스트 작성**

모든 합법적 전이, 종료 상태의 멱등성, 미수신, 연결 실패, 사용자 종료, 안전 차단, 시간 제한을 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/call/application/call_state_controller_test.dart`

예상 결과: 상태 controller가 없으므로 실패한다.

- [ ] **단계 3: 상태 기반 UI와 한국어·영어 문구 구현**

기기 언어가 한국어이면 한국어를 사용하고, 그 외에는 영어를 사용한다. 승인된 계약의 예상 시각 안내와 안전 오류 문구를 사용한다.

- [ ] **단계 4: 전체 Flutter 검증 실행**

실행: `flutter test` 및 `flutter build ios --no-codesign`

예상 결과: 통과한다.
