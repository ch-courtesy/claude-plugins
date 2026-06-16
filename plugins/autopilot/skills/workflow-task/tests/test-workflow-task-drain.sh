#!/usr/bin/env bash
# test-workflow-task-drain.sh — list_ready → execute-task 병렬 fan-out → done (1패스, DAG 없음).
# 실제 flow.sh + 실제 adapter(filesystem), execute-task 는 mock(상태를 done 으로).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT="$HERE/../references/workflow-task.sh"
ADAPTER="$HERE/../../../task-backend/adapter.sh"
FLOW="$HERE/../../flow/references/flow.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
bash "$ADAPTER" init --backend filesystem >/dev/null

# mock execute-task: 'start <id>' → 해당 태스크를 done 으로
mkdir -p bin
cat > bin/exec-mock <<EOF
#!/usr/bin/env bash
# args: start <id>
bash "$ADAPTER" set_status --task-id "\$2" --status done >/dev/null
EOF
chmod +x bin/exec-mock

# B depends_on A. 처음엔 A 만 ready.
a="$(bash "$ADAPTER" create_task --title A --body '## 목표'$'\n'a | jq -r .task_id)"
b="$(bash "$ADAPTER" create_task --title B --body '## 목표'$'\n'b --depends-on "$a" | jq -r .task_id)"

drain() { ADAPTER_CMD="bash $ADAPTER" FLOW_CMD="bash $FLOW" EXECUTE_CMD="bash $TMP/bin/exec-mock" bash "$WT" start; }

# 1패스: A 만 실행되어 done, B 는 아직
out1="$(drain)"
chk "1패스 ready=1" "$(printf '%s' "$out1" | jq -r .ready)" "1"
chk "A done" "$(bash "$ADAPTER" get_task --task-id "$a" | jq -r .status)" "done"
chk "B 아직 backlog" "$(bash "$ADAPTER" get_task --task-id "$b" | jq -r .status)" "backlog"

# 2패스: 이제 B ready(의존 해제) → 실행
out2="$(drain)"
chk "2패스 ready=1" "$(printf '%s' "$out2" | jq -r .ready)" "1"
chk "B done" "$(bash "$ADAPTER" get_task --task-id "$b" | jq -r .status)" "done"

# 3패스: 남은 ready 없음
out3="$(drain)"
chk "3패스 ready=0" "$(printf '%s' "$out3" | jq -r .ready)" "0"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
