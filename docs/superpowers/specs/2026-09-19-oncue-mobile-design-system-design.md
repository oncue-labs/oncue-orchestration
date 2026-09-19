# OnCue 모바일 디자인 시스템 적용 사양

## 목적

`design/mockups/`에 정의된 다크 · 웜톤 디자인(HTML 목업 10개 + `design-system.html` 컴포넌트 카탈로그 + `tokens.css`)을 `oncue-mobile` Flutter 앱의 실제 화면에 동일하게 적용한다. 화면마다 반복되는 컴포넌트(버튼 · 카드 · 칩 · 모달 · 스낵바 · 탭바)는 앱 내 디자인 시스템 위젯으로 추출해 재사용한다.

이 문서는 비주얼(색상 · 타이포 · 컴포넌트 스타일 · 아이콘)의 범위만 정의한다. 화면 흐름과 비즈니스 로직은 `2026-09-14-oncue-mobile-screen-flow-design.md`를 따르며 이번 작업으로 변경하지 않는다.

## 비목표

- 라이트 모드 지원 (앱은 다크 테마 전용)
- 신규 pub 패키지 설치 (`flutter_svg`, `google_fonts` 등) — Flutter Material 위젯과 asset(폰트 파일 · 이미지)만 사용한다
- 기존 상태관리 · API 호출 · WebRTC 연결 로직 변경
- 기존 위젯 테스트가 참조하는 `ValueKey` · 텍스트 · Finder 구조 변경

## 화면 매핑

| 목업 파일 | 앱 파일 | 비고 |
|---|---|---|
| `auth-gate.html` | `lib/auth/presentation/auth_gate.dart` | |
| `login.html` | `lib/auth/presentation/login_page.dart` | |
| `home.html` | `lib/app/oncue_home_page.dart` | 하단 탭 셸(조합 탭 · 예약 탭) |
| `combination-list.html` | `lib/combination/presentation/combination_list_page.dart` | |
| `combination-detail.html` | `lib/combination/presentation/combination_detail_page.dart` | |
| `reservation-form.html` | `lib/reservation/presentation/reservation_form_page.dart` | |
| `permission-guide.html` | `lib/common/permissions/permission_guide_page.dart` | |
| `reservation-list.html` | `lib/reservation/presentation/reservation_list_page.dart` | |
| `reservation-detail.html` | `lib/reservation/presentation/reservation_detail_page.dart` | |
| `incoming-call.html` (수신 중) | 해당 없음 | iOS 시스템(CallKit) 네이티브 화면 — Flutter 코드 범위 아님 |
| `incoming-call.html` (통화 연결 후) | `lib/call/presentation/immediate_call_page.dart` | **목업에 없는 화면.** 목업의 "통화 연결 후" 레이아웃(페르소나 사진 · 이름 · 컨트롤)을 그대로 재사용해 보완한다 |
| `design-system.html` | `lib/common/design_system/` (신규) | 화면에 대응하는 파일이 아니라 공용 위젯 카탈로그의 근거 |

## 디자인 토큰 레이어

- `lib/common/design_system/oncue_theme.dart`에 다크 전용 `ThemeData` 하나를 정의한다.
- `tokens.css`의 색상 변수를 `Color` 상수로 그대로 포팅한다: `background`, `surface`, `surface-light`, `surface-raised`, `text`, `muted`, `muted-strong`, `accent`, `accent-strong`, `danger`, `danger-strong`, `success`, `line`, `line-strong`.
- `ColorScheme` 표준 슬롯에 대응되는 값(`surface`, `onSurface`, `primary`, `error` 등)은 `ColorScheme.dark(...)`에 매핑한다.
- 표준 슬롯이 없는 값(`surface-light`, `surface-raised`, `muted-strong`, `line`, `line-strong`, `success`)은 `ThemeExtension<OnCueColors>`로 확장해 `Theme.of(context).extension<OnCueColors>()`로 접근한다.
- 타이포그래피: `assets/fonts/`에 Noto Sans KR `.ttf`(OFL 라이선스, Google Fonts 공개 저장소에서 확보)를 추가하고 pubspec에 등록, `ThemeData.fontFamily`로 전역 적용한다. pub 패키지는 추가하지 않는다.

## 공통 위젯 (디자인 시스템 카탈로그)

`design-system.html` 기준으로 `lib/common/design_system/widgets/`에 아래 위젯을 추출한다.

- `PrimaryButton` / `OutlineButton` — 기본 · 비활성 상태 (`onPressed == null`로 비활성 표현)
- `AppCard`, `StatusChip`, `IconBadge`, `AppAvatar`
- `ConfirmDialog` — 파괴적 동작(예약 취소 등) 확인 모달
- `AppSnackbar` — `showError` / `showSuccess` / `showInfo` 헬퍼 함수
- `OnCueBottomTabBar` — 블러 pill 형태 하단 탭바
- `HeaderBanner`, `EmptyState`

### 아이콘

- 목업의 Lucide 아이콘을 Flutter 내장 Material Icons로 1:1 매핑한다 (예: `chevron-left` → `Icons.chevron_left`, `mic-off` → `Icons.mic_off`, `clock` → `Icons.access_time`, `calendar-days` → `Icons.calendar_month`, `circle-check` → `Icons.check_circle`, `triangle-alert`/`alert-triangle` → `Icons.warning_amber`, `shield-check` → `Icons.verified_user`, `sparkles` → `Icons.auto_awesome`, `inbox` → `Icons.inbox`, `info` → `Icons.info`, `volume-2` → `Icons.volume_up`, `phone-call` → `Icons.call`).
- 카카오 로그인 버튼의 카카오 로고는 Material Icons에 대응 아이콘이 없으므로 `assets/images/kakao_symbol.png` 예외로 추가한다. 이 외의 브랜드 로고는 없다.

## 작업 단위 (PR 분리 아님, 순차 구현 단위)

1. 디자인 시스템 기반: 폰트 asset 등록 + `oncue_theme.dart` + 공통 위젯 세트 + `oncue_app.dart`의 `ThemeData` 교체
2. 로그인 플로우: `auth_gate.dart` + `login_page.dart`
3. `oncue_home_page.dart` (탭 셸)
4. `combination_list_page.dart` + `combination_detail_page.dart`
5. `reservation_form_page.dart` + `permission_guide_page.dart`
6. `reservation_list_page.dart` + `reservation_detail_page.dart`
7. `immediate_call_page.dart` (목업 보완)

## 테스트 · 검증

- 기존 위젯 테스트가 참조하는 `ValueKey` · 텍스트 · Finder는 유지한다. 비주얼 변경만이므로 기존 테스트가 수정 없이 통과해야 회귀 없음의 근거가 된다.
- 새 디자인 시스템 위젯에는 자체 widget test를 추가한다 (예: `PrimaryButton`이 비활성일 때 탭이 아무 동작도 하지 않는지).
- `flutter analyze` + `flutter test`를 일반 검증으로 사용한다.

## 작업 위치

`oncue-mobile` 저장소의 워크트리 `feature/mobile-design-system-2` (`/Users/yeonny0723/orca/workspaces/oncue-mobile/feature-mobile-design-system-2`)에서 작업한다. `main` 브랜치는 별도로 진행 중인 통화 실패 버그 추적과 분리해 건드리지 않는다.
