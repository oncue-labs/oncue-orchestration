# OnCue 백엔드 MVP 구현 계획

> **에이전트 작업자 필수 안내:** 이 계획을 작업별로 실행할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 작업 단계는 추적할 수 있도록 체크박스(`- [ ]`)로 작성되어 있다.

**목표:** 사용자 인증, 페르소나·시나리오 데이터, 예약, 안전성 판정, 대화 정책 조합, 통화 세션 제어와 상태 저장을 담당하는 Spring Boot 백엔드를 구축한다.

**아키텍처:** 기능 중심의 단순한 모듈형 계층 구조를 사용한다. 각 기능은 controller, service, model, repository로 구성하고 외부 시스템은 `identity_provider`, `voice_server`, `safety_classifier`라는 명시적인 경계로 분리한다. 헥사고날 아키텍처를 전체 코드에 적용하지 않는다.

**기술 스택:** Java 21, Spring Boot 3.2.3, Gradle, MySQL 8, Redis 7, Flyway, Spring Security, JPA, JUnit 5, Mockito, AssertJ, Testcontainers.

**사양:** `docs/superpowers/specs/2026-09-08-oncue-mvp-design.md`, `docs/superpowers/specs/2026-09-09-oncue-mvp-api-data-contract.md`

## 전체 제약 조건

- API 경계에서는 `personaKey`와 `scenarioKey`를 사용하고, DB 내부에서만 `BIGINT UNSIGNED AUTO_INCREMENT` ID를 사용한다.
- 활성 상태인 페르소나와 시나리오의 조합은 모두 허용하며, 조합 허용 목록을 만들거나 검증하지 않는다.
- 페르소나와 시나리오의 기본 지시사항·대화 규칙은 각 테이블에 저장하고, MVP에서는 `call_combinations`와 `dialogue_policies` 테이블을 만들지 않는다.
- API 시간은 ISO-8601 UTC를 사용하고 JSON 생성 시각 속성은 `createdAt`으로 통일한다. DB의 `created_at`은 Java의 `createdAt`으로 매핑한다.
- 통화 음성과 대화 텍스트를 저장하지 않는다.
- 통화 5분 전 수정·취소 마감, 1회 시도, 60초 수신 대기, 최대 5분 통화 시간을 적용한다.
- 통화 준비 시각은 `scheduledAtUtc - 3분`이며, 준비 worker는 1분마다 due 상태인 미준비 예약만 확인한다. 준비된 보이스 세션은 실제 음성 provider 연결을 유지하지 않는다.
- 보이스 서버의 연결 제한시간은 30초이며, 백엔드 상태 보정 작업은 하루 1회 실행한다.
- 결정적 안전 규칙을 먼저 실행하고, 위험 신호가 있을 때만 안전성 판정 LLM을 호출하며, 판정 실패·불확실 시 차단한다.
- 스키마는 Flyway가 소유하고 JPA는 `ddl-auto: validate`로 동작한다.
- 반복 예약, 관리자 API, Android API, 사용자 페르소나 생성, 동적 음성 설정은 추가하지 않는다.

---

### 작업 1: Spring Boot 애플리케이션 뼈대 만들기

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-backend/settings.gradle`
- 생성: `/Users/yeonny0723/orca/oncue-backend/build.gradle`
- 생성: `/Users/yeonny0723/orca/oncue-backend/Dockerfile`
- 생성: `/Users/yeonny0723/orca/oncue-backend/src/main/java/com/oncue/OncueApplication.java`
- 생성: `/Users/yeonny0723/orca/oncue-backend/src/main/java/com/oncue/common/config/ApplicationProperties.java`
- 생성: `/Users/yeonny0723/orca/oncue-backend/src/main/resources/application.yml`
- 테스트: `/Users/yeonny0723/orca/oncue-backend/src/test/java/com/oncue/OncueApplicationTest.java`

**인터페이스:**
- MySQL, Redis, JWT 서명, 외부 제공자 설정을 읽고 Spring 컨텍스트를 실행할 수 있어야 한다.

- [ ] **단계 1: 컨텍스트 로딩 실패 테스트 작성**

```java
@SpringBootTest
class OncueApplicationTest {
    @Test
    void applicationContextLoads() {
    }
}
```

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `./gradlew test --tests com.oncue.OncueApplicationTest`

예상 결과: 애플리케이션과 Gradle 프로젝트가 없으므로 실패한다.

- [ ] **단계 3: 최소 애플리케이션과 빌드 설정 작성**

Java 21, Spring Boot 3.2.3, Web, Validation, Security, JPA, Redis, Flyway, MySQL 런타임 의존성을 설정한다. `ddl-auto: validate`, 환경 변수 기반 비밀값, `/actuator/health`를 설정한다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `./gradlew test --tests com.oncue.OncueApplicationTest`

예상 결과: 통과한다.
### 작업 2: Flyway 스키마와 제공자 데이터 만들기

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-backend/src/main/resources/db/migration/V1__create_users_login_accounts_personas_scenarios.sql`
- 생성: `/Users/yeonny0723/orca/oncue-backend/src/main/resources/db/migration/V2__create_reservations_and_call_sessions.sql`
- 생성: `/Users/yeonny0723/orca/oncue-backend/src/main/resources/db/migration/V3__seed_mvp_personas_and_scenarios.sql`
- 생성: `/Users/yeonny0723/orca/oncue-backend/src/test/java/com/oncue/database/FlywaySchemaIntegrationTest.java`

**인터페이스:**
- `users`, `user_login_accounts`, `personas`, `scenarios`, `reservations`, `call_sessions` 테이블을 제공한다.
- 중복되지 않는 페르소나·시나리오 key와 MVP 콘텐츠를 제공한다. 조합 테이블은 만들지 않는다.

- [ ] **단계 1: 테이블과 제약 조건에 대한 통합 테스트 작성**

6개 테이블의 존재 여부, `(provider, provider_user_id)` 유니크, `personas.key`와 `scenarios.key` 유니크, `call_sessions.reservation_id` 유니크를 검증한다.

- [ ] **단계 2: 통합 테스트 실행 및 실패 확인**

실행: `./gradlew integrationTest --tests com.oncue.database.FlywaySchemaIntegrationTest`

예상 결과: migration과 통합 테스트 작업이 없으므로 실패한다.

- [ ] **단계 3: migration 작성**

기본키는 `BIGINT UNSIGNED AUTO_INCREMENT`, 상태값은 `VARCHAR`, 시간은 UTC `DATETIME(6)`, 지시사항과 사용자 입력은 `TEXT`, `dialogue_rules`는 `JSON`으로 만든다. `scenarios`에 `persona_id`를 추가하지 않고, 페르소나·시나리오 조합 제약도 추가하지 않는다.

- [ ] **단계 4: MVP 페르소나·시나리오 seed 추가**

`santa`, `princess`, `friend`와 `child-roleplay`, `go-home`, `travel-friend-introduction` 같은 안정적인 key를 사용한다. 이미지, 미리듣기 음성, voice ID는 제공자 데이터로 넣는다.

- [ ] **단계 5: 통합 테스트 실행 및 통과 확인**

실행: `./gradlew integrationTest --tests com.oncue.database.FlywaySchemaIntegrationTest`

예상 결과: MySQL Testcontainers에서 통과한다.

### 작업 3: Kakao/X 로그인 계정 연결 구현

**파일:**
- 생성: `src/main/java/com/oncue/auth/controller/AuthController.java`
- 생성: `src/main/java/com/oncue/auth/controller/request/LoginRequest.java`
- 생성: `src/main/java/com/oncue/auth/controller/response/LoginResponse.java`
- 생성: `src/main/java/com/oncue/auth/service/AuthService.java`
- 생성: `src/main/java/com/oncue/auth/model/User.java`
- 생성: `src/main/java/com/oncue/auth/model/UserLoginAccount.java`
- 생성: `src/main/java/com/oncue/auth/repository/UserRepository.java`
- 생성: `src/main/java/com/oncue/auth/repository/UserLoginAccountRepository.java`
- 생성: `src/main/java/com/oncue/auth/identity_provider/IdentityProviderClient.java`
- 생성: `src/main/java/com/oncue/auth/identity_provider/KakaoIdentityProviderClient.java`
- 생성: `src/main/java/com/oncue/auth/identity_provider/XIdentityProviderClient.java`
- 생성: `src/main/java/com/oncue/common/security/AccessTokenService.java`
- 테스트: `src/test/java/com/oncue/auth/AuthServiceTest.java`

**인터페이스:**
- `POST /api/v1/auth/login`
- `LoginRequest`는 `provider`와 provider별 인증 입력을 가진다. Kakao는 `providerAccessToken`, X는 `authorizationCode`와 `codeVerifier`를 사용한다.
- `LoginResponse`는 `accessToken`, `expiresAt`, `createdAt`을 가진다.
- `IdentityProviderClient#resolve(LoginRequest): ExternalIdentity`
- `AuthService#login(LoginRequest): LoginResponse`
- `AccessTokenService#issue(User): AccessToken`

- [ ] **단계 1: 외부 identity 조회와 계정 재사용 테스트 작성**

첫 로그인, 반복 로그인, provider 계정 충돌, 지원하지 않는 provider 거부를 mock client로 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `./gradlew test --tests com.oncue.auth.AuthServiceTest`

예상 결과: auth 기능이 없으므로 실패한다.

- [ ] **단계 3: auth 서비스와 provider 경계 구현**

Kakao/X 외부 identity를 `user_login_accounts`에 매핑하고, 최초 로그인 시 사용자를 생성하며 백엔드 access token을 발급한다. Kakao client는 모바일이 전달한 provider access token으로 Kakao 사용자 정보를 확인하고, X client는 authorization code와 codeVerifier로 provider token을 교환한다. provider별 HTTP 응답 파싱은 각 `identity_provider` client 안에 둔다. MVP에서는 refresh token을 발급하지 않는다.

- [ ] **단계 4: controller와 보안 필터 추가**

`KAKAO`, `X`만 허용하고, 이후 API 요청은 `Authorization: Bearer` access token으로 인증한다.

- [ ] **단계 5: 테스트 실행 및 통과 확인**

실행: `./gradlew test --tests com.oncue.auth.AuthServiceTest`

예상 결과: 통과한다.

### 작업 4: 페르소나·시나리오 조회와 대화 정책 조합 구현

**파일:**
- 생성: `src/main/java/com/oncue/combination/model/Persona.java`
- 생성: `src/main/java/com/oncue/combination/model/Scenario.java`
- 생성: `src/main/java/com/oncue/combination/repository/PersonaRepository.java`
- 생성: `src/main/java/com/oncue/combination/repository/ScenarioRepository.java`
- 생성: `src/main/java/com/oncue/conversation/model/DialoguePolicy.java`
- 생성: `src/main/java/com/oncue/conversation/service/DialoguePolicyService.java`
- 생성: `src/main/java/com/oncue/conversation/builder/DialoguePolicyBuilder.java`
- 생성: `src/main/java/com/oncue/conversation/rules/DialogueRulesMerger.java`
- 테스트: `src/test/java/com/oncue/conversation/DialoguePolicyBuilderTest.java`

**인터페이스:**
- `PersonaRepository#findActiveByKey(String): Optional<Persona>`
- `ScenarioRepository#findActiveByKey(String): Optional<Scenario>`
- `DialoguePolicyService#build(Persona, Scenario, String scenarioContext, String callGoal, Locale): DialoguePolicy`
- `DialoguePolicy`는 보이스 서비스 계약의 `role`, `stages`, `goal`, `allowedTopics`, `forbiddenTopics`, `terminationConditions`, `language`, `voiceId`, `instructions`, `dialogueRules`, `scenarioContext`, `voiceSettings`를 제공한다.

- [x] **단계 1: 정책 조합 테스트 작성**

두 정책이 모두 있는 경우, 페르소나 정책만 있는 경우, 시나리오 정책만 있는 경우, 빈 규칙, 시나리오 규칙 우선순위, 사용자 입력이 상위 지시사항이 되지 않는 경우를 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `./gradlew test --tests com.oncue.conversation.DialoguePolicyBuilderTest`

검증 대기: 현재 실행 환경에 Gradle wrapper와 시스템 Gradle이 없어 실행하지 못했다.

- [x] **단계 3: 구조화된 정책 모델과 병합 규칙 구현**

우선순위는 `공통 안전 정책 > 시나리오 규칙 > 페르소나 규칙 > 사용자 컨텍스트·목표`로 한다. 지시사항이나 규칙이 없으면 기본 정책을 사용한다. 정책 조합을 위해 별도 LLM 호출을 하지 않는다. 공통 안전 정책은 금융·인증정보·실존 인물 사칭·음성 복제·로맨스 스캠·성적 그루밍·섹스토션·아동 대상 성적 대화·협박·스토킹·피싱·계정 탈취·폭력·납치·자해·위험 행동 유도를 금지한다. backend가 voice server에 전달하는 정책은 voice 계획의 `DialoguePolicy` 구조와 같은 JSON 필드명을 사용하며, notebook의 `policySnapshot`은 이 최종 정책을 그대로 기록한다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `./gradlew test --tests com.oncue.conversation.DialoguePolicyBuilderTest`

검증 대기: 백엔드 환경에 Gradle wrapper와 시스템 Gradle이 없어 아직 실행하지 못했다.

### 작업 5: 예약 생성·수정·조회·취소 구현

**파일:**
- 생성: `src/main/java/com/oncue/reservation/controller/ReservationController.java`
- 생성: `src/main/java/com/oncue/reservation/controller/request/CreateReservationRequest.java`
- 생성: `src/main/java/com/oncue/reservation/controller/request/UpdateReservationRequest.java`
- 생성: `src/main/java/com/oncue/reservation/controller/response/ReservationResponse.java`
- 생성: `src/main/java/com/oncue/reservation/service/ReservationService.java`
- 생성: `src/main/java/com/oncue/reservation/model/Reservation.java`
- 생성: `src/main/java/com/oncue/reservation/repository/ReservationRepository.java`
- 생성: `src/main/java/com/oncue/reservation/scheduler/ReservationLockService.java`
- 생성: `src/main/java/com/oncue/common/error/OncueExceptionHandler.java`
- 테스트: `src/test/java/com/oncue/reservation/ReservationServiceTest.java`
- 테스트: `src/test/java/com/oncue/reservation/ReservationControllerTest.java`

**인터페이스:**
- `ReservationService#create(UserId, CreateReservationRequest): ReservationResponse`
- `ReservationService#update(UserId, ReservationId, UpdateReservationRequest): ReservationResponse`
- `ReservationService#cancel(UserId, ReservationId): ReservationResponse`
- `ReservationService#list(UserId): List<ReservationResponse>`

- [x] **단계 1: 비즈니스 규칙 테스트 작성**

활성 key 개별 조회, 조합 검증을 하지 않는 동작, 현지 시각 변환, 5분 전 마감, 같은 사용자의 겹치는 예약 거부, 겹치지 않는 여러 예약 허용, 안전 차단, 취소, 소유권 확인을 테스트한다.

- [x] **단계 2: 테스트 실행 및 실패 확인**

실행: `./gradlew test --tests com.oncue.reservation.ReservationServiceTest`

실행 결과: 예약 테스트를 작성했지만 현재 환경에 Gradle wrapper와 시스템 Gradle이 없어 실행하지 못했다.

- [x] **단계 3: 예약 저장과 시간 변환 구현**

`personaKey`, `scenarioKey`, `scenarioContext`, `callGoal`, `scheduledAtLocal`, `timeZone`을 받고 key를 개별 조회한 뒤 DB ID를 저장한다. `scheduled_at_utc`를 계산한다.

- [x] **단계 4: 겹침·마감 검사 구현**

트랜잭션 안에서 해당 사용자의 예약 시간대를 조회하고, 마감 시각 이후 수정·취소를 거부하며, 5분 통화 시간대가 겹치면 거부한다.

- [x] **단계 5: 안전성 판정 서비스 연결**

결정적 규칙을 먼저 실행한다. 규칙이 위험 신호를 찾은 경우에만 `SafetyClassifierClient`를 호출한다. 판정 결과는 `SAFE`, `UNSAFE`, `FAILED` 세 가지이며, `SAFE`만 예약 저장·수정을 허용한다. `UNSAFE`는 위험 입력, `FAILED`는 애매한 입력이나 LLM 오류·타임아웃처럼 안전 여부를 확인하지 못한 경우다. 두 결과 모두 예약을 저장·수정하지 않으며, `FAILED`의 세부 원인은 내부 로그에만 남긴다.

- [x] **단계 6: REST controller와 공통 오류 추가**

`POST /api/v1/reservations`, `GET /api/v1/reservations`, `GET /api/v1/reservations/{id}`, `PATCH /api/v1/reservations/{id}`, `POST /api/v1/reservations/{id}/cancel`을 구현한다.

- [ ] **단계 7: 테스트 실행 및 통과 확인**

실행: `./gradlew test --tests com.oncue.reservation.ReservationServiceTest --tests com.oncue.reservation.ReservationControllerTest`

검증 대기: 현재 환경에 Gradle wrapper와 시스템 Gradle이 없어 컴파일·테스트 통과 여부를 확인하지 못했다. 실제 LLM 안전 판정 provider는 `SafetyClassifierClient` 경계와 fail-closed 기본 구현까지만 추가했으며, provider 연동은 별도 작업으로 남겼다.

### 작업 6: 예약 스케줄링과 보이스 세션 제어 구현

**파일:**
- 생성: `src/main/java/com/oncue/call/CallSession.java`
- 생성: `src/main/java/com/oncue/call/CallStatus.java`
- 생성: `src/main/java/com/oncue/call/CallOutcome.java`
- 생성: `src/main/java/com/oncue/call/CallResult.java`
- 생성: `src/main/java/com/oncue/call/CallSessionRepository.java`
- 생성: `src/main/java/com/oncue/call/VoiceServerClient.java`
- 생성: `src/main/java/com/oncue/call/CreateVoiceSessionRequest.java`
- 생성: `src/main/java/com/oncue/call/VoiceSessionResponse.java`
- 생성: `src/main/java/com/oncue/call/CallSessionService.java`
- 수정: `src/main/java/com/oncue/reservation/scheduler/ReservationScheduler.java`
- 테스트: `src/test/java/com/oncue/call/CallSessionServiceTest.java`

**인터페이스:**
- `VoiceServerClient#createSession(CreateVoiceSessionRequest): VoiceSessionResponse`
- `VoiceServerClient#terminateSession(String voiceSessionId): void`
- `CallSessionService#prepare(ReservationId): CallSession`
- `CallSessionService#reject(UserId, CallSessionId): CallSession`
- `CallSessionService#applyResult(CallResult): void`
- `CreateVoiceSessionRequest`는 `callSessionId`, `userId`, `policySnapshot`, `expiresAt`을 가진다. `policySnapshot`은 백엔드가 해당 세션에 사용할 최종 대화 정책 전체다.
- 거절 API 성공 응답은 `callSessionId`, `callStatus`, `callOutcome`, `createdAt`, `endedAt`을 반환한다.

- [x] **단계 1: 상태 전이 테스트 작성**

`PREPARING → RINGING → CONNECTING → IN_CALL`, 각 단계의 `SUCCEEDED`·`FAILED` 결과, 중복 결과와 종료 결과 이후 결과를 테스트한다.
수신 중인 세션을 사용자가 거절하면 보이스 세션 종료를 요청하고 `RINGING + FAILED`로 즉시 마감하는 동작도 테스트한다.

- [x] **단계 2: 테스트 실행 및 실패 확인**

실행: `./gradlew test --tests com.oncue.call.CallSessionServiceTest`.

Gradle Wrapper를 추가하기 전에는 실행 환경이 없어 검증하지 못했으며, Wrapper 추가 후에는 구현 전제의 실패 확인을 거쳐 통과 상태를 확인했다.

- [x] **단계 3: 통화 세션 모델과 전이 구현**

예약 하나당 세션 하나만 만들고 `callStatus`, `callOutcome`, 시간, 외부 `voiceSessionId`를 저장한다. 통화 종료 뒤에도 `callStatus`는 마지막 진행 단계를 유지한다. 음성·대화 텍스트는 저장하지 않는다.

`prepare()`는 먼저 DB의 `callSessionId`를 확보한 뒤 보이스 서버에 요청한다. 요청에는 `callSessionId`, `userId`, 최종 `policySnapshot`, `expiresAt`을 포함하며, `expiresAt`은 `scheduledAtUtc + 7분`으로 계산한다. 현재 구현은 보이스 서버 호출 경계(`VoiceServerClient`)까지만 제공하고 실제 HTTP 어댑터는 다음 단계에서 추가한다.

- [x] **단계 4: 스케줄러와 보이스 서버 client 구현**

`prepareAt = scheduledAtUtc - 3분`을 계산한다. 준비 worker는 1분마다 `prepareAt`이 지났고 아직 통화 세션이 없는 예약만 조회한다. 트랜잭션과 예약별 중복 방지 조건으로 한 예약이 두 번 준비되지 않게 한다. 활성 페르소나·시나리오를 독립적으로 읽고, 대화 정책을 만들고, 보이스 서버에 보이스 세션 준비 데이터와 정책 스냅샷을 보낸다. 이 단계에서는 실제 WebRTC·STT·LLM·TTS 연결을 열지 않는다.

`RestVoiceServerClient`가 `/internal/v1/voice-sessions` 생성·종료 API를 내부 Bearer 토큰으로 호출하고, `ReservationPreparationScheduler`가 `@Scheduled` 1분 주기로 due 예약을 준비한다. 예약 시각에는 준비된 세션을 `PREPARING → RINGING`으로 전환하고 APNs VoIP Push를 전송한다. 보이스 서버 URL과 내부 서비스 토큰은 `VOICE_SERVER_URL`, `VOICE_INTERNAL_SERVICE_TOKEN` 환경 변수로 주입한다. APNs는 `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY_FILE` 환경 변수로 주입한다.

- [x] **단계 6: 예약 시각의 `RINGING` 전환과 APNs 전송 구현**

예약 시각이 지난 `PREPARING` 세션을 한 번만 `RINGING`으로 전환하고 등록된 기기에 APNs VoIP Push를 보낸다. 기기 토큰이 없거나 APNs 전송이 실패하면 `RINGING + FAILED`로 종료한다. 이미 종료된 세션이나 취소된 예약은 변경하지 않는다. Foreground WebSocket, 주기 조회, 앱 타이머는 구현하지 않는다.

- [x] **단계 5: 테스트 실행 및 통과 확인**

실행: `JAVA_HOME=... ./gradlew clean test`

JDK 21 기준 전체 테스트가 통과했다. 스케줄러, 보이스 HTTP 어댑터, 연결 토큰은 작업 6의 남은 범위다.

### 작업 7: 연결 토큰과 보이스 통화 결과 구현

**파일:**
- 생성: `src/main/java/com/oncue/call/controller/CallSessionController.java`
- 생성: `src/main/java/com/oncue/call/controller/response/ConnectionTokenResponse.java`
- 생성: `src/main/java/com/oncue/call/service/ConnectionTokenService.java`
- 생성: `src/main/java/com/oncue/call/voice_server/VoiceCallResultRequest.java`
- 생성: `src/main/java/com/oncue/call/controller/InternalCallSessionController.java`
- 생성: `src/main/java/com/oncue/common/security/ServiceTokenValidator.java`
- 테스트: `src/test/java/com/oncue/call/ConnectionTokenServiceTest.java`
- 테스트: `src/test/java/com/oncue/call/InternalCallSessionControllerTest.java`

**인터페이스:**
- `ConnectionTokenService#issue(UserId, CallSessionId): ConnectionTokenResponse`
- `CallSessionService#applyResult(CallResult): void`

- [x] **단계 1: 연결 토큰 테스트 작성**

소유자만 토큰을 발급받는지, 종료·미준비 세션을 거부하는지, 토큰의 `callSessionId`, `userId`, `scope`, `jti`, `iat`, `exp`와 ICE `urls` 배열을 검증한다.

- [x] **단계 2: 테스트 실행 및 실패 확인**

실행: `./gradlew test --tests com.oncue.call.ConnectionTokenServiceTest --tests com.oncue.call.ConnectionTokenControllerTest`

연결 토큰과 컨트롤러가 없던 상태에서는 실패했으며, 구현 후 해당 테스트가 통과했다.

- [x] **단계 3: 서명된 연결 토큰 구현**

통화 연결 토큰은 백엔드 개인키로 RS256 서명하고 1분 후 만료시킨다. 보이스 서버는 대응하는 공개키로 검증한다. 로그인 access token용 HMAC secret과 통화 연결 토큰용 RSA 키 쌍은 분리한다. signaling URL, 토큰, `createdAt`, `expiresAt`, ICE 서버 자격 정보를 반환하며 모바일 access token은 보이스 서버 요청에 넣지 않는다. 현재 구현은 `VOICE_JWT_PRIVATE_KEY`, `VOICE_JWT_PRIVATE_KEY_FILE`, `ONCUE_VOICE_SIGNALING_URL`, `ONCUE_VOICE_ICE_SERVERS_URLS`, `ONCUE_VOICE_ICE_SERVERS_USERNAME`, `ONCUE_VOICE_ICE_SERVERS_CREDENTIAL` 환경 변수에 대응하는 `oncue.voice.*` 설정을 사용한다.

- [x] **단계 4: 내부 통화 결과 처리 구현**

보이스 서버 callback은 `oncue.voice.service-token`을 Bearer 토큰으로 검증한다. `callSessionId` 기준으로 도착한 최종 결과를 기존 서비스에 위임하며, 같은 결과는 상태를 중복 변경하지 않고 이미 접수된 것으로 처리하고, 다른 결과가 늦게 오면 상태를 바꾸지 않는다. 내부 callback 경로는 access token 인증 대상에서 제외하고 callback controller가 service token을 직접 검증한다.

- [x] **단계 5: 하루 1회 상태 보정 작업 구현**

`callOutcome`이 비어 있고 `scheduledAtUtc + 7분`이 지난 세션을 조회한다. 마지막 `callStatus`가 `PREPARING`, `RINGING` 또는 `CONNECTING`이면 `FAILED`, `IN_CALL`이면 `SUCCEEDED`로 보정한다. 보정 작업은 통화 재시도가 아니라 누락된 최종 결과를 정리하는 작업이며, UTC 기준 하루 1회 cron으로 실행한다.

- [x] **단계 6: 테스트 실행 및 통과 확인**

실행: `./gradlew clean test`

JDK 21 기준 백엔드 전체 테스트가 통과했다.

### 작업 8: 통합 검증과 Docker 상태 확인 추가

**파일:**
- 생성: `src/test/java/com/oncue/integration/ReservationToCallIntegrationTest.java`
- 생성: `src/main/java/com/oncue/common/web/RequestIdFilter.java`
- 수정: `src/main/resources/application.yml`
- 수정: `Dockerfile`

**인터페이스:**
- 백엔드가 음성을 중계하지 않고 예약부터 보이스 세션 경계까지 동작하는지 검증한다.

- [x] **단계 1: 백엔드 전체 흐름 통합 테스트 작성**

MySQL과 Redis Testcontainers를 사용한다. 사용자 생성, key를 이용한 안전한 예약, 통화 세션 준비, 연결 토큰 발급, `IN_CALL` 상태의 최종 결과 전달을 수행하고 저장된 상태를 검증한다.

- [x] **단계 2: 통합 테스트 실행 및 실패 확인**

실행: `JAVA_HOME=... ./gradlew integrationTest --tests com.oncue.integration.ReservationToCallIntegrationTest`

처음에는 테스트의 응답 필드명이 `connectionToken`이 아니라 `token`으로 작성되어 실패했고, 계약에 맞게 수정한 뒤 통과했다.

- [x] **단계 3: request ID, health check, 안전한 컨테이너 설정 추가**

오류 응답에 `requestId`와 `createdAt`을 넣고, 비밀값을 노출하지 않는 의존성 health check를 제공하며, Docker 애플리케이션을 non-root 사용자로 실행한다.

- [x] **단계 4: 전체 백엔드 검증 실행**

실행: `JAVA_HOME=... ./gradlew clean test integrationTest`

결과: JDK 21 기준 일반 테스트와 MySQL·Redis Testcontainers 통합 테스트가 통과했다. Docker 이미지 build와 로컬 Compose 재기동도 통과했고, backend 컨테이너는 `oncue` non-root 사용자로 `healthy` 상태가 되었다.
