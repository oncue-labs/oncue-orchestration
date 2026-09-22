# Docker 로컬 검증 TODO

현재 Docker Desktop 앱은 설치되었지만, 관리자 암호가 필요한 자격 증명 도구 심볼릭 링크 설치는 건너뛴 상태다. Docker Desktop 실행과 아래 검증은 수동으로 진행한다.

## 1. Docker Desktop 실행

응용 프로그램에서 `Docker.app`을 실행하고, Docker Desktop에 `Running` 또는 정상 실행 상태가 표시될 때까지 기다린다.

터미널에서 CLI 경로가 자동으로 잡히지 않으면 현재 터미널에서만 다음을 실행한다.

```bash
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
```

## 2. Docker와 Compose 확인

```bash
docker --version
docker compose version
docker info
```

`docker info`가 서버 정보를 출력하면 Docker 엔진까지 실행된 것이다.

## 3. Compose 설정 검증

오케스트레이션 저장소 루트에서 실행한다.

```bash
bash tests/compose_config_test.sh
```

성공 기준은 마지막에 다음 문구가 출력되는 것이다.

```text
compose config is valid
```

## 4. 실제 로컬 스택 실행

먼저 예시 환경 파일을 복사한다.

```bash
cp .env.template .env.local
```

`.env`에서 최소한 다음 값을 로컬용으로 채운다.

- `VOICE_JWT_PRIVATE_KEY`: 백엔드가 연결 토큰을 서명할 RSA 개인키
- `ONCUE_VOICE_JWT_PUBLIC_KEY`: 보이스 서버가 연결 토큰을 검증할 같은 키 쌍의 공개키
- `OPENAI_API_KEY`: Realtime 통화를 실제로 테스트할 때 필요한 provider 키

RSA 키 생성 방법은 저장소 README의 안내를 따른다. PEM 줄바꿈은 `.env` 안에서 literal `\n` 형식으로 넣는다.

```bash
docker compose --env-file .env.local -f docker-compose.local.yml up --build -d
docker compose --env-file .env.local -f docker-compose.local.yml ps
```

## 5. 상태와 로그 확인

```bash
docker compose --env-file .env.local -f docker-compose.local.yml ps
docker compose --env-file .env.local -f docker-compose.local.yml logs --tail=100 oncue-backend oncue-voice
curl http://localhost:8080/actuator/health
curl http://localhost:8000/health
```

MySQL, Redis, 백엔드, 보이스 서버가 `healthy` 또는 정상 실행 상태여야 한다. 실제 음성 통화는 OpenAI API key와 모바일 클라이언트 연결까지 준비한 뒤 별도 검증한다.

## 검증 완료 상태

- Compose 전체 stack의 health와 backend↔voice HTTP, voice↔Redis 연결을 확인했다.
- 실제 backend 발급 RS256 connection token으로 voice WebSocket 인증을 확인했다.
- `hangup` 후 WebSocket close code `1000`과 backend callback의 `CONNECTING/SUCCEEDED` 반영을 확인했다.
- 검증용 임시 사용자·예약·콜 세션은 검증 후 삭제했다.
- 이 과정에서 발견한 backend lazy-loading 오류와 voice 정상 종료 오류는 각 레포에 회귀 테스트와 함께 수정했다.

## 다음 작업

1. backend와 voice의 수정사항을 각 레포에 커밋·push한다.
2. `oncue-mobile`에서 connection-token 응답, WebSocket signaling, `flutter_webrtc` 연결을 구현한다.

서비스 간 API나 토큰 계약을 바꿔야 하는 문제가 나오면 관련 레포 작업을 멈추고 계약을 먼저 확정한다.
