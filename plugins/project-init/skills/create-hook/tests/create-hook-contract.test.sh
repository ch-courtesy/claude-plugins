#!/usr/bin/env bash
# create-hook: shared/hook-standard 단일 출처 참조 계약 테스트.
# 스킬이 표준 사본 없이 shared/hook-standard 를 참조하고, SPEC 완료 조건
# (인터뷰 확정 항목·기존 핸들러 디스패치 추가·검사기 1회 재검·덮어쓰기 승인)을 담는지 확인한다.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
README="$DIR/README.md"

fail=0
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fail=1; fi; }

check "SKILL.md exists" test -f "$SKILL"
check "README.md exists" test -f "$README"

# 단일 출처 참조 (사본 금지)
check "SKILL.md references shared hook-standard standard" grep -qF '../../shared/hook-standard/standard.md' "$SKILL"
check "SKILL.md references shared checker invocation contract" grep -qF '../../shared/hook-standard/checker-invocation.md' "$SKILL"
check "SKILL.md references shared hook_checker script" grep -qF 'hook_checker.py' "$SKILL"
check "README references shared hook-standard" grep -qF 'shared/hook-standard' "$README"
check "no local copy of standard.md" test ! -e "$DIR/references/standard.md"
check "no local copy of hook_checker.py" test ! -e "$DIR/references/hook_checker.py"

# 완료 조건: 인터뷰가 이벤트·기능·차단 여부·대상 디렉토리를 확정
check "interview covers event, command, blocking, target dir" bash -c \
  "grep -q '이벤트' '$SKILL' && grep -q 'command' '$SKILL' && grep -q '차단' '$SKILL' && grep -q '대상 디렉토리' '$SKILL'"
check "interview uses structured user question capability" grep -qF '구조화된 사용자 질문' "$SKILL"

# 완료 조건: 기존 핸들러 존재 시 새 핸들러 대신 디스패치 추가
check "existing handler gets dispatch addition, not a new handler" bash -c \
  "grep -q '기존 핸들러' '$SKILL' && grep -q '디스패치' '$SKILL'"

# 완료 조건: 검사기 BLOCKER·MAJOR 0 확인 + 1회만 재검
check "checker gate targets BLOCKER and MAJOR zero" bash -c \
  "grep -q 'BLOCKER' '$SKILL' && grep -q 'MAJOR' '$SKILL'"
check "recheck happens at most once" grep -qF '1회만 재검' "$SKILL"

# 완료 조건: 기존 파일 덮어쓰기는 diff 제시 + 명시적 승인
check "overwrite gated behind diff and explicit approval" bash -c \
  "grep -q 'diff' '$SKILL' && grep -qE '명시적 승인' '$SKILL'"

# 제약: placeholder 등록 계약
check "settings registration uses CLAUDE_PROJECT_DIR placeholder" grep -qF 'CLAUDE_PROJECT_DIR' "$SKILL"

if [ "$fail" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi
