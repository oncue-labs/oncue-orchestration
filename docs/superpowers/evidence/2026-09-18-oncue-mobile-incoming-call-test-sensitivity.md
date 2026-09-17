# OnCue 모바일 수신 전화 테스트 민감도 근거

## 대상 행위

`IncomingCallService`가 같은 `callSessionId`의 VoIP Push를 여러 번 받아도 시스템 수신 전화 등록을 한 번만 수행하는지 검증했다.

## 검증 결과

- 기준 테스트: `flutter test test/call/application/incoming_call_service_test.dart`
- mutation: `lib/call/application/incoming_call_service.dart`의 중복 등록 방지 조건을 임시 제거
- mutation 결과: `does not report the same call twice` 테스트가 2회 등록을 확인하며 실패했다.
- 복구 hash: `119e542572db8a3f0484dffdd41651ec1a353201af4442acd2085678e56bed44`
- 복구 후 대상 테스트: 8개 통과
- 복구 후 전체 Flutter 테스트: 73개 통과
- 정적 분석: `flutter analyze` 통과
- iOS 시뮬레이터 빌드: `flutter build ios --simulator --no-codesign` 통과

실제 VoIP Push 전달은 iOS 시뮬레이터가 테스트 source를 인증하지 않아 `Source is not authorized`로 거부됐다. APNs 개발 entitlement와 PushKit 백엔드 전송은 실기기 및 별도 device-token 등록 계약이 필요하다.
