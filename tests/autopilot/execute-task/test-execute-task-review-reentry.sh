#!/usr/bin/env bash
# test-execute-task-review-reentry.sh — review 상태 crash 후 forge 단계 재진입 검증.
#   (a) 정상 경로: review_entered 미존재 → loop.start 1회 → forge 진입 시점 마커 존재 → done 후 runs/ 정리
#   (b) 재진입 경로: review_entered 존재 → loop.start 미호출 → forge → done 후 runs/ 정리
#   (c) --stop-at review: forge 미진입 → review_entered 미생성
# done 전이는 et_cleanup_dirs 로 dirname(spec_path)·runs/<id>/ 를 정리하므로(의도된 기능),
# 마커 존재는 done 이전(forge integrate 시점, mock forge 가 기록)에 검증한다.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../../../plugins/autopilot/skills/execute-task/references/execute-task.sh"
ADAPTER="$HERE/../../../plugins/autopilot/lib/task-backend/adapter.sh"
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
# integrate 시점($3=run_dir; 호출 계약 integrate <sp> <run_dir> <key>)에 review_entered
# 존재 여부를 FORGE_MARKER_LOG 에 기록 — done-정리가 마커를 지우기 전, forge 진입 시점의
# 마커 생성을 검증하기 위함.
cat > bin/forge << 'EOF'
#!/usr/bin/env bash
case "$1" in
  integrate)
    [[ -f "$3/review_entered" ]] && echo "marker" >> "${FORGE_MARKER_LOG:-/dev/null}"
    echo "branch: feat/x"; echo "pr: 7"; exit 0;;
  review) exit 20;;
  merge) exit 0;;
  *) exit 0;;
esac
EOF
chmod +x bin/forge

# mock adapter: claim 항상 true, set_status 결과를 MOCK_STATUS_FILE 에 기록.
# MOCK_STATUS_LOG 가 설정되면 모든 set_status 호출의 상태값을 줄 단위로 append.
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
    if [[ -n "$s" && -n "${MOCK_STATUS_LOG:-}" ]]; then printf '%s\n' "$s" >> "$MOCK_STATUS_LOG"; fi
    printf '{"task_id":"X","status":"%s"}\n' "$s";;
  renew_lease|append_log)
    printf '{"task_id":"X"}\n';;
  *)
    printf '{"task_id":"X"}\n';;
esac
EOF
chmod +x bin/adapter_mock

# renew_lease 만 no-op 하고 나머지는 실제 fs adapter 로 패스스루하는 래퍼(run_fs 용).
# 백그라운드 heartbeat 의 renew_lease 가 메인 흐름 set_status 와 같은 태스크 파일에 동시
# 기록(fs_fm_set 공유 $f.tmp)하면 status 소실·truncation 플레이크가 난다. 이 테스트의 단정은
# lease 를 검증하지 않으므로(heartbeat 는 전용 테스트 별도) 동시 기록자만 제거한다.
cat > bin/adapter_norenew << EOF
#!/usr/bin/env bash
[[ "\$1" == renew_lease ]] && { echo '{"task_id":"noop"}'; exit 0; }
exec bash "$ADAPTER" "\$@"
EOF
chmod +x bin/adapter_norenew

# mock materialize 용 spec 배치: done-정리가 dirname(spec_path) 를 제거하므로
# 테스트 루트($TMP)가 아닌 케이스별 하위 디렉터리에 둔다(루트 삭제 방지).
mkdir -p "$TMP/wd_b" "$TMP/wd_c"; touch "$TMP/wd_b/dummy.md" "$TMP/wd_c/dummy.md"
status_of(){ bash "$ADAPTER" get_task --task-id "$1" | jq -r .status; }

run_fs() {  # 실제 filesystem adapter (renew_lease 만 no-op — 위 래퍼 주석 참조)
  ADAPTER_CMD="bash $TMP/bin/adapter_norenew" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
  HEARTBEAT_INTERVAL=999 APPROVAL_CHECK_CMD=true BLOCKING_CHECK_CMD=true SLEEP_CMD=: \
  bash "$ET" "$@"
}
run_mock() {  # 완전 mock adapter (claim 항상 true)
  ADAPTER_CMD="bash $TMP/bin/adapter_mock" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
  HEARTBEAT_INTERVAL=999 APPROVAL_CHECK_CMD=true BLOCKING_CHECK_CMD=true SLEEP_CMD=: \
  bash "$ET" "$@"
}

# --- (a) 정상 경로: loop.start 1회 → forge 진입 시점 review_entered 존재 → done 후 runs/ 정리 ---
id_a="$(bash "$ADAPTER" create_task --title "A" --body '## 목표'$'\n'x | jq -r .task_id)"
clog_a="$TMP/loop_a.log"; : > "$clog_a"
mlog_a="$TMP/marker_a.log"; : > "$mlog_a"
LOOP_CALL_LOG="$clog_a" FORGE_MARKER_LOG="$mlog_a" run_fs start "$id_a" >/dev/null 2>&1 || true
chk "(a) 정상 경로 → done" "$(status_of "$id_a")" "done"
chk "(a) loop.start 1회" "$(awk '/^start$/{c++}END{print c+0}' "$clog_a")" "1"
grep -qx "marker" "$mlog_a" 2>/dev/null \
  && ok "(a) forge 진입 시점 review_entered 존재" || bad "(a) forge 진입 시점 review_entered 존재"
[[ ! -d "$TMP/.autopilot/runs/$id_a" ]] \
  && ok "(a) done 후 runs 디렉터리 정리됨" || bad "(a) done 후 runs 디렉터리 정리됨"

# --- (b) 재진입: review_entered 존재 → loop.start 미호출 → forge → done 후 runs/ 정리 ---
# 완전 mock adapter: claim 항상 true (filesystem claim lock 우회)
st_b="$TMP/st_b"; slog_b="$TMP/sl_b"
mkdir -p "$TMP/.autopilot/runs/Xb"
touch "$TMP/.autopilot/runs/Xb/review_entered"
clog_b="$TMP/loop_b.log"; : > "$clog_b"
MOCK_WD="$TMP/wd_b" MOCK_STATUS_FILE="$st_b" MOCK_STATUS_LOG="$slog_b" LOOP_CALL_LOG="$clog_b" \
  run_mock start Xb >/dev/null 2>&1 || true
chk "(b) 재진입 → done" "$(cat "$st_b" 2>/dev/null || echo '')" "done"
chk "(b) 재진입: loop.start 미호출" "$(awk '/^start$/{c++}END{print c+0}' "$clog_b")" "0"
grep -qx "review" "$slog_b" 2>/dev/null \
  && ok "(b) 재진입: set_status review 호출됨" \
  || bad "(b) 재진입: set_status review 호출됨"
[[ ! -d "$TMP/.autopilot/runs/Xb" ]] \
  && ok "(b) done 후 runs 디렉터리 정리됨" || bad "(b) done 후 runs 디렉터리 정리됨"

# --- (c) --stop-at review: review_entered 미생성, forge 미진입 ---
st_c="$TMP/st_c"
mkdir -p "$TMP/.autopilot/runs/Xc"
clog_c="$TMP/loop_c.log"; : > "$clog_c"
MOCK_WD="$TMP/wd_c" MOCK_STATUS_FILE="$st_c" LOOP_CALL_LOG="$clog_c" \
  run_mock start Xc --stop-at review >/dev/null 2>&1 || true
chk "(c) stop-at review → review 상태" "$(cat "$st_c" 2>/dev/null || echo '')" "review"
[[ ! -f "$TMP/.autopilot/runs/Xc/review_entered" ]] \
  && ok "(c) stop-at review: review_entered 미생성" \
  || bad "(c) stop-at review: review_entered 미생성"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
