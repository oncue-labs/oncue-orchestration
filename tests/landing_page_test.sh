#!/usr/bin/env bash

set -euo pipefail

landing_page="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/index.html"

test -f "$landing_page"
test -f "$(dirname "$landing_page")/assets/favicon.png"

rg -q '<title>OnCue</title>' "$landing_page"
rg -q '<link rel="icon" type="image/png" href="assets/favicon.png" />' "$landing_page"
rg -q '<img class="brand-mark" src="assets/favicon.png" alt="OnCue 로고" />' "$landing_page"
rg -q '<img src="assets/favicon.png" alt="산타 할아버지" />' "$landing_page"
rg -q '산타도 친구도,' "$landing_page"
rg -q '원하는 순간에 불러볼까요\?' "$landing_page"
rg -q '12살 민수가 빨리 잤으면 좋겠어요' "$landing_page"
rg -q '민수가 오늘은 일찍 잠들 수 있게 도와주세요' "$landing_page"
rg -q '원하는 전화 한 통을 만드는 4단계' "$landing_page"
rg -q '오늘은 어떤 목소리를 만나볼까요\?' "$landing_page"
rg -q '이번 전화에 어떤 이야기를 담아볼까요\?' "$landing_page"
rg -q '언제 그 전화가 오면 좋을까요\?' "$landing_page"
rg -q '전화를 받는 순간, 이야기가 시작돼요\.' "$landing_page"
rg -q '상황과 통화 목표를 입력해보세요\.' "$landing_page"
rg -q 'TestFlight로 먼저 써보기' "$landing_page"
rg -q 'iPhone 전용 · 초기 테스트 사용자 모집 중' "$landing_page"
rg -q 'href="https://github.com/orgs/oncue-labs/repositories"' "$landing_page"
rg -q 'href="https://www.linkedin.com/in/juyeon-kim-6a227a207/"' "$landing_page"

printf '%s\n' 'landing page contract passed'
