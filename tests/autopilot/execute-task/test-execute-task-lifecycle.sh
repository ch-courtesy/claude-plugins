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
  start) touch loop.start.called 2>/dev/null; exit 0;;
  cleanup) touch loop.cleanup.called 2>/dev/null; exit 0;;
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

# renew_lease 만 no-op 하고 나머지는 실제 fs adapter 로 패스스루하는 래퍼.
# 백그라운드 heartbeat 의 renew_lease(fs_fm_set)가 메인 흐름 set_status 와 같은 태스크 파일에
# 동시 기록하면 공유 $f.tmp 클로버로 status 소실·파일 truncation 플레이크가 난다(케이스 7에서 관측).
# 이 테스트의 단정은 lease 를 검증하지 않으므로(heartbeat 는 전용 테스트 별도) 동시 기록자만 제거한다.
cat > bin/adapter_norenew << EOF
#!/usr/bin/env bash
[[ "\$1" == renew_lease ]] && { echo '{"task_id":"noop"}'; exit 0; }
exec bash "$ADAPTER" "\$@"
EOF
chmod +x bin/adapter_norenew

# 승인 게이트는 실제 PR 승인 상태로 판정한다(review rc 아님). 해피패스 = 즉시 승인(true) +
# 미해결 [blocking] 인라인 없음(BLOCKING_CHECK_CMD=true=clear). blocking 가산 차단은 별도 테스트.
run() { ADAPTER_CMD="bash $TMP/bin/adapter_norenew" LOOP_CMD="bash $TMP/bin/loop" FORGE_CMD="bash $TMP/bin/forge" \
        HEARTBEAT_INTERVAL=1 APPROVAL_CHECK_CMD=true BLOCKING_CHECK_CMD=true SLEEP_CMD=: bash "$ET" "$@"; }
status_of(){ bash "$ADAPTER" get_task --task-id "$1" | jq -r .status; }

# 1) --stop-at review: DONE → review 에서 정지
id="$(bash "$ADAPTER" create_task --title "T1" --body '## 목표'$'\n'x | jq -r .task_id)"
mkdir -p "$TMP/.review/tasks/$id"
MOCK_RESULT=DONE run start "$id" --stop-at review >/dev/null
chk "stop-at review → review" "$(status_of "$id")" "review"
[[ -d "$TMP/.task-work/$id" ]] && ok "1) stop-at: task-work 잔존" || bad "1) stop-at: task-work 잔존"
[[ -d "$TMP/.review/tasks/$id" ]] && ok "1) stop-at: review 상태 잔존" || bad "1) stop-at: review 상태 잔존"

# 2) 전체 경로: DONE + forge 승인/머지 → done
id2="$(bash "$ADAPTER" create_task --title "T2" --body '## 목표'$'\n'y | jq -r .task_id)"
mkdir -p "$TMP/.review/tasks/$id2" "$TMP/.review/tasks/other-keep"
MOCK_RESULT=DONE run start "$id2" >/dev/null
chk "전체 경로 → done" "$(status_of "$id2")" "done"
[[ ! -d "$TMP/.task-work/$id2" ]] && ok "2) done: task-work 삭제" || bad "2) done: task-work 삭제"
[[ ! -d "$TMP/.autopilot/runs/$id2" ]] && ok "2) done: run-dir 삭제" || bad "2) done: run-dir 삭제"
[[ ! -d "$TMP/.review/tasks/$id2" ]] && ok "2) done: review 상태 삭제" || bad "2) done: review 상태 삭제"
[[ -d "$TMP/.review/tasks/other-keep" ]] && ok "2) done: 다른 태스크 review 상태 보존" || bad "2) done: 다른 태스크 review 상태 보존"

# 3) BLOCKED 신호 → blocked
id3="$(bash "$ADAPTER" create_task --title "T3" --body '## 목표'$'\n'z | jq -r .task_id)"
mkdir -p "$TMP/.review/tasks/$id3"
MOCK_RESULT=BLOCKED run start "$id3" >/dev/null 2>&1 || true
chk "BLOCKED → blocked" "$(status_of "$id3")" "blocked"
[[ -d "$TMP/.task-work/$id3" ]] && ok "3) blocked: task-work 잔존" || bad "3) blocked: task-work 잔존"
[[ -d "$TMP/.review/tasks/$id3" ]] && ok "3) blocked: review 상태 잔존" || bad "3) blocked: review 상태 잔존"

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

# 5) status=done 선제 가드: 잔존 .task-work/.autopilot 디렉토리 정리 + 파이프라인(loop) 미재실행(#541)
id5="$(bash "$ADAPTER" create_task --title "T5" --body '## 목표'$'\n'w | jq -r .task_id)"
bash "$ADAPTER" set_status --task-id "$id5" --status done >/dev/null
mkdir -p "$TMP/.task-work/$id5" "$TMP/.autopilot/runs/$id5" "$TMP/.review/tasks/$id5"
touch "$TMP/.task-work/$id5/SPEC.md" "$TMP/.autopilot/runs/$id5/LOG.md"
rm -f "$TMP/loop.start.called"
run start "$id5" >/dev/null
[[ ! -d "$TMP/.task-work/$id5" ]] && ok "5) done 선제: task-work 정리" || bad "5) done 선제: task-work 정리"
[[ ! -d "$TMP/.autopilot/runs/$id5" ]] && ok "5) done 선제: run-dir 정리" || bad "5) done 선제: run-dir 정리"
[[ ! -d "$TMP/.review/tasks/$id5" ]] && ok "5) done 선제: review 상태 정리" || bad "5) done 선제: review 상태 정리"
chk "5) done 선제: status 유지" "$(status_of "$id5")" "done"
[[ ! -f "$TMP/loop.start.called" ]] && ok "5) done 선제: 파이프라인 미재실행(loop 미호출)" || bad "5) done 선제: 파이프라인 미재실행(loop 미호출)"

# 6) 멱등: 두 디렉토리 모두 이미 없는 상태에서 재호출해도 에러·디렉토리 생성 없이 안전 종료
run start "$id5" >/dev/null
[[ ! -d "$TMP/.task-work/$id5" && ! -d "$TMP/.autopilot/runs/$id5" ]] \
  && ok "6) 멱등 재호출: 디렉토리 미생성" || bad "6) 멱등 재호출: 디렉토리 미생성"

# 7) forge-단계 재진입 보존: review_entered 표지가 있으면 loop cleanup 을 건너뛴다(완료된 .worktree 보존)
#    → loop 미재실행 + integrate 부터 재개 → done. cleanup 이 호출되면 .worktree 가 삭제돼 integrate 가 깨진다.
id7="$(bash "$ADAPTER" create_task --title "T7" --body '## 목표'$'\n'r | jq -r .task_id)"
mkdir -p "$TMP/.autopilot/runs/$id7"; touch "$TMP/.autopilot/runs/$id7/review_entered"  # forge-단계 재진입 표지
rm -f "$TMP/loop.cleanup.called" "$TMP/loop.start.called"
run start "$id7" >/dev/null
[[ ! -f "$TMP/loop.cleanup.called" ]] && ok "7) forge 재진입: loop cleanup 미호출(.worktree 보존)" || bad "7) forge 재진입: loop cleanup 미호출(.worktree 보존)"
[[ ! -f "$TMP/loop.start.called" ]] && ok "7) forge 재진입: loop 미재실행(integrate 부터 재개)" || bad "7) forge 재진입: loop 미재실행(integrate 부터 재개)"
chk "7) forge 재진입 → done" "$(status_of "$id7")" "done"

# 8) loop-단계 재진입/최초 실행: review_entered 표지가 없으면 loop cleanup 을 정상 호출(회귀 방지)
id8="$(bash "$ADAPTER" create_task --title "T8" --body '## 목표'$'\n's | jq -r .task_id)"
rm -f "$TMP/loop.cleanup.called"
MOCK_RESULT=DONE run start "$id8" >/dev/null
[[ -f "$TMP/loop.cleanup.called" ]] && ok "8) loop-단계: loop cleanup 정상 호출" || bad "8) loop-단계: loop cleanup 정상 호출"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
