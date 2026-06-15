#!/usr/bin/env bash
# beads.sh — task-backend beads 백엔드 (bd CLI, 의존 그래프 네이티브)
# adapter.sh 가 source 해 be_<verb> 를 호출한다. 계약: contract.md.
#
# 가정한 bd CLI 동사 (구현 시 `bd --help` 로 실검증 필요):
#   bd create "<title>" -t task                 → 생성, stdout 또는 `bd list` 로 id(bd-xxxx) 회수
#   bd show <id> --json                         → {id,title,status,description,...}
#   bd update <id> --status <state>             → 상태 변경
#   bd update <id> --description <text>         → 본문(= SPEC) 갱신
#   bd dep add <id> --depends-on <dep>          → depends_on 추가
#   bd dep list <id> --json                     → 의존 목록
#   bd ready --json                             → 차단 없는(모든 dep done) 이슈 목록
#   bd note add <id> "[marker] text"            → 진행 로그
# bd 미설치 시 hard-abort (조용한 폴백 없음 — dispatch 의 python3 정책과 동일).
#
# NOTE: 이 저장소 환경엔 bd 가 미설치라 런타임 검증 불가. 동사 형태가 실제 bd 와
#       다르면 이 파일만 수정한다(어댑터 계약/타 백엔드 불변).

be_require() { command -v bd >/dev/null 2>&1 || tb_die "beads 백엔드는 bd CLI 가 필요합니다 (미설치). 'bd init' 후 재시도하세요."; }

bd_lease_field() { printf 'autopilot-lease'; }  # bd custom field 또는 note 로 lease 저장

be_create_task() {
  local title body deps; title="$(_argval --title "$@")"; body="$(_argval --body "$@")"; deps="$(_argval --depends-on "$@")"
  [[ -n "$title" ]] || tb_die "create_task: --title 필요"
  local id; id="$(bd create "$title" -t task --description "$body" --json 2>/dev/null | jq -r '.id // empty')" \
    || tb_die "bd create 실패"
  [[ -n "$id" ]] || tb_die "bd create: id 회수 실패"
  if [[ -n "$deps" ]]; then local d; IFS=',' read -ra d <<<"$deps"; for x in "${d[@]}"; do bd dep add "$id" --depends-on "$x" >/dev/null 2>&1 || true; done; fi
  jq -nc --arg id "$id" '{task_id:$id, status:"backlog", url:null}'
}

be_get_task() {
  local id; id="$(_argval --task-id "$@")"
  local j; j="$(bd show "$id" --json 2>/dev/null)" || tb_die "bd show 실패: $id"
  local djson; djson="$(bd dep list "$id" --json 2>/dev/null | jq -c '[.[].id]' 2>/dev/null || echo '[]')"
  printf '%s' "$j" | jq -c --argjson d "$djson" '{task_id:.id, title:.title, status:.status, depends_on:$d, url:(.url//null)}'
}

be_get_body() {
  local id; id="$(_argval --task-id "$@")"
  bd show "$id" --json 2>/dev/null | jq -c '{task_id:.id, title:.title, body:(.description//"")}' || tb_die "bd show 실패: $id"
}

be_set_status() {
  local id s; id="$(_argval --task-id "$@")"; s="$(_argval --status "$@")"
  bd update "$id" --status "$s" >/dev/null 2>&1 || tb_die "bd update --status 실패"
  [[ "$s" == "in_progress" ]] && bd note add "$id" "[lease] $(tb_now_epoch)" >/dev/null 2>&1 || true
  jq -nc --arg id "$id" --arg s "$s" '{task_id:$id, status:$s}'
}

be_link_dependency() {
  local id dep; id="$(_argval --task-id "$@")"; dep="$(_argval --depends-on-id "$@")"
  bd dep add "$id" --depends-on "$dep" >/dev/null 2>&1 || tb_die "bd dep add 실패"
  local djson; djson="$(bd dep list "$id" --json 2>/dev/null | jq -c '[.[].id]' || echo '[]')"
  jq -nc --arg id "$id" --argjson d "$djson" '{task_id:$id, depends_on:$d}'
}

be_list_ready() {
  # bd ready 가 의존 충족분을 반환. stale-lease in_progress 회수는 note 의 마지막 [lease] epoch 로 판정.
  local now ttl; now="$(tb_now_epoch)"; ttl="${TB_LEASE_TTL:-300}"
  bd ready --json 2>/dev/null | jq -c '[.[] | {task_id:.id, title:.title}]' || echo '[]'
  # NOTE: stale-lease in_progress 회수는 bd note 파싱이 필요 — bd 실환경에서 보강.
}

be_append_log() {
  local id marker text; id="$(_argval --task-id "$@")"; marker="$(_argval --marker "$@")"; text="$(_argval --text "$@")"
  bd note add "$id" "[$marker] $text" >/dev/null 2>&1 || tb_die "bd note add 실패"
  jq -nc --arg id "$id" '{task_id:$id, logged:true}'
}

be_materialize() {
  local id; id="$(_argval --task-id "$@")"
  local dir="$TB_ROOT/.task-work/$id"; mkdir -p "$dir"; local sp="$dir/SPEC.md"
  local j; j="$(bd show "$id" --json 2>/dev/null)" || tb_die "bd show 실패: $id"
  { printf '# %s\n\n' "$(printf '%s' "$j" | jq -r .title)"; printf '%s\n' "$(printf '%s' "$j" | jq -r '.description//""')"; } > "$sp"
  jq -nc --arg id "$id" --arg p "$sp" '{task_id:$id, spec_path:$p}'
}

be_renew_lease() {
  local id; id="$(_argval --task-id "$@")"; local now; now="$(tb_now_epoch)"
  bd note add "$id" "[lease] $now" >/dev/null 2>&1 || tb_die "bd note add 실패"
  jq -nc --arg id "$id" --arg t "$now" '{task_id:$id, lease_renewed_at:$t}'
}
