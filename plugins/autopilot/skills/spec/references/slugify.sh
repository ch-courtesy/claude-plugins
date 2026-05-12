#!/usr/bin/env bash
# slugify.sh — SPEC §1 제목과 task-id에서 결정적으로 feat 브랜치 이름을 도출.
#
# 사용:
#   bash slugify.sh <task-id> <title>
#
# 출력:
#   feat/<task-id>-<slug>          (slug 유효한 경우)
#   feat/<task-id>                  (slug 결과가 비어 fallback)
#
# 슬러그 규칙 (결정적, deterministic):
#   1) [^A-Za-z0-9-]를 모두 '-'로 치환
#   2) 연속된 '-'를 단일 '-'로 압축
#   3) 양끝 '-' 제거
#   4) 소문자화
#   5) 빈 결과면 fallback (slug 없이 task-id 단독)
#
# 호출자: plugins/autopilot/skills/spec/SKILL.md 단계 9 (SPEC 최종 승인 직후).

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "ERROR: 사용: $0 <task-id> [<title>]" >&2
  exit 1
fi

task_id="$1"
title="${2:-}"

# 슬러그화. macOS BSD·Linux GNU 양쪽 동작하는 POSIX tr/sed만 사용.
# tr -c '[set]' '-': [set] 밖 모든 바이트를 '-'로 치환 (개행 포함 — 안전)
# tr -s '-':         연속된 '-'를 하나로 squeeze
# sed strip:         양끝 '-' 제거
# tr lowercase:      ASCII 영문 대→소 변환
slug=$(printf '%s' "$title" \
  | tr -c 'A-Za-z0-9-' '-' \
  | tr -s '-' \
  | sed 's/^-//; s/-$//' \
  | tr 'A-Z' 'a-z')

if [[ -z "$slug" ]]; then
  printf 'feat/%s\n' "$task_id"
else
  printf 'feat/%s-%s\n' "$task_id" "$slug"
fi
