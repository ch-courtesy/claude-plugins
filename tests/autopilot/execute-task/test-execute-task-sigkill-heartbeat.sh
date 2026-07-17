#!/usr/bin/env bash
# test-execute-task-sigkill-heartbeat.sh — SIGKILL 후 heartbeat subshell orphan 자가종료 검증.
#   execute-task가 SIGKILL로 종료될 때, heartbeat subshell이 부모 생존 확인 후
#   스스로 종료해야 한다(orphan으로 lease를 영구 갱신하는 버그 회귀 방지).
#
#   TC1: SIGKILL 후 heartbeat orphan이 살아남으면 FAIL.
#   TC2: 세마포어 파일(/tmp/execute-task-<PID>.alive)이 실행 중 존재하지 않으면 FAIL
#         (PID 재사용 방지 메커니즘 부재 → 비-Linux에서 SIGTERM+PID재사용 시 orphan 재발).
#
#   GREEN → fix 후 TC1·TC2 모두 통과.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../../../plugins/autopilot/skills/execute-task/references/execute-task.sh"
ADAPTER="$HERE/../../../plugins/autopilot/lib/task-backend/adapter.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

TMP="$(mktemp -d)"
ET_PID=""
HB_PID_FILE="$TMP/hb.pid"
cleanup_test(){
  # 남은 백그라운드 프로세스 정리
  if [[ -s "$HB_PID_FILE" ]]; then
    hbp="$(cat "$HB_PID_FILE" 2>/dev/null || true)"
    [[ -n "$hbp" ]] && kill "$hbp" 2>/dev/null || true
  fi
  jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true
  # 세마포어 파일 잔재 정리 (SIGKILL 시 EXIT trap 미실행으로 남을 수 있음)
  [[ -n "$ET_PID" ]] && rm -f "/tmp/execute-task-${ET_PID}.alive" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup_test EXIT

cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
bash "$ADAPTER" init --backend filesystem >/dev/null

mkdir -p bin

# mock adapter: renew_lease → PPID(=heartbeat PID)를 파일에 기록 후 정상 반환.
# ADAPTER_EOF 미인용 → $TMP·$HB_PID_FILE 는 지금 치환, \$PPID 는 런타임에 치환.
cat > bin/adapter <<ADAPTER_EOF
#!/usr/bin/env bash
case "\$1" in
  materialize) echo '{"spec_path":"$TMP/spec.md"}';;
  claim)       echo '{"claimed":"true"}';;
  renew_lease) echo \$PPID > "$HB_PID_FILE"; exit 0;;
  set_status|append_log|get_task) exit 0;;
  *) exit 0;;
esac
ADAPTER_EOF
chmod +x bin/adapter

# mock loop: start → 영원히 블록(메인 프로세스가 kill되기 전까지 실행 중)
cat > bin/loop <<'LOOP_EOF'
#!/usr/bin/env bash
case "$1" in
  start)    sleep 999;;
  cleanup)  exit 0;;
  status)   echo '{"state":"terminal","signals":["DONE"]}';;
  *)        exit 0;;
esac
LOOP_EOF
chmod +x bin/loop

# 더미 spec 파일(materialize 결과 경로)
echo "# spec" > "$TMP/spec.md"

# adapter create_task (실제 백엔드 사용)
id="$(bash "$ADAPTER" create_task --title "T-hb-sigkill" --body $'## 목표\nx' | jq -r .task_id)"

# execute-task 백그라운드 실행 (HEARTBEAT_INTERVAL=1 → 빠른 감지)
ADAPTER_CMD="bash $TMP/bin/adapter" \
LOOP_CMD="bash $TMP/bin/loop" \
FORGE_CMD=":" \
HEARTBEAT_INTERVAL=1 \
bash "$ET" start "$id" &
ET_PID=$!   # 세마포어 파일 경로 예측: /tmp/execute-task-${ET_PID}.alive

# heartbeat가 첫 renew_lease 호출해 HB_PID_FILE에 기록될 때까지 대기(최대 5s)
waited=0
while [[ ! -s "$HB_PID_FILE" ]] && (( waited < 25 )); do
  sleep 0.2; waited=$((waited+1))
done

if [[ ! -s "$HB_PID_FILE" ]]; then
  bad "heartbeat가 시작되지 않았음(HB_PID_FILE 비어있음)"
  kill "$ET_PID" 2>/dev/null || true
  echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
fi

HB_PID="$(cat "$HB_PID_FILE")"

# heartbeat가 실제로 실행 중인지 확인
if ! kill -0 "$HB_PID" 2>/dev/null; then
  bad "heartbeat PID $HB_PID 가 초기 실행 중이 아님 — 테스트 셋업 이상"
  kill "$ET_PID" 2>/dev/null || true
  echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
fi

# TC2: 세마포어 파일 생성 확인 (PID 재사용 방지 메커니즘, fix 전 → FAIL)
# execute-task 실행 중 /tmp/execute-task-${ET_PID}.alive 가 존재해야 한다.
# 비-Linux fallback 에서 SIGTERM+PID재사용 시 heartbeat 가 오인하지 않도록 막는 역할.
if [[ -f "/tmp/execute-task-${ET_PID}.alive" ]]; then
  ok "세마포어 파일 생성됨 (/tmp/execute-task-${ET_PID}.alive)"
else
  bad "세마포어 파일 없음 — PID 재사용 방지 메커니즘 미구현 (kill-0 fallback만 있음)"
fi

# execute-task 메인 프로세스에 SIGKILL
kill -9 "$ET_PID" 2>/dev/null || true
wait "$ET_PID" 2>/dev/null || true

# heartbeat가 자가종료할 때까지 대기(최대 4s — HEARTBEAT_INTERVAL*3 + 여유)
waited_hb=0
while kill -0 "$HB_PID" 2>/dev/null && (( waited_hb < 20 )); do
  sleep 0.2; waited_hb=$((waited_hb+1))
done

if kill -0 "$HB_PID" 2>/dev/null; then
  bad "heartbeat (PID $HB_PID) 가 SIGKILL 후에도 살아있음 — orphan lease 갱신 버그"
else
  ok "SIGKILL 후 heartbeat 자가종료 확인"
fi

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
