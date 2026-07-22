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

ADAPTER_CMD="${ADAPTER_CMD:-bash $PLUGIN/lib/task-backend/adapter.sh}"
FLOW_CMD="${FLOW_CMD:-bash $PLUGIN/skills/flow/references/flow.sh}"
EXECUTE_CMD="${EXECUTE_CMD:-bash $PLUGIN/skills/execute-task/references/execute-task.sh}"

die() { echo "workflow-task: $*" >&2; exit 1; }

# wt_scope_covers <pattern> <path> — scope 표기 <pattern> 이 <path> 를 덮으면 0.
#   정확 일치 / 후행 '/' 디렉터리 prefix / 글롭('*' 포함, bash 확장 패턴 매칭).
wt_scope_covers() {
  local pat="$1" path="$2"
  [[ "$pat" == "$path" ]] && return 0
  case "$pat" in
    */) [[ "$path" == "$pat"* ]] && return 0 ;;
    *'*'*)
      # shellcheck disable=SC2053
      [[ "$path" == $pat ]] && return 0
      # 'dir/**' 는 dir/ 하위 전체를 덮는다(글롭 매칭이 '/' 를 넘지 못하는 경우 보완).
      local base="${pat%%\**}"
      [[ -n "$base" && "$path" == "$base"* ]] && return 0
      ;;
  esac
  return 1
}

# wt_paths_overlap <a> <b> — 두 scope 표기가 산출물에서 겹치면 0(양방향 판정).
wt_paths_overlap() {
  wt_scope_covers "$1" "$2" && return 0
  wt_scope_covers "$2" "$1" && return 0
  return 1
}

wt_start() {
  local maxp=""
  while [[ $# -gt 0 ]]; do case "$1" in --max-parallel) maxp="$2"; shift 2;; *) shift;; esac; done

  local ready ids; ready="$($ADAPTER_CMD list_ready)"
  mapfile -t ids < <(printf '%s' "$ready" | jq -r '.[].task_id')
  if [[ ${#ids[@]} -eq 0 ]]; then echo '{"drained":0,"ready":0,"note":"no ready tasks"}'; return 0; fi

  # 산출물(버전 표면) 겹침 직렬화(#628): 태스크 본문 frontmatter scope.include 항목이 이미
  # 앞선 태스크에 선점됐으면 이번 패스에서 실행하지 않는다(공유 CHANGELOG·매니페스트를 동시에
  # 만지면 첫 머지가 형제 브랜치를 연쇄 충돌시킨다). 유예분은 deferred_ids 로 보고(조용한 누락
  # 금지)하고 다음 틱 list_ready 가 다시 집는다. 특정 경로 하드코딩 없음 — 일반 경로 겹침.
  local run_ids=() deferred=() claimed=$'\n'
  local id body entries e c overlap
  for id in "${ids[@]}"; do
    body="$($ADAPTER_CMD get_body --task-id "$id" 2>/dev/null | jq -r '.body // empty' 2>/dev/null || true)"
    entries="$(printf '%s\n' "$body" | awk '
      NR==1 && /^---[[:space:]]*$/ { fm=1; next }
      fm && /^---[[:space:]]*$/ { exit }
      fm && /^[[:space:]]*include:[[:space:]]*$/ { inc=1; next }
      fm && inc && /^[[:space:]]*-[[:space:]]/ { s=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", s); print s; next }
      fm && inc { inc=0 }
    ')"
    overlap=0
    if [[ -n "$entries" ]]; then
      while IFS= read -r e; do
        [[ -n "$e" ]] || continue
        while IFS= read -r c; do
          [[ -n "$c" ]] || continue
          if wt_paths_overlap "$c" "$e"; then overlap=1; break 2; fi
        done <<< "$claimed"
      done <<< "$entries"
    fi
    if [[ "$overlap" == "1" ]]; then deferred+=("$id"); continue; fi
    if [[ -n "$entries" ]]; then
      while IFS= read -r e; do [[ -n "$e" ]] && claimed+="$e"$'\n'; done <<< "$entries"
    fi
    run_ids+=("$id")
  done
  local deferred_ids='[]'
  if [[ ${#deferred[@]} -gt 0 ]]; then
    deferred_ids="$(printf '%s\n' "${deferred[@]}" | jq -R . | jq -sc .)"
  fi

  local conc="${maxp:-${#run_ids[@]}}"
  # 평면 flow 정의 생성: 의존 없는 command_node 들(즉시 병렬). 각 노드 = execute-task start <id>.
  local def; def="$(mktemp "${TMPDIR:-/tmp}/wt-def.XXXXXX.py")"
  {
    echo "from workflow_replica.nodes import command_node"
    echo "CONCURRENCY = $conc"
    echo "NODES = ["
    local argv_json
    for id in "${run_ids[@]}"; do
      # EXECUTE_CMD(공백 분리) + start <id> 를 argv 리스트로
      argv_json="$(printf '%s\n' $EXECUTE_CMD start "$id" | jq -R . | jq -sc .)"
      printf '  command_node(%s, %s, cwd=%s),\n' "$(printf '%s' "$id" | jq -R .)" "$argv_json" "$(printf '%s' "$ROOT_DIR" | jq -R .)"
    done
    echo "]"
  } > "$def"

  local out; out="$($FLOW_CMD run "$def" 2>&1)" || true
  rm -f "$def"
  # flow 결과 요약
  local ok succ failed failed_ids
  ok="$(printf '%s' "$out" | jq -r '.ok // false' 2>/dev/null || echo false)"
  succ="$(printf '%s' "$out" | jq -r '(.succeeded // []) | length' 2>/dev/null || echo 0)"
  failed="$(printf '%s' "$out" | jq -r '(.failed // []) | length' 2>/dev/null || echo 0)"
  # 실패 노드명(flow 노드 id = execute-task 가 blocked 로 둔 task_id). 드레인자(SKILL)가 이
  # 핸들로 버그 신호를 감지해 중앙에서 fix 를 호출한다(SKILL.md 「버그 신호 수거」).
  failed_ids="$(printf '%s' "$out" | jq -c '.failed // []' 2>/dev/null || echo '[]')"
  [[ -n "$failed_ids" ]] || failed_ids='[]'
  jq -nc --argjson r "${#ids[@]}" --argjson s "${succ:-0}" --argjson f "${failed:-0}" \
    --argjson fids "$failed_ids" --argjson d "${#deferred[@]}" --argjson dids "$deferred_ids" \
    --arg ok "$ok" \
    '{ready:$r, succeeded:$s, failed:$f, failed_ids:$fids, deferred:$d, deferred_ids:$dids, flow_ok:($ok=="true")}'
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
