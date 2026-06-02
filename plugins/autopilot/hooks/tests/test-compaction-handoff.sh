#!/usr/bin/env bash
# autopilot 대화형 세션 compaction handoff hook 검증 테스트
#
# 커버하는 SPEC 완료 조건:
#  AC1 PreCompact 직전 → 7필드 구조화 핸드오프 문서를 디스크에 기록
#  AC2 핸드오프 문서 존재 + 새 세션 시작 → 내용을 컨텍스트로 자동 주입(restore)
#  AC3 캡처 실패/타임아웃 → 비차단(exit 0), 관찰 가능
#  AC4 loop 헤드리스(`.loop/` 작업 공간) → 핸드오프 미적용
#  AC5 기존 using-autopilot SessionStart 주입과 공존

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/plugins/autopilot/hooks"
HOOKS_JSON="$HOOKS_DIR/hooks.json"
PRECOMPACT_SH="$HOOKS_DIR/pre-compact.sh"
RESTORE_SH="$HOOKS_DIR/session-restore.sh"
COMMON_SH="$HOOKS_DIR/handoff-common.sh"
SESSION_START_SH="$HOOKS_DIR/session-start.sh"

FIELDS="task completed current_state constraints files_touched open_questions next_steps"

pass() { echo "OK: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

echo "=== 파일 존재 ==="
for f in "$HOOKS_JSON" "$PRECOMPACT_SH" "$RESTORE_SH" "$COMMON_SH" "$SESSION_START_SH"; do
  [ -f "$f" ] || fail "$f 부재"
  pass "${f#"$REPO_ROOT"/}"
done

echo ""
echo "=== 실행 권한 + syntax ==="
for f in "$PRECOMPACT_SH" "$RESTORE_SH"; do
  [ -x "$f" ] || fail "$f 실행 권한 없음"
  sh -n "$f" || fail "$f syntax 오류"
done
sh -n "$COMMON_SH" || fail "$COMMON_SH syntax 오류"
pass "syntax/exec"

echo ""
echo "=== hooks.json: PreCompact + SessionStart(공존) ==="
jq -e . "$HOOKS_JSON" >/dev/null || fail "hooks.json invalid JSON"
jq -e '.hooks.PreCompact' "$HOOKS_JSON" >/dev/null || fail "PreCompact 엔트리 없음"
jq -e '[.hooks.PreCompact[].hooks[].command] | any(test("pre-compact.sh"))' "$HOOKS_JSON" >/dev/null \
  || fail "PreCompact 가 pre-compact.sh 를 참조하지 않음"
# SessionStart: 기존 session-start.sh + 신규 session-restore.sh 둘 다 존재(AC5)
jq -e '[.hooks.SessionStart[].hooks[].command] | any(test("session-start.sh"))' "$HOOKS_JSON" >/dev/null \
  || fail "SessionStart 가 기존 session-start.sh 를 잃음(공존 위반)"
jq -e '[.hooks.SessionStart[].hooks[].command] | any(test("session-restore.sh"))' "$HOOKS_JSON" >/dev/null \
  || fail "SessionStart 가 session-restore.sh 복원 단계를 갖지 않음"
pass "hooks.json"

# 가짜 Claude Code transcript JSONL 생성기
make_transcript() {
  out=$1
  cat > "$out" <<'JSONL'
{"type":"user","message":{"role":"user","content":"PreCompact 핸드오프 훅을 만들어줘"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"핸드오프 스크립트를 추가하겠습니다."},{"type":"tool_use","name":"Write","input":{"file_path":"/proj/plugins/autopilot/hooks/pre-compact.sh"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"다음 단계: session-restore.sh 를 구현합니다."},{"type":"tool_use","name":"Edit","input":{"file_path":"/proj/plugins/autopilot/hooks/hooks.json"}}]}}
JSONL
}

echo ""
echo "=== AC1: PreCompact → 7필드 구조화 핸드오프 기록 ==="
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"; mkdir -p "$PROJ"
TR="$TMP/transcript.jsonl"; make_transcript "$TR"
IN=$(jq -nc --arg t "$TR" --arg c "$PROJ" \
  '{session_id:"s1",transcript_path:$t,cwd:$c,hook_event_name:"PreCompact",trigger:"auto"}')
set +e
printf '%s' "$IN" | env CLAUDE_PROJECT_DIR="$PROJ" sh "$PRECOMPACT_SH"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "pre-compact.sh exit $rc (0 기대)"
HANDOFF="$PROJ/.autopilot/handoff/HANDOFF.md"
[ -f "$HANDOFF" ] || fail "핸드오프 문서 미생성: $HANDOFF"
for fld in $FIELDS; do
  grep -qi "$fld" "$HANDOFF" || fail "핸드오프에 필드 '$fld' 없음"
done
# 실질 내용(substantive): transcript 의 실제 task 문구·만진 파일 반영
grep -q "핸드오프" "$HANDOFF" || fail "핸드오프에 실제 task 내용 없음(stub 의심)"
grep -q "pre-compact.sh" "$HANDOFF" || fail "files_touched 에 실제 편집 파일 반영 안 됨"
pass "AC1 구조화 핸드오프 생성"

echo ""
echo "=== git 추적 제외(.autopilot/.gitignore) ==="
[ -f "$PROJ/.autopilot/.gitignore" ] || fail ".autopilot/.gitignore 미생성"
grep -q '\*' "$PROJ/.autopilot/.gitignore" || fail ".autopilot/.gitignore 가 전체 무시(*) 아님"
pass "gitignore"

echo ""
echo "=== AC4: loop 헤드리스(.loop/) → 핸드오프 미적용 ==="
PROJL="$TMP/loopproj"; mkdir -p "$PROJL/.loop/signals"
IN2=$(jq -nc --arg t "$TR" --arg c "$PROJL" \
  '{session_id:"s2",transcript_path:$t,cwd:$c,hook_event_name:"PreCompact",trigger:"auto"}')
set +e
printf '%s' "$IN2" | env CLAUDE_PROJECT_DIR="$PROJL" sh "$PRECOMPACT_SH"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "loop 작업 공간에서 pre-compact.sh exit $rc (0 기대)"
[ ! -f "$PROJL/.autopilot/handoff/HANDOFF.md" ] || fail "loop 작업 공간에서 핸드오프가 생성됨(AC4 위반)"
pass "AC4 loop 제외"

echo ""
echo "=== AC3: 실패/누락 입력 → 비차단(exit 0) ==="
PROJ3="$TMP/proj3"; mkdir -p "$PROJ3"
IN3=$(jq -nc --arg t "$TMP/does-not-exist.jsonl" --arg c "$PROJ3" \
  '{session_id:"s3",transcript_path:$t,cwd:$c,hook_event_name:"PreCompact",trigger:"auto"}')
set +e
printf '%s' "$IN3" | env CLAUDE_PROJECT_DIR="$PROJ3" sh "$PRECOMPACT_SH" 2>/tmp/_handoff_err; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "transcript 누락 시 exit $rc (0 기대, graceful passthrough)"
# 빈 stdin 도 비차단
set +e
printf '' | env CLAUDE_PROJECT_DIR="$PROJ3" sh "$PRECOMPACT_SH"; rc=$?
set -e
[ "$rc" -eq 0 ] || fail "빈 stdin 시 exit $rc (0 기대)"
pass "AC3 graceful passthrough"

echo ""
echo "=== AC2: SessionStart restore → 핸드오프 내용 컨텍스트 주입 ==="
OUT=$(jq -nc --arg c "$PROJ" \
  '{session_id:"s4",source:"compact",cwd:$c,hook_event_name:"SessionStart"}' \
  | env CLAUDE_PROJECT_DIR="$PROJ" sh "$RESTORE_SH")
echo "$OUT" | grep -q "핸드오프" || fail "restore 출력에 핸드오프 내용 없음"
echo "$OUT" | grep -q "pre-compact.sh" || fail "restore 출력에 만진 파일 내용 없음"
pass "AC2 restore 주입"

echo ""
echo "=== AC2: 핸드오프 부재 시 restore 무해(빈 출력, exit 0) ==="
PROJ5="$TMP/proj5"; mkdir -p "$PROJ5"
set +e
OUT5=$(jq -nc --arg c "$PROJ5" '{source:"startup",cwd:$c,hook_event_name:"SessionStart"}' \
  | env CLAUDE_PROJECT_DIR="$PROJ5" sh "$RESTORE_SH"); rc=$?
set -e
[ "$rc" -eq 0 ] || fail "핸드오프 부재 시 restore exit $rc (0 기대)"
[ -z "$OUT5" ] || fail "핸드오프 부재인데 restore 가 내용을 출력함"
pass "AC2 부재시 무해"

echo ""
echo "=== AC4: loop 작업 공간에서 restore 미적용 ==="
# 핸드오프가 존재하는 loop 작업 공간을 인위 구성(정상 경로라면 캡처가 막혔겠지만,
# 복원 단계도 독립적으로 loop 를 제외하는지 확인).
mkdir -p "$PROJL/.autopilot/handoff"
printf '# handoff\n## task\n핸드오프\n## files_touched\n- pre-compact.sh\n' \
  > "$PROJL/.autopilot/handoff/HANDOFF.md"
OUTL=$(jq -nc --arg c "$PROJL" '{source:"startup",cwd:$c,hook_event_name:"SessionStart"}' \
  | env CLAUDE_PROJECT_DIR="$PROJL" sh "$RESTORE_SH" || true)
[ -z "$OUTL" ] || fail "loop 작업 공간에서 restore 가 주입함(AC4 위반)"
pass "AC4 restore loop 제외"

echo ""
echo "=== 모든 테스트 통과 ==="
