#!/usr/bin/env bash
# test-execute-task-review-codes.sh — PR 경로가 rl_round(=$FORGE_CMD review) 반환코드로 분기하는지 검증(#426).
#   리워크 구동/빠른 실패로 '오지 않을 승인 무의미 대기' 제거.
#   (30) approve     → 머지 진행(done), 승인폴링/sleep 미경유
#   (0)  재작업 재푸시 → 루프 계속(재리뷰). 0,0,30 시퀀스 → 3 라운드 후 done, sleep 미경유
#   (10) 에스컬레이션/라운드상한/핑퐁 → 폴링 상한 대기 없이 즉시 blocked(review 1회, sleep 0), merge 미호출
#   (7)  알 수 없는 비-0 → 보수적 즉시 blocked(빠른 실패)
#   (20) 할 일 없음(깨끗+비동기 승인대기) → 기존 APPROVAL_WAIT_MAX 폴링 유지(회귀)
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
cat > bin/loop <<'EOF'
#!/usr/bin/env bash
case "$1" in
  start|cleanup) exit 0;;
  status) printf '{"state":"terminal","signals":["DONE"]}\n';;
  *) exit 0;;
esac
EOF
chmod +x bin/loop

# mock forge: review 가 rl_round 코드를 표면화하도록 시뮬레이션.
#   REVIEW_SEQ(파일, 줄당 코드)로 순차 반환(소진 후 마지막 줄 고정), 없으면 REVIEW_RC(단일).
#   review:<code> 를 REVIEW_LOG 에 기록(호출 횟수·코드 추적). integrate→branch+pr(7), merge→기록.
cat > bin/forge <<'EOF'
#!/usr/bin/env bash
case "$1" in
  integrate) echo "branch: feat/x"; echo "pr: 7"; exit 0;;
  review)
    code="${REVIEW_RC:-20}"
    if [[ -n "${REVIEW_SEQ:-}" ]]; then
      idxf="${REVIEW_SEQ}.idx"
      i=$(( $(cat "$idxf" 2>/dev/null || echo 0) + 1 )); printf '%s' "$i" > "$idxf"
      code="$(sed -n "${i}p" "$REVIEW_SEQ")"; [[ -n "$code" ]] || code="$(tail -n1 "$REVIEW_SEQ")"
    fi
    [[ -n "${REVIEW_LOG:-}" ]] && echo "review:$code" >> "$REVIEW_LOG"
    exit "$code";;
  merge) [[ -n "${MERGE_LOG:-}" ]] && echo merged >> "$MERGE_LOG"; exit 0;;
  *) exit 0;;
esac
EOF
chmod +x bin/forge

# mock approval: 호출 카운트 증가. APPROVE_AFTER 설정 시 n>=AFTER 면 승인(rc0), 아니면 미승인(rc1).
#   미설정 → 항상 미승인(rc1). 비-20 분기에서 이 mock 이 호출되면 안 됨(카운트로 검증).
cat > bin/approve <<'EOF'
#!/usr/bin/env bash
f="${APPROVE_COUNTER:?}"
n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$f"
[[ -n "${APPROVE_AFTER:-}" && "$n" -ge "$APPROVE_AFTER" ]]
EOF
chmod +x bin/approve

# mock sleep: 호출 기록(실제 대기 없음).
cat > bin/sleeprec <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${SLEEP_LOG:?}"
EOF
chmod +x bin/sleeprec

status_of(){ bash "$ADAPTER" get_task --task-id "$1" | jq -r .status; }
newtask(){ bash "$ADAPTER" create_task --title "$1" --body '## 목표'$'\n'x | jq -r .task_id; }
# BLOCKING_CHECK_CMD=:(clear) 로 가산 게이트 중립화 — 이 파일은 review 반환코드 분기만 검증한다.
run() { local id="$1"; shift
  env ADAPTER_CMD="bash $ADAPTER" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
      HEARTBEAT_INTERVAL=1 BLOCKING_CHECK_CMD=: "$@" bash "$ET" start "$id"; }
rc_count(){ wc -l < "$1" 2>/dev/null | tr -d ' '; }

# (30) approve → 머지(done). 승인폴링/sleep 미경유(approval mock 미호출).
id="$(newtask A30)"; rlog="$TMP/rA"; : > "$rlog"; mlog="$TMP/mA"; : > "$mlog"
acnt="$TMP/acA"; printf 0 > "$acnt"; slog="$TMP/sA"; : > "$slog"
run "$id" REVIEW_RC=30 REVIEW_LOG="$rlog" MERGE_LOG="$mlog" \
  APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$acnt" \
  SLEEP_CMD="bash $TMP/bin/sleeprec" SLEEP_LOG="$slog" >/dev/null 2>&1 || true
chk "(30) approve → done" "$(status_of "$id")" "done"
chk "(30) merge 호출" "$(grep -c merged "$mlog")" "1"
chk "(30) 승인폴링 미호출" "$(cat "$acnt")" "0"
chk "(30) sleep 미호출" "$(rc_count "$slog")" "0"

# (0,0,30) 재작업 재푸시 진전 → 루프 계속 → 3 라운드 후 approve → done. sleep 미경유.
id="$(newtask A0)"; rlog="$TMP/r0"; : > "$rlog"; mlog="$TMP/m0"; : > "$mlog"
seq="$TMP/seq0"; printf '0\n0\n30\n' > "$seq"; slog="$TMP/s0"; : > "$slog"
run "$id" REVIEW_SEQ="$seq" REVIEW_LOG="$rlog" MERGE_LOG="$mlog" \
  APPROVAL_CHECK_CMD=false SLEEP_CMD="bash $TMP/bin/sleeprec" SLEEP_LOG="$slog" >/dev/null 2>&1 || true
chk "(0) 재작업 진전 → 루프 계속 → done" "$(status_of "$id")" "done"
chk "(0) review 3 라운드 수행" "$(rc_count "$rlog")" "3"
chk "(0) merge 호출" "$(grep -c merged "$mlog")" "1"
chk "(0) 진전 루프는 sleep 미경유" "$(rc_count "$slog")" "0"

# (10) 에스컬레이션/라운드상한/핑퐁 → 폴링 상한 대기 없이 즉시 blocked. review 1회, sleep 0, merge 미호출.
id="$(newtask A10)"; rlog="$TMP/r10"; : > "$rlog"; mlog="$TMP/m10"; : > "$mlog"
acnt="$TMP/ac10"; printf 0 > "$acnt"; slog="$TMP/s10"; : > "$slog"
run "$id" REVIEW_RC=10 REVIEW_LOG="$rlog" MERGE_LOG="$mlog" \
  APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$acnt" \
  APPROVAL_WAIT_MAX=1000 APPROVAL_POLL_INTERVAL=10 \
  SLEEP_CMD="bash $TMP/bin/sleeprec" SLEEP_LOG="$slog" >/dev/null 2>&1 || true
chk "(10) 진전 불가 → 즉시 blocked" "$(status_of "$id")" "blocked"
chk "(10) review 1회만(폴링 미대기)" "$(rc_count "$rlog")" "1"
chk "(10) sleep 미호출(빠른 실패)" "$(rc_count "$slog")" "0"
chk "(10) 승인폴링 미호출" "$(cat "$acnt")" "0"
chk "(10) merge 미호출" "$(rc_count "$mlog")" "0"

# (7) 알 수 없는 비-0 → 보수적 즉시 blocked(빠른 실패).
id="$(newtask A7)"; rlog="$TMP/r7"; : > "$rlog"; slog="$TMP/s7"; : > "$slog"
run "$id" REVIEW_RC=7 REVIEW_LOG="$rlog" \
  APPROVAL_CHECK_CMD=false APPROVAL_WAIT_MAX=1000 APPROVAL_POLL_INTERVAL=10 \
  SLEEP_CMD="bash $TMP/bin/sleeprec" SLEEP_LOG="$slog" >/dev/null 2>&1 || true
chk "(7) 알 수 없는 rc → 즉시 blocked" "$(status_of "$id")" "blocked"
chk "(7) review 1회만" "$(rc_count "$rlog")" "1"
chk "(7) sleep 미호출" "$(rc_count "$slog")" "0"

# (20) 할 일 없음 → 기존 승인 폴링 유지(회귀). 2회째 승인 → 폴링 후 done, sleep 경유.
id="$(newtask A20)"; acnt="$TMP/ac20"; : > "$acnt"; slog="$TMP/s20"; : > "$slog"; mlog="$TMP/m20"; : > "$mlog"
run "$id" REVIEW_RC=20 MERGE_LOG="$mlog" \
  APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$acnt" APPROVE_AFTER=2 \
  APPROVAL_WAIT_MAX=100 APPROVAL_POLL_INTERVAL=10 \
  SLEEP_CMD="bash $TMP/bin/sleeprec" SLEEP_LOG="$slog" >/dev/null 2>&1 || true
chk "(20) 깨끗+비동기 승인대기 → 폴링 후 done" "$(status_of "$id")" "done"
chk "(20) merge 호출" "$(grep -c merged "$mlog")" "1"
chk "(20) 승인까지 2회 폴링" "$(cat "$acnt")" "2"
[[ "$(rc_count "$slog")" -ge 1 ]] && ok "(20) 폴링 대기 sleep 경유(1회+)" || bad "(20) 폴링 대기 sleep 경유 got $(rc_count "$slog")"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
