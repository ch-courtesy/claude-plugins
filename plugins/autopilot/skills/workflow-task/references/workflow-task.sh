#!/usr/bin/env bash
# workflow-task.sh — DAG 없는 1회 드레이너. list_ready 의 준비 태스크를 flow 평면 병렬
#   fan-out 으로 execute-task 에 돌리고 종료한다. 의존 순서는 백엔드 list_ready 가 틱 간 해결.
#
# 재사용 엔진(런타임 호출): flow.sh(병렬 러너), execute-task.sh(단일 태스크 전체 생애).
# 백엔드: task-backend/adapter.sh. 무인 실행: 대화형 호출 없음.
# 모킹: ADAPTER_CMD / FLOW_CMD / EXECUTE_CMD 환경변수.
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PLUGIN="$ROOT_DIR/plugins/autopilot"
[[ -d "$PLUGIN" ]] || PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

ADAPTER_CMD="${ADAPTER_CMD:-bash $PLUGIN/task-backend/adapter.sh}"
FLOW_CMD="${FLOW_CMD:-bash $PLUGIN/skills/flow/references/flow.sh}"
EXECUTE_CMD="${EXECUTE_CMD:-bash $PLUGIN/skills/execute-task/references/execute-task.sh}"

die() { echo "workflow-task: $*" >&2; exit 1; }

wt_start() {
  local maxp=""
  while [[ $# -gt 0 ]]; do case "$1" in --max-parallel) maxp="$2"; shift 2;; *) shift;; esac; done

  local ready ids; ready="$($ADAPTER_CMD list_ready)"
  mapfile -t ids < <(printf '%s' "$ready" | jq -r '.[].task_id')
  if [[ ${#ids[@]} -eq 0 ]]; then echo '{"drained":0,"ready":0,"note":"no ready tasks"}'; return 0; fi

  local conc="${maxp:-${#ids[@]}}"
  # 평면 flow 정의 생성: 의존 없는 command_node 들(즉시 병렬). 각 노드 = execute-task start <id>.
  local def; def="$(mktemp "${TMPDIR:-/tmp}/wt-def.XXXXXX.py")"
  {
    echo "from workflow_replica.nodes import command_node"
    echo "CONCURRENCY = $conc"
    echo "NODES = ["
    local id argv_json
    for id in "${ids[@]}"; do
      # EXECUTE_CMD(공백 분리) + start <id> 를 argv 리스트로
      argv_json="$(printf '%s\n' $EXECUTE_CMD start "$id" | jq -R . | jq -sc .)"
      printf '  command_node(%s, %s, cwd=%s),\n' "$(printf '%s' "$id" | jq -R .)" "$argv_json" "$(printf '%s' "$ROOT_DIR" | jq -R .)"
    done
    echo "]"
  } > "$def"

  local out; out="$($FLOW_CMD run "$def" 2>&1)" || true
  rm -f "$def"
  # flow 결과 요약
  local ok succ failed
  ok="$(printf '%s' "$out" | jq -r '.ok // false' 2>/dev/null || echo false)"
  succ="$(printf '%s' "$out" | jq -r '(.succeeded // []) | length' 2>/dev/null || echo 0)"
  failed="$(printf '%s' "$out" | jq -r '(.failed // []) | length' 2>/dev/null || echo 0)"
  jq -nc --argjson r "${#ids[@]}" --argjson s "${succ:-0}" --argjson f "${failed:-0}" --arg ok "$ok" \
    '{ready:$r, succeeded:$s, failed:$f, flow_ok:($ok=="true")}'
  [[ "${failed:-0}" -eq 0 ]] || return 1
}

main() {
  local verb="${1:-}"; shift || true
  case "$verb" in
    start) wt_start "$@";;
    ""|-h|--help|help) echo "usage: workflow-task.sh start [--max-parallel N]" >&2; exit 2;;
    *) die "알 수 없는 동사: $verb";;
  esac
}
main "$@"
