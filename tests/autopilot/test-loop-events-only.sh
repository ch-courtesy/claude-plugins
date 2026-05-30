#!/usr/bin/env bash
# SPEC 173: autopilot:loop 스킬 실행 로그를 호출 세션으로 실시간 출력
#
# 검증 대상 (정적 grep 기반, 현 spec-file-driven loop contract):
#
# [loop SKILL.md — `#### Monitor` 섹션]
# 1. 기존 핵심 이벤트 정규식 패턴이 default 위치에서 제거됨
#    (`--events-only` 분기 설명에만 잔존하면 OK)
# 2. 새 default 필터가 "noise-only 제외" 의미를 표현하는 패턴으로 정의됨
#    (빈 줄·단독 dot 제외)
# 3. `--events-only` 플래그 정의 섹션이 존재
#    (명세·contract·`--no-monitor`와 일관 명시)
# 4. 셸 드라이버 직접 호출 시 미적용이 명시됨
#
# 외부 API 호출은 수행하지 않는다.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOOP_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/loop/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$LOOP_SKILL_MD" ]] || fail "$LOOP_SKILL_MD 부재"

# 핵심 이벤트 정규식 패턴 (default 필터의 옛 형태) — `--events-only` 분기에만 잔존해야 함.
KEY_EVENT_REGEX='이터 #|HALT|WARN|FAIL|ERROR|rate limit|claude 비정상|에스컬레이션|완료 신호'

# ---------------------------------------------------------------------------
# loop SKILL.md 의 "#### Monitor" 섹션 추출
# 다음 `#### ` 헤더 또는 `### ` 헤더 직전까지.
extract_section() {
  local file="$1" start_marker="$2"
  awk -v start="$start_marker" '
    BEGIN { capturing = 0 }
    {
      if ($0 ~ "^"start) { capturing = 1; print; next }
      if (capturing && /^#### / && $0 !~ "^"start) { exit }
      if (capturing && /^### /) { exit }
      if (capturing) print
    }
  ' "$file"
}

DEFAULT_MONITOR_SECTION="$(extract_section "$LOOP_SKILL_MD" "#### Monitor")"
[[ -n "$DEFAULT_MONITOR_SECTION" ]] \
  || fail "loop SKILL.md 에서 '#### Monitor' 섹션을 찾을 수 없음"

# ---------------------------------------------------------------------------
echo "=== check 1: default 위치에서 기존 핵심 이벤트 정규식 제거 ==="
# 기본 동작 섹션 내에서 KEY_EVENT_REGEX 패턴 자체가 "기본 필터"로 제시되는지 검사.
# `--events-only` 옵션 분기 설명 내부에서만 등장해야 함.
#
# 검증 전략:
#   - 기본 동작 섹션에서 `--events-only` 토큰의 첫 등장 *이전* 텍스트를
#     "default 영역"으로 추출 (현 contract 는 default 필터 설명과 `--events-only`
#     분기 설명을 같은 라인에 둘 수 있으므로 라인 단위가 아니라 토큰 단위로 절단)
#   - 그 default 영역 안에 KEY_EVENT_REGEX 가 등장하면 실패
DEFAULT_BEFORE_OPT="$(awk 'BEGIN { RS = "--events-only" } { print; exit }' <<< "$DEFAULT_MONITOR_SECTION")"

if grep -qF -- "$KEY_EVENT_REGEX" <<< "$DEFAULT_BEFORE_OPT"; then
  fail "check 1: 기존 핵심 이벤트 정규식이 default 필터 위치에 여전히 존재"
fi
ok "check 1: default 위치에서 기존 핵심 이벤트 정규식 제거됨"

# ---------------------------------------------------------------------------
echo ""
echo "=== check 2: 새 default 필터가 noise-only 제외 의미 표현 ==="
# default 필터 의미 — 빈 줄·단독 dot 만 제외. SKILL.md 가 "빈 줄"·"단독 dot" 어휘로
# 의미를 명시적으로 기술하는지 검사.
grep -q "빈 줄" <<< "$DEFAULT_BEFORE_OPT" \
  || fail "check 2: default 필터 설명에 '빈 줄' 어휘 부재"
grep -qE "(단독 dot|단독 \\.)" <<< "$DEFAULT_BEFORE_OPT" \
  || fail "check 2: default 필터 설명에 '단독 dot' 어휘 부재"
ok "check 2: default 필터가 noise-only 제외 의미로 정의됨 (빈 줄·단독 dot)"

# ---------------------------------------------------------------------------
echo ""
echo "=== check 3: --events-only 플래그 정의 섹션 존재 ==="
# `--events-only` 가 plugin 본문에 정의로 등장하고, contract 가 `--no-monitor` 와
# 일관됨을 명시해야 함.
grep -q -- "--events-only" "$LOOP_SKILL_MD" \
  || fail "check 3: loop SKILL.md 에 '--events-only' 토큰 부재"

# `--events-only` 와 `--no-monitor` 가 일관 명시되는 라인이 한 곳이라도 있어야 함.
grep -q -E -- "--events-only.*--no-monitor|--no-monitor.*--events-only" "$LOOP_SKILL_MD" \
  || fail "check 3: '--events-only' 와 '--no-monitor' contract 일관 명시 부재"
ok "check 3: --events-only 플래그 정의 + --no-monitor contract 일관 명시 존재"

# ---------------------------------------------------------------------------
echo ""
echo "=== check 4: 셸 드라이버 직접 호출 시 미적용 명시 ==="
# `--events-only` 플래그 정의 부근에서 셸 드라이버 직접 호출 시 효력 없음을 명시.
# `--no-monitor` 의 기존 정책과 동일하게 SKILL.md 차원 옵션이며 loop.sh 로 전달되지 않음.
# 다음 어휘 조합 중 적어도 하나가 events-only 관련 문장에 등장하면 통과:
#   - "직접 호출" + "효력이 없"  (예: "직접 호출하는 경우엔 효력이 없다")
#   - "SKILL.md 차원 옵션" + "loop.sh 로 ... 전달하지 않"  (--no-monitor 와 동일 contract)
events_only_context="$(grep -E -A3 -B1 -- "--events-only" "$LOOP_SKILL_MD" || true)"
if ! { grep -qE "(직접 호출.*효력이 없|효력이 없.*직접 호출)" <<< "$events_only_context" \
       || grep -qE "SKILL\.md 차원 옵션" <<< "$events_only_context"; }; then
  fail "check 4: --events-only 가 셸 드라이버 직접 호출 시 미적용임이 명시되지 않음"
fi
ok "check 4: 셸 드라이버 직접 호출 시 --events-only 미적용 명시 존재"

# ---------------------------------------------------------------------------
# 구 contract 검증 항목 제거 메모:
#   기존 check 5·6 은 spec SKILL.md 의 "step 10 → 지금 loop start 호출 (--events-only
#   opt-out)" 자동 연계 분기를 검증했다. spec-file-driven 리팩토링으로 spec 스킬은
#   더 이상 loop 를 직접 기동하지 않고(8단계로 끝나며 구현 스킬 추천만 수행), 자동
#   연계 chaining 과 거기에 딸린 `--events-only` opt-out 개념 자체가 제거되었다.
#   현 contract 에 대응 개념이 없으므로(`--events-only` 는 이제 loop SKILL.md 에만
#   존재) 두 항목은 재작성 대상이 아니라 삭제 대상이다.

echo ""
echo "ALL CHECKS PASSED"
