#!/usr/bin/env bash
# loop 워커 지침 구성이 소비 프로젝트의 벤더 지침(AGENTS.md/CLAUDE.md → rules 인덱스 등)을
# 보존하고 그 뒤에 constitution 을 병합하는지 검증(정적). 회귀: 과거엔 constitution 을
# CLAUDE.md/AGENTS.md 로 cp 덮어써 워커가 프로젝트 지침(versioning 등)을 보지 못했다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFS="$SCRIPT_DIR/../../../plugins/autopilot/skills/loop/references"
LOOP_SH="$REFS/loop.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$LOOP_SH" ]] || fail "loop.sh 부재: $LOOP_SH"

# 1) 더 이상 constitution 을 CLAUDE.md/AGENTS.md 로 덮어쓰지(cp) 않는다(프로젝트 지침 유실 회귀 방지).
if grep -qE 'cp +"\$SCRIPT_DIR/constitution\.md" +"\$WT/(CLAUDE|AGENTS)\.md"' "$LOOP_SH"; then
  fail "loop.sh 가 여전히 constitution 을 CLAUDE.md/AGENTS.md 로 cp 덮어쓴다 — 프로젝트 지침 유실"
fi

# 2) 원본(프로젝트 지침) 보존 + 병합 로직 존재.
grep -q '_loop_base' "$LOOP_SH"   || fail "원본 지침 보존(_loop_base) 로직 부재"
grep -q '_loop_merged' "$LOOP_SH" || fail "병합(_loop_merged) 로직 부재"

# 3) 병합본을 두 워커 지침 파일에 기록.
grep -qE 'printf .+_loop_merged.+> *"\$WT/CLAUDE\.md"' "$LOOP_SH" \
  || fail "CLAUDE.md 에 병합본 기록 부재"
grep -qE 'printf .+_loop_merged.+> *"\$WT/AGENTS\.md"' "$LOOP_SH" \
  || fail "AGENTS.md 에 병합본 기록 부재"

# 4) 멱등성: 병합 기반은 작업 사본이 아니라 git HEAD(pristine)에서 읽어야 한다.
#    prepare_workspace 가 워크트리를 재사용하므로, 이미 병합된 작업 사본을 base 로 다시 읽으면
#    재시작마다 constitution 이 중복 누적된다.
grep -qE 'git -C "\$WT" show HEAD:AGENTS\.md' "$LOOP_SH" \
  || fail "멱등 base(git show HEAD:AGENTS.md) 미사용 — 재시작 시 constitution 중복 누적 위험"
# 작업 사본을 base 로 cat 하지 않는다(중복 누적 회귀 방지).
if grep -qE '_loop_base="\$\(cat "\$WT/(AGENTS|CLAUDE)\.md"\)"' "$LOOP_SH"; then
  fail "병합 base 를 작업 사본에서 cat 한다 — 재시작 시 중복 누적"
fi

# 5) constitution 읽기 실패는 즉시 die(silent failure 방지).
grep -A1 '_loop_const="\$(cat' "$LOOP_SH" | grep -q '|| die' \
  || fail "constitution 읽기 실패 시 die 부재(silent failure)"

echo "=== loop 프로젝트 지침 보존+병합 테스트 통과 ==="
