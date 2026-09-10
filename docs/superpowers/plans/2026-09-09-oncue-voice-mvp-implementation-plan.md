# OnCue 보이스 MVP 구현 계획

> **에이전트 작업자 필수 안내:** 이 계획을 작업별로 실행할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 작업 단계는 추적할 수 있도록 체크박스(`- [ ]`)로 작성되어 있다.

**목표:** provider 교체가 가능한 Python 음성 서비스를 먼저 만들고, 하나의 Public STT·LLM·TTS provider 조합과 하위 모델·voice 설정을 Jupyter notebook에서 검증한 뒤, 인증된 WebRTC 통화와 최종 결과 callback을 구현한다.

**아키텍처:** `src/oncue_voice` 패키지 안에서 provider interface·factory, 대화 정책·runtime, session, media를 기능별로 나눈다. 대화 runtime은 provider SDK에 직접 의존하지 않고 공통 interface를 사용한다. `notebooks/voice_persona_scenario_evaluation.ipynb`는 실제 `oncue-voice` service code를 사용해 평가하며, notebook 안에 STT·LLM·TTS나 별도 대화 처리 모듈을 구현하지 않는다.

**기술 스택:** Python 3.11, Poetry, FastAPI, Uvicorn, asyncio, aiortc, Pydantic, 짧은 기술 상태 저장용 Redis, Jupyter, pytest, pytest-asyncio, HTTPX.

**사양:** `docs/superpowers/specs/2026-09-08-oncue-mvp-design.md`, `docs/superpowers/specs/2026-09-09-oncue-mvp-api-data-contract.md`, `docs/superpowers/specs/2026-09-09-oncue-voice-evaluation-design.md`

## 전체 제약 조건

- Python 3.11, Poetry, `src/oncue_voice` 패키지, 타입 힌트, wildcard import 금지를 사용한다.
- 사용자·예약·페르소나 DB에 직접 의존하지 않는다.
- 활성 상태인 모든 페르소나·시나리오 조합을 받아들이고, 전달받은 대화 정책 또는 기본 정책을 실행한다.
- 대화 runtime은 `LlmProvider`, `SttProvider`, `TtsProvider` interface에만 의존하며 provider SDK를 직접 import하지 않는다.
- `ProviderFactory`를 통해 provider 종류와 모델·voice 설정을 선택한다. MVP에서 실제 연결하는 기준은 하나의 Public provider 조합이다.
- 기준 Public provider가 충분하지 않을 때만 같은 interface에 두 번째 Public provider adapter를 추가한다.
- Local provider를 나중에 연결할 확장 지점은 두지만 MVP에서 Local provider 구현이나 Local LLM Compose service는 추가하지 않는다.
- 모바일 연결 토큰을 독립적으로 검증하고 토큰 비밀값을 로그에 남기지 않는다.
- JSON에는 `createdAt`을 사용하고 시간은 UTC로 처리한다.
- 음성, 운영 통화 대화 텍스트, 장기 사용자 데이터를 운영 환경에 저장하지 않는다.
- Jupyter 평가 결과는 합성 테스트 데이터에 한해 `notebooks/artifacts/`에 로컬 저장하고 Git에서 제외한다.
- 평가 실행 당시 runtime에 전달한 최종 대화 정책 전체를 `policySnapshot`으로 저장하며, 정책 버전 번호를 사용하지 않는다.
- 60초 수신 대기와 300초 최대 통화 시간을 적용한다.
- 외부 전화번호 발신, 음성 복제, 반복 통화, 사용자 페르소나 생성은 추가하지 않는다.

---

### 작업 1: provider 중립 interface·factory와 Python 서비스 뼈대 만들기

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-voice/pyproject.toml`
- 생성: `/Users/yeonny0723/orca/oncue-voice/poetry.lock`
- 생성: `/Users/yeonny0723/orca/oncue-voice/Dockerfile`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/main.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/config.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/llm_provider.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/stt_provider.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/tts_provider.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/models.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/factory.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/.gitignore`
- 생성: `/Users/yeonny0723/orca/oncue-voice/tests/unit/test_health.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/tests/unit/providers/test_provider_factory.py`

**인터페이스:**
- `LlmProvider#stream_reply(policy: DialoguePolicy, turns: AsyncIterator[UserTurn]): AsyncIterator[AssistantChunk]`
- `SttProvider#stream_transcribe(audio: AsyncIterator[bytes]): AsyncIterator[TranscriptSegment]`
- `TtsProvider#stream_synthesize(text: str): AsyncIterator[bytes]`
- `ProviderFactory#create(settings: ProviderSettings): ProviderBundle`
- `ProviderSettings`는 `provider`, `llmModel`, `sttModel`, `ttsVoiceId`, `ttsOptions`를 가진다.
- `ProviderBundle`은 `llm: LlmProvider`, `stt: SttProvider`, `tts: TtsProvider`를 가진다.
- `ProviderCapabilities`는 provider가 지원하는 모델·voice·음성 설정 목록을 표현한다.
- 환경 변수 기반 설정과 `GET /health` endpoint를 제공하는 FastAPI 앱

- [x] **단계 1: factory와 health 실패 테스트 작성**

지원 provider 설정이 `ProviderBundle`을 반환하고 지원하지 않는 provider·voice 옵션을 명시적으로 거부하는 테스트를 작성한다. health endpoint가 `{"status": "ok"}`를 반환하는 테스트도 작성한다.

- [x] **단계 2: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/test_health.py tests/unit/providers/test_provider_factory.py -q`

예상 결과: 패키지, factory, endpoint가 없으므로 실패한다.

- [x] **단계 3: provider protocol·설정 모델·factory 구현**

provider별 SDK 타입이 밖으로 노출되지 않는 `ProviderSettings`, `ProviderCapabilities`, `ProviderBundle`을 만든다. `ProviderFactory`는 provider 이름과 설정을 받아 등록된 adapter를 선택하고, capability에 없는 설정은 조용히 무시하지 않고 오류로 반환한다. `pyproject.toml`에는 runtime 의존성과 Jupyter·`ipykernel`·`nbclient` 등 평가용 개발 의존성을 분리해 기록한다.

- [x] **단계 4: health와 factory 테스트 실행**

실행: `poetry run pytest tests/unit/test_health.py tests/unit/providers/test_provider_factory.py -q`

예상 결과: 통과한다.

### 작업 2: fake provider와 대화 정책·runtime 구현

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/fake_llm_provider.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/fake_stt_provider.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/fake_tts_provider.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/conversation/models.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/conversation/runtime.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/conversation/events.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/tests/unit/providers/test_provider_contracts.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/tests/unit/conversation/test_runtime.py`

**인터페이스:**
- `DialoguePolicy`는 `role`, `stages`, `goal`, `allowedTopics`, `forbiddenTopics`, `terminationConditions`, `language`, `voiceId`, `instructions`, `dialogueRules`, `scenarioContext`, `voiceSettings`를 가진다.
- `UserTurn`은 `text`, `createdAt`을 가진다. `AssistantChunk`는 `text`, `sequence`를 가진다. `TranscriptSegment`는 `text`, `isFinal`, `startMs`, `endMs`를 가진다.
- `ConversationRuntime#run(session_id: str, policy: DialoguePolicy, audio: AsyncIterator[bytes]): AsyncIterator[bytes]`
- `ConversationRuntime#stop(session_id: str, reason: str): None`
- `ConversationRuntimeOptions`는 clock, 최대 통화 시간, 이벤트 sink를 주입한다.
- `ConversationEvent`는 사용자 발화와 assistant chunk를 관찰하기 위한 내부 이벤트다.

- [x] **단계 1: provider contract와 runtime 실패 테스트 작성**

순서가 보장된 chunk, 취소, provider timeout, provider 오류 전달을 테스트한다. STT→LLM→TTS 순서, 정책 전달, 침묵, 사용자 종료, 안전 거부, 5분 종료를 fake provider로 테스트한다.

- [x] **단계 2: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/providers/test_provider_contracts.py tests/unit/conversation/test_runtime.py -q`

예상 결과: fake provider, 정책 model, runtime이 없으므로 실패한다.

- [x] **단계 3: 정책 model·fake provider·비동기 runtime 구현**

Pydantic model이 backend가 전달하는 camelCase 정책 JSON을 읽고 Python 내부에서는 일관된 타입으로 사용하도록 한다. fake provider는 네트워크 없이 고정된 transcript와 audio chunk를 반환한다. runtime은 provider interface만 호출하고 금지 주제 입력을 감지하면 응답을 생성하지 않으며, 중지 요청과 5분 제한을 처리한다. 실제 보안 판정과 시나리오 정책 생성은 backend 책임으로 남긴다.

- [x] **단계 4: provider와 runtime 테스트 실행**

실행: `poetry run pytest tests/unit/providers/test_provider_contracts.py tests/unit/conversation/test_runtime.py -q`

예상 결과: 통과한다.

### 작업 3: OpenAI 기준 Public provider adapter 구현

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/openai_llm_provider.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/openai_stt_provider.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/openai_tts_provider.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/docs/providers/openai.md`
- 수정: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/config.py`
- 수정: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/factory.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/errors.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/tests/integration/providers/test_openai_provider_adapters.py`

**인터페이스:**
- `OpenAiLlmProvider`, `OpenAiSttProvider`, `OpenAiTtsProvider`는 작업 1의 provider protocol을 각각 구현한다.
- 자격 증명은 환경 변수에서만 읽고 provider SDK 타입은 `providers/` adapter 밖으로 내보내지 않는다.
- adapter는 모델·voice·provider 지원 옵션을 검증하고 `ProviderError` 계열 공통 오류 타입으로 변환한다.

- [x] **단계 1: 기준 provider와 지원 항목 기록**

OpenAI STT·LLM·TTS 각각의 API 버전, streaming 방식, timeout, 데이터 보존 설정, 모델·voice·속도·톤·감정 옵션의 지원 여부를 `docs/providers/openai.md`에 기록한다. 지원하지 않는 조정 항목은 불가능하다고 기록한다.

- [x] **단계 2: mock 응답 기반 adapter 실패 테스트 작성**

정상 streaming, 인증 실패, rate limit, timeout, 잘못된 provider 응답, 취소, 지원하지 않는 voice 옵션을 테스트한다.

- [x] **단계 3: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/integration/providers/test_openai_provider_adapters.py -q`

예상 결과: 기준 Public adapter가 없으므로 실패한다.

- [x] **단계 4: adapter와 factory 연결 구현**

provider별 직렬화와 오류 매핑은 각 adapter 안에 둔다. `ProviderFactory`가 기준 provider 설정에 맞는 adapter bundle을 반환하도록 연결하고, 실제 API 호출은 환경 변수로 활성화한다.

- [x] **단계 5: mock adapter 테스트 실행**

실행: `poetry run pytest tests/integration/providers/test_openai_provider_adapters.py -q`

예상 결과: 통과한다.

### 작업 4: Jupyter 기반 음성·대화 품질 평가와 A/B 실행 구현

**파일:**
- 생성: `/Users/yeonny0723/orca/oncue-voice/notebooks/voice_persona_scenario_evaluation.ipynb`
- 생성: `/Users/yeonny0723/orca/oncue-voice/notebooks/README.md`
- 생성: `/Users/yeonny0723/orca/oncue-voice/notebooks/artifacts/.gitkeep`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/evaluation/service.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/evaluation/factories.py`
- 생성: `/Users/yeonny0723/orca/oncue-voice/tests/evaluation/test_evaluation_service.py`
- 수정: `/Users/yeonny0723/orca/oncue-voice/.gitignore`
- 생성: `/Users/yeonny0723/orca/oncue-voice/tests/evaluation/test_evaluation_notebook.py`

**인터페이스:**
- `EvaluationService`가 `ProviderFactory#create`, `ConversationRuntime#run`, `DialoguePolicy`를 사용하고 notebook은 이 서비스만 호출한다.
- 실행 결과는 `run.json`, `policy-snapshot.json`, `provider-config.json`, `input.json`, `transcript.json`, `response.wav`, `evaluation.md`로 저장한다.
- `policySnapshot`은 해당 실행의 variant가 적용된 최종 정책 전체를 저장한다. `policyVersion`을 요구하지 않는다.

- [x] **단계 1: fake provider를 사용하는 notebook 실행 테스트 작성**

notebook이 fake provider로 실행되고, 네 가지 MVP 통화 조합의 합성 입력을 처리하며, 정책 snapshot·텍스트·음성·평가 파일을 생성하는지 테스트한다. API key나 token이 artifact에 기록되지 않는지도 검증한다.

- [x] **단계 2: notebook 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/evaluation/test_evaluation_notebook.py -q`

예상 결과: notebook과 평가 실행 규칙이 없으므로 실패한다.

- [x] **단계 3: 서비스 코드만 사용하는 notebook 작성**

notebook은 테스트 케이스, variant, 실행 요청, 결과 표시, 사람이 입력하는 1~5점과 코멘트만 담당한다. STT·LLM·TTS 구현과 별도 대화 loop를 notebook에 작성하지 않는다. 동일한 입력으로 한 번에 하나의 주요 변수만 바꾸고, 정책을 바꾼 실행은 각각의 `policySnapshot`을 저장한다.

- [x] **단계 4: 로컬 artifact와 개인정보 제한 추가**

`notebooks/artifacts/`를 Git에서 제외한다. 합성 테스트 데이터만 사용하고 실제 이름·전화번호·가족 정보·계정 정보·실제 인물의 음성을 사용하지 않는다. provider 설정에는 API key, token, password를 저장하지 않는다.

- [x] **단계 5: notebook fake 실행 검증**

실행: `poetry run pytest tests/evaluation/test_evaluation_notebook.py -q` 및 `poetry run jupyter nbconvert --execute --to notebook --ExecutePreprocessor.kernel_name=python3 notebooks/voice_persona_scenario_evaluation.ipynb --output /tmp/oncue-voice-evaluation.ipynb`

예상 결과: fake provider로 notebook이 재현 가능하게 실행되고 artifact가 생성된다.

- [ ] **단계 6: Public provider A/B 수동 평가 실행**

실행: `poetry run jupyter lab notebooks/voice_persona_scenario_evaluation.ipynb`

같은 입력으로 하위 LLM 모델·prompt·temperature·TTS voice ID·지원되는 음성 설정을 비교한다. 음성 품질, 페르소나 일관성, 시나리오 목표, 안전성을 사람이 평가하고 첫 음성까지의 시간과 응답 지연을 기록한다. 기준 provider가 충분하지 않으면 이 결과를 근거로 두 번째 Public provider adapter를 별도 작업으로 추가한다.

### 작업 5: 독립적인 토큰 인증과 세션 모델 구현

**파일:**
- 생성: `src/oncue_voice/session/models.py`
- 생성: `src/oncue_voice/session/auth.py`
- 생성: `src/oncue_voice/session/store.py`
- 생성: `src/oncue_voice/session/service.py`
- 생성: `tests/unit/session/test_auth.py`
- 생성: `tests/unit/session/test_service.py`

**인터페이스:**
- `ConnectionTokenVerifier#verify(token: str, call_session_id: str, user_id: str | None): ConnectionClaims`
- `ConnectionClaims`는 `callSessionId`, `userId`, `exp`, `jti`, `iat`, `scope`를 가진다.
- `callSessionId`는 백엔드와 모바일이 공유하는 통화 식별자이며, `voiceSessionId`는 보이스 서버가 생성하는 내부 식별자다.
- `SessionService#create(request: CreateSessionRequest): VoiceSession`
- `SessionService#close(voice_session_id: str, reason: str): None`
- `CreateSessionRequest`는 `callSessionId`, `userId`, `policy`, `expiresAt`을 가진다. `expiresAt`은 준비된 보이스 세션을 정리할 만료 시각이며 연결 시작 시각이나 연결 토큰의 만료 시각이 아니다. `VoiceSession`은 `voiceSessionId`, `callSessionId`, `userId`, `policy`, `expiresAt`, `status`, `createdAt`을 가진다.

- [x] **단계 1: 토큰 검증 테스트 작성**

유효한 서명, 만료 토큰, 다른 session ID, 다른 user claim, scope 누락, 이미 사용한 `jti`를 테스트한다.

- [x] **단계 2: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/session -q`

예상 결과: verifier와 session service가 없으므로 실패한다.

- [x] **단계 3: 검증과 짧은 기술 상태 구현**

백엔드 공개키로 서명된 RS256 토큰을 검증한다. `voice:connect` scope, call session ID, 필요 시 user ID를 확인하고, 사용한 `jti`는 토큰 TTL 동안 Redis에 원자적으로 저장한다. 보이스 세션 준비 데이터는 Redis에 보관하며, token secret과 credential은 로그에 남기지 않는다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/unit/session -q`

예상 결과: 통과한다.

### 작업 6: 내부 세션 제어와 최종 결과 callback 구현

**파일:**
- 생성: `src/oncue_voice/api/http.py`
- 생성: `src/oncue_voice/api/schemas.py`
- 생성: `src/oncue_voice/api/results.py`
- 생성: `src/oncue_voice/session/results.py`
- 생성: `tests/unit/api/test_session_api.py`

**인터페이스:**
- `POST /internal/v1/voice-sessions`
- `POST /internal/v1/voice-sessions/{voiceSessionId}/terminate`
- `VoiceCallResultCallbackClient#sendResult(call_session_id: str, result: CallResult): None`가 백엔드의 `POST /internal/v1/call-sessions/{callSessionId}/result`를 호출한다.
- `CallResult`는 `voiceSessionId`, `callStatus`, `callOutcome`, `startedAt`, `endedAt`을 가진다.

- [ ] **단계 1: 세션 생성·종료 API 테스트 작성**

서비스 간 인증, 필수 대화 정책 필드, 중복 세션 생성의 멱등성, 종료된 세션 처리를 검증한다. 최종 결과에 `callStatus`와 `callOutcome`을 담을 수 있는 schema도 검증한다.

- [ ] **단계 2: API 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/api/test_session_api.py -q`

예상 결과: route가 없으므로 실패한다.

- [ ] **단계 3: 내부 제어 route와 callback client 구현**

백엔드 요청에는 별도의 서비스 자격 증명을 사용한다. 모바일 사용자 access token은 내부 route에서 받지 않는다. 세션 생성 시에는 정책과 만료 시각을 저장할 뿐 실제 STT·LLM·TTS provider 연결을 열지 않는다. 사용자가 WebRTC 연결을 완료한 뒤 실제 runtime과 provider를 시작한다. 최종 결과는 타입이 지정된 callback client로 보내고 `callSessionId` 기준 중복 결과를 안전하게 처리한다.

- [x] **단계 4: 인증·세션 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/unit/session -q`

예상 결과: 통과한다.

### 작업 7: WebSocket 시그널링과 WebRTC 미디어 생명주기 구현

**파일:**
- 생성: `src/oncue_voice/api/signaling.py`
- 생성: `src/oncue_voice/media/webrtc.py`
- 생성: `src/oncue_voice/media/audio.py`
- 생성: `tests/unit/media/test_webrtc.py`
- 생성: `tests/integration/test_webrtc_signaling.py`

**인터페이스:**
- `WebSocket /v1/signaling/call-sessions/{callSessionId}`
- `SdpOffer`와 `SdpAnswer`는 WebRTC 연결 방법을 설명하는 SDP 문자열을 `sdp` 필드로 가진다.
- `IceCandidate`는 `candidate`, `sdpMid`, `sdpMLineIndex`를 가진다.
- `HangupMessage`는 사용자가 정상 종료했음을 알리는 `{"type":"hangup"}` 제어 메시지다.
- `WebRtcSession#accept_offer(offer: SdpOffer): SdpAnswer`
- `WebRtcSession#close(): None`

> 읽기 메모: SDP는 실제 음성이 아니라 연결 설명서다. ICE candidate는 가능한 네트워크 경로 후보이며, 이 정보들을 WebSocket으로 교환한 뒤 실제 음성은 WebRTC로 전달한다.

- [ ] **단계 1: 시그널링 테스트 작성**

유효한 연결 토큰, 잘못된 토큰, 모르는 세션, 잘못된 SDP, offer 수락, ICE candidate 교환, `hangup` 정상 종료와 비정상 연결 끊김을 테스트한다. 단위 테스트에서는 fake peer connection을 사용한다.

- [ ] **단계 2: 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/unit/media tests/integration/test_webrtc_signaling.py -q`

예상 결과: 시그널링과 미디어 모듈이 없으므로 실패한다.

- [ ] **단계 3: aiortc 시그널링과 음성 track 구현**

offer를 받기 전에 연결 토큰을 검증한다. 세션 요청에서 ICE 서버를 구성하고, 백엔드가 제공한 STUN/TURN 자격 정보를 사용하며, SDP나 오디오 내용을 로그에 남기지 않는다. WebSocket은 시그널링과 `hangup` 같은 제어 메시지에만 사용하고 오디오는 WebRTC media track으로 전달한다. `hangup`을 받은 뒤 연결이 닫히면 사용자 종료로 처리하고, `hangup` 없이 끊기거나 provider·시나리오·시간 제한에 따른 종료는 구분해 최종 `callOutcome`을 백엔드에 전달한다.

- [ ] **단계 4: 테스트 실행 및 통과 확인**

실행: `poetry run pytest tests/unit/media tests/integration/test_webrtc_signaling.py -q`

예상 결과: 필요한 WebRTC 테스트 의존성이 있는 환경에서 통과한다.

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

fake provider로 세션을 만들고 offer를 인증하며 테스트 오디오 track을 교환한다. 출력 track과 최종 결과 callback을 확인하고 운영 저장소에 오디오가 저장되지 않는지 검증한다.

- [ ] **단계 2: 통합 테스트 실행 및 실패 확인**

실행: `poetry run pytest tests/integration/test_session_to_audio.py -q`

예상 결과: 세션, 시그널링, 미디어, runtime 연결 전이므로 실패한다.

- [ ] **단계 3: coturn 참고 설정과 컨테이너 검사 추가**

realm, 외부 주소, 자격 정보, 포트는 환경 변수에서 받는다. `coturn.conf`에 비밀값을 넣지 않고 README에 필요한 변수를 기록한다.

- [ ] **단계 4: 전체 Python 검증 실행**

실행: `poetry run pytest` 및 `docker build -t oncue-voice:test .`

예상 결과: 테스트가 통과하고 이미지가 빌드된다.
