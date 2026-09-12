# 구조 리팩터링 테스트 민감도 근거

- **검증 행위:** split pipeline provider factory가 등록되지 않은 provider를 거부하고, 등록된 provider를 정상 생성한다.
- **운영 코드 위치:** `/Users/yeonny0723/orca/oncue-voice/src/oncue_voice/providers/split_pipeline/factory.py`
- **결함을 잡아야 하는 테스트:** `tests/unit/providers/test_split_pipeline_provider_factory.py`
- **기준 명령과 결과:** 관련 테스트 실행 → `8 passed`
- **mutation:** `if registration is None`을 `if registration is not None`으로 변경
- **mutation 명령과 결과:** 관련 테스트 실행 → `3 failed, 5 passed`
- **판정:** `killed`
- **테스트 보강 변경:** 없음. 기존 factory 계약 테스트가 mutation을 탐지했다.
- **snapshot SHA-256:** `858c1a26fd69e3685f0a0e3627e51e13fd9aaef8fdc22605b15085230b960d73`
- **복구 SHA-256과 일치 여부:** 일치
- **최종 명령과 결과:** 전체 테스트 실행 → `44 passed`
