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

### 백엔드 → 보이스 서버

서비스 간 인증 토큰을 사용한다. 보이스 서버는 백엔드가 보낸 요청인지 확인한 뒤 세션 생성과 상태 이벤트를 처리한다.

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
  "scheduledAtLocal": "2026-09-08T21:00:00",
  "timeZone": "Asia/Seoul",
  "scheduledAtUtc": "2026-09-08T12:00:00Z",
  "editableUntil": "2026-09-08T11:55:00Z",
  "createdAt": "2026-09-08T10:00:00Z"
}
```

### 예약 목록·상세

```text
GET /api/v1/reservations
GET /api/v1/reservations/{reservationId}
```

사용자 본인의 예약만 반환한다. 상세 응답에는 예약 정보와 연결된 통화 상태를 포함할 수 있다.

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

예약은 달력상의 약속이고, 통화 세션은 실제로 한 번 시도한 전화다. 예약 하나에는 통화 세션 하나만 생성한다.

### 백엔드 → 보이스 서버: 세션 준비

```text
POST /internal/v1/voice-sessions
```

백엔드는 페르소나·시나리오 기본 지시사항, 대화 규칙, 공통 안전 정책, 사용자 컨텍스트와 목표를 조합한 대화 정책을 전달한다.

### 모바일 → 백엔드: 연결 토큰 발급

```text
POST /api/v1/call-sessions/{sessionId}/connection-token
```

백엔드는 세션과 사용자 소유권을 확인한 뒤 1회성 연결 토큰과 WebRTC 연결에 필요한 STUN/TURN 정보를 반환한다.

### 모바일 → 보이스 서버: WebRTC 시그널링

```text
POST /v1/sessions/{sessionId}/webrtc/offer
```

요청에는 연결 토큰과 WebRTC `offer`가 포함된다. 보이스 서버는 토큰을 검증한 뒤 `answer`를 반환한다. 이 과정 이후 실제 음성은 모바일과 보이스 서버 사이에서 WebRTC로 전달된다.

### 보이스 서버 → 백엔드: 상태 이벤트

```text
POST /internal/v1/call-sessions/{sessionId}/events
```

요청:

```json
{
  "eventId": "event-123",
  "callStatus": "IN_CALL",
  "createdAt": "2026-09-08T12:01:10Z"
}
```

`eventId`를 이용해 중복 이벤트를 한 번만 처리한다.

## 6. 상태 모델

### 예약 상태

```text
SCHEDULED → CANCELLED
SCHEDULED → CLOSED
```

`CLOSED`는 예약 작업이 끝났다는 뜻이며, 통화 성공을 의미하지 않는다.

### 통화 상태

```text
PREPARING → RINGING ─────→ CONNECTING → IN_CALL → ENDED
             └→ MISSED       └→ FAILED
```

통화 결과와 종료 이유는 별도 속성으로 관리한다.

```json
{
  "callStatus": "ENDED",
  "callOutcome": "SUCCEEDED",
  "callEndReason": "USER_ENDED"
}
```

가능한 결과와 종료 이유는 다음과 같다.

```text
callOutcome:
- SUCCEEDED
- MISSED
- FAILED
- SAFETY_BLOCKED

callEndReason:
- USER_ENDED
- TIME_LIMIT_REACHED
- RING_TIMEOUT
- TECHNICAL_ERROR
```

### 상태 처리 규칙

- 상태는 이전 단계로 돌아가지 않는다.
- `MISSED`, `FAILED`, `ENDED` 이후 재시도하지 않는다.
- 종료 상태 이후 도착한 이전 상태 이벤트는 무시한다.
- 백엔드가 최종 상태를 관리한다.

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

### 음성·대화 품질 평가의 정책 재현

`oncue-voice`의 Jupyter notebook은 운영 API가 아니라 개발용 평가 도구다. notebook은 runtime에 전달한 최종 대화 정책 전체를 `policySnapshot`으로 로컬 artifact에 저장한다. 정책 버전 번호나 운영 정책 이력 테이블은 만들지 않는다.

정책 snapshot에는 페르소나·시나리오 지시사항과 규칙, 공통 안전 정책, 사용자 시나리오 컨텍스트와 통화 목표, 언어, voice 식별자·설정, 평가 variant가 적용된 최종값을 포함한다. notebook에서 변경한 정책·voice 설정은 운영 예약 API나 사용자 기능으로 노출하지 않는다.

정책 snapshot과 생성된 음성·대화 텍스트는 합성 테스트 데이터에 한해 `oncue-voice/notebooks/artifacts/`에 로컬 저장할 수 있다. 운영 API·운영 DB·운영 로그에는 저장하지 않는다.

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
- call_status, call_outcome, call_end_reason
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
