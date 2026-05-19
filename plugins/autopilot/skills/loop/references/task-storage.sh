# source-only — do not execute directly
# task-storage.sh — task 저장소(GitHub Issue) 라벨 검출 공통 헬퍼.
#
# loop.sh·dispatch.sh 가 함께 source 하는 헬퍼. 완료 검출의 단일 출처는
# task 식별자에 부속된 LOOP_DONE_LABEL 라벨이다(헌법 §12, SPEC 134/150/175).
# 본 파일은 source 전용이며 단독 실행하지 않는다.
#
# 매체: GitHub Issue + label. 환경: gh CLI 인증을 전제.
#
# Provides:
#   LOOP_DONE_LABEL                       — 완료 검출 키 (기본 'loop:done')
#   task_issue_number  <task-id>          — task-id → issue number 매핑
#   task_label_present <task-id> <label>  — label 부착 여부 (0=있음)
#   task_status_is_done <task-id>         — LOOP_DONE_LABEL 부착 여부
#   ensure_label_exists <label>           — 미존재 시 자동 생성 (best-effort)
#
# task-id 기본값은 환경 변수 $TASK_ID — loop.sh 의 이터 컨텍스트에서 자연 set.
# dispatch.sh 등 다른 호출자는 task-id 를 명시적으로 넘긴다.

# 완료 신호의 검출 키. 환경 변수 override 허용 — 단, 프로젝트 수준에서 단일 위치에
# 고정되어 task storage adapter 다중 분기를 만들지 않는다 (SPEC 134 §비-목표).
LOOP_DONE_LABEL="${LOOP_DONE_LABEL:-loop:done}"

# 내부 전용 — ensure_label_exists 의 stderr WARN 라인 타임스탬프.
# loop.sh 의 now_iso 와 식별 분리하여 source 순서·재정의 충돌 방지.
_task_storage_now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# task ↔ GitHub issue 매핑 (헌법 §11, rules/context.md).
# task-id 의 마지막 컴포넌트(예: 'regular/124' → '124')가 숫자면 issue number 로 직접 사용.
# 그 외 문자열이면 `gh issue list --search` 로 첫 매칭 lookup. 실패 시 빈 출력 + return 1.
# 호출자(halt·iterate·cmd_status·dispatch child_state)는 매핑 실패 시 graceful degrade 한다.
task_issue_number() {
  local task_id="${1:-${TASK_ID:-}}"
  local child="${task_id##*/}"
  if [[ "$child" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$child"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  local n
  n=$(gh issue list --search "$task_id" --json number --jq '.[0].number' 2>/dev/null || true)
  if [[ -n "$n" && "$n" != "null" ]]; then
    printf '%s\n' "$n"
    return 0
  fi
  return 1
}

# task issue 에 특정 label 이 붙어 있는지 boolean 검사 (SPEC 134 AC3).
# 인자: $1=task-id (생략 시 $TASK_ID), $2=label 이름 (필수).
# 반환: 0=label 존재, 1=label 부재 또는 판정 불가 (issue 매핑 실패·gh 부재 포함).
# 구현은 단일 GitHub 호출(`gh issue view --json labels`)로 한정 — adapter 인터페이스
# 신설 없음 (SPEC 134 §비-목표).
task_label_present() {
  local task_id="${1:-${TASK_ID:-}}"
  local label="${2:-}"
  [[ -z "$label" ]] && return 1
  local issue
  issue=$(task_issue_number "$task_id" 2>/dev/null) || return 1
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  # gh CLI 의 `--jq` 는 단일 expression 인자만 받아 jq 의 `--arg` 를 통과시키지 않으므로
  # name 목록만 추출해 셸에서 정확 일치 비교 (grep -F -x).
  local names
  names=$(gh issue view "$issue" --json labels \
    --jq '.labels[].name' 2>/dev/null || true)
  [[ -z "$names" ]] && return 1
  printf '%s\n' "$names" | grep -qxF "$label" && return 0
  return 1
}

# task storage 에 label 이 존재하는지 확인하고, 없으면 자동 생성 (SPEC 134 AC5).
# 인자: $1=label 이름 (필수).
# 권한 부족·gh 부재 시 best-effort 로 stderr WARN + 비-0 반환 (비차단 진행).
# SPEC 134 §위험 "label 자동 생성 권한 부족" — runtime 실패는 verify 범위 밖.
ensure_label_exists() {
  local label="${1:-}"
  [[ -z "$label" ]] && return 1
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  # 존재 여부 확인 — `gh label list --search` 는 prefix·substring 을 함께 반환할 수
  # 있으므로 name 목록만 추출 후 셸에서 정확 일치 비교 (gh `--jq` 는 jq `--arg` 를
  # 통과시키지 않아 셸 비교가 안전).
  local names
  names=$(gh label list --search "$label" --json name \
    --jq '.[].name' 2>/dev/null || true)
  if [[ -n "$names" ]] && printf '%s\n' "$names" | grep -qxF "$label"; then
    return 0
  fi
  # 미존재 — 생성 시도. race 또는 권한 부족 시 WARN.
  if ! gh label create "$label" \
        --description "autopilot loop 완료 신호 (드라이버 검출 키)" \
        >/dev/null 2>&1; then
    echo "[$(_task_storage_now_iso)] WARN: label '$label' 자동 생성 실패 — 권한 부족·race·gh 응답 비정상. 수동 생성 필요." >&2
    return 1
  fi
  echo "[$(_task_storage_now_iso)] label '$label' 자동 생성 완료." >&2
  return 0
}

# task issue 의 완료 신호 검사 (헌법 §12, SPEC 134 AC2, SPEC 175 AC1).
# 정식 검출 키: task issue 에 LOOP_DONE_LABEL 값과 일치하는 label 이 붙어 있는지.
# comment 본문은 가독·로그 채널이며 판정에 사용되지 않는다 — 워커가 [done] prefix
# comment 발행과 함께 label 추가 두 동작을 모두 수행해야 0(done) 을 반환한다.
# 반환: 0=done, 1=done 아님(판정 불가 포함).
task_status_is_done() {
  local task_id="${1:-${TASK_ID:-}}"
  task_label_present "$task_id" "$LOOP_DONE_LABEL"
}
