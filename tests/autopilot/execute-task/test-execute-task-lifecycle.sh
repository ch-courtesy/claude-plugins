#!/usr/bin/env bash
# test-execute-task-lifecycle.sh — task-id→materialize→loop→(forge)→상태전이 (mock 엔진).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../../../plugins/autopilot/skills/execute-task/references/execute-task.sh"
ADAPTER="$HERE/../../../plugins/autopilot/task-backend/adapter.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
bash "$ADAPTER" init --backend filesystem >/dev/null

# mock loop: start=noop, status --json 은 $MOCK_RESULT 신호 방출, cleanup 무시
mkdir -p bin
cat > bin/loop <<'EOF'
#!/usr/bin/env bash
case "$1" in
  start|cleanup) exit 0;;
  status) printf '{"state":"terminal","signals":["%s"]}\n' "${MOCK_RESULT:-DONE}";;
  *) exit 0;;
esac
EOF
chmod +x bin/loop
# mock forge: integrate→branch 출력, review→rc20(할 일 없음=깨끗+비동기 승인대기), merge→rc0.
#   review 반환코드는 rl_round 계약(#426): 20 = 승인 폴링 유지 시나리오. 해피패스는 즉시 승인.
cat > bin/forge <<'EOF'
#!/usr/bin/env bash
case "$1" in
  integrate) echo "branch: feat/x"; echo "pr: 7"; exit 0;;
  review) exit 20;;
  merge) exit 0;;
  *) exit 0;;
esac
EOF
chmod +x bin/forge

# 승인 게이트는 실제 PR 승인 상태로 판정한다(review rc 아님). 해피패스 = 즉시 승인(true) +
# 미해결 [blocking] 인라인 없음(BLOCKING_CHECK_CMD=true=clear). blocking 가산 차단은 별도 테스트.
run() { ADAPTER_CMD="bash $ADAPTER" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
        HEARTBEAT_INTERVAL=1 APPROVAL_CHECK_CMD=true BLOCKING_CHECK_CMD=true SLEEP_CMD=: bash "$ET" "$@"; }
status_of(){ bash "$ADAPTER" get_task --task-id "$1" | jq -r .status; }

# 1) --stop-at review: DONE → review 에서 정지
id="$(bash "$ADAPTER" create_task --title "T1" --body '## 목표'$'\n'x | jq -r .task_id)"
MOCK_RESULT=DONE run start "$id" --stop-at review >/dev/null
chk "stop-at review → review" "$(status_of "$id")" "review"
[[ -d "$TMP/.task-work/$id" ]] && ok "1) stop-at: task-work 잔존" || bad "1) stop-at: task-work 잔존"

# 2) 전체 경로: DONE + forge 승인/머지 → done
id2="$(bash "$ADAPTER" create_task --title "T2" --body '## 목표'$'\n'y | jq -r .task_id)"
MOCK_RESULT=DONE run start "$id2" >/dev/null
chk "전체 경로 → done" "$(status_of "$id2")" "done"
[[ ! -d "$TMP/.task-work/$id2" ]] && ok "2) done: task-work 삭제" || bad "2) done: task-work 삭제"
[[ ! -d "$TMP/.autopilot/runs/$id2" ]] && ok "2) done: run-dir 삭제" || bad "2) done: run-dir 삭제"

# 3) BLOCKED 신호 → blocked
id3="$(bash "$ADAPTER" create_task --title "T3" --body '## 목표'$'\n'z | jq -r .task_id)"
MOCK_RESULT=BLOCKED run start "$id3" >/dev/null 2>&1 || true
chk "BLOCKED → blocked" "$(status_of "$id3")" "blocked"
[[ -d "$TMP/.task-work/$id3" ]] && ok "3) blocked: task-work 잔존" || bad "3) blocked: task-work 잔존"

# 4) ROOT_DIR 회귀: 링크드 워크트리 안에서 호출해도 run_dir 이 메인 리포 루트에 생성됨
T2="$(mktemp -d)"
trap 'rm -rf "$TMP" "$T2"' EXIT
git init -q "$T2"
git -C "$T2" config user.email t@t
git -C "$T2" config user.name t
git -C "$T2" commit -q --allow-empty -m "init"
git -C "$T2" worktree add -q "$T2/.task-work/wt" --detach
# 완전 목 어댑터 (git root 비의존 — adapter.sh 는 --show-toplevel 기반이어서 worktree 내에서 오동작)
mkdir -p "$T2/bin"
cat > "$T2/bin/adapter_wt" << AMOCK
#!/usr/bin/env bash
case "\$1" in
  materialize) echo '{"spec_path":"$T2/.task-work/wt_task/SPEC.md"}';;
  claim)        echo '{"claimed":true}';;
  renew_lease|set_status|append_log) exit 0;;
  *) exit 0;;
esac
AMOCK
chmod +x "$T2/bin/adapter_wt"
touch "$T2/dummy.md"
# 링크드 워크트리 안에서 execute-task.sh 실행 (run_dir 생성 지점까지 도달: --stop-at review 없음)
(cd "$T2/.task-work/wt"
 ADAPTER_CMD="bash $T2/bin/adapter_wt" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
 MOCK_RESULT=DONE HEARTBEAT_INTERVAL=1 APPROVAL_CHECK_CMD=true BLOCKING_CHECK_CMD=true SLEEP_CMD=: \
 bash "$ET" start wt_task >/dev/null 2>&1 || true)
# done 후 run_dir(leaf) 삭제됐지만 parent 가 $T2 에 있으면 ROOT_DIR 이 올바르게 결정된 것
[[ -d "$T2/.autopilot/runs" ]] \
  && ok "4) worktree-내-호출 → run_dir 메인 루트 생성" \
  || bad "4) worktree-내-호출 → run_dir 메인 루트 생성"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
