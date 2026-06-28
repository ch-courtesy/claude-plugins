#!/usr/bin/env bash
# test-execute-task-review-reentry.sh — review 상태 crash 후 forge 단계 재진입 검증.
#   (a) 정상 경로: review_entered 미존재 → loop.start 1회 → review_entered 생성 → forge → done
#   (b) 재진입 경로: review_entered 존재 → loop.start 미호출 → forge → done
#   (c) --stop-at review: forge 미진입 → review_entered 미생성
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../../../plugins/autopilot/skills/execute-task/references/execute-task.sh"
ADAPTER="$HERE/../../../plugins/autopilot/task-backend/adapter.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
bash "$ADAPTER" init --backend filesystem >/dev/null

mkdir -p bin

# mock loop: 호출 기록 + DONE 신호. LOOP_CALL_LOG 파일에 verb 기록.
cat > bin/loop << 'EOF'
#!/usr/bin/env bash
echo "$1" >> "${LOOP_CALL_LOG:-/dev/null}"
case "$1" in
  start|cleanup) exit 0;;
  status) printf '{"state":"terminal","signals":["DONE"]}\n';;
  *) exit 0;;
esac
EOF
chmod +x bin/loop

# mock forge: integrate→branch+pr, review→rc20(승인폴링 대기), merge→rc0
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

# mock adapter: claim 항상 true, set_status 결과를 MOCK_STATUS_FILE 에 기록.
cat > bin/adapter_mock << 'EOF'
#!/usr/bin/env bash
case "$1" in
  materialize)
    printf '{"spec_path":"%s/dummy.md"}\n' "${MOCK_WD:-.}";;
  claim)
    printf '{"task_id":"X","claimed":true}\n';;
  set_status)
    s=""; i=2
    while [[ $i -le $# ]]; do
      a="${!i}"
      if [[ "$a" == "--status" ]]; then j=$((i+1)); s="${!j}"; break; fi
      i=$((i+1))
    done
    if [[ -n "$s" && -n "${MOCK_STATUS_FILE:-}" ]]; then printf '%s' "$s" > "$MOCK_STATUS_FILE"; fi
    printf '{"task_id":"X","status":"%s"}\n' "$s";;
  renew_lease|append_log)
    printf '{"task_id":"X"}\n';;
  *)
    printf '{"task_id":"X"}\n';;
esac
EOF
chmod +x bin/adapter_mock

touch "$TMP/dummy.md"
status_of(){ bash "$ADAPTER" get_task --task-id "$1" | jq -r .status; }

run_fs() {  # 실제 filesystem adapter
  ADAPTER_CMD="bash $ADAPTER" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
  HEARTBEAT_INTERVAL=999 APPROVAL_CHECK_CMD=true BLOCKING_CHECK_CMD=true SLEEP_CMD=: \
  bash "$ET" "$@"
}
run_mock() {  # 완전 mock adapter (claim 항상 true)
  ADAPTER_CMD="bash $TMP/bin/adapter_mock" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
  HEARTBEAT_INTERVAL=999 APPROVAL_CHECK_CMD=true BLOCKING_CHECK_CMD=true SLEEP_CMD=: \
  bash "$ET" "$@"
}

# --- (a) 정상 경로: review_entered 미존재 → loop.start 1회 → review_entered 생성 → done ---
id_a="$(bash "$ADAPTER" create_task --title "A" --body '## 목표'$'\n'x | jq -r .task_id)"
clog_a="$TMP/loop_a.log"; : > "$clog_a"
LOOP_CALL_LOG="$clog_a" run_fs start "$id_a" >/dev/null 2>&1 || true
chk "(a) 정상 경로 → done" "$(status_of "$id_a")" "done"
chk "(a) loop.start 1회" "$(awk '/^start$/{c++}END{print c+0}' "$clog_a")" "1"
[[ -f "$TMP/.autopilot/runs/$id_a/review_entered" ]] \
  && ok "(a) review_entered 생성됨" || bad "(a) review_entered 생성됨"

# --- (b) 재진입: review_entered 존재 → loop.start 미호출 → forge → done ---
# 완전 mock adapter: claim 항상 true (filesystem claim lock 우회)
st_b="$TMP/st_b"
mkdir -p "$TMP/.autopilot/runs/Xb"
touch "$TMP/.autopilot/runs/Xb/review_entered"
clog_b="$TMP/loop_b.log"; : > "$clog_b"
MOCK_WD="$TMP" MOCK_STATUS_FILE="$st_b" LOOP_CALL_LOG="$clog_b" \
  run_mock start Xb >/dev/null 2>&1 || true
chk "(b) 재진입 → done" "$(cat "$st_b" 2>/dev/null || echo '')" "done"
chk "(b) 재진입: loop.start 미호출" "$(awk '/^start$/{c++}END{print c+0}' "$clog_b")" "0"

# --- (c) --stop-at review: review_entered 미생성, forge 미진입 ---
st_c="$TMP/st_c"
mkdir -p "$TMP/.autopilot/runs/Xc"
clog_c="$TMP/loop_c.log"; : > "$clog_c"
MOCK_WD="$TMP" MOCK_STATUS_FILE="$st_c" LOOP_CALL_LOG="$clog_c" \
  run_mock start Xc --stop-at review >/dev/null 2>&1 || true
chk "(c) stop-at review → review 상태" "$(cat "$st_c" 2>/dev/null || echo '')" "review"
[[ ! -f "$TMP/.autopilot/runs/Xc/review_entered" ]] \
  && ok "(c) stop-at review: review_entered 미생성" \
  || bad "(c) stop-at review: review_entered 미생성"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
