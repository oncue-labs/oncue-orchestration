# OnCue refresh token TODO (완료)

로그인 및 refresh 응답은 `accessToken`, `refreshToken`, 각 만료 시각을 반환한다. 모바일은 access token이 만료되면 한 번 갱신하고 원래 요청을 재시도하며, refresh token도 만료되면 저장 세션을 삭제하고 로그인 화면으로 전환한다.

다음 버전에서 검토할 작업:

- [x] 백엔드 refresh token 발급·재발급 endpoint 추가
- [x] refresh token 회전과 폐기·로그아웃 정책 정의
- [x] 모바일 Secure Storage에 refresh token 저장
- [x] access token 만료 시 1회 재발급 후 원래 요청 재시도
- [x] refresh token 만료·재사용 시 전체 로컬 세션 폐기
