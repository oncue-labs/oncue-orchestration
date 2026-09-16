# OnCue refresh token TODO

MVP에서는 OnCue refresh token을 사용하지 않는다. 로그인 응답은 `accessToken`, `expiresAt`, `createdAt`만 반환하며, access token이 만료되면 모바일이 저장된 세션을 삭제하고 다시 로그인한다.

다음 버전에서 검토할 작업:

- 백엔드 refresh token 발급·재발급 endpoint 추가
- refresh token 회전과 폐기·로그아웃 정책 정의
- 모바일 Keychain·Android 보안 저장소에 refresh token 저장
- access token 만료 시 1회 재발급 후 원래 요청 재시도
- refresh token 탈취·재사용 감지와 전체 세션 폐기
