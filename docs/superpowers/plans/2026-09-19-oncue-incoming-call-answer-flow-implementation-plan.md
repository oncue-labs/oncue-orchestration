# OnCue 수신 응답·음성 연결 구현 계획

> **For agentic workers:** 승인된 기존 spec을 기준으로 현재 세션에서 작업한다. 각 단계는 TDD로 실행하고, 기존 사용자 변경은 보존한다.

**Goal:** iOS 시스템 수신 전화 화면에서 사용자가 응답하면 백엔드가 발급한 연결 토큰으로 보이스 서버와 WebRTC 음성 연결을 시작하고, 종료·실패 상태를 정리한다.

**Architecture:** 모바일은 CallKit 이벤트를 Flutter coordinator로 전달하고, coordinator가 기존 connection-token API를 호출한 뒤 WebSocket 시그널링과 WebRTC 미디어 연결을 관리한다. 백엔드와 보이스 서버의 기존 토큰·시그널링·결과 콜백 계약은 유지하고, 로컬 실기기 테스트에서만 접근 가능한 LAN 주소를 주입한다.

**Tech Stack:** Flutter/Dart, `flutter_webrtc`, Dart `WebSocket`, Spring Boot 기존 connection-token API, FastAPI 기존 WebRTC signaling API, Docker Compose.

**Spec:** `docs/superpowers/specs/2026-09-09-oncue-mvp-api-data-contract.md`, `docs/superpowers/specs/2026-09-14-oncue-mobile-screen-flow-design.md`

## Global Constraints

- 모바일은 백엔드 access token을 보이스 서버에 보내지 않고, 짧은 수명의 connection token만 WebSocket `Authorization` 헤더에 사용한다.
- WebSocket 메시지 타입은 기존 `offer`, `answer`, `ice-candidate`, `hangup`을 사용한다.
- iOS 시스템 통화 화면은 계속 CallKit을 사용하며 Flutter에 별도 수신·통화 화면을 만들지 않는다.
- 음성 채널만 사용하고, 음성·대화 텍스트는 저장하지 않는다.
- `voiceSessionId`는 모바일에 노출하지 않는다.
- Android 구현은 이번 범위에 포함하지 않지만 Dart 계층의 공통 계약은 이후 Android adapter가 사용할 수 있도록 만든다.
- 기존 사용자 변경인 `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner/Info.plist`는 커밋에 포함하지 않는다.

---

### Task 1: 모바일 WebRTC·시그널링 연결 계약 추가

**Files:**
- Modify: `/Users/yeonny0723/orca/oncue-mobile/pubspec.yaml`
- Create: `/Users/yeonny0723/orca/oncue-mobile/lib/call/model/connection_token.dart`
- Create: `/Users/yeonny0723/orca/oncue-mobile/lib/call/data/call_connection_api_client.dart`
- Create: `/Users/yeonny0723/orca/oncue-mobile/lib/call/application/call_connection_service.dart`
- Create: `/Users/yeonny0723/orca/oncue-mobile/test/call/data/call_connection_api_client_test.dart`
- Create: `/Users/yeonny0723/orca/oncue-mobile/test/call/application/call_connection_service_test.dart`

**Interfaces:**
- `CallConnectionApiClient.issueConnectionToken(callSessionId, accessToken)` returns `ConnectionToken` with `connectionToken`, `signalingUrl`, `iceServers`, `expiresAt`, `createdAt`.
- `CallConnectionService.connect(callSessionId, accessToken)` obtains media, opens WebSocket, sends an SDP offer, applies the answer, forwards local ICE candidates, and completes only when the peer connection reaches `connected` or `completed`.
- `CallConnectionService.hangup()` sends `{"type":"hangup"}` when the signaling socket is open and then closes media resources.

- [x] **Step 1: Add failing API client test**

  Assert that the client calls `POST /api/v1/call-sessions/321/connection-token` with the access token and parses all response fields without logging token values.

- [x] **Step 2: Run the focused API client test and confirm RED**

  Run: `flutter test test/call/data/call_connection_api_client_test.dart`

  Expected: FAIL because the connection-token model/client does not exist.

- [x] **Step 3: Add the connection-token model and API client**

  Reuse the existing `ApiClient.postJson` contract. Parse `iceServers` as immutable value objects and parse all timestamps with `DateTime.parse`.

- [x] **Step 4: Run the focused API client test and confirm GREEN**

  Run: `flutter test test/call/data/call_connection_api_client_test.dart`

  Expected: PASS.

- [x] **Step 5: Add failing WebRTC service tests**

  Use fake peer connection, WebSocket, media stream, and API client collaborators to cover: offer/answer exchange, local ICE forwarding, connection completion, server answer application, and hangup message.

- [x] **Step 6: Run the focused service test and confirm RED**

  Run: `flutter test test/call/application/call_connection_service_test.dart`

  Expected: FAIL because the service behavior is not implemented.

- [x] **Step 7: Add the minimal service implementation**

  Configure `RTCPeerConnection` with the response `iceServers`, add the microphone audio track from `getUserMedia`, connect the WebSocket with `Authorization: Bearer <connectionToken>`, exchange SDP, forward ICE candidates, and always close tracks/socket/peer connection on failure or hangup.

- [x] **Step 8: Run focused service tests and confirm GREEN**

  Run: `flutter test test/call/application/call_connection_service_test.dart`

  Expected: PASS.

- [x] **Step 9: Run mobile static analysis**

  Run: `flutter analyze`

  Expected: no analyzer issues.

### Task 2: CallKit answer/reject/end event coordinator 연결

**Files:**
- Create: `/Users/yeonny0723/orca/oncue-mobile/lib/call/application/incoming_call_coordinator.dart`
- Modify: `/Users/yeonny0723/orca/oncue-mobile/lib/call/data/call_session_api_client.dart`
- Modify: `/Users/yeonny0723/orca/oncue-mobile/lib/app/oncue_app.dart`
- Modify: `/Users/yeonny0723/orca/oncue-mobile/lib/auth/application/auth_service.dart`
- Modify: `/Users/yeonny0723/orca/oncue-mobile/ios/Runner/OnCueCallKitBridge.swift`
- Create: `/Users/yeonny0723/orca/oncue-mobile/test/call/application/incoming_call_coordinator_test.dart`
- Modify: `/Users/yeonny0723/orca/oncue-mobile/test/auth/application/auth_service_test.dart`

**Interfaces:**
- `IncomingCallCoordinator` subscribes to `SystemCallManager.onAnswered`, `.onRejected`, and `.onEnded`.
- On answer it loads the current authenticated session, connects the call, then calls `answerSucceeded`; on connection failure it calls `answerFailed`.
- On reject it calls the existing backend reject endpoint and closes any local connection.
- On end it hangs up the WebRTC connection and releases resources.
- `AuthService.currentSession` exposes only the in-memory `AuthSession?` needed by the coordinator and is updated on restore, login, and logout.

- [x] **Step 1: Add failing coordinator tests**

  Cover: answer success acknowledges CallKit after connection, answer failure acknowledges failure, reject calls the existing reject endpoint, end sends hangup, and an event received before login is ignored safely.

- [x] **Step 2: Run the coordinator test and confirm RED**

  Run: `flutter test test/call/application/incoming_call_coordinator_test.dart`

  Expected: FAIL because the coordinator and current-session access do not exist.

- [x] **Step 3: Add the current-session access to `AuthService`**

  Keep the existing secure storage behavior. Update the in-memory session at the same points where the session is restored, saved after login, and cleared during logout.

- [x] **Step 4: Implement the coordinator**

  Subscribe once during app startup, serialize one active call connection at a time, and use `try/finally` to release subscriptions and media resources. Never include scenario context, call goal, or connection token in logs.

- [x] **Step 5: Wire the coordinator into `OnCueApp`**

  Construct it in `main.dart` with the existing `MethodChannelSystemCallManager`, `CallSessionApiClient`, `CallConnectionService`, and `AuthService`. Dispose it when the app is disposed.

- [x] **Step 6: Activate the iOS audio session for CallKit**

  Configure `AVAudioSession` in `provider(_:didActivate:)` and deactivate it in
  `provider(_:didDeactivate:)` so the WebRTC microphone and remote audio use the
  CallKit-managed audio route after the system call is answered.

- [x] **Step 7: Run coordinator and auth tests**

  Run: `flutter test test/call/application/incoming_call_coordinator_test.dart test/auth/application/auth_service_test.dart`

  Expected: PASS.

### Task 3: 로컬 실기기 signaling·TURN 주소 수정

**Files:**
- Modify: `/Users/yeonny0723/orca/projects/oncue-orchestration/docker-compose.local.yml`
- Modify: `/Users/yeonny0723/orca/projects/oncue-orchestration/.env.example`
- Modify: `/Users/yeonny0723/orca/projects/oncue-orchestration/README.md`
- Modify: `/Users/yeonny0723/orca/projects/oncue-orchestration/tests/compose_config_test.sh`

**Interfaces:**
- Add `ONCUE_PUBLIC_HOST` for an address reachable from the physical iPhone, such as the Mac LAN IP.
- Build the backend response signaling URL as `ws://${ONCUE_PUBLIC_HOST}:${VOICE_PORT}/v1/signaling`.
- Return ICE server URLs using `ONCUE_PUBLIC_HOST`, not `localhost`.
- Configure the voice container to reach coturn through the Compose service name
  (`turn:coturn:3478`); the backend's ICE values are for the iPhone and therefore
  use the public host. These are two different network paths.
- Keep container-to-container `VOICE_SERVER_URL=http://oncue-voice:8000` unchanged.

- [x] **Step 1: Add a failing compose configuration assertion**

  Assert that the rendered backend environment contains the public host in signaling and ICE URLs and does not expose `localhost` in the mobile connection values.

- [x] **Step 2: Run the compose configuration test and confirm RED**

  Run: `bash tests/compose_config_test.sh`

  Expected: FAIL because the current compose file uses `localhost` for mobile-received values.

- [x] **Step 3: Implement the public-host variables**

  Update the example and README. Set the local uncommitted `.env` value to the current Mac LAN address without printing any secrets.

- [x] **Step 4: Run the compose configuration test and confirm GREEN**

  Run: `bash tests/compose_config_test.sh`

  Expected: PASS.

### Task 4: 통합 검증

**Files:**
- No production file changes unless a failing integration test identifies a contract defect.

- [x] **Step 1: Run all mobile tests**

  Run: `flutter test`

- [x] **Step 2: Run backend tests**

  Run: `GRADLE_USER_HOME=/private/tmp/oncue-gradle-home JAVA_HOME='/Users/yeonny0723/Library/Java/JavaVirtualMachines/temurin-21.0.11/Contents/Home' ./gradlew --no-daemon test`

- [x] **Step 3: Run voice tests**

  Run: `poetry run pytest`

- [x] **Step 4: Rebuild local services**

  Run: `docker compose --env-file .env -f docker-compose.local.yml up -d --build oncue-backend oncue-voice`

- [ ] **Step 5: Perform a real-device E2E test**

  Launch the mobile app with `flutter run -d 00008140-000634A63630801C --dart-define-from-file=config/local.json`, create a reservation two minutes in the future, leave the app in the background without force-quitting it, answer the CallKit screen, and verify that the WebRTC connection reaches `connected`, the CallKit answer action completes, and the backend call session transitions beyond `RINGING`.

- [ ] **Step 6: Run test-sensitivity review**

  Check that the new tests fail when the connection-token path, WebSocket authorization, SDP exchange, CallKit acknowledgement, or public-host configuration is removed.
