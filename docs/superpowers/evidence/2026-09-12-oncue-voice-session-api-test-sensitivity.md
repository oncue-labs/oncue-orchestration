# OnCue Voice 세션 API 테스트 민감도 근거

## 검증 대상

- 운영 코드: `oncue-voice/src/oncue_voice/api/http.py`
- 핵심 행위: 내부 서비스 토큰이 일치하지 않으면 세션 API를 거부한다.
- 연결 테스트: `oncue-voice/tests/unit/api/test_session_api.py`

## 검증 결과

1. 원본 관련 테스트: `22 passed`
2. 원본 전체 테스트: `53 passed`
3. snapshot SHA-256: `08e34bcc47ac45bfdd5cebbf83a8b62bd7e178e62796ccb7b09e3d5232cf9eed`
4. mutation: 내부 토큰 검사 조건의 `or`를 `and`로 바꿔 잘못된 토큰을 통과시킴
5. mutation 결과: `1 failed, 8 passed` — 잘못된 서비스 토큰 테스트가 mutation을 감지함
6. 복원 후 SHA-256: `08e34bcc47ac45bfdd5cebbf83a8b62bd7e178e62796ccb7b09e3d5232cf9eed`
7. 복원 후 관련 테스트: `22 passed`
8. 복원 후 전체 테스트: `53 passed`

## 해석

잘못된 토큰을 허용하는 인증 우회 결함을 API 테스트가 감지하며, mutation 이후 운영 코드가 원본과 동일하게 복원되었음을 확인했다.
