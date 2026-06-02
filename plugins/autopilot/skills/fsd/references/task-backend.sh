#!/usr/bin/env bash
# task-backend.sh — autopilot:fsd task 백엔드 어댑터 (C1)
#
# fsd 가 task backend(이슈 + 프로젝트 보드)와 상호작용하는 **단일 지점**이다.
# 본 모듈은 다음 규칙의 실행자다(규칙 재정의 금지):
#   - rules/context.md                          이슈=task, 상태 어휘, 본문 구조, 코멘트 접두 규약
#   - rules/orchestration/task-state-alignment.md  4분기 상태 정합
#   - rules/orchestration/issue-sync.md         펜스 단방향 본문 동기화
#
# 수행하는 것:
#   - 상태 정합(4분기): 대응 task 상태에 따라 생성/유지/전이/신규.
#   - task 생성·상태 전이: 정확한 상태 어휘로만.
#   - 이슈 본문 동기화: SPEC 전문을 spec-sync 펜스 안에 단방향 반영(펜스 밖 보존).
#   - intake: 미해결 마커 없으면 task 생성(계획 채움→In Design, 캡처만→Backlog).
#   - 로컬 미러 동기화: 백엔드가 진실의 원천, 불일치 시 백엔드 우선.
#
# 하지 않는 것:
#   - 규칙 재정의, 역방향 동기화(task→SPEC), DONE→PR(C2)·리뷰 루프(C3)·머지(C4)·poll(C5).
#
# 사용: 이 파일을 source 하여 tb_* 함수를 쓰거나, `bash task-backend.sh selftest` 로
#       mock 백엔드 기반 자체 검증을 실행한다(self-referential: runtime artifact 미검사).
#
# 백엔드 추상화:
#   모든 백엔드 호출은 tb_backend() 단일 게이트를 지난다. TASK_BACKEND_CMD 가 설정되면
#   그 명령(또는 함수)으로 위임하고, 없으면 gh 기반 기본 구현(tb_backend_gh)을 쓴다.
#   verb: create <title> | get-status <id> | set-status <id> <status>
#         get-body <id> | set-body <id> <bodyfile> | comment <id> <message>
#
# task-id 는 fsd 의 로컬 상태 디렉토리 키(slug-hash)이고,
# 백엔드 식별자(이슈 번호)는 미러 필드 `issue` 에 보관한다. 미러 필드 `backend-status`
# 는 백엔드 상태 어휘를 그대로 미러링한다. 두 필드는 lib-state.sh 헬퍼로 IO 한다.
#
# bash 3.2+ 호환 (associative array 미사용).

set -uo pipefail

TB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 상태 저장소 헬퍼(C0). 이미 source 되어 있으면 재로드하지 않는다.
if ! declare -f set_field >/dev/null 2>&1; then
  # shellcheck source=lib-state.sh
  . "$TB_SCRIPT_DIR/lib-state.sh"
fi

# ===== 상태 어휘 (단일 출처) =====
# 정확히 7개 값. rules/context.md 와 일치시킨다. 이 외 값은 전이에 쓰지 않는다.
TB_STATUS_BACKLOG="Backlog"
TB_STATUS_DESIGN="In Design"
TB_STATUS_PROGRESS="In Progress"
TB_STATUS_REVIEW="Review"
TB_STATUS_DONE="Done"
TB_STATUS_BLOCKED="Blocked"
TB_STATUS_CANCELLED="Cancelled"
# 검증·grep 단일 출처 목록.
TB_STATUSES="$TB_STATUS_BACKLOG|$TB_STATUS_DESIGN|$TB_STATUS_PROGRESS|$TB_STATUS_REVIEW|$TB_STATUS_DONE|$TB_STATUS_BLOCKED|$TB_STATUS_CANCELLED"

tb_die() { echo "task-backend: $*" >&2; return 1; }

# tb_valid_status <status> — 어휘 7개 중 하나면 0, 아니면 1.
tb_valid_status() {
  local s="$1" v
  local IFS='|'
  for v in $TB_STATUSES; do
    [[ "$s" == "$v" ]] && return 0
  done
  return 1
}

# ===== 백엔드 추상화 게이트 =====
TASK_BACKEND_CMD="${TASK_BACKEND_CMD:-}"

# tb_backend_gh — gh 기반 기본 구현. 상태는 GitHub Project 의 Status field, 본문은
# 이슈 body, 코멘트는 이슈 comment. (self-hosted forge 별 차이는 후속 조정.)
# 주: self-referential 검증은 mock 으로 하며 이 경로를 runtime 호출하지 않는다.
tb_backend_gh() {
  local verb="$1"; shift
  command -v gh >/dev/null 2>&1 || { tb_die "gh CLI 필요"; return 1; }
  case "$verb" in
    create)
      # create <title> [bodyfile] -> 이슈 번호
      local title="$1" bodyfile="${2:-}"
      if [[ -n "$bodyfile" && -f "$bodyfile" ]]; then
        gh issue create --title "$title" --body-file "$bodyfile" 2>/dev/null \
          | sed -nE 's#.*/issues/([0-9]+).*#\1#p' | tail -1
      else
        gh issue create --title "$title" --body "" 2>/dev/null \
          | sed -nE 's#.*/issues/([0-9]+).*#\1#p' | tail -1
      fi
      ;;
    get-status)
      gh issue view "$1" --json projectItems \
        --jq '.projectItems[]?.status.name // empty' 2>/dev/null | head -1
      ;;
    set-status)
      # set-status <id> <status>: GitHub Project 의 Status 필드를 실제로 전이한다.
      #   "백엔드가 진실의 원천" 계약(C1/C5)을 지키려면, 전이가 실제로 성공한
      #   경우에만 0 을 반환해야 한다(호출자는 그때만 미러를 갱신한다).
      #   Project/field/option 식별자는 환경에서 주입한다:
      #     FSD_PROJECT_NUMBER  project *번호* (item-list/field-list 위치 인자용)
      #     FSD_PROJECT_OWNER   project owner (기본 "@me")
      #     FSD_STATUS_FIELD    Status 필드 이름(기본 "Status")
      #   식별자 미설정이면 전이할 수 없으므로 가독용 라벨만 남기고 **실패(비-0)**
      #   를 반환한다 — 라벨-only no-op 을 성공으로 보고하지 않는다.
      local _id="$1" _status="$2" _field="${FSD_STATUS_FIELD:-Status}"
      local _num="${FSD_PROJECT_NUMBER:-}"
      local _owner="${FSD_PROJECT_OWNER:-@me}"
      gh issue edit "$_id" --add-label "status:$_status" >/dev/null 2>&1 || true
      if [[ -z "$_num" ]]; then
        tb_die "Project Status 전이 불가: FSD_PROJECT_NUMBER 미설정 (라벨만 기록, 미러 미갱신)"
        return 1
      fi
      # gh project 식별자 의미(중요): 두 종류의 식별자가 섞이지 않게 한다.
      #   - item-list/field-list/view : project *번호* 를 위치 인자로 받는다.
      #   - item-edit --project-id    : GraphQL project *node id* 를 요구한다(번호 아님).
      #   - item-edit --single-select-option-id : 옵션 *이름*("Backlog")이 아니라 옵션 *id*.
      #   따라서 번호로 (0) project node id, (1) item id, (2) Status field id,
      #   (3) 상태 이름→option id 를 모두 조회한 뒤 node/id 기반으로만 edit 한다.
      #   어느 조회·전이라도 실패하면 비-0 을 반환해 호출자가 미러를 갱신하지 않게 한다.
      local _pid _item _fid _oid
      _pid="$(gh project view "$_num" --owner "$_owner" --format json \
        --jq '.id' 2>/dev/null | head -1)"
      [[ -n "$_pid" ]] || { tb_die "Project node id 조회 실패: number=$_num owner=$_owner"; return 1; }
      _item="$(gh project item-list "$_num" --owner "$_owner" --format json \
        --jq ".items[] | select(.content.number == ($_id|tonumber)) | .id" 2>/dev/null | head -1)"
      [[ -n "$_item" ]] || { tb_die "Project item 미발견: issue=$_id"; return 1; }
      _fid="$(gh project field-list "$_num" --owner "$_owner" --format json \
        --jq ".fields[] | select(.name == \"$_field\") | .id" 2>/dev/null | head -1)"
      [[ -n "$_fid" ]] || { tb_die "Status field id 조회 실패: field=$_field"; return 1; }
      _oid="$(gh project field-list "$_num" --owner "$_owner" --format json \
        --jq ".fields[] | select(.name == \"$_field\") | .options[] | select(.name == \"$_status\") | .id" 2>/dev/null | head -1)"
      [[ -n "$_oid" ]] || { tb_die "Status 옵션 id 조회 실패: $_status (옵션 이름이 보드와 일치하는지 확인)"; return 1; }
      gh project item-edit --project-id "$_pid" --id "$_item" \
        --field-id "$_fid" --single-select-option-id "$_oid" >/dev/null 2>&1 \
        || { tb_die "Project Status 전이 실패: issue=$_id → $_status"; return 1; }
      ;;
    get-body) gh issue view "$1" --json body --jq '.body' 2>/dev/null ;;
    set-body) gh issue edit "$1" --body-file "$2" >/dev/null 2>&1 ;;
    comment)  gh issue comment "$1" --body "$2" >/dev/null 2>&1 ;;
    *) tb_die "알 수 없는 backend verb: $verb"; return 2 ;;
  esac
}

# tb_backend <verb> [args...] — 단일 게이트.
tb_backend() {
  if [[ -n "$TASK_BACKEND_CMD" ]]; then
    $TASK_BACKEND_CMD "$@"
  else
    tb_backend_gh "$@"
  fi
}

# ===== 펜스 본문 동기화 =====
TB_FENCE_BEGIN="<!-- autopilot:spec-sync:begin -->"
TB_FENCE_END="<!-- autopilot:spec-sync:end -->"

# tb_render_fence <spec-path> — fence 블록 전체를 stdout 으로.
tb_render_fence() {
  printf '%s\n' "$TB_FENCE_BEGIN"
  printf '## SPEC (auto-synced)\n\n'
  cat "$1"
  printf '\n%s\n' "$TB_FENCE_END"
}

# tb_apply_fence <bodyfile> <fencefile> — body 에 fence 적용 stdout.
#   begin 마커가 있으면 begin..end 사이만 교체(펜스 밖 보존), 없으면 append.
tb_apply_fence() {
  local bodyfile="$1" fencefile="$2"
  if grep -qF 'autopilot:spec-sync:begin' "$bodyfile"; then
    awk -v fencef="$fencefile" '
      BEGIN { fb=""; while ((getline l < fencef) > 0) fb = fb l "\n"; sub(/\n$/, "", fb) }
      index($0, "autopilot:spec-sync:begin") { print fb; inb=1; next }
      index($0, "autopilot:spec-sync:end")   { if (inb) { inb=0; next } }
      !inb { print }
    ' "$bodyfile"
  else
    cat "$bodyfile"
    printf '\n'
    cat "$fencefile"
  fi
}

# tb_sync_body <task-id> <spec-path> — 현재 body 조회 → SPEC 펜스 반영 → set-body.
#   issue-sync.md: 펜스 안만 교체, 밖은 보존. 단방향(SPEC→task).
tb_sync_body() {
  local id="$1" spec="$2" iid
  iid="$(get_field "$id" issue)"
  [[ -n "$iid" ]] || { tb_die "issue 미연결 task: $id"; return 1; }
  [[ -f "$spec" ]] || { tb_die "SPEC 없음: $spec"; return 1; }
  local td; td="$(task_dir "$id")"; ensure_task_dir "$id"
  local cur="$td/.body-cur" fence="$td/.body-fence" next="$td/.body-next"
  tb_backend get-body "$iid" > "$cur" 2>/dev/null || : > "$cur"
  tb_render_fence "$spec" > "$fence"
  tb_apply_fence "$cur" "$fence" > "$next"
  tb_backend set-body "$iid" "$next"
  rm -f "$cur" "$fence" "$next"
}

# ===== task 생성 본문 (rules/context.md 본문 구조 + spec-sync 펜스) =====
# tb_render_body <spec-path> — 머리말(필수 섹션 + SPEC 경로) + fence 블록.
tb_render_body() {
  local spec="$1" title
  title="$(grep -m1 -E '^#[[:space:]]+' "$spec" | sed -E 's/^#[[:space:]]+//')"
  [[ -n "$title" ]] || title="(제목 미상)"
  cat <<EOF
## 목표
$title — 자세한 내용은 아래 자동 동기화된 SPEC 전문 참조.

## 배경
이 task 는 SPEC 문서를 단일 출처로 하는 fsd 파이프라인에서 생성되었다.

## 제안
아래 SPEC 의 수용 기준·범위·제약을 구현 흐름이 그대로 따른다.

## 검증 계획
SPEC 의 수용 기준(EARS)을 인수 바로 사용하고, 진입 명령은 프로젝트 규칙을 따른다.

## 완료 기준 (Definition of Done)
- [ ] SPEC 의 모든 수용 기준 충족

SPEC: $spec

EOF
  tb_render_fence "$spec"
}

# ===== task 생성 / 상태 전이 =====

# tb_create_task <task-id> <spec-path> <status> — 이슈+보드 항목 생성, 본문·상태 설정,
#   로컬 미러(issue·backend-status) 기록. echo 새 이슈 식별자.
tb_create_task() {
  local id="$1" spec="$2" status="$3"
  tb_valid_status "$status" || { tb_die "잘못된 상태 어휘: $status"; return 1; }
  [[ -f "$spec" ]] || { tb_die "SPEC 없음: $spec"; return 1; }
  ensure_task_dir "$id"
  local title bodyfile iid
  title="$(grep -m1 -E '^#[[:space:]]+' "$spec" | sed -E 's/^#[[:space:]]+//')"
  [[ -n "$title" ]] || title="$(spec_fallback_title "$spec")"
  bodyfile="$(task_dir "$id")/.body-init"
  tb_render_body "$spec" > "$bodyfile"
  iid="$(tb_backend create "$title" "$bodyfile")"
  rm -f "$bodyfile"
  [[ -n "$iid" ]] || { tb_die "백엔드 task 생성 실패"; return 1; }
  set_field "$id" issue "$iid"
  add_spec "$id" "$spec"
  tb_set_status "$id" "$status"
  tb_sync_body "$id" "$spec"
  log_event "$id" "task 생성 issue=$iid status=$status"
  echo "$iid"
}

# spec_fallback_title <spec> — 제목 없을 때 slug fallback (lib-state 의 spec_slug 부재 대비).
spec_fallback_title() {
  local b; b="$(basename "$1")"
  [[ "$b" == "SPEC.md" ]] && b="$(basename "$(dirname "$1")")"
  echo "${b%.md}"
}

# tb_set_status <task-id> <status> — 어휘 검증 후 백엔드 전이 + 미러 기록.
#   "백엔드가 진실의 원천": 백엔드 전이가 실제로 성공한 경우에만 미러를 갱신한다.
#   전이가 실패하면 미러를 갱신하지 않고 오류를 전파해, fsd 가 실제로는
#   전이되지 않은 상태를 전이됐다고 오판하지 않게 한다(poll 정합 깨짐 방지).
tb_set_status() {
  local id="$1" status="$2" iid
  tb_valid_status "$status" || { tb_die "잘못된 상태 어휘: $status"; return 1; }
  iid="$(get_field "$id" issue)"
  [[ -n "$iid" ]] || { tb_die "issue 미연결 task: $id"; return 1; }
  if ! tb_backend set-status "$iid" "$status"; then
    tb_die "백엔드 상태 전이 실패 — 미러 미갱신: $id → $status"
    return 1
  fi
  set_field "$id" backend-status "$status"
  log_event "$id" "상태 전이 → $status"
}

# ===== 4분기 상태 정합 =====
# tb_align <task-id> <spec-path> — 대응 task 상태에 따라 분기. echo 사용할 이슈 식별자.
#   (a) issue 미연결      → 새 task 생성, In Design
#   (b) In Design         → 변경 없이 진행
#   (c) Backlog           → In Design 전이
#   (d) In Progress/Review/Done → 새 task 생성(새 식별자 사용), In Design
#   그 외(Blocked/Cancelled): 안전하게 새 task 생성.
tb_align() {
  local id="$1" spec="$2" iid status
  iid="$(get_field "$id" issue)"
  if [[ -z "$iid" ]]; then
    tb_create_task "$id" "$spec" "$TB_STATUS_DESIGN"   # (a)
    return
  fi
  # 백엔드를 진실의 원천으로 미러 정합 후 현재 상태 판정.
  status="$(tb_reconcile "$id")"
  case "$status" in
    "$TB_STATUS_DESIGN")
      echo "$iid" ;;                                    # (b)
    "$TB_STATUS_BACKLOG")
      tb_set_status "$id" "$TB_STATUS_DESIGN"           # (c)
      echo "$iid" ;;
    "$TB_STATUS_PROGRESS"|"$TB_STATUS_REVIEW"|"$TB_STATUS_DONE")
      log_event "$id" "정합 (d): $status → 새 task 생성"
      tb_create_task "$id" "$spec" "$TB_STATUS_DESIGN" ;; # (d) 새 식별자
    *)
      log_event "$id" "정합 기타 상태($status) → 새 task 생성"
      tb_create_task "$id" "$spec" "$TB_STATUS_DESIGN" ;;
  esac
}

# ===== intake =====
# tb_spec_has_marker <spec> — 미해결 명확화 마커가 있으면 0.
tb_spec_has_marker() {
  grep -qF '[NEEDS CLARIFICATION' "$1"
}

# tb_spec_has_plan <spec> — 계획(수용 기준/완료 조건)이 채워졌으면 0.
tb_spec_has_plan() {
  grep -qE '수용 기준|완료 조건|Acceptance Criteria' "$1" \
    && grep -qE '^[[:space:]]*[0-9]+\.|^[[:space:]]*-[[:space:]]' "$1"
}

# tb_intake <task-id> <spec-path> — 마커 있으면 task 미생성(1). 없으면 계획 채움 여부로
#   In Design / Backlog 결정해 task 생성. echo 이슈 식별자.
tb_intake() {
  local id="$1" spec="$2"
  [[ -f "$spec" ]] || { tb_die "SPEC 없음: $spec"; return 1; }
  if tb_spec_has_marker "$spec"; then
    log_event "$id" "intake 차단: 미해결 NEEDS CLARIFICATION 마커"
    return 1
  fi
  local status="$TB_STATUS_BACKLOG"
  tb_spec_has_plan "$spec" && status="$TB_STATUS_DESIGN"
  tb_create_task "$id" "$spec" "$status"
}

# ===== 로컬 미러 동기화 (백엔드 우선) =====
# tb_reconcile <task-id> — 백엔드 상태를 진실의 원천으로 미러에 반영. echo 최종 상태.
tb_reconcile() {
  local id="$1" iid be mirror
  iid="$(get_field "$id" issue)"
  [[ -n "$iid" ]] || { get_field "$id" backend-status ""; return 0; }
  be="$(tb_backend get-status "$iid" 2>/dev/null || true)"
  mirror="$(get_field "$id" backend-status "")"
  if [[ -n "$be" && "$be" != "$mirror" ]]; then
    set_field "$id" backend-status "$be"
    log_event "$id" "미러 정합: 백엔드 우선 $mirror → $be"
  fi
  get_field "$id" backend-status ""
}

# ===== 코멘트 (접두 규약: [handoff]·[decision]·[blocked]) =====
# tb_comment <task-id> <prefix> <message> — prefix 검증 후 백엔드 코멘트.
tb_comment() {
  local id="$1" prefix="$2" msg="$3" iid
  case "$prefix" in
    handoff|decision|blocked|verification) ;;
    *) tb_die "알 수 없는 코멘트 접두: $prefix"; return 1 ;;
  esac
  iid="$(get_field "$id" issue)"
  [[ -n "$iid" ]] || { tb_die "issue 미연결 task: $id"; return 1; }
  tb_backend comment "$iid" "[$prefix] $msg"
}

# ===== 자체 검증 (mock 백엔드) =====
# self-referential 위험에 따라 runtime artifact(.fsd/·실제 이슈)를 검사하지 않고
# mock 인터페이스로 동작만 검증한다.
tb_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  export FSD_STATE_ROOT="$TMP/.fsd"
  local BK="$TMP/backend"; mkdir -p "$BK"; echo 0 > "$BK/.counter"
  mock_backend() {
    local verb="$1"; shift
    case "$verb" in
      create) local n; n=$(( $(cat "$BK/.counter") + 1 )); echo "$n" > "$BK/.counter"
              : > "$BK/$n.status"; : > "$BK/$n.body"
              [[ -n "${2:-}" && -f "${2:-}" ]] && cp "$2" "$BK/$n.body"
              echo "$n" ;;
      get-status) cat "$BK/$1.status" 2>/dev/null || true ;;
      set-status) printf '%s' "$2" > "$BK/$1.status" ;;
      get-body)   cat "$BK/$1.body" 2>/dev/null || true ;;
      set-body)   cp "$2" "$BK/$1.body" ;;
      comment)    printf '%s\n' "$2" >> "$BK/$1.comments" ;;
      *) return 2 ;;
    esac
  }
  export TASK_BACKEND_CMD=mock_backend
  local fail=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }

  local SP="$TMP/spec-ok.md" SPM="$TMP/spec-marker.md" SPC="$TMP/spec-capture.md"
  printf '# 제목있는 SPEC\n## 수용 기준 (EARS)\n1. 항상 X 한다.\n' > "$SP"
  printf '# 마커 SPEC\n[NEEDS CLARIFICATION: 무엇?]\n' > "$SPM"
  printf '# 캡처만 SPEC\n한 줄 아이디어.\n' > "$SPC"

  # AC5 vocabulary
  tb_valid_status "In Design" && ok "AC5 valid In Design" || bad "AC5 valid In Design"
  if tb_valid_status "WrongState"; then bad "AC5 reject WrongState"; else ok "AC5 reject WrongState"; fi
  set_field t1 issue 1; mock_backend set-status 1 ""
  if tb_set_status t1 "Nope" 2>/dev/null; then bad "AC5 set rejects bad"; else ok "AC5 set rejects bad"; fi

  # AC2 align: no task -> create + In Design
  local id; id="$(tb_align t2 "$SP")"
  [[ -n "$id" ]] && ok "AC2 align creates id" || bad "AC2 align creates id"
  chk "AC2 status In Design" "$(get_field t2 backend-status)" "In Design"

  # AC3 align: Backlog -> In Design
  set_field t3 issue 30; mock_backend set-status 30 "Backlog"; set_field t3 backend-status "Backlog"
  tb_align t3 "$SP" >/dev/null
  chk "AC3 Backlog->In Design (mirror)" "$(get_field t3 backend-status)" "In Design"

  # AC4 align: In Progress -> new task id, mirror updated
  set_field t4 issue 40; mock_backend set-status 40 "In Progress"; set_field t4 backend-status "In Progress"
  local newid; newid="$(tb_align t4 "$SP")"
  [[ -n "$newid" && "$newid" != "40" ]] && ok "AC4 new identifier" || bad "AC4 new identifier (got '$newid')"
  chk "AC4 mirror updated" "$(get_field t4 issue)" "$newid"
  chk "AC4 new status In Design" "$(get_field t4 backend-status)" "In Design"

  # AC6 fence sync preserves outside
  local iid; iid="$(get_field t2 issue)"
  printf 'USER-TOP\n%s\nOLD\n%s\nUSER-BOT\n' "$TB_FENCE_BEGIN" "$TB_FENCE_END" > "$BK/$iid.body"
  tb_sync_body t2 "$SP"
  local body; body="$(mock_backend get-body "$iid")"
  case "$body" in *USER-TOP*) ok "AC6 preserve top";; *) bad "AC6 preserve top";; esac
  case "$body" in *USER-BOT*) ok "AC6 preserve bottom";; *) bad "AC6 preserve bottom";; esac
  case "$body" in *OLD*) bad "AC6 replaced old";; *) ok "AC6 replaced old";; esac
  case "$body" in *"항상 X 한다"*) ok "AC6 spec content in";; *) bad "AC6 spec content in";; esac

  # AC7 intake with marker -> no task
  if tb_intake t7 "$SPM" >/dev/null 2>&1; then bad "AC7 marker blocks"; else ok "AC7 marker blocks"; fi
  if [[ -n "$(get_field t7 issue '')" ]]; then bad "AC7 no issue created"; else ok "AC7 no issue created"; fi

  # AC8 intake marker-free (plan) -> task + mirror, In Design
  local i8; i8="$(tb_intake t8 "$SP")"
  [[ -n "$i8" ]] && ok "AC8 intake creates" || bad "AC8 intake creates"
  chk "AC8 plan->In Design mirror" "$(get_field t8 backend-status)" "In Design"
  # AC8 capture-only -> Backlog
  local i8b; i8b="$(tb_intake t8b "$SPC")"
  chk "AC8 capture->Backlog mirror" "$(get_field t8b backend-status)" "Backlog"

  # AC9 reconcile: backend wins
  set_field t9 issue 90; set_field t9 backend-status "Backlog"; mock_backend set-status 90 "Review"
  tb_reconcile t9 >/dev/null
  chk "AC9 backend wins" "$(get_field t9 backend-status)" "Review"

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ===== CLI 진입 (source 시 미실행) =====
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    selftest) tb_selftest ;;
    *) echo "task-backend.sh: source 하여 tb_* 함수 사용. 자체 검증: bash task-backend.sh selftest" >&2 ;;
  esac
fi
