#!/usr/bin/env bash
# Subagent 모델 벤치마크 러너
#
# 4 task × 3 variant × N회 dispatch를 실행해 raw/<variant>/<task>/<run-N>/에 결과 저장.
# 세션 jsonl에서 usage·timing을 추출, admin-aggregate.json은 별 단계(collect-costs.sh)에서 통합.
#
# 사용:
#   bash runner.sh                          # 기본: 모든 variant × 모든 task × N=5
#   N=10 bash runner.sh                     # 회수만 변경
#   VARIANT=A-fast bash runner.sh           # 단일 variant만
#   TASK=01-spec-compliance bash runner.sh  # 단일 task만
#
# 의존: claude CLI (PATH), jq.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_DIR="${ROOT}/tasks"
VARIANTS_DIR="${ROOT}/variants"
RAW_DIR="${ROOT}/raw"

N="${N:-5}"
VARIANT_FILTER="${VARIANT:-}"
TASK_FILTER="${TASK:-}"

mkdir -p "${RAW_DIR}"

# variant 파일 목록
mapfile -t VARIANTS < <(find "${VARIANTS_DIR}" -maxdepth 1 -type f -name '*.json' | sort)
# task 파일 목록
mapfile -t TASKS < <(find "${TASKS_DIR}" -maxdepth 1 -type f -name '*.task.md' | sort)

if [[ ${#VARIANTS[@]} -eq 0 ]]; then
  echo "ERROR: no variant configs in ${VARIANTS_DIR}" >&2
  exit 2
fi
if [[ ${#TASKS[@]} -eq 0 ]]; then
  echo "ERROR: no task definitions in ${TASKS_DIR}" >&2
  exit 2
fi

# 한 셀 실행: variant × task × run
run_cell() {
  local variant_file="$1"
  local task_file="$2"
  local run_idx="$3"

  local variant_name
  variant_name="$(basename "${variant_file}" .json)"
  local task_name
  task_name="$(basename "${task_file}" .task.md)"

  # variant config에서 역할별 모델 추출 (jq) — 본 셀의 role은 task 파일 frontmatter에서 결정
  local role
  role="$(awk '/^role:/ {print $2; exit}' "${task_file}")"
  if [[ -z "${role}" ]]; then
    echo "WARN: task ${task_name} has no 'role:' frontmatter, skip" >&2
    return 0
  fi

  local model
  model="$(jq -r --arg r "${role}" '.roles[$r] // empty' "${variant_file}")"
  if [[ -z "${model}" ]]; then
    echo "WARN: variant ${variant_name} has no model for role ${role}, skip" >&2
    return 0
  fi

  local cell_dir="${RAW_DIR}/${variant_name}/${task_name}/run-${run_idx}"
  mkdir -p "${cell_dir}"

  # task 본문 (frontmatter 제외) 추출
  local prompt_body
  prompt_body="$(awk '/^---$/{c++; next} c>=2' "${task_file}")"

  # input
  printf "%s" "${prompt_body}" > "${cell_dir}/input.txt"

  # 실행 (CC --print --output-format json --model <model>)
  local started_at
  started_at="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
  local t0
  t0="$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')"

  local session_id
  session_id="$(uuidgen | tr 'A-Z' 'a-z')"

  set +e
  claude --print \
    --output-format json \
    --model "${model}" \
    --session-id "${session_id}" \
    -- "${prompt_body}" \
    > "${cell_dir}/session.jsonl"
  local rc=$?
  set -e

  local ended_at
  ended_at="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
  local t1
  t1="$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')"
  local duration_ms=$((t1 - t0))

  # output·timing·usage 추출
  jq -r '.result // empty' "${cell_dir}/session.jsonl" > "${cell_dir}/output.txt" || true

  jq -c --arg started "${started_at}" --arg ended "${ended_at}" --argjson dur "${duration_ms}" --argjson rc "${rc}" \
    '{started_at: $started, ended_at: $ended, duration_ms: $dur, exit_code: $rc}' \
    < /dev/null > "${cell_dir}/timing.json"

  jq -c --arg model "${model}" '
    {
      model: $model,
      total_cost_usd: (.total_cost_usd // 0),
      input_tokens: (.usage.input_tokens // 0),
      output_tokens: (.usage.output_tokens // 0),
      cache_read_input_tokens: (.usage.cache_read_input_tokens // 0),
      cache_creation_input_tokens: (.usage.cache_creation_input_tokens // 0),
      session_id: (.session_id // "")
    }
  ' "${cell_dir}/session.jsonl" > "${cell_dir}/usage.json"

  echo "[${variant_name}][${task_name}][run-${run_idx}] model=${model} duration=${duration_ms}ms rc=${rc}"
}

# 메인 루프
for variant_file in "${VARIANTS[@]}"; do
  variant_name="$(basename "${variant_file}" .json)"
  if [[ -n "${VARIANT_FILTER}" && "${variant_name}" != "${VARIANT_FILTER}" ]]; then
    continue
  fi
  for task_file in "${TASKS[@]}"; do
    task_name="$(basename "${task_file}" .task.md)"
    if [[ -n "${TASK_FILTER}" && "${task_name}" != "${TASK_FILTER}" ]]; then
      continue
    fi
    for ((i=1; i<=N; i++)); do
      run_cell "${variant_file}" "${task_file}" "${i}"
    done
  done
done

echo
echo "Done. Results: ${RAW_DIR}"
echo "Next: bash $(dirname "${BASH_SOURCE[0]}")/collect-costs.sh"
