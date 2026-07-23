#!/usr/bin/env bash
# test-execute-task-stale-residue.sh — 재실행이 이전 시도의 stale 워크트리 '등록'을 정리하고 진행하는지(#630).
#   (a) run-dir 디렉터리만 삭제돼 git 워크트리 등록이 stale 로 남은 상태에서 재실행하면,
#       그 등록을 정리해 loop 의 worktree add 가 성공한다("missing but already registered" 회귀 가드).
#   (b) 잔재가 없으면 기존 동작 그대로(정리 로그 없이 loop.start 진행).
#   (c) 워크트리 디렉터리가 살아 있으면 건드리지 않는다(오정리로 작업 유실 방지).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../../../plugins/autopilot/skills/execute-task/references/execute-task.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
echo tracked > tracked.txt; git add tracked.txt; git commit -q -m init

mkdir -p bin wd; touch wd/dummy.md

# mock loop: start 에서 **실제** worktree add 를 수행한다(재현 대상이 loop 의 add 실패이므로).
#   성공/실패를 LOOP_CALL_LOG 에 남겨 정리 여부를 관찰한다.
cat > bin/loop << 'EOF'
#!/usr/bin/env bash
case "$1" in
  start)
    # 실제 loop 처럼 materialize 된 run-dir(=워크트리 부모) 아래에 워크트리를 만든다.
    # 부모가 존재해야 git 이 stale 등록을 "missing but already registered" 로 판정한다.
    # 잔재 정리 단계가 살아 있는 워크트리를 지웠는지 관찰(loop 진입 시점 = 정리 직후).
    [[ -f "$MOCK_WT/tracked.txt" ]] && echo "keep-ok" >> "${LOOP_CALL_LOG:-/dev/null}"
    mkdir -p "$(dirname "$MOCK_WT")"
    if git -C "$MOCK_ROOT" worktree add --detach -q "$MOCK_WT" HEAD 2>/dev/null; then
      echo "add-ok" >> "${LOOP_CALL_LOG:-/dev/null}"
    else
      echo "add-fail" >> "${LOOP_CALL_LOG:-/dev/null}"
    fi
    exit 0;;
  cleanup) exit 0;;
  status) printf '{"state":"terminal","signals":["DONE"]}\n';;
  *) exit 0;;
esac
EOF
chmod +x bin/loop

cat > bin/forge << 'EOF'
#!/usr/bin/env bash
case "$1" in
  integrate) echo "branch: feat/x"; echo "pr: 7"; exit 0;;
  review) exit 20;;
  merge) exit 0;;
  *) exit 0;;
esac
EOF
chmod +x bin/forge

cat > bin/adapter_mock << 'EOF'
#!/usr/bin/env bash
case "$1" in
  materialize) printf '{"spec_path":"%s/dummy.md"}\n' "${MOCK_WD:-.}";;
  claim)       printf '{"task_id":"X","claimed":true}\n';;
  *)           printf '{"task_id":"X"}\n';;
esac
EOF
chmod +x bin/adapter_mock

run_mock() {
  ADAPTER_CMD="bash $TMP/bin/adapter_mock" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
  HEARTBEAT_INTERVAL=999 APPROVAL_CHECK_CMD=true BLOCKING_CHECK_CMD=true SLEEP_CMD=: \
  MOCK_ROOT="$TMP" MOCK_WD="$TMP/wd" \
  bash "$ET" "$@"
}

registered() {  # <path> — git 워크트리 등록 목록에 있으면 0.
  git worktree list --porcelain 2>/dev/null | grep -Fxq "worktree $1"
}

# --- (a) stale 등록(디렉터리 부재) → 정리 후 진행 ---
wt_a="$TMP/.autopilot/runs/Xa/.worktree"
git worktree add --detach -q "$wt_a" HEAD
rm -rf "$TMP/.autopilot/runs/Xa"
registered "$wt_a" && ok "(a) 사전조건: stale 워크트리 등록 존재" || bad "(a) 사전조건: stale 워크트리 등록 존재"
log_a="$TMP/loop_a.log"; : > "$log_a"
LOOP_CALL_LOG="$log_a" MOCK_WT="$wt_a" run_mock start Xa >/dev/null 2>&1 || true
grep -qx "add-ok" "$log_a" \
  && ok "(a) stale 등록 정리 후 worktree add 성공(재실행 자력 회복)" \
  || bad "(a) stale 등록 정리 후 worktree add 성공(재실행 자력 회복)"

# --- (b) 잔재 없음 → 기존 동작 유지 ---
wt_b="$TMP/.autopilot/runs/Xb/.worktree"
log_b="$TMP/loop_b.log"; : > "$log_b"
LOOP_CALL_LOG="$log_b" MOCK_WT="$wt_b" run_mock start Xb >/dev/null 2>&1 || true
grep -qx "add-ok" "$log_b" && ok "(b) 잔재 없음 → 기존 동작 유지(add 성공)" || bad "(b) 잔재 없음 → 기존 동작 유지(add 성공)"

# --- (c) 살아 있는 워크트리는 미훼손 ---
#   등록 존재 여부만 보면 loop 의 재-add 가 흔적을 덮어 항상 통과한다(무의미 단언).
#   워크트리 안의 작업 파일이 정리 단계 직후(loop 진입 시점)에도 남아 있는지로 관찰한다
#   (done 경로의 run-dir 정리는 의도된 기능이라 실행 후 관찰은 불가).
wt_c="$TMP/.autopilot/runs/Xc/.worktree"
git worktree add --detach -q "$wt_c" HEAD
log_c="$TMP/loop_c.log"; : > "$log_c"
LOOP_CALL_LOG="$log_c" MOCK_WT="$wt_c" run_mock start Xc >/dev/null 2>&1 || true
grep -qx "keep-ok" "$log_c" \
  && ok "(c) 살아 있는 워크트리 보존(작업 내용 미훼손)" \
  || bad "(c) 살아 있는 워크트리 보존(작업 내용 미훼손)"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
