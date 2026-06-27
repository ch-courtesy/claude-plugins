#!/usr/bin/env bash
# test-execute-task-approval-poll.sh — PR 경로 비동기 호스팅 봇 승인 폴링 대기 검증.
#   (a) 미승인→N초 후 APPROVED → 대기 후 머지·done
#   (b) 상한까지 미승인 → blocked
#   (c) 폴링 상한/간격 env override
#   (d) 즉시 APPROVED → 대기(sleep) 없이 머지(회귀)
#   (e) direct(PR 없음) 경로는 폴링 미적용(기존 동작 보존)
#   (f) 머지 게이트(forge/lib/merge.sh mg_approval_gate)는 단발 검사로 유지
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../../../plugins/autopilot/skills/execute-task/references/execute-task.sh"
ADAPTER="$HERE/../../../plugins/autopilot/task-backend/adapter.sh"
MERGE="$HERE/../../../plugins/autopilot/forge/lib/merge.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
bash "$ADAPTER" init --backend filesystem >/dev/null

mkdir -p bin
# mock loop: start/cleanup noop, status→DONE 신호.
cat > bin/loop <<'EOF'
#!/usr/bin/env bash
case "$1" in
  start|cleanup) exit 0;;
  status) printf '{"state":"terminal","signals":["%s"]}\n' "${MOCK_RESULT:-DONE}";;
  *) exit 0;;
esac
EOF
chmod +x bin/loop

# mock forge: integrate→branch(+pr; NO_PR=1 이면 pr 생략), review→rc20(할 일 없음=깨끗+비동기
#   승인대기, rl_round #426 계약 → 승인 폴링 유지 시나리오), merge→rc0(+기록)
cat > bin/forge <<'EOF'
#!/usr/bin/env bash
case "$1" in
  integrate) echo "branch: feat/x"; [[ "${NO_PR:-}" == "1" ]] || echo "pr: 7"; exit 0;;
  # direct(NO_PR=1) 은 run-direct(항상 0=approve collapse) 미러; PR 은 round 20(승인 폴링 유지) 미러.
  review) [[ "${NO_PR:-}" == "1" ]] && exit 0 || exit 20;;
  merge) [[ -n "${MERGE_LOG:-}" ]] && echo merged >> "$MERGE_LOG"; exit 0;;
  *) exit 0;;
esac
EOF
chmod +x bin/forge

# mock approval check: 호출 카운트($APPROVE_COUNTER) 증가, n>=APPROVE_AFTER 면 승인(rc0).
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
run_poll() { local id="$1"; shift
  # BLOCKING_CHECK_CMD=:(clear) 로 미해결-[blocking] 가산 게이트를 중립화 — 이 파일은 승인 폴링만
  # 검증한다. blocking 가산 차단은 test-execute-task-blocking-gate.sh 가 별도로 다룬다.
  env ADAPTER_CMD="bash $ADAPTER" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
      HEARTBEAT_INTERVAL=1 MOCK_RESULT=DONE BLOCKING_CHECK_CMD=: "$@" bash "$ET" start "$id"
}

# (a) 미승인 후 폴링하다 3번째 확인에서 APPROVED → 대기 후 머지·done
id="$(newtask A)"; cnt="$TMP/cntA"; : > "$cnt"
run_poll "$id" APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$cnt" APPROVE_AFTER=3 \
  APPROVAL_WAIT_MAX=100 APPROVAL_POLL_INTERVAL=10 SLEEP_CMD=: >/dev/null 2>&1 || true
chk "(a) 폴링 후 승인 → done" "$(status_of "$id")" "done"
chk "(a) 승인까지 3회 확인" "$(cat "$cnt")" "3"

# (b) 상한까지 미승인 → blocked (MAX=4,interval=2 → 3회 확인)
id="$(newtask B)"; cnt="$TMP/cntB"; : > "$cnt"
run_poll "$id" APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$cnt" \
  APPROVAL_WAIT_MAX=4 APPROVAL_POLL_INTERVAL=2 SLEEP_CMD=: >/dev/null 2>&1 || true
chk "(b) 상한까지 미승인 → blocked" "$(status_of "$id")" "blocked"
chk "(b) 상한 내 확인 횟수=3" "$(cat "$cnt")" "3"

# (c) override: MAX=6,interval=2 → 4회 확인
id="$(newtask C)"; cnt="$TMP/cntC"; : > "$cnt"
run_poll "$id" APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$cnt" \
  APPROVAL_WAIT_MAX=6 APPROVAL_POLL_INTERVAL=2 SLEEP_CMD=: >/dev/null 2>&1 || true
chk "(c) override 상한/간격 반영(6/2→4회)" "$(cat "$cnt")" "4"

# (d) 즉시 APPROVED → 대기(sleep) 없이 머지·done (회귀)
id="$(newtask D)"; cnt="$TMP/cntD"; : > "$cnt"; slog="$TMP/slogD"; : > "$slog"
run_poll "$id" APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$cnt" APPROVE_AFTER=1 \
  APPROVAL_WAIT_MAX=100 APPROVAL_POLL_INTERVAL=10 SLEEP_CMD="bash $TMP/bin/sleeprec" SLEEP_LOG="$slog" \
  >/dev/null 2>&1 || true
chk "(d) 즉시 승인 → done" "$(status_of "$id")" "done"
chk "(d) 즉시 승인 시 1회만 확인" "$(cat "$cnt")" "1"
chk "(d) 즉시 승인 → sleep 미호출" "$(wc -l < "$slog" | tr -d ' ')" "0"

# (e) direct(PR 없음) 경로: 폴링 미적용, 기존 동작 보존 → done, 승인 확인 미호출
id="$(newtask E)"; cnt="$TMP/cntE"; rm -f "$cnt"
run_poll "$id" NO_PR=1 APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$cnt" APPROVE_AFTER=9999 \
  SLEEP_CMD=: >/dev/null 2>&1 || true
chk "(e) direct 경로 → done(폴링 미적용)" "$(status_of "$id")" "done"
chk "(e) direct 경로 승인 폴링 미호출" "$(cat "$cnt" 2>/dev/null || echo 0)" "0"

# (g) 비숫자 APPROVAL_WAIT_MAX override → 기본값(360)으로 보정돼 폴링이 즉시 오종료하지 않음.
#   보정 전: (( waited >= abc )) 가 0>=0 으로 평가돼 1회 확인 후 즉시 break(blocked) → 오종료.
#   보정 후: 360 으로 보정, interval=200 → 0,200,400 누적으로 3회 확인 후 blocked.
id="$(newtask G)"; cnt="$TMP/cntG"; : > "$cnt"
run_poll "$id" APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$cnt" \
  APPROVAL_WAIT_MAX=abc APPROVAL_POLL_INTERVAL=200 SLEEP_CMD=: >/dev/null 2>&1 || true
chk "(g) 비숫자 상한 → 기본값 보정 후 blocked" "$(status_of "$id")" "blocked"
chk "(g) 비숫자 상한 보정(360/200→3회)" "$(cat "$cnt")" "3"

# (h) 빈 APPROVAL_WAIT_MAX override 도 무한 멈춤 없이 정상 종료(기본값 동작) — timeout 가드.
id="$(newtask H)"; cnt="$TMP/cntH"; : > "$cnt"
timeout 20 env ADAPTER_CMD="bash $ADAPTER" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
  HEARTBEAT_INTERVAL=1 MOCK_RESULT=DONE BLOCKING_CHECK_CMD=: APPROVAL_CHECK_CMD="bash $TMP/bin/approve" APPROVE_COUNTER="$cnt" \
  APPROVAL_WAIT_MAX= APPROVAL_POLL_INTERVAL=200 SLEEP_CMD=: bash "$ET" start "$id" >/dev/null 2>&1 || true
chk "(h) 빈 상한 → 무한 멈춤 없이 blocked" "$(status_of "$id")" "blocked"

# (f) merge.sh mg_approval_gate 는 단발 검사(sleep/loop 없음) 유지
gate="$(awk '/^mg_approval_gate\(\)/{f=1} f{print} f&&/^}/{if(NR>1)exit}' "$MERGE")"
if printf '%s' "$gate" | grep -qE 'sleep|while|[^a-z]for[^a-z]'; then bad "(f) merge gate 단발 유지(폴링 없음)"; else ok "(f) merge gate 단발 유지(폴링 없음)"; fi

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
