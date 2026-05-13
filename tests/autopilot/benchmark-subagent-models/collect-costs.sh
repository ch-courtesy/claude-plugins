#!/usr/bin/env bash
# raw/<variant>/<task>/<run-N>/usage.json + timing.json 을 한 TSV로 집계.
# admin-aggregate.json (있을 때)와 cross-check.
#
# 사용:
#   bash collect-costs.sh                # 표준 출력에 TSV
#   bash collect-costs.sh > summary.tsv  # 파일로
#
# 의존: jq, awk.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW_DIR="${ROOT}/raw"

printf "variant\ttask\trun\tmodel\tduration_ms\texit_code\ttotal_cost_usd\tinput_tokens\toutput_tokens\tcache_read\tcache_creation\tsession_id\n"

if [[ ! -d "${RAW_DIR}" ]]; then
  echo "ERROR: raw/ not found: ${RAW_DIR}" >&2
  exit 2
fi

# 모든 cell 디렉토리 순회
find "${RAW_DIR}" -mindepth 3 -maxdepth 3 -type d -name 'run-*' | sort | while read -r cell; do
  rel="${cell#${RAW_DIR}/}"
  variant="${rel%%/*}"
  rest="${rel#*/}"
  task="${rest%%/*}"
  run="${rest##*/}"

  usage_json="${cell}/usage.json"
  timing_json="${cell}/timing.json"

  if [[ ! -f "${usage_json}" || ! -f "${timing_json}" ]]; then
    continue
  fi

  model="$(jq -r '.model // ""' "${usage_json}")"
  cost="$(jq -r '.total_cost_usd // 0' "${usage_json}")"
  in_tok="$(jq -r '.input_tokens // 0' "${usage_json}")"
  out_tok="$(jq -r '.output_tokens // 0' "${usage_json}")"
  cache_r="$(jq -r '.cache_read_input_tokens // 0' "${usage_json}")"
  cache_c="$(jq -r '.cache_creation_input_tokens // 0' "${usage_json}")"
  sid="$(jq -r '.session_id // ""' "${usage_json}")"
  dur="$(jq -r '.duration_ms // 0' "${timing_json}")"
  rc="$(jq -r '.exit_code // -1' "${timing_json}")"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "${variant}" "${task}" "${run}" "${model}" "${dur}" "${rc}" "${cost}" "${in_tok}" "${out_tok}" "${cache_r}" "${cache_c}" "${sid}"
done

# admin-aggregate.json cross-check (있을 때만)
admin_file="${RAW_DIR}/admin-aggregate.json"
if [[ -f "${admin_file}" ]]; then
  {
    echo
    echo "# admin-aggregate.json (cross-check 소스 #2) 요약"
    jq -c '{
      window: {start: .window.start, end: .window.end},
      totals: {input_tokens: .totals.input_tokens, output_tokens: .totals.output_tokens, cost_usd: .totals.cost_usd},
      by_model: .by_model
    }' "${admin_file}"
  } >&2
fi
