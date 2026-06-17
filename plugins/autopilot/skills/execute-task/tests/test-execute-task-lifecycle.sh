#!/usr/bin/env bash
# test-execute-task-lifecycle.sh — task-id→materialize→loop→(forge)→상태전이 (mock 엔진).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ET="$HERE/../references/execute-task.sh"
ADAPTER="$HERE/../../../task-backend/adapter.sh"
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
# mock forge: integrate→branch 출력, review/merge→rc0
cat > bin/forge <<'EOF'
#!/usr/bin/env bash
case "$1" in
  integrate) echo "branch: feat/x"; echo "pr: 7"; exit 0;;
  review) exit 0;;
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

# 2) 전체 경로: DONE + forge 승인/머지 → done
id2="$(bash "$ADAPTER" create_task --title "T2" --body '## 목표'$'\n'y | jq -r .task_id)"
MOCK_RESULT=DONE run start "$id2" >/dev/null
chk "전체 경로 → done" "$(status_of "$id2")" "done"

# 3) BLOCKED 신호 → blocked
id3="$(bash "$ADAPTER" create_task --title "T3" --body '## 목표'$'\n'z | jq -r .task_id)"
MOCK_RESULT=BLOCKED run start "$id3" >/dev/null 2>&1 || true
chk "BLOCKED → blocked" "$(status_of "$id3")" "blocked"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
