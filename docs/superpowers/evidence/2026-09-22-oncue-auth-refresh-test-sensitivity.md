# Auth refresh 테스트 민감도 검증

2026-09-22 로컬 검증 기록

## Backend

- 대상: `RefreshTokenService.consume`의 만료 조건
- 변이 검증 시점 스냅샷 해시: `fa02f8e08e64c2cbd7be985b7ff19ce916a5e5084c537600458e175402ddbefd`
- 변이: `!token.getExpiresAt().isAfter(now)`를 `token.getExpiresAt().isAfter(now)`로 반전
- 결과: `RefreshTokenServiceTest` 2개 실패. 만료 토큰 거부와 유효 토큰 회전 테스트가 변이를 검출함.
- 복구 후 원래 테스트 재실행: 통과
- 최종 작업 트리 파일 해시: `88b7010deeb18163d1020f6856844778da1d41d0`

## Mobile

- 대상: `HttpApiClient._sendWithRefresh`의 갱신 access token 재시도
- 변이 검증 시점 스냅샷 해시: `d39739865dfaab24e4c8228a60e4ad983192f52517bef3ac8becf4868fb3f394`
- 변이: 재시도에 새 access token 대신 기존 access token을 전달
- 결과: HTTP refresh/retry 테스트가 기존 Bearer token 전송을 검출해 실패함.
- 복구 후 변이 테스트를 다시 실행하고 통과를 확인함.
- 최종 작업 트리 파일 해시: `5cce3c0ed5e27743aabd156296f83980fb295ccb`

변이 검증은 로컬 임시 작업 사본에서 수행했으며 운영 서버나 운영 데이터에는 접근하지 않았다.
