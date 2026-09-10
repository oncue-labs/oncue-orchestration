# 세션 인증 테스트 민감도 근거

- **검증 행위:** 연결 토큰에 `voice:connect` scope가 있어야 검증을 통과한다.
- **운영 코드 위치:** `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/session/auth.py`
- **결함을 잡아야 하는 테스트:** `tests/unit/session/test_auth.py::test_verifier_accepts_signed_token_and_consumes_jti_once`, `tests/unit/session/test_auth.py::test_verifier_rejects_missing_required_scope`
- **기준 명령과 결과:** `poetry run pytest tests/unit/session/test_auth.py -q` → `7 passed`
- **mutation:** required scope 조건을 `not in`에서 `in`으로 반전했다.
- **mutation 명령과 결과:** 동일 테스트 → `4 failed, 3 passed`
- **판정:** `killed`
- **테스트 보강 변경:** 없음
- **snapshot SHA-256:** `0a969d2bd1fdf88ddffe177fb1474718af5dadf58c1c6411afeb5452cd99dbf3`
- **복구 SHA-256과 일치 여부:** 일치
- **최종 명령과 결과:** 원본 복구 후 동일 테스트 → `7 passed`
