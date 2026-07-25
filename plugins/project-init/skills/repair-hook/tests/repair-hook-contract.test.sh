#!/usr/bin/env bash
# repair-hook: shared/hook-standard 평가→수정 계약 테스트.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
README="$DIR/README.md"

fail=0
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fail=1; fi; }

check "SKILL.md exists" test -f "$SKILL"
check "README.md exists" test -f "$README"
check "name matches folder" grep -qE '^name: repair-hook$' "$SKILL"

check "description has WHAT(평가) keyword" grep -qE '평가' "$SKILL"
check "description has WHEN trigger keyword" grep -qE '활성화|할 때' "$SKILL"
check "documents default hooks dir argument" grep -qF '.claude/hooks/' "$SKILL"

check "references shared hook-standard checker" grep -qF '../../shared/hook-standard/hook_checker.py' "$SKILL"
check "references shared hook-standard document" grep -qF '../../shared/hook-standard/standard.md' "$SKILL"
check "references shared invocation contract" grep -qF '../../shared/hook-standard/checker-invocation.md' "$SKILL"

check "requires approval before applying fixes" grep -qE '승인' "$SKILL"
check "mentions diff presentation before apply" grep -qF 'diff' "$SKILL"
check "re-evaluates after applying approved fixes" grep -qE '재평가' "$SKILL"
check "MINOR items are report-only" grep -qF 'MINOR' "$SKILL"
check "reports pass with no edits when 0 BLOCKER/MAJOR" grep -qE '0건' "$SKILL"
check "rejection leaves item unresolved without edits" grep -qE '거부' "$SKILL"
check "proposes 2-tier migration for flat layout" bash -c "grep -qE '플랫' '$SKILL' && grep -qE '2계층' '$SKILL'"

check "no destructive tools in allowed-tools" bash -c "! grep -qE 'rm -rf|push --force' '$SKILL'"
# 모델 검사(3단계)는 핸들러·lib 스크립트·settings 를 직접 읽어야 하므로 파일 열거
# 수단이 allowed-tools 에 있어야 한다 (PR 639 [blocking/85]).
check "allowed-tools includes Glob for model-check file enumeration" grep -qE '^  - Glob$' "$SKILL"

# Bash 실행 인자는 cwd 비의존 절대경로(repo_root 기준)여야 한다 — Read 전용 상대경로(../../)와
# 구분: 코드펜스 안의 'python3 ...hook_checker.py' 줄에 상대경로가 남아있으면 실패.
check "hook_checker.py invocation uses repo-root-based absolute path, not a bare relative path" \
  bash -c "! grep -E '^python3 \.\./\.\./shared/hook-standard/hook_checker\.py' '$SKILL'"
# repo-root 확정 계약은 shared/hook-standard/checker-invocation.md 로 단일 출처화됨 —
# SKILL.md 가 그 계약을 참조하고, 계약 문서가 실제로 repo root 확정을 요구하는지 체인으로 검증.
CONTRACT="$DIR/../../shared/hook-standard/checker-invocation.md"
check "invocation contract resolves repo root before invoking the checker" \
  grep -qF 'git rev-parse --show-toplevel' "$CONTRACT"

if [ "$fail" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi
