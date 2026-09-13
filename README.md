# OnCue 오케스트레이션

OnCue의 로컬 개발 환경을 Docker Compose로 연결하는 저장소다. 서비스별 애플리케이션 코드와 Dockerfile은 각 서비스 저장소가 소유한다.

## 로컬 시작

먼저 예시 환경 파일을 복사하고 로컬 비밀값을 바꾼다.

```bash
cp .env.example .env
docker compose --env-file .env -f docker-compose.local.yml up --build
```

기본 stack에는 MySQL, Redis, `oncue-backend`, `oncue-voice`, coturn이 포함된다. Flutter 앱은 Docker에 넣지 않고 Xcode에서 실행한다.

통화 연결 토큰은 로그인 토큰과 별도의 RSA 키 쌍을 사용한다. 로컬에서는 같은 키 쌍으로 개인키와 공개키를 생성한 뒤 `.env`의 `VOICE_JWT_PRIVATE_KEY`와 `ONCUE_VOICE_JWT_PUBLIC_KEY`에 PEM 내용을 입력한다. 줄바꿈은 `\\n`으로 적는다.

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /tmp/oncue-voice-private.pem
openssl rsa -pubout -in /tmp/oncue-voice-private.pem -out /tmp/oncue-voice-public.pem
```

운영 환경에서는 PEM을 환경 변수에 직접 넣지 말고 배포 환경의 비밀 저장소에서 주입한다.

```bash
docker compose --env-file .env -f docker-compose.local.yml --profile local-llm up --build
```

현재 Local LLM provider container는 아직 추가하지 않았다. 위 profile은 다음 단계에서 선택적으로 추가할 확장 지점이다. 일반 개발에서는 Public provider를 사용하므로 GPU가 필요하지 않다.

## 검증

```bash
bash tests/compose_config_test.sh
```

실제 통화를 검증하려면 `oncue-voice` 저장소의 Jupyter 평가를 별도로 실행한다. 평가 API key와 결과 artifact는 이 저장소에 저장하거나 Compose volume으로 공유하지 않는다.

```bash
cd ../../oncue-voice
poetry run jupyter lab notebooks/voice_persona_scenario_evaluation.ipynb
```

coturn의 기준 설정은 [oncue-voice/docker/turn](../../oncue-voice/docker/turn)이 소유한다. 운영 환경에서는 예시 비밀번호를 사용하지 말고, TURN 자격 증명·JWT 키·provider API key를 배포 환경의 비밀 저장소에서 주입한다.
