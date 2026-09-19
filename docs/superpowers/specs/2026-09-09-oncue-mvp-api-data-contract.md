# OnCue MVP API·데이터 계약

## 1. 목적

이 문서는 `oncue-mobile`, `oncue-backend`, `oncue-voice`가 서로 다른 작업 세션에서 개발되어도 같은 요청·응답·상태·데이터 구조를 사용하도록 정한 공통 계약이다.

이 문서는 구현 코드나 Flyway migration이 아니라, 레포 간 경계를 정하는 설계 기준이다.

## 2. 공통 규칙

- API JSON 속성명은 camelCase를 사용한다.
- 생성 시각 속성명은 `createdAt`으로 통일한다.
- API 시각 값은 ISO-8601 UTC를 사용한다.
- 사용자가 입력한 예약 시각은 `scheduledAtLocal`과 `timeZone`으로 받고, 백엔드는 UTC 시각으로 변환해 저장한다.
- DB 컬럼명은 SQL 관례에 따라 snake_case를 사용하고 API·Java 속성명과 매핑한다.
- 음성 및 대화 텍스트는 저장하지 않는다.
- 모든 리소스 접근은 로그인 사용자와 리소스 소유권을 확인한다.

## 3. 인증 경계

### 모바일 → 백엔드

사용자 로그인 access token을 `Authorization: Bearer {token}`으로 전달한다.

로그인은 다음 endpoint를 사용한다.

```text
POST /api/v1/auth/login
```

요청:

Kakao 네이티브 로그인:

```json
{
  "provider": "kakao",
  "providerAccessToken": "..."
}
```

X 로그인:

```json
{
  "provider": "x",
  "authorizationCode": "...",
  "codeVerifier": "..."
}
```

`provider`는 `kakao` 또는 `x`만 허용한다. Kakao는 네이티브 Flutter SDK가 발급한 단기 `providerAccessToken`을 전달하고, 백엔드는 Kakao 사용자 정보 API로 외부 identity를 확인한다. X는 OAuth 2.0 Authorization Code + PKCE를 사용하며, 모바일이 인증 코드를 전달할 때 단기 `codeVerifier`도 함께 전달한다. `providerAccessToken`, `authorizationCode`, `codeVerifier`는 OnCue 장기 자격 증명이 아니며 백엔드가 사용자 로그인 처리 후 보관하지 않는다.

X 모바일 callback URI는 `com.oncue.oncuemobile://oauth/x/callback`으로 고정한다. 이 값은 X 개발자 콘솔의 callback URL, 모바일 AppAuth 설정, 백엔드 `X_REDIRECT_URI`가 정확히 일치해야 한다. X client ID는 public client 값이므로 실행 환경에서 주입하고 저장하지 않는다.

Kakao iOS custom scheme은 Kakao native app key에 따라 `kakao{nativeAppKey}`로 설정한다. native app key는 코드와 저장소에 커밋하지 않고 실행 환경에 주입하며, iOS `Info.plist`의 scheme은 해당 키로 별도 설정한다.

응답:

```json
{
  "accessToken": "...",
  "expiresAt": "2026-09-08T13:00:00Z",
  "createdAt": "2026-09-08T12:00:00Z"
}
```

MVP에서는 OnCue `refreshToken`을 발급하거나 받지 않는다. `accessToken`이 만료되면 모바일은 저장된 세션을 삭제하고 사용자가 다시 로그인한다. refresh token을 도입할 때는 재발급 endpoint, 회전·폐기 정책, 모바일 보안 저장소 변경을 별도 버전에서 함께 정의한다.

### 모바일 → 백엔드: iOS PushKit 기기 토큰 등록

```text
PUT /api/v1/push-device
```

로그인 또는 앱 시작 시 현재 기기의 PushKit VoIP 토큰을 등록한다. 사용자당 활성 토큰은 하나만 보관하며, 다른 기기에서 로그인하거나 토큰이 갱신되면 기존 값을 새 값으로 교체한다.

요청:

```json
{
  "deviceToken": "hex-encoded-apns-token",
  "platform": "IOS",
  "environment": "SANDBOX"
}
```

`environment`는 개발 빌드의 APNs sandbox endpoint를 뜻하는 `SANDBOX` 또는 TestFlight·배포 빌드의 APNs production endpoint를 뜻하는 `PRODUCTION`만 허용한다. `DEVELOPMENT`라는 API 값은 사용하지 않는다.

로그아웃 시 현재 사용자 토큰을 삭제한다.

```text
DELETE /api/v1/push-device
```

### 백엔드 → 보이스 서버

서비스 간 인증 토큰을 사용한다. 보이스 서버는 백엔드가 보낸 요청인지 확인한 뒤 세션 생성과 통화 결과 전달을 처리한다.

### 모바일 → 보이스 서버

사용자가 전화를 받은 뒤 백엔드가 발급한 짧은 만료 시간의 1회성 WebRTC 연결 토큰을 사용한다. 모바일 access token을 보이스 서버에 전달하지 않는다.

## 4. 예약 API

### 예약 생성

```text
POST /api/v1/reservations
```

요청:

```json
{
  "personaKey": "santa",
  "scenarioKey": "child-roleplay",
  "scenarioContext": "아이 이름은 민수이고 다정한 말투로 말해 주세요.",
  "callGoal": "민수가 빨리 잠들게 해 주세요.",
  "scheduledAtLocal": "2026-09-08T21:00:00",
  "timeZone": "Asia/Seoul"
}
```

모바일 UI는 안정적인 `personaKey`와 `scenarioKey`를 하드코딩할 수 있다. 백엔드는 두 key의 조합을 별도 허용 목록으로 검증하지 않고, 각 페르소나·시나리오가 존재하고 활성 상태인지 확인한 뒤 각 요소의 정책을 조합한다. DB 내부 관계에는 숫자 ID를 사용한다.

처리 순서:

1. 사용자 인증과 입력 형식을 확인한다.
2. 페르소나와 시나리오를 개별적으로 확인한다.
3. 예약 시각, 5분 전 변경 마감, 중복 예약을 확인한다.
4. 시나리오 컨텍스트와 통화 목표를 안전 검사한다.
5. 통과하면 예약을 저장한다.

성공 응답:

```json
{
  "reservationId": 1001,
  "reservationStatus": "SCHEDULED",
  "personaKey": "santa",
  "scenarioKey": "child-roleplay",
  "displayName": "산타",
  "personaImageUrl": "/assets/personas/santa.png",
  "previewAudioUrl": "/assets/audio/santa-preview.mp3",
  "scheduledAtLocal": "2026-09-08T21:00:00",
  "timeZone": "Asia/Seoul",
  "scheduledAtUtc": "2026-09-08T12:00:00Z",
  "editableUntil": "2026-09-08T11:55:00Z",
  "createdAt": "2026-09-08T10:00:00Z"
}
```

필수 통화 권한과 플랫폼 통화 설정은 모바일이 예약 API를 호출하기 전에 확인한다. 준비되지 않은 경우 모바일은 예약 요청을 보내지 않고 권한 안내 화면을 표시한다. 백엔드는 모바일 OS의 권한 상태를 관리하거나 대신 변경하지 않는다.

### 예약 목록·상세

```text
GET /api/v1/reservations
GET /api/v1/reservations/{reservationId}
```

사용자 본인의 예약만 반환한다. 목록·상세 응답에는 예약 정보, 페르소나 표시 정보(`displayName`, `personaImageUrl`, `previewAudioUrl`), 연결된 통화 상태를 포함할 수 있다. 통화 세션이 준비된 뒤에는 `callSessionId`도 포함한다. `voiceSessionId`와 정책 스냅샷은 반환하지 않는다.

### 예약 수정

```text
PATCH /api/v1/reservations/{reservationId}
```

수정할 수 있는 값은 `personaKey`, `scenarioKey`, `scenarioContext`, `callGoal`, `scheduledAtLocal`, `timeZone`이다.

수정할 때도 페르소나·시나리오의 개별 활성 상태, 예약 시간, 중복 예약, 안전 정책을 다시 확인한다.

### 예약 취소

```text
POST /api/v1/reservations/{reservationId}/cancel
```

취소는 데이터를 삭제하지 않고 `reservationStatus`를 `CANCELLED`로 변경한다.

## 5. 통화 세션 API

예약은 달력상의 약속이고, 통화 세션은 예약 통화 한 번의 시도 단위다. 준비 단계에서 생성될 수 있으며, 수신·응답되지 않아도 `FAILED` 결과로 종료될 수 있다. 예약 하나에는 통화 세션 하나만 생성한다.

### 세션 준비 시점

통화 세션은 예약 생성 즉시 만들지 않는다. 백엔드는 `prepareAt = scheduledAtUtc - 3분`으로 계산하고, 통화 준비 worker가 1분마다 `prepareAt`이 지났으며 아직 통화 세션이 없는 예약만 조회해 한 번 처리한다. 이 조회는 외부 LLM 호출이나 음성 연결을 시작하는 작업이 아니다.

통화 준비 단계에서는 식별자·정책 스냅샷·provider 설정·만료 시각을 포함한 보이스 세션 준비 데이터를 만든다. 보이스 서버는 실제 STT·LLM·TTS provider 연결과 WebRTC 미디어 처리를 사용자가 전화를 받은 뒤 시작한다. 따라서 통화 준비 후 예정 시각까지 실제 음성 연결을 계속 유지하지 않는다.

예약 시각이 되면 백엔드는 준비된 세션을 `PREPARING → RINGING`으로 전환하고 등록된 기기에 APNs VoIP Push를 보낸다. Push payload에는 `callSessionId`와 안전한 `displayName`만 포함한다. 기기 토큰이 없거나 APNs 전송이 실패하면 `RINGING + FAILED`로 종료한다.

예약 생성·목록·상세 응답에서 아직 준비 시각에 도달하지 않았다면 `callSessionId`가 없을 수 있다. 세션이 준비된 뒤에는 통화 세션의 `callSessionId`를 조회할 수 있지만, `voiceSessionId`는 모바일에 노출하지 않는다. CallKit 수신 정보에는 `callSessionId`와 `displayName`만 사용하며, 이미지·미리듣기 URL은 예약·조합 화면에서만 사용한다.

### 모바일 → 백엔드: 수신 거절

```text
POST /api/v1/call-sessions/{callSessionId}/reject
```

사용자가 시스템 수신 전화 화면에서 거절했을 때 모바일이 호출한다. 백엔드는 사용자 소유권과 현재 통화 상태를 확인하고, 보이스 서버에 세션 종료를 요청한 뒤 `callStatus=RINGING`, `callOutcome=FAILED`를 저장한다. 사용자가 거절한 통화이므로 60초 수신 대기를 기다리지 않는다.

이미 최종 결과가 저장된 경우에는 현재 결과를 그대로 반환하는 멱등 동작을 사용한다. `CONNECTING` 이후 거절 요청처럼 현재 상태와 맞지 않는 요청은 상태를 임의로 되돌리지 않고 충돌로 처리한다.

성공 응답:

```json
{
  "callSessionId": 12345,
  "callStatus": "RINGING",
  "callOutcome": "FAILED",
  "createdAt": "2026-09-08T12:00:00Z",
  "endedAt": "2026-09-08T12:01:00Z"
}
```

### 백엔드 → 보이스 서버: 세션 준비

```text
POST /internal/v1/voice-sessions
```

백엔드는 페르소나·시나리오 기본 지시사항, 대화 규칙, 공통 안전 정책, 사용자 컨텍스트와 목표를 조합한 최종 `policySnapshot`을 전달한다. 보이스 서버는 이 스냅샷을 provider별 실행 형식으로 변환한다.

응답은 동기적으로 반환한다.

```json
{
  "callSessionId": 12345,
  "voiceSessionId": "voice-session-abc",
  "createdAt": "2026-09-08T12:00:00Z"
}
```

세션 종료 요청은 백엔드가 보이스 서버에 동기적으로 전달한다.

```text
POST /internal/v1/voice-sessions/{voiceSessionId}/terminate
```

종료가 처리되면 보이스 서버는 `2xx` 응답을 반환한다. MVP에서 백엔드는 응답 본문을 사용하지 않는다.

두 내부 요청 모두 서비스 간 Bearer 인증을 사용하며, 보이스 서버는 `voiceSessionId`를 기준으로 자신의 세션을 관리한다.

> 읽기 메모: `callSessionId`는 온큐 전체의 통화 ID이고 `voiceSessionId`는 보이스 서버 내부 실행 ID다. 모바일에는 `voiceSessionId`를 노출하지 않는다.

### 모바일 → 백엔드: 연결 토큰 발급

```text
POST /api/v1/call-sessions/{callSessionId}/connection-token
```

백엔드는 세션과 사용자 소유권을 확인한 뒤 1회성 연결 토큰, 보이스 WebSocket 주소와 WebRTC 연결에 필요한 STUN/TURN 정보를 반환한다.

여기서 `iceServers`는 휴대폰이 WebRTC 연결 경로를 찾을 때 사용하는 설정이다. 운영 환경에서는 온큐가 직접 운영하는 coturn을 사용한다. 휴대폰은 백엔드 응답의 `iceServers`를 사용하고, 보이스 서버는 같은 coturn의 주소·자격 정보를 환경 변수 또는 Docker Secret으로 읽는다. 보이스 세션 생성 요청에 ICE 설정을 추가하지 않는다.

```json
{
  "connectionToken": "실제 서명된 JWT 문자열",
  "signalingUrl": "wss://voice.oncue.example/v1/signaling/call-sessions/12345",
  "iceServers": [
    { "urls": ["stun:stun.example.com"] },
    {
      "urls": ["turns:turn.example.com"],
      "username": "temporary-user",
      "credential": "temporary-credential"
    }
  ],
  "expiresAt": "2026-09-08T12:01:00Z",
  "createdAt": "2026-09-08T12:00:00Z"
}
```

연결 토큰의 핵심 claim은 `callSessionId`, `userId`, `scope`, `jti`, `iat`, `exp`다. `scope`는 현재 `voice:connect` 하나만 허용한다. `jti`는 1회 사용 확인, `iat`는 발급 시각, `exp`는 만료 시각이다.

연결 토큰은 백엔드의 RSA 개인키로 `RS256` 서명하고, 보이스 서버가 대응하는 공개키로 검증한다. 이 RSA 키 쌍은 사용자 로그인 access token에 사용하는 HMAC secret과 분리한다. 보이스 서버에는 개인키를 전달하지 않는다.

### 모바일 ↔ 보이스 서버: WebRTC 시그널링

```text
wss://voice.oncue.example/v1/signaling/call-sessions/{callSessionId}
```

WebSocket 연결 시 `Authorization: Bearer {connectionToken}`을 사용한다. 모바일이 `offer`를 보내면 보이스 서버가 `answer`를 반환하고, 양쪽이 `ICE candidate`를 교환한다. 이 과정 이후 실제 음성은 모바일과 보이스 서버 사이에서 WebRTC로 전달된다.

`offer`와 `answer`의 `sdp`는 연결 방법을 설명하는 텍스트이며 실제 음성이 아니다. 여기서 음성 방식은 음성 압축 형식(`Opus`, `PCMU`), 보내기·받기 방향, 품질 설정, 암호화·네트워크 정보를 뜻한다. `ICE candidate`는 연결에 사용할 수 있는 네트워크 후보 주소다. `sdpMid`는 후보가 속한 미디어 채널(음성·영상·데이터)을 가리키고, `sdpMLineIndex`는 SDP의 `m=` 미디어 설명 줄 순서이며 candidate 배열 순서가 아니다.

```json
{
  "type": "offer",
  "payload": { "sdp": "v=0..." }
}
```

```json
{
  "type": "answer",
  "payload": { "sdp": "v=0..." }
}
```

```json
{
  "type": "ice-candidate",
  "payload": {
    "candidate": "candidate:...",
    "sdpMid": "0",
    "sdpMLineIndex": 0
  }
}
```

통화 중 사용자가 종료한 경우에는 WebSocket으로 다음 제어 메시지를 먼저 보낸다.

```json
{
  "type": "hangup"
}
```

사용자가 통화 중 시스템 화면에서 종료하면 모바일은 WebSocket으로 `hangup` 제어 메시지를 먼저 보낸 뒤 WebRTC와 WebSocket 연결을 닫는다. 별도의 모바일 → 백엔드 종료 API는 만들지 않는다. 보이스 서버는 `hangup`을 받은 연결 종료를 정상적인 사용자 종료로 판단해 `IN_CALL + SUCCEEDED` 결과를 백엔드에 전달한다. `hangup` 없이 연결이 끊기면 기술 오류 가능성으로 처리한다. 보이스 서버의 시간 제한·시나리오 종료·기술 오류도 보이스 서버가 최종 결과를 판단해 전달한다.

### 보이스 서버 → 백엔드: 통화 결과

```text
POST /internal/v1/call-sessions/{callSessionId}/result
```

요청:

```json
{
  "voiceSessionId": "voice-session-abc",
  "callStatus": "IN_CALL",
  "callOutcome": "SUCCEEDED",
  "startedAt": "2026-09-08T12:01:10Z",
  "endedAt": "2026-09-08T12:06:10Z"
}
```

`callSessionId`를 기준으로 최종 결과를 한 번만 반영한다. 같은 결과가 다시 오면 현재 값을 유지하고 성공 응답하며, 이미 종료된 세션에 다른 결과가 오면 상태를 바꾸지 않고 로그에 기록한다.

> 계약 메모: `callSessionId`와 `userId`는 DB의 `BIGINT UNSIGNED AUTO_INCREMENT` 값에 대응하는 JSON 숫자다. `voiceSessionId`만 보이스 서버가 생성하는 문자열 UUID다.

## 6. 상태 모델

### 예약 상태

```text
SCHEDULED → CANCELLED
SCHEDULED → CLOSED
```

`CLOSED`는 예약 작업이 끝났다는 뜻이며, 통화 성공을 의미하지 않는다.

### 통화 상태와 결과

```text
PREPARING → RINGING → CONNECTING → IN_CALL
```

`callStatus`는 현재 또는 종료 직전의 마지막 진행 단계이고, `callOutcome`은 종료 여부와 결과다.

```json
{
  "callStatus": "RINGING",
  "callOutcome": "FAILED"
}
```

가능한 상태와 결과는 다음과 같다.

```text
callOutcome:
- SUCCEEDED
- FAILED

callStatus:
- PREPARING
- RINGING
- CONNECTING
- IN_CALL
```

### 상태 처리 규칙

- 상태는 이전 단계로 돌아가지 않는다.
- `callOutcome`이 설정된 뒤에는 재시도하지 않는다.
- 통화 종료 뒤 도착한 이전 결과는 무시한다.
- 백엔드가 최종 상태를 관리한다.
- 보이스 서버는 `RINGING` 60초, `CONNECTING` 30초, `IN_CALL` 300초 제한을 적용한다.
- 백엔드는 하루 1회 `callOutcome`이 비어 있고 예상 종료 시간이 지난 세션을 보정한다.

## 7. 대화 정책 조합

페르소나와 시나리오에는 같은 정책 구조를 둔다.

```text
contextPlaceholder
defaultInstructions
dialogueRules
```

시나리오에는 추가로 `callGoalPlaceholder`를 둔다.

`contextPlaceholder`는 사용자 입력 화면에 보여주는 안내 문구이고, `defaultInstructions`는 사용자에게 노출하지 않는 LLM 행동 지침이다. 둘은 같은 내용이 아니다.

통화 정책은 다음 순서로 구성한다.

```text
기본 대화 정책
+ persona.defaultInstructions가 있으면 추가
+ persona.dialogueRules가 있으면 추가
+ scenario.defaultInstructions가 있으면 추가
+ scenario.dialogueRules가 있으면 추가
+ 사용자 시나리오 컨텍스트
+ 사용자 통화 목표
```

공통 안전 정책은 위 정책 전체에 항상 적용되는 최우선 규칙이다. 페르소나·시나리오에 정책이 없으면 기본 대화 정책을 사용한다. 조합별 정책 테이블은 MVP에서 만들지 않는다.

MVP 공통 안전 정책은 금융·송금·결제·투자 사기, 비밀번호·OTP·계정 정보 요구, 실존 인물·기관·기업 사칭 및 음성 복제, 로맨스 스캠, 성적 그루밍·섹스토션·아동 대상 성적 대화, 협박·강요·스토킹·감시·사생활 침해, 피싱·계정 탈취·악성 링크, 폭력·납치·몸값·자해·위험 행동 유도를 금지한다. 특정 실존 인물을 복제하지 않는 제품 제공 가상 페르소나의 역할극과 MVP에 정의된 친구·가족 상황극은 허용한다.

### 음성·대화 품질 평가의 정책 재현

`oncue-voice`의 Jupyter notebook은 운영 API가 아니라 개발용 평가 도구다. notebook은 runtime에 전달한 최종 대화 정책 전체를 `policySnapshot`으로 로컬 artifact에 저장한다. 정책 버전 번호나 운영 정책 이력 테이블은 만들지 않는다.

정책 snapshot에는 페르소나·시나리오 지시사항과 규칙, 공통 안전 정책, 사용자 시나리오 컨텍스트와 통화 목표, 언어, voice 식별자·설정, 해당 실행 설정이 적용된 최종값을 포함한다. notebook에서 변경한 정책·voice 설정은 운영 예약 API나 사용자 기능으로 노출하지 않는다.

정책 snapshot과 생성된 음성·대화 텍스트는 합성 테스트 데이터에 한해 `oncue-voice/notebooks/evaluations/<combinationKey>/<runId>/`에 로컬 저장할 수 있다. 입력은 `input/`, 실행 결과는 `artifacts/` 아래에 저장한다. 운영 API·운영 DB·운영 로그에는 저장하지 않는다.

## 8. DB 테이블

MVP에서는 다음 테이블만 만든다.

```text
users
user_login_accounts
personas
scenarios
reservations
call_sessions
```

모든 기본키는 `BIGINT UNSIGNED AUTO_INCREMENT`로 한다. DB 외래키는 `users`, `personas`, `scenarios`, `reservations` 사이의 개별 참조에만 사용한다. 페르소나·시나리오 조합을 제한하는 조합 테이블이나 외래키는 만들지 않는다.

### 핵심 컬럼

```text
users:
- id, status, created_at, updated_at

user_login_accounts:
- id, user_id, provider, provider_user_id, created_at, updated_at

personas:
- id, key, name, description, context_placeholder
- default_instructions, dialogue_rules
- voice_id, image_url, preview_audio_url
- status, created_at, updated_at

scenarios:
- id, key, name, description, context_placeholder
- call_goal_placeholder, default_instructions, dialogue_rules
- status, created_at, updated_at

reservations:
- id, user_id, persona_id, scenario_id
- scenario_context, call_goal
- scheduled_at_utc, time_zone, reservation_status
- cancelled_at, created_at, updated_at

call_sessions:
- id, reservation_id, voice_session_id
- call_status, call_outcome
- started_at, ended_at, created_at, updated_at
```

`(provider, provider_user_id)`는 중복을 허용하지 않으며, `personas.key`와 `scenarios.key`는 각각 중복을 허용하지 않는다. `reservation_id`는 통화 세션마다 하나만 연결한다.

## 9. 오류 응답

```json
{
  "code": "RESERVATION_LOCKED",
  "message": "통화 5분 전부터 예약을 수정할 수 없습니다.",
  "requestId": "request-123",
  "createdAt": "2026-09-08T12:00:00Z"
}
```

```text
400 입력 형식 오류
401 인증 오류
403 권한 없음
404 대상 없음
409 상태 충돌 또는 중복 예약
422 안전 정책에 따른 차단
500 서버 오류
503 외부 서비스 일시 오류
```

## 10. MVP에서 제외하는 것

- 조합 자체를 저장하는 `call_combinations` 테이블
- 조합별 대화 정책 테이블
- 사용자 직접 페르소나 생성
- 관리자 페이지를 통한 정책 편집
- 반복 예약
- 통화 음성·대화 텍스트 저장
- 운영 API를 통한 사용자 voice 설정
- 운영 API를 통한 음성·대화 품질 평가 실행
