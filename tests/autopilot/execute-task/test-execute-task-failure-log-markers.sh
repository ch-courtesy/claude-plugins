#!/usr/bin/env bash
# test-execute-task-failure-log-markers.sh — integrate/merge 실패 시 무로그 blocked 회귀 가드 (run 592 관측).
#   결함: integrate/merge 실패 분기가 set_status blocked 만 호출하고 append_log 마커를 남기지 않아,
#   실패 사유가 stderr 로만 흘러 백그라운드 실행에서 유실(무로그 blocked → 수동 포렌식 필요).
#   기대: 두 분기 모두 백엔드 로그에 [blocked] 마커 + 원인 식별 가능한 실패 사유 텍스트를 남긴다.
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

# mock forge: FORGE_MODE 로 실패 지점 선택.
#   integrate-fail → integrate 가 non-ff push 거부 사유를 출력하고 rc4.
#   merge-fail     → integrate/review 정상(즉시 approve), merge 가 사유 출력 후 rc1.
cat > bin/forge <<'EOF'
#!/usr/bin/env bash
case "$1" in
  integrate)
    if [[ "${FORGE_MODE:-}" == "integrate-fail" ]]; then
      echo "integration: push 실패(force 금지): feat/x" >&2
      echo "! [rejected] feat/x -> feat/x (non-fast-forward)" >&2
      exit 4
    fi
    echo "branch: feat/x"; echo "pr: 7"; exit 0;;
  review) exit 30;;  # rl_round 계약: 30=approve → 머지 진행
  merge)
    if [[ "${FORGE_MODE:-}" == "merge-fail" ]]; then
      echo "merge: ff-only 게이트 실패 — base 전진(재동기화 필요)" >&2
      exit 1
    fi
    exit 0;;
  *) exit 0;;
esac
EOF
chmod +x bin/forge

# renew_lease 동시 기록자 제거 래퍼(lifecycle 테스트와 동일 이유 — 상태 파일 클로버 방지).
cat > bin/adapter_norenew << EOF
#!/usr/bin/env bash
[[ "\$1" == renew_lease ]] && { echo '{"task_id":"noop"}'; exit 0; }
exec bash "$ADAPTER" "\$@"
EOF
chmod +x bin/adapter_norenew

run() { ADAPTER_CMD="bash $TMP/bin/adapter_norenew" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
        HEARTBEAT_INTERVAL=1 APPROVAL_CHECK_CMD=true BLOCKING_CHECK_CMD=true SLEEP_CMD=: bash "$ET" "$@"; }
status_of(){ bash "$ADAPTER" get_task --task-id "$1" | jq -r .status; }
task_file(){ printf '%s/.tasks/%s.md' "$TMP" "$1"; }

# ---- 1: integrate 실패 → blocked 마커 + 실패 사유 텍스트가 백엔드 로그에 남는다 ----
id1="$(bash "$ADAPTER" create_task --title "T-int" --body '## 목표'$'\n'x | jq -r .task_id)"
rc=0; FORGE_MODE=integrate-fail run start "$id1" >/dev/null 2>&1 || rc=$?
chk "1: integrate 실패 rc=1" "$rc" "1"
chk "1: status=blocked" "$(status_of "$id1")" "blocked"
grep -q '\[blocked\].*integrate' "$(task_file "$id1")" \
  && ok "1: [blocked] 마커(integrate) 기록" || bad "1: [blocked] 마커(integrate) 기록"
grep -q 'non-fast-forward' "$(task_file "$id1")" \
  && ok "1: 실패 사유 텍스트(non-fast-forward) 기록" || bad "1: 실패 사유 텍스트(non-fast-forward) 기록"

# ---- 2: merge 실패 → blocked 마커 + 실패 사유 텍스트가 백엔드 로그에 남는다 ----
id2="$(bash "$ADAPTER" create_task --title "T-mrg" --body '## 목표'$'\n'y | jq -r .task_id)"
rc=0; FORGE_MODE=merge-fail run start "$id2" >/dev/null 2>&1 || rc=$?
chk "2: merge 실패 rc=1" "$rc" "1"
chk "2: status=blocked" "$(status_of "$id2")" "blocked"
grep -q '\[blocked\].*merge' "$(task_file "$id2")" \
  && ok "2: [blocked] 마커(merge) 기록" || bad "2: [blocked] 마커(merge) 기록"
grep -q 'ff-only 게이트 실패' "$(task_file "$id2")" \
  && ok "2: 실패 사유 텍스트(ff-only) 기록" || bad "2: 실패 사유 텍스트(ff-only) 기록"

# ---- 3: 정상 경로 회귀 없음(성공 시 blocked 마커 미기록, done 전이 유지) ----
id3="$(bash "$ADAPTER" create_task --title "T-ok" --body '## 목표'$'\n'z | jq -r .task_id)"
run start "$id3" >/dev/null 2>&1 || true
chk "3: 성공 경로 status=done" "$(status_of "$id3")" "done"
grep -q '\[blocked\]' "$(task_file "$id3")" \
  && bad "3: 성공 경로에 blocked 마커 없음" || ok "3: 성공 경로에 blocked 마커 없음"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "FAILURES present"; exit 1; }
