#!/usr/bin/env bash
# loop 워커가 --print(일회성)로 실행되어 SessionStart 훅(project-init/hooks/rules-index.sh)이
# 돌지 않아 <project-rules-index> 가 워커에 닿지 않는 문제(#463)의 회귀 테스트.
# autopilot loop.sh 가 자체적으로(project-init 무의존) 워크트리 rules/ 를 훑어 동일 블록을
# 생성하고 워커 컨텍스트(_loop_merged)에 포함하는지 검증한다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFS="$SCRIPT_DIR/../references"
LOOP_SH="$REFS/loop.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$LOOP_SH" ]] || fail "loop.sh 부재: $LOOP_SH"

# loop.sh 는 source 시 함수만 노출(디스패처는 BASH_SOURCE 가드). build_rules_index 를 직접 호출.
# set -euo pipefail 격리를 위해 모든 호출을 서브셸에서 수행.

# --- 1) rules/ 존재 + .md 있음 → <project-rules-index> 블록 생성 ---
tmp1="$(mktemp -d)"
trap 'rm -rf "${tmp1:-}" "${tmp2:-}" "${tmp3:-}"' EXIT
mkdir -p "$tmp1/rules"
printf '# 버전 범프 규칙\n본문\n' > "$tmp1/rules/versioning.md"
printf '# 보안 규칙\n본문\n'   > "$tmp1/rules/security.md"

out1="$( ( source "$LOOP_SH"; build_rules_index "$tmp1" ) )" \
  || fail "build_rules_index 호출 실패(함수 부재 가능) — rules/ 케이스"

grep -q '<project-rules-index>'  <<<"$out1" || fail "출력에 <project-rules-index> 여는 태그 부재"
grep -q '</project-rules-index>' <<<"$out1" || fail "출력에 </project-rules-index> 닫는 태그 부재"
grep -q 'rules/versioning.md — 버전 범프 규칙' <<<"$out1" \
  || fail "versioning 룰 경로+목적(첫 H1) 항목 부재"
grep -q 'rules/security.md — 보안 규칙' <<<"$out1" \
  || fail "security 룰 경로+목적(첫 H1) 항목 부재"

# --- 2) rules/ 없음 → no-op(빈 출력) ---
tmp2="$(mktemp -d)"
out2="$( ( source "$LOOP_SH"; build_rules_index "$tmp2" ) )" \
  || fail "build_rules_index 호출 실패 — rules/ 없는 케이스"
[[ -z "$out2" ]] || fail "rules/ 없을 때 no-op 아님(출력: $out2)"

# --- 3) rules/ 있으나 .md 없음 → no-op(빈 출력) ---
tmp3="$(mktemp -d)"
mkdir -p "$tmp3/rules"
printf 'not markdown\n' > "$tmp3/rules/README.txt"
out3="$( ( source "$LOOP_SH"; build_rules_index "$tmp3" ) )" \
  || fail "build_rules_index 호출 실패 — .md 없는 케이스"
[[ -z "$out3" ]] || fail ".md 없을 때 no-op 아님(출력: $out3)"

# --- 4) 와이어링: prepare_workspace 가 build_rules_index 를 _loop_merged 에 포함 ---
grep -q 'build_rules_index' "$LOOP_SH" || fail "loop.sh 에 build_rules_index 정의/호출 부재"
grep -qE 'build_rules_index[^\n]*\$WT|build_rules_index "\$WT"' "$LOOP_SH" \
  || fail "prepare_workspace 가 워크트리(\$WT) 대상으로 build_rules_index 호출하지 않음"

# --- 5) project-init 무의존: 훅 스크립트 경로/호출 없음(자기완결). 산문 언급은 무방하나
#        실제 의존 신호(플러그인 경로 또는 rules-index.sh 실행)는 금지. ---
if grep -qE 'project-init/|rules-index\.sh' "$LOOP_SH"; then
  fail "loop.sh 가 project-init 훅 스크립트에 의존 — 플러그인 자기완결 위반"
fi

echo "=== loop rules-index(자기완결) 테스트 통과 ==="
