# OnCue 오케스트레이션

OnCue의 로컬 개발 환경을 Docker Compose로 연결하는 저장소다. 서비스별 애플리케이션 코드와 Dockerfile은 각 서비스 저장소가 소유한다.

## 로컬 시작

먼저 예시 환경 파일을 복사하고 로컬 비밀값을 바꾼다.

```bash
cp .env.example .env
docker compose --env-file .env -f docker-compose.local.yml up --build
```

실제 iPhone에서 통화 연결을 테스트할 때는 `.env`의 `ONCUE_PUBLIC_HOST`를
Mac과 iPhone이 같은 Wi-Fi에서 접근할 수 있는 Mac의 LAN IP로 설정한다.
`localhost`는 iPhone이 아니라 컨테이너 자신을 가리키므로 사용할 수 없다.
모바일에 내려가는 signaling/TURN 주소는 이 값을 사용하고, 보이스 컨테이너가
coturn에 접근하는 주소는 Compose 서비스명 `coturn`을 사용한다.
coturn은 같은 값을 외부 relay 주소로 광고하므로, `TURN_RELAY_PORT_START`부터
`TURN_RELAY_PORT_END`까지의 포트도 Mac 방화벽에서 허용되어야 한다.

기본 stack에는 MySQL, Redis, `oncue-backend`, `oncue-voice`, coturn이 포함된다. Flutter 앱은 Docker에 넣지 않고 Xcode에서 실행한다.

보이스 서버는 Redis에 짧은 수명의 보이스 세션 준비 정보와 1회성 연결 토큰의 사용 기록(JTI)을 저장한다. 그래서 앱 프로세스가 재시작되어도 진행 중인 짧은 통화 준비 상태를 복구할 수 있다.

통화 연결 토큰은 로그인 토큰과 별도의 RSA 키 쌍을 사용한다. 로컬에서는 같은 키 쌍으로 개인키와 공개키를 생성한 뒤 `.env`의 `VOICE_JWT_PRIVATE_KEY`와 `ONCUE_VOICE_JWT_PUBLIC_KEY`에 PEM 내용을 입력한다. 줄바꿈은 `\\n`으로 적는다.

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /tmp/oncue-voice-private.pem
openssl rsa -pubout -in /tmp/oncue-voice-private.pem -out /tmp/oncue-voice-public.pem
```

운영 환경에서는 PEM을 환경 변수에 직접 넣지 말고 배포 환경의 비밀 저장소에서 주입한다.

## 로컬 APNs PushKit 연결

실제 iPhone으로 VoIP 푸시를 보내려면 Apple Developer에서 만든 APNs Auth Key
(`.p8`)를 백엔드 컨테이너에 읽기 전용으로 연결해야 한다. 키 내용은 저장소나
`.env`에 넣지 않는다.

1. `.env`의 `APNS_KEY_ID`, `APNS_TEAM_ID`를 실제 값으로 바꾼다.
2. `.env`의 `APNS_SECRET_DIR_HOST` 디렉터리를 만들고, 그 안에 키 파일을
   `apns-auth-key.p8`라는 이름으로 둔다.

```bash
mkdir -p .secrets
cp /path/to/AuthKey_XXXXXXXXXX.p8 .secrets/apns-auth-key.p8
chmod 600 .secrets/apns-auth-key.p8
```

3. `ONCUE_APNS_ENVIRONMENT=SANDBOX`로 빌드한 개발 앱은 APNs Sandbox로,
   TestFlight 앱은 `PRODUCTION`으로 등록되어야 한다. 이 값은 앱의 PushKit
   토큰 등록 환경과 백엔드가 호출할 APNs 주소를 맞추는 데 사용된다.

키가 아직 연결되지 않아도 컨테이너 자체는 실행되지만, 실제 수신 푸시 전송은
`APNS_KEY_ID`, `APNS_TEAM_ID`, `.p8` 파일이 모두 준비된 뒤에만 성공한다.

X 로그인은 OAuth 2.0 Authorization Code + PKCE를 사용한다. `.env`의
`ONCUE_AUTH_X_CLIENT_ID`에는 X Developer Portal에서 발급한 Client ID를 입력하고,
`X_REDIRECT_URI`는 X 콘솔과 동일한 아래 값으로 유지한다.

```text
com.oncue.oncuemobile://oauth/x/callback
```

Native App의 Client Secret은 모바일에 넣지 않는다. 현재 MVP에서는 PKCE를 사용하므로
Client ID만 모바일과 백엔드에 전달한다.

로그인 응답에는 OnCue access token과 refresh token이 함께 포함된다. 모바일은 access
token이 만료되어 백엔드가 `401`을 반환하면 refresh endpoint를 한 번 호출하고 원래
요청을 한 번 재시도한다. refresh token도 만료되거나 폐기된 경우 저장된 세션을 삭제하고
로그인 화면으로 돌아간다. refresh token은 모바일 Secure Storage와 백엔드의 해시 값으로만
관리한다.

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
