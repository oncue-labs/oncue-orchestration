# OnCue 보이스 MVP 구현 계획

> **에이전트 작업자 필수 안내:** 이 계획을 작업별로 실행할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 작업 단계는 추적할 수 있도록 체크박스(`- [ ]`)로 작성되어 있다.

**목표:** 짧은 만료 시간의 세션 접근을 인증하고, WebRTC 음성을 연결하며, 대화 정책에 따른 STT·LLM·TTS 대화를 실행하고, 통화 상태를 백엔드에 전달하는 독립 Python 음성 서비스를 구축한다.

**아키텍처:** `src/oncue_voice` 패키지 안에서 API, session, media, conversation, providers를 기능별로 나눈다. 이 서비스는 비즈니스 DB에 의존하지 않고 백엔드가 전달한 구조화된 대화 정책을 받아 실행한다.

**기술 스택:** Python 3.11, Poetry, FastAPI, Uvicorn, asyncio, aiortc, Pydantic, 짧은 기술 상태 저장용 Redis, pytest, pytest-asyncio, HTTPX.

**사양:** `docs/superpowers/specs/2026-09-08-oncue-mvp-design.md`, `docs/superpowers/specs/2026-09-09-oncue-mvp-api-data-contract.md`

## 전체 제약 조건

- Python 3.11, Poetry, `src/oncue_voice` 패키지, 타입 힌트, wildcard import 금지를 사용한다.
- 사용자·예약·페르소나 DB에 직접 의존하지 않는다.
- 활성 상태인 모든 페르소나·시나리오 조합을 받아들이고, 전달받은 대화 정책 또는 기본 정책을 실행한다.
- 모바일 연결 토큰을 독립적으로 검증하고 토큰 비밀값을 로그에 남기지 않는다.
- JSON에는 `createdAt`을 사용하고 시간은 UTC로 처리한다.
- 음성, 대화 텍스트, 장기 사용자 데이터를 저장하지 않는다.
- 60초 수신 대기와 300초 최대 통화 시간을 적용한다.
- STT, LLM, TTS는 provider별 adapter 뒤에 두며 Public LLM을 MVP 기본 방향으로 사용한다. Local LLM은 선택 사항이다.
- 외부 전화번호 발신, 음성 복제, 반복 통화, 사용자 페르소나 생성은 추가하지 않는다.

---

### 작업 1: Python 패키지와 서비스 시작점 만들기

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-voice/pyproject.toml`
- 생성: `/Users/yeonny0723/orca/oncue-voice/poetry.lock`
- 생성: `/Users/yeonny0723/orca/oncue-voice/Dockerfile`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/main.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/config.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/tests/unit/test_health.py`

**인터페이스:**
- 환경 변수 기반 설정과 health endpoint를 제공하는 FastAPI 앱을 만든다.

- [ ] **단계 1: health 실패 테스트 작성**

```python
def test_health_endpoint_returns_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
```

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/test_health.py -q`

예상 결과: 패키지와 endpoint가 없으므로 실패한다.

- [ ] **단계 3: 패키지와 health endpoint 구현**

FastAPI, Uvicorn, Pydantic settings, 구조화된 로깅, non-root Docker 이미지를 설정한다. 새로운 서비스에서는 기존 `run.sh`를 사용하지 않는다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/unit/test_health.py -q`

예상 결과: 통과한다.

### 작업 2: 독립적인 토큰 인증과 세션 모델 구현

**파일:**
- 생성: `src/oncue_voice/session/models.py`
- 생성: `src/oncue_voice/session/auth.py`
- 생성: `src/oncue_voice/session/service.py`
- 생성: `tests/unit/session/test_auth.py`
- 생성: `tests/unit/session/test_service.py`

**인터페이스:**
- `ConnectionTokenVerifier#verify(token: str, session_id: str): ConnectionClaims`
- `SessionService#create(request: CreateSessionRequest): VoiceSession`
- `SessionService#close(session_id: str, reason: str): None`

- [ ] **단계 1: 토큰 검증 테스트 작성**

유효한 서명, 만료 토큰, 다른 session ID, 다른 user claim, scope 누락, 이미 사용한 `jti`를 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/session -q`

예상 결과: verifier와 session service가 없으므로 실패한다.

- [ ] **단계 3: 검증과 짧은 기술 상태 구현**

백엔드 공개키로 서명된 토큰을 검증한다. 사용한 `jti`는 토큰 TTL 동안 Redis에 저장하고, 비즈니스 데이터가 아닌 기술 세션 상태만 Redis 또는 메모리에 보관한다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/unit/session -q`

예상 결과: 통과한다.

### 작업 3: 내부 세션 제어와 상태 callback 구현

**파일:**
- 생성: `src/oncue_voice/api/http.py`
- 생성: `src/oncue_voice/api/schemas.py`
- 생성: `src/oncue_voice/api/events.py`
- 생성: `src/oncue_voice/session/events.py`
- 생성: `tests/unit/api/test_session_api.py`

**인터페이스:**
- `POST /internal/v1/voice-sessions`
- `POST /internal/v1/voice-sessions/{session_id}/terminate`
- `VoiceStatusCallbackClient#sendEvent(session_id: str, event: SessionEvent): None`가 백엔드의 `POST /internal/v1/call-sessions/{session_id}/events`를 호출한다.

- [ ] **단계 1: 세션 생성·종료 API 테스트 작성**

서비스 간 인증, 필수 정책 필드, 중복 세션 생성의 멱등성, 종료된 세션 처리를 검증한다.

- [ ] **단계 2: API 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/api/test_session_api.py -q`

예상 결과: route가 없으므로 실패한다.

- [ ] **단계 3: 내부 제어 route 구현**

백엔드 요청에는 별도의 서비스 자격 증명을 사용한다. 모바일 사용자 access token은 내부 route에서 받지 않는다. 상태 이벤트는 타입이 지정된 callback client로 백엔드에 보낸다.

- [ ] **단계 4: API 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/unit/api/test_session_api.py -q`

예상 결과: 통과한다.

### 작업 4: provider 계약과 결정적인 테스트 double 정의

**파일:**
- 생성: `src/oncue_voice/providers/llm_provider.py`
- 생성: `src/oncue_voice/providers/stt_provider.py`
- 생성: `src/oncue_voice/providers/tts_provider.py`
- 생성: `src/oncue_voice/providers/fake_llm_provider.py`
- 생성: `src/oncue_voice/providers/fake_stt_provider.py`
- 생성: `src/oncue_voice/providers/fake_tts_provider.py`
- 생성: `tests/unit/providers/test_provider_contracts.py`

**인터페이스:**
- `LlmProvider#stream_reply(policy: DialoguePolicy, turns: AsyncIterator[UserTurn]): AsyncIterator[AssistantChunk]`
- `SttProvider#stream_transcribe(audio: AsyncIterator[bytes]): AsyncIterator[TranscriptSegment]`
- `TtsProvider#stream_synthesize(text: str): AsyncIterator[bytes]`

- [ ] **단계 1: fake provider 계약 테스트 작성**

순서가 보장된 chunk, 취소, provider timeout, provider 오류 전달을 검증한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/providers/test_provider_contracts.py -q`

예상 결과: provider 계약이 없으므로 실패한다.

- [ ] **단계 3: typed protocol과 fake 구현**

provider 선택은 설정에서 처리한다. fake 구현은 네트워크 없이 모든 runtime 테스트에 사용할 수 있어야 한다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/unit/providers/test_provider_contracts.py -q`

예상 결과: 통과한다.

### 작업 5: WebRTC 시그널링과 미디어 생명주기 구현

**파일:**
- 생성: `src/oncue_voice/api/signaling.py`
- 생성: `src/oncue_voice/media/webrtc.py`
- 생성: `src/oncue_voice/media/audio.py`
- 생성: `tests/unit/media/test_webrtc.py`
- 생성: `tests/integration/test_webrtc_signaling.py`

**인터페이스:**
- `POST /v1/sessions/{session_id}/webrtc/offer`
- `WebRtcSession#accept_offer(offer: SdpOffer): SdpAnswer`
- `WebRtcSession#close(reason: str): None`

- [ ] **단계 1: 시그널링 테스트 작성**

유효한 연결 토큰, 잘못된 토큰, 모르는 세션, 잘못된 SDP, offer 수락, 종료 동작을 테스트한다. 단위 테스트에서는 fake peer connection을 사용한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/media tests/integration/test_webrtc_signaling.py -q`

예상 결과: 시그널링과 미디어 모듈이 없으므로 실패한다.

- [ ] **단계 3: aiortc 시그널링과 음성 track 구현**

offer를 받기 전에 연결 토큰을 검증한다. 세션 요청에서 ICE 서버를 구성하고, 백엔드가 제공한 STUN/TURN 자격 정보를 사용하며, SDP나 오디오 내용을 로그에 남기지 않는다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/unit/media tests/integration/test_webrtc_signaling.py -q`

예상 결과: 필요한 WebRTC 테스트 의존성이 있는 환경에서 통과한다.

### 작업 6: 대화 정책 기반 runtime 구현

**파일:**
- 생성: `src/oncue_voice/conversation/policy.py`
- 생성: `src/oncue_voice/conversation/runtime.py`
- 생성: `src/oncue_voice/conversation/events.py`
- 생성: `tests/unit/conversation/test_runtime.py`

**인터페이스:**
- `ConversationRuntime#run(session: VoiceSession, policy: DialoguePolicy, audio: AsyncIterator[bytes]): AsyncIterator[bytes]`
- `ConversationRuntime#stop(session_id: str, reason: str): None`

- [ ] **단계 1: runtime 테스트 작성**

STT→LLM→TTS 순서, 정책 전달, provider timeout, 침묵, 사용자 종료, 안전 거부, 5분 종료를 테스트한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/conversation/test_runtime.py -q`

예상 결과: runtime이 없으므로 실패한다.

- [ ] **단계 3: 비동기 대화 loop 구현**

사용자 컨텍스트와 목표는 provider 정책보다 낮은 우선순위의 신뢰하지 않은 데이터로 취급한다. 응답 생성 전에 공통 안전 규칙과 시나리오 규칙을 적용한다. 외부에는 상태 이벤트와 오디오 frame만 내보낸다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/unit/conversation/test_runtime.py -q`

예상 결과: 통과한다.

### 작업 7: Public provider adapter와 서비스 연결

**파일:**
- 생성: `src/oncue_voice/providers/public_llm_provider.py`
- 생성: `src/oncue_voice/providers/public_stt_provider.py`
- 생성: `src/oncue_voice/providers/public_tts_provider.py`
- 수정: `src/oncue_voice/config.py`
- 수정: `src/oncue_voice/main.py`
- 생성: `tests/integration/providers/test_public_provider_adapters.py`

**인터페이스:**
- 각 Public adapter는 작업 4의 provider protocol을 구현하고, 자격 증명은 환경 변수 설정에서만 읽는다.

- [ ] **단계 1: 구체적인 Public STT·LLM·TTS 제공자 선택**

adapter를 구현하기 전에 선택한 서비스의 API 버전, streaming 방식, timeout, 데이터 보존 설정, 오류 매핑을 provider README에 기록한다. provider protocol은 변경하지 않는다.

- [ ] **단계 2: mock 응답 기반 adapter 테스트 작성**

정상 streaming, 인증 실패, rate limit, timeout, 잘못된 provider 응답, 취소를 테스트한다.

- [ ] **단계 3: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/integration/providers/test_public_provider_adapters.py -q`

예상 결과: 구체적인 adapter가 없으므로 실패한다.

- [ ] **단계 4: adapter와 설정 연결 구현**

provider별 직렬화는 각 adapter 안에 둔다. provider SDK 타입을 `conversation/runtime.py`로 가져오지 않는다.

- [ ] **단계 5: 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/integration/providers/test_public_provider_adapters.py -q`

예상 결과: mock provider 응답 기준으로 통과한다.

### 작업 8: TURN 설정, 컨테이너 검증, 전체 테스트 추가

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-voice/docker/turn/coturn.conf`
- 생성: `/Users/yeonny0723/orca/oncue-voice/docker/turn/README.md`
- 생성: `/Users/yeonny0723/orca/oncue-voice/.dockerignore`
- 생성: `/Users/yeonny0723/orca/oncue-voice/tests/integration/test_session_to_audio.py`
- 수정: `/Users/yeonny0723/orca/oncue-voice/Dockerfile`

**인터페이스:**
- 오케스트레이션 Compose가 사용하는 coturn 참고 설정을 제공한다. TURN 설정을 `oncue-orchestration`에 두지 않는다.

- [ ] **단계 1: 세션부터 오디오까지 통합 테스트 작성**

fake provider로 세션을 만들고 offer를 인증하며 테스트 오디오 track을 교환한다. 출력 track과 최종 상태 callback을 확인하고 오디오가 저장되지 않는지 검증한다.

- [ ] **단계 2: 통합 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/integration/test_session_to_audio.py -q`

예상 결과: 세션, 시그널링, 미디어, runtime 연결 전이므로 실패한다.

- [ ] **단계 3: coturn 참고 설정과 컨테이너 검사 추가**

realm, 외부 주소, 자격 정보, 포트는 환경 변수에서 받는다. `coturn.conf`에 비밀값을 넣지 않고 README에 필요한 변수를 기록한다.

- [ ] **단계 4: 전체 Python 검증 실행**

실행: `poetry run pytest` 및 `docker build -t oncue-voice:test .`

예상 결과: 테스트가 통과하고 이미지가 빌드된다.
