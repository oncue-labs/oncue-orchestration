# Realtime provider 테스트 민감도 근거

- **검증 행위:** `pcm16` 입력·출력 형식을 OpenAI Realtime session 설정의 `audio/pcm`으로 변환한다.
- **운영 코드 위치:** `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/realtime/openai_provider.py`
- **결함을 잡아야 하는 테스트:** `tests/integration/providers/test_openai_realtime_provider.py::test_openai_realtime_adapter_sends_policy_and_audio_event`
- **기준 명령과 결과:** `pytest tests/integration/providers/test_openai_realtime_provider.py -q` → `3 passed`
- **mutation:** `pcm16` 변환 결과의 media type을 `audio/pcm`에서 `audio/pcmu`로 변경했다.
- **mutation 명령과 결과:** 동일 테스트 → `1 failed, 2 passed`
- **판정:** `killed`
- **테스트 보강 변경:** 없음
- **snapshot SHA-256:** `aedaa5ae1d623c07036a8443fcf6e6755006f906f9d40a71d515cee9557d34db`
- **복구 SHA-256과 일치 여부:** 일치
- **최종 명령과 결과:** 원본 복구 후 전체 테스트 → `44 passed`
