# OnCue X 로그인 및 세션 갱신 설계

## 목적

현재 X OAuth 로그인은 PKCE 인증 결과를 백엔드에 전달하지만 X refresh scope가 없어 provider refresh token이 발급되지 않을 수 있다. 또한 OnCue 로그인 응답은 access token만 반환해 access token 만료 때마다 사용자가 다시 로그인해야 한다.

이번 변경은 X OAuth 계약을 보완하고, OnCue access/refresh token 회전과 모바일 로그인 상태 전환을 레포 간 동일한 계약으로 제공한다. 모든 검증은 로컬 테스트와 로컬 Compose 환경에서만 수행한다.

## 이슈 분할

1. 백엔드 인증 계약과 X provider 보강: 로그인 응답 확장, 해시 저장·1회 회전, refresh/logout endpoint, X 설정 명시화.
2. 모바일 세션 자동 갱신과 로그인 게이트: `offline.access`, Secure Storage, 401 refresh·재시도, 실패 시 로그인 화면 전환.
3. 오케스트레이션 로컬 계약과 검증: Compose·문서·로컬 검증 갱신. 운영 서버와 운영 secret은 비범위.

## 계약

로그인과 갱신 응답은 `accessToken`, `expiresAt`, `createdAt`, `refreshToken`, `refreshTokenExpiresAt`을 반환한다. refresh token 원문은 백엔드 DB에 저장하지 않는다. 갱신이 성공하면 기존 token을 즉시 폐기하고 새 pair를 발급하며, 이미 사용했거나 만료된 token은 `401`을 반환한다.

모바일은 인증 요청이 `401`을 받으면 같은 refresh 작업을 중복 실행하지 않고 한 번만 수행한다. 갱신 성공 시 원 요청을 새 access token으로 한 번 재시도한다. 갱신 실패가 `401`, `403`, 또는 잘못된 refresh 입력이면 세션을 삭제하고 로그인 화면을 표시한다. 네트워크 오류나 서버 오류만으로는 세션을 삭제하지 않는다.

## 비범위

- X provider refresh token을 OnCue DB에 보관하지 않는다.
- 운영 서버 배포, 운영 secret 교체, 실제 X Developer Portal 설정 변경은 수행하지 않는다.
- Android 저장소나 Android OAuth redirect 설정은 이번 로컬 iOS 흐름에 포함하지 않는다.

## 검증 기준

- 백엔드 단위·웹 계층·전체 테스트가 통과한다.
- 모바일 X scope, 401 재시도, refresh 실패 후 로그인 화면 전환 테스트가 통과한다.
- 오케스트레이션 Compose 설정 검사가 통과한다.
