# OnCue 모바일 MVP 구현 계획

> **에이전트 작업자 필수 안내:** 이 계획을 작업별로 실행할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 작업 단계는 추적할 수 있도록 체크박스(`- [ ]`)로 작성되어 있다.

**목표:** 사용자가 제공된 통화 조합 카드를 선택하고 예약하며, 시스템과 비슷한 수신 전화 화면으로 전화를 받고, 인증된 WebRTC 대화를 시작할 수 있는 iOS 우선 Flutter 앱을 구축한다.

**아키텍처:** Flutter UI, 애플리케이션 상태, API client는 플랫폼 공통으로 유지한다. iOS CallKit과 Android system-managed Telecom은 `SystemCallManager` 플랫폼 adapter 뒤에 두고, 두 OS가 같은 통화 상태 계약을 구현하도록 한다. 백엔드·보이스 서버 통신과 WebRTC 연결은 별도의 `VoiceCallService`가 담당한다.

**기술 스택:** Flutter stable, Dart, iOS Swift, PushKit·CallKit bridge, `flutter_webrtc`, HTTPS REST, unit/widget/integration test. APNs VoIP Push는 MVP에 포함한다.

**사양:** `docs/superpowers/specs/2026-09-08-oncue-mvp-design.md`, `docs/superpowers/specs/2026-09-09-oncue-mvp-api-data-contract.md`

## 전체 제약 조건

- iOS를 먼저 지원하고 Android는 나중에 같은 Dart 도메인 계약 뒤에 구현한다.
- 하드코딩된 MVP 통화 카드에는 DB 숫자 ID가 아니라 `personaKey`와 `scenarioKey`를 사용한다.
- 네 개의 MVP 선택 카드와 로컬 이미지·음성 미리듣기 asset을 사용하며, 관리자 편집 화면과 동적 음성 설정은 만들지 않는다.
- MVP에서는 iOS 예약 시각 자동 수신 알림을 PushKit과 CallKit으로 구현한다. Android는 후속 범위에서 FCM과 system-managed Telecom을 사용한다.
- 음성은 WebRTC로 전달하고 백엔드를 거치지 않는다. WebSocket은 WebRTC 시그널링에만 사용한다.
- 백엔드 API에는 사용자 access token을, 보이스 시그널링에는 1회성 연결 토큰을 사용한다.
- 시나리오 컨텍스트 placeholder 하나와 통화 목표 placeholder 하나만 표시한다.
- 예약 시각은 정확한 보장이 아니라 예상 시각으로 표시한다.
- 예약 API를 호출하기 전에 플랫폼별 필수 통화 권한과 통화 기능 설정을 확인한다. 준비되지 않았으면 예약을 막고 권한 안내 화면으로 이동한다.
- Foreground 수신 알림용 WebSocket, 주기 조회, 앱 타이머와 앱 재개 후 수신 복구 조회는 MVP에서 구현하지 않는다.
- Android UI, 반복 예약, 임의 전화번호 수신자, 사용자 직접 페르소나 생성은 추가하지 않는다.

---

### 작업 1: Flutter 프로젝트 구조와 플랫폼 계약 만들기

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-mobile/pubspec.yaml`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/lib/main.dart`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/lib/common/config/app_config.dart`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/lib/common/auth/auth_session.dart`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/lib/common/call/system_call_manager.dart`
- 테스트: `/Users/yeonny0723/orca/oncue-mobile/test/common/call/system_call_manager_test.dart`
- 생성: `/Users/yeonny0723/orca/oncue-mobile/ios/Runner/OnCueCallKitBridge.swift`

**인터페이스:**
- `SystemCallManager.presentIncomingCall(IncomingCallDisplayInfo): Future<void>`
- `SystemCallManager.endCall(String callSessionId): Future<void>`
- `SystemCallManager.answerSucceeded(String callSessionId): Future<void>`
- `SystemCallManager.answerFailed(String callSessionId): Future<void>`
- `SystemCallManager.onAnswered: Stream<String>`
- `SystemCallManager.onRejected: Stream<String>`
- `SystemCallManager.onEnded: Stream<String>`
- `IncomingCallDisplayInfo`는 `callSessionId`, `displayName`, `callType`을 가진다.

- [ ] **단계 1: 시스템 통화 관리자 계약 테스트 작성**

Dart 공통 계약이 수신 전화를 OS에 등록하고, answer/reject/end 이벤트를 `callSessionId`와 함께 전달하며, 연결 성공·실패 결과를 OS에 반영하고, fake 구현을 widget test에 주입할 수 있는지 검증한다. 이 계약은 보이스 서버 통신을 포함하지 않는다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/common/call/system_call_manager_test.dart`

예상 결과: Flutter 프로젝트와 계약이 없으므로 실패한다.

- [ ] **단계 3: Flutter 프로젝트와 플랫폼 interface 생성**

선택한 Flutter stable release와 CallKit/PushKit 구현이 지원하는 최소 iOS 배포 버전을 설정한다. Android 파일은 생성된 stub만 유지한다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `flutter test test/common/call/system_call_manager_test.dart`

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
- `AuthApiClient.login(AuthLoginRequest): Future<AuthSession>`
- `ApiClient.request<T>(ApiRequest<T> request): Future<T>`
- `AuthService.loginWithKakao(): Future<void>`
- `AuthService.loginWithX(): Future<void>`

- [ ] **단계 1: 인증 서비스 테스트 작성**

Kakao/X 로그인 성공, access token 저장, 만료 token 처리, 401 logout, `code`, `message`, `requestId`, `createdAt`을 포함한 공통 오류 해석을 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/auth/application/auth_service_test.dart`

예상 결과: 인증 client와 세션 저장 기능이 없으므로 실패한다.

- [ ] **단계 3: provider 공통 인증과 API transport 구현**

Kakao/X provider 세부 사항은 auth adapter 안에 둔다. Kakao adapter는 네이티브 SDK가 받은 `providerAccessToken`을 백엔드에 전달하고, X adapter는 authorization code와 PKCE `codeVerifier`를 전달한다. 백엔드 access token을 `Authorization: Bearer`에 넣고 보이스 시그널링 요청에는 넣지 않는다. MVP에서는 refresh token을 저장하거나 갱신하지 않는다.

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
- 각 카드는 `personaKey`, `scenarioKey`, 페르소나 이름, 시나리오 요약·상세 설명, 이미지 asset, 미리듣기 음성 asset, 입력 placeholder를 가진다.

- [ ] **단계 1: 네 개 통화 카드 widget test 작성**

네 개 카드가 보이고, 각 카드가 persona key 하나와 scenario key 하나를 가지며, 페르소나 이미지·이름·짧은 시나리오 요약을 표시하는지 검증한다. 긴 시나리오 요약은 카드 영역에서 말줄임표로 축약되는지 확인한다. 상세 화면에는 같은 이미지와 10초 미리듣기, 시나리오 설명, 시나리오 컨텍스트 placeholder 하나와 통화 목표 placeholder 하나가 있는지 검증한다.

- [ ] **단계 2: widget test 실행 및 실패 확인**

실행: `flutter test test/combination/presentation/combination_list_page_test.dart`

예상 결과: 카드 model과 화면이 없으므로 실패한다.

- [ ] **단계 3: 카드·상세 화면과 정적 asset 추가**

`santa`, `princess`, `friend`, `child-roleplay`, `go-home`, `travel-friend-introduction` 같은 안정적인 key를 사용한다. 카드에는 페르소나 이미지·이름과 짧은 시나리오 요약을 표시하고, 요약이 영역을 넘으면 말줄임표로 처리한다. 카드 선택 시 상세 화면으로 이동해 같은 이미지, 10초 미리듣기, 전체 시나리오 설명, 시나리오 컨텍스트·통화 목표 입력과 예약 시각 선택을 제공한다. 이미지는 제품 소유자가 제공한 local asset으로 넣고, 미리듣기 음성은 조합별 정적 asset으로 등록한다.

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
- 생성: `lib/reservation/presentation/reservation_detail_page.dart`
- 생성: `lib/common/permissions/call_permission_service.dart`
- 생성: `lib/common/permissions/permission_guide_page.dart`
- 테스트: `test/reservation/application/reservation_service_test.dart`
- 테스트: `test/reservation/presentation/reservation_form_page_test.dart`

**인터페이스:**
- `ReservationApiClient.create(CreateReservationRequest): Future<Reservation>`
- `ReservationApiClient.update(String reservationId, UpdateReservationRequest): Future<Reservation>`
- `ReservationApiClient.cancel(String reservationId): Future<Reservation>`
- `ReservationService.edit(String reservationId, EditReservationInput): Future<Reservation>`
- `CallPermissionService.checkRequiredPermissions(): Future<CallPermissionStatus>`
- `CallPermissionService.requestMissingPermissions(): Future<CallPermissionStatus>`
- `CallPermissionService.openSettings(): Future<void>`
- `ReservationService.createFromCard(CallCombinationCard, String context, String goal, DateTime localTime, String timeZone): Future<Reservation>`

- [ ] **단계 1: 권한·요청 매핑과 form 규칙 테스트 작성**

필수 통화 권한이 없으면 예약 API를 호출하지 않고 안내 화면으로 이동하는지, 권한이 준비되면 선택 카드가 `personaKey`와 `scenarioKey`로 매핑되는지, 현지 시각과 time zone이 전송되는지, placeholder가 한 번만 표시되는지, 백엔드 안전·마감 오류가 입력값을 지우지 않고 표시되는지 검증한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/reservation/application/reservation_service_test.dart test/reservation/presentation/reservation_form_page_test.dart`

예상 결과: 예약 코드가 없으므로 실패한다.

- [ ] **단계 3: 권한 안내와 타입이 지정된 예약 요청·화면 구현**

플랫폼 adapter가 권한 상태를 확인하고 누락된 권한 요청 또는 시스템 설정 이동을 제공한다. 필수 조건이 충족될 때만 예약 API를 호출한다. 기기 time zone과 locale을 사용하고, 예약 시각 근처에 예상 시각 안내를 표시한다. client에서 시나리오 적합성 LLM 검사를 실행하지 않는다.

- [ ] **단계 4: 목록·상세·수정·취소 흐름 구현**

예약 목록에서 상세 화면으로 이동하고, 상세 화면에서 수정 화면으로 이어지게 한다. 상세 화면에는 예약 상태, 통화 조합, 페르소나 이미지, 예약 시각·시간대, 예상 시각 안내, 시나리오 컨텍스트, 통화 목표, `editableUntil`, 통화 결과를 표시한다. 생성·수정은 같은 `ReservationFormPage`를 모드만 바꿔 재사용한다. 백엔드가 반환한 `editableUntil`이 지나면 수정 버튼을 비활성화하고 `통화 5분 전부터는 예약을 수정할 수 없습니다.`를 표시한다. 수정 중 마감 시간이 지나면 백엔드 오류를 표시하고 입력값은 유지한다. `reservationStatus`, `callStatus`, `callOutcome`을 서로 구분해 표시하며, `callOutcome`이 비어 있으면 통화 진행 중이고 값이 있으면 종료된 것으로 표시한다. `voiceSessionId`, 정책 스냅샷과 내부 오류 정보는 표시하지 않는다.

- [ ] **단계 5: 테스트 실행 및 통과 확인**

실행: `flutter test test/reservation/application/reservation_service_test.dart test/reservation/presentation/reservation_form_page_test.dart`

예상 결과: 통과한다.

### 작업 6: PushKit과 CallKit 자동 수신 전화 구현

> **MVP 포함:** Apple Developer Program과 APNs 설정은 실기기 검증 전에 사용자가 준비한다. Foreground 수신 WebSocket·주기 조회·앱 타이머는 추가하지 않는다.

**파일:**
- 수정: `ios/Runner/OnCueCallKitBridge.swift`
- 생성: `ios/Runner/OnCueVoIPPushHandler.swift`
- 생성: `ios/Runner/OnCueCallKitProvider.swift`
- 수정: `ios/Runner/AppDelegate.swift`
- 생성: `lib/call/application/incoming_call_service.dart`
- 테스트: `test/call/application/incoming_call_service_test.dart`

**인터페이스:**
- `IncomingCallService.handleVoipPayload(Map<String, dynamic>): Future<void>`
- Push payload에는 `callSessionId`와 시스템 수신 화면에 표시할 안전한 `displayName`만 넣는다. 사용자 `scenarioContext`·`callGoal`, 백엔드 `accessToken`, WebRTC `connectionToken`은 넣지 않는다. 앱은 사용자가 전화를 받은 뒤 백엔드 access token으로 connection token을 요청한다.

- [ ] **단계 1: 수신 전화 서비스 테스트 작성**

정상 payload, 잘못된 payload, 중복 Push, 시스템 통화 등록 실패, answer/reject/end callback을 테스트한다.

- [x] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/call/application/incoming_call_service_test.dart`

예상 결과: PushKit payload 처리 테스트가 통과한다.

- [x] **단계 3: native PushKit 등록과 CallKit 보고 구현**

Apple Developer Program과 APNs 설정은 실기기 검증 전에 사용자가 준비한다. iOS VoIP Push와 CallKit은 MVP에 포함하고, Android는 FCM과 system-managed Telecom을 사용하도록 별도 native adapter 경계를 둔다. Push payload에는 `callSessionId`와 안전한 `displayName`만 포함한다.

- [x] **단계 4: answer/end callback을 Dart로 전달**

`callSessionId`를 Dart로 내보낸다. 플랫폼 내부의 CallKit UUID나 Telecom 식별자는 공통 계층에 노출하지 않는다. 사용자가 응답하기 전에는 연결 token을 요청하지 않는다.

- [x] **단계 5: 테스트와 iOS simulator smoke check 실행**

실행: `flutter test test/call/application/incoming_call_service_test.dart` 및 `flutter build ios --no-codesign`

예상 결과: 테스트와 iOS build가 통과한다.

### 작업 6: 연결 token 조회와 WebRTC client 구현

**파일:**
- 생성: `lib/call/data/call_session_api_client.dart`
- 생성: `lib/call/application/voice_call_service.dart`
- 생성: `lib/call/data/webrtc_client.dart`
- 생성: `lib/call/presentation/in_call_page.dart`
- 테스트: `test/call/application/voice_call_service_test.dart`
- 테스트: `test/call/data/webrtc_client_test.dart`

**인터페이스:**
- `CallSessionApiClient.issueConnectionToken(String callSessionId): Future<ConnectionToken>`
- `CallSessionApiClient.reject(String callSessionId): Future<CallSession>`
- `VoiceCallService.answer(String callSessionId): Future<void>`
- `VoiceCallService.end(String callSessionId): Future<void>`
- `WebRtcClient.connect(ConnectionToken token): Future<void>`는 token의 `signalingUrl`과 `iceServers`를 사용해 WebSocket 시그널링 후 WebRTC 음성 연결을 시작한다.
- `WebRtcClient.close(String reason): Future<void>`
- 거절 API 응답은 `callSessionId`, `callStatus`, `callOutcome`, `createdAt`, `endedAt`을 사용한다.

- [ ] **단계 1: 연결 흐름 테스트 작성**

answer → token 요청 → token 만료 → WebSocket signaling offer → answer/ICE candidate 교환 → WebRTC connected 상태, 잘못된 token, WebRTC 실패를 테스트한다. reject → 거절 API 호출 → `RINGING + FAILED` 반영과 중복 거절도 테스트한다. in-call end → WebRTC·WebSocket 종료와 보이스 서버의 최종 결과 callback 대기를 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `flutter test test/call/application/voice_call_service_test.dart test/call/data/webrtc_client_test.dart`

예상 결과: 연결과 WebRTC 코드가 없으므로 실패한다.

- [ ] **단계 3: token 조회와 ICE 설정 구현**

token 요청과 거절 요청에는 백엔드 access token만 사용한다. 통화 중 종료는 WebSocket으로 `hangup` 제어 메시지를 먼저 보낸 뒤 별도 백엔드 API 없이 WebRTC·WebSocket을 닫는 것으로 처리한다. 반환된 1회성 연결 token, `signalingUrl`, STUN/TURN 설정을 `flutter_webrtc`와 WebSocket signaling에 전달한다. WebSocket으로 음성 데이터를 전송하지 않는다.

- [ ] **단계 4: 통화 화면 구현**

페르소나 식별 정보, 경과 시간, 통화 종료, 연결 실패를 표시한다. transcript는 표시하거나 저장하지 않는다.

- [ ] **단계 5: 테스트와 실제 기기 WebRTC 확인**

실행: `flutter test test/call/application/voice_call_service_test.dart test/call/data/webrtc_client_test.dart` 및 TURN 설정이 있는 iPhone에서 테스트한다.

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
