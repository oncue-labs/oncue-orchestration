# OnCue 오케스트레이션 MVP 구현 계획

> **에이전트 작업자 필수 안내:** 이 계획을 작업별로 실행할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 작업 단계는 추적할 수 있도록 체크박스(`- [ ]`)로 작성되어 있다.

**목표:** MySQL, Redis, `oncue-backend`, `oncue-voice`, coturn을 연결하는 재현 가능한 Docker Compose 개발 환경을 제공한다. 서비스별 Dockerfile이나 TURN 설정은 오케스트레이션 저장소에 두지 않는다.

**아키텍처:** 이 저장소는 저장소 간 통합 wiring, 환경 변수 예시, 로컬 공통 의존성, 통합 문서만 소유한다. `oncue-backend`와 `oncue-voice`가 각자의 Dockerfile을 소유하고, 기준 coturn 설정은 `oncue-voice/docker/turn`이 소유한다. Flutter는 Docker 밖에서 Xcode로 실행한다.

**기술 스택:** Docker, Docker Compose, MySQL 8, Redis 7, coturn, Spring Boot backend image, Python voice image.

**사양:** `docs/superpowers/specs/2026-09-08-oncue-mvp-design.md`, `docs/superpowers/specs/2026-09-09-oncue-mvp-api-data-contract.md`

## 전체 제약 조건

- 이 저장소의 저장소 간 Compose 파일은 `docker-compose.local.yml` 하나만 유지한다.
- 이 저장소에 `docker/turn`이나 TURN Dockerfile을 만들지 않는다.
- backend는 `../../oncue-backend`에서 build하고 voice service는 `../../oncue-voice`에서 build한다.
- Flutter는 Xcode를 통해 호스트에서 실행하며 iOS 개발 환경을 containerize하지 않는다.
- `oncue-voice`의 Jupyter 품질 평가는 voice 저장소의 Poetry 환경에서 실행하며 Compose service로 만들지 않는다.
- `oncue-voice/notebooks/artifacts/`는 Compose volume으로 mount하지 않고 각 개발자의 로컬 평가 결과로만 유지한다.
- Public LLM을 기본값으로 사용하고 Local LLM은 선택적으로 켜는 Compose profile로 둔다. 일반 개발에는 Local LLM이 필요하지 않다.
- API key, OAuth secret, TURN password, JWT private key, provider credential을 커밋하지 않는다.
- MySQL과 Redis 데이터는 이름이 있는 local volume에 보관한다.

---

### 작업 1: 로컬 환경 문서와 Compose 뼈대 만들기

**파일:**
- 생성: `/Users/yeonny0723/orca/projects/oncue-orchestration/docker-compose.local.yml`
- 생성: `/Users/yeonny0723/orca/projects/oncue-orchestration/.env.example`
- 생성: `/Users/yeonny0723/orca/projects/oncue-orchestration/README.md`
- 테스트: `/Users/yeonny0723/orca/projects/oncue-orchestration/tests/compose_config_test.sh`

**인터페이스:**
- `docker compose -f docker-compose.local.yml config`이 통합 정의를 검증한다.

- [x] **단계 1: Compose 검증 스크립트 작성**

스크립트는 `.env.example`을 사용해 Compose 파일을 렌더링하고, 서비스 이름·build context·health check·필수 환경 변수가 없으면 실패해야 한다.

- [x] **단계 2: 검증 실행 및 실패 확인**

실행: `bash tests/compose_config_test.sh`

실행 결과: 현재 환경에 Docker CLI가 없어 `docker compose`를 실행하지 못했다.

- [x] **단계 3: Compose service와 환경 변수 예시 추가**

`mysql`, `redis`, `oncue-backend`, `oncue-voice`, `coturn`을 정의한다. container 안에서는 `localhost`가 아니라 service hostname을 사용하고, MySQL·Redis·backend·voice에 health check를 추가한다.

- [ ] **단계 4: 검증 실행 및 통과 확인**

실행: `bash tests/compose_config_test.sh`

검증 대기: Docker CLI가 설치된 환경에서 `bash tests/compose_config_test.sh`를 실행해야 한다.

### 작업 2: 서비스 소유 Dockerfile과 네트워크 연결

**파일:**
- 수정: `docker-compose.local.yml`
- 수정: `.env.example`
- 수정: `README.md`
- 테스트: `tests/compose_config_test.sh`

**인터페이스:**
- backend는 `mysql:3306`, `redis:6379`, Compose service hostname으로 voice에 접근한다.
- voice는 backend service hostname을 통해 backend로 최종 결과 callback을 보낸다.

- [ ] **단계 1: build context와 의존성 조건 추가**

backend는 `../../oncue-backend`에서 build하고 voice는 `../../oncue-voice`에서 build한다. 의존 service의 health check가 통과한 뒤 application container가 시작되도록 한다.

- [ ] **단계 2: 비밀값 없는 환경 변수 이름 추가**

`DB_HOST`, `REDIS_HOST`, `VOICE_SERVER_URL`, `BACKEND_INTERNAL_URL`, JWT key path, Public LLM 설정, TURN realm/port를 문서화한다.

- [ ] **단계 3: Compose 설정 검증 실행**

실행: `docker compose --env-file .env.example -f docker-compose.local.yml config` 및 `bash tests/compose_config_test.sh`

예상 결과: Flutter 프로젝트를 Docker로 실행하지 않아도 통과한다.

### 작업 3: voice가 소유한 설정을 사용해 coturn 연결

**파일:**
- 수정: `docker-compose.local.yml`
- 수정: `.env.example`
- 수정: `README.md`
- 사용: `/Users/yeonny0723/orca/oncue-voice/docker/turn/coturn.conf`

**인터페이스:**
- coturn은 문서에 정의된 STUN/TURN host와 port에서 접근할 수 있다.
- 모바일 connection-token 응답은 같은 local TURN realm과 임시 credential 설정을 사용할 수 있다.

- [ ] **단계 1: coturn service 정의 추가**

coturn image를 사용하고 `../../oncue-voice/docker/turn/coturn.conf`를 mount한다. 문서화한 UDP/TCP listener와 relay port 범위를 노출하고 credential은 환경 변수로 관리한다.

- [ ] **단계 2: 연결 smoke check 추가**

coturn container가 시작되는지 확인하고, credential을 노출하지 않으면서 로그 또는 health 결과에 설정된 realm이 나타나는지 검증한다.

- [ ] **단계 3: smoke check 실행**

실행: `docker compose --env-file .env.example -f docker-compose.local.yml up -d coturn` 및 `docker compose --env-file .env.example -f docker-compose.local.yml ps`

예상 결과: coturn이 실행되고 healthy 상태가 된다.

### 작업 4: 선택적으로 켜는 Local LLM profile 추가

**파일:**
- 수정: `docker-compose.local.yml`
- 수정: `.env.example`
- 수정: `README.md`
- 테스트: `tests/compose_profile_test.sh`

**인터페이스:**
- 기본 시작에서는 Public LLM 설정을 사용하고 local model container를 시작하지 않는다.
- `docker compose --profile local-llm up`을 실행하면 선택적인 local provider service가 추가된다.

- [ ] **단계 1: profile 동작 검사 작성**

기본 렌더링 service에는 local model이 없고, `local-llm` profile을 사용하면 명시적인 provider URL과 함께 local model이 포함되는지 검증한다.

- [ ] **단계 2: 검사 실행 및 실패 확인**

실행: `bash tests/compose_profile_test.sh`

예상 결과: profile이 아직 없으므로 실패한다.

- [ ] **단계 3: GPU를 자동으로 요구하지 않는 profile 추가**

기본 profile은 CPU 부담이 적게 유지한다. GPU runtime 설정은 호스트 환경에 따라 달라지며, profile은 service 선택만 제어하고 GPU를 만들거나 제공하지 않는다는 점을 문서화한다.

- [ ] **단계 4: 검사 실행 및 통과 확인**

실행: `bash tests/compose_profile_test.sh`

예상 결과: 통과한다.

### 작업 5: 로컬 통합 smoke test와 실행 문서 추가

**파일:**
- 생성: `tests/integration/compose_smoke_test.sh`
- 수정: `README.md`
- 수정: `.env.example`

**인터페이스:**
- 개발자가 service 내부 구현을 몰라도 기본 stack을 시작하고 health를 확인하고 종료할 수 있다.

- [ ] **단계 1: smoke test 명령 작성**

MySQL, Redis, backend, voice, coturn을 시작하고 health를 기다린다. backend와 voice health endpoint를 호출하며 application container가 service name으로 서로를 resolve할 수 있는지 확인한다.

- [ ] **단계 2: smoke test 실행 및 실패 확인**

실행: `bash tests/integration/compose_smoke_test.sh`

예상 결과: service Dockerfile과 health endpoint가 준비되기 전까지 실패한다.

- [ ] **단계 3: 기본 및 profile 실행 방법 문서화**

다음 명령을 문서화한다.

```bash
docker compose --env-file .env.example -f docker-compose.local.yml up --build
docker compose --env-file .env.example -f docker-compose.local.yml --profile local-llm up --build
```

또한 iOS는 Xcode에서 실행한다는 점과 production TURN credential에는 예시 값을 사용하면 안 된다는 점을 문서화한다.

`oncue-voice`의 개발용 품질 평가는 다음처럼 별도로 실행한다고 문서화한다.

```bash
cd ../../oncue-voice
poetry run jupyter lab notebooks/voice_persona_scenario_evaluation.ipynb
```

이 notebook은 실제 Public provider를 호출할 수 있으므로 API key는 환경 변수에서만 읽고 결과 artifact는 Git이나 Compose volume에 포함하지 않는다.

- [ ] **단계 4: 전체 로컬 검증 실행**

실행: `bash tests/compose_config_test.sh`, `bash tests/compose_profile_test.sh`, `bash tests/integration/compose_smoke_test.sh` 및 `cd ../../oncue-voice && poetry run pytest tests/evaluation/test_evaluation_notebook.py -q`

예상 결과: backend와 voice 계획에서 Dockerfile과 health endpoint를 제공하면 통과한다.
