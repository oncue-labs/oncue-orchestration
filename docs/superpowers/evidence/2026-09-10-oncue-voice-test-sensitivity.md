# 테스트 민감도 근거

- **검증 행위:** 최종 STT 결과만 사용자 발화로 확정하고 대화 이벤트 순서를 사용자 발화 → assistant 응답으로 유지한다.
- **운영 코드 위치:** `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/conversation/split_pipeline_runtime.py`
- **결함을 잡아야 하는 테스트:** `tests/unit/conversation/test_runtime.py::test_runtime_emits_user_and_assistant_events_for_evaluation`
- **기준 명령과 결과:** `poetry run pytest tests/unit/conversation/test_runtime.py -q` → `5 passed`
- **mutation:** `if segment.is_final`을 `if not segment.is_final`로 반전했다.
- **mutation 명령과 결과:** 동일 테스트 → `1 failed, 4 passed`
- **판정:** `killed`
- **테스트 보강 변경:** 없음
- **snapshot SHA-256:** `f0cc307d5945d45bca4109740f9cbad7b39a1c846b75f0707e083544d8d912e2`
- **복구 SHA-256과 일치 여부:** 일치
- **최종 명령과 결과:** 원본 복구 후 동일 테스트 → `5 passed`
