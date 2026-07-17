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
# bd 미설치 시 hard-abort (조용한 폴백 없음).
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

# be_set_body — 본문(=SPEC)만 교체. status·depends_on(bd dep)·notes 는 별도 경로라 보존된다.
be_set_body() {
  local id body; id="$(_argval --task-id "$@")"; body="$(_argval --body "$@")"
  bd update "$id" --description "$body" >/dev/null 2>&1 || tb_die "bd update --description 실패"
  jq -nc --arg id "$id" '{task_id:$id}'
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

# bd_last_lease <id> — notes 의 마지막 "[lease] <epoch>" 값(없으면 0). (가정한 notes 스키마: .notes[].text)
bd_last_lease() {
  bd show "$1" --json 2>/dev/null \
    | jq -r '[.notes[]? | (.text // .) | select(type=="string" and startswith("[lease] ")) | (ltrimstr("[lease] ")|tonumber?)] | max // 0' 2>/dev/null \
    || echo 0
}

be_list_ready() {
  local now ttl; now="$(tb_now_epoch)"; ttl="${TB_LEASE_TTL:-300}"
  # 1) 의존 충족분(bd ready)
  local base; base="$(bd ready --json 2>/dev/null | jq -c '[.[] | {task_id:.id, title:.title}]' 2>/dev/null || echo '[]')"
  # 2) stale-lease in_progress 회수 (계약: 모든 백엔드가 회수)
  local stale="[]" id last title
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    last="$(bd_last_lease "$id")"; [[ "$last" =~ ^[0-9]+$ ]] || last=0
    if (( now - last > ttl )); then
      title="$(bd show "$id" --json 2>/dev/null | jq -r '.title // ""')"
      stale="$(printf '%s' "$stale" | jq -c --arg id "$id" --arg t "$title" '. + [{task_id:$id, title:$t}]')"
    fi
  done < <(bd list --status in_progress --json 2>/dev/null | jq -r '.[].id' 2>/dev/null)
  jq -cn --argjson a "$base" --argjson b "$stale" '($a + $b) | unique_by(.task_id)'
}

# be_claim — 실행권 획득(best-effort). 신선한 lease 의 in_progress 면 양보. 진정한 원자성은 bd 측 CAS 필요.
be_claim() {
  local id owner; id="$(_argval --task-id "$@")"; owner="$(_argval --owner "$@")"
  local now ttl s; now="$(tb_now_epoch)"; ttl="${TB_LEASE_TTL:-300}"
  s="$(bd show "$id" --json 2>/dev/null | jq -r '.status // ""')"
  if [[ "$s" == "in_progress" ]]; then
    local last; last="$(bd_last_lease "$id")"; [[ "$last" =~ ^[0-9]+$ ]] || last=0
    (( now - last <= ttl )) && { jq -nc --arg id "$id" '{task_id:$id, claimed:false}'; return 0; }
  fi
  bd update "$id" --status in_progress >/dev/null 2>&1 || tb_die "bd update 실패"
  bd note add "$id" "[lease] $now" >/dev/null 2>&1 || true
  jq -nc --arg id "$id" '{task_id:$id, claimed:true}'
}

be_append_log() {
  local id marker text; id="$(_argval --task-id "$@")"; marker="$(_argval --marker "$@")"; text="$(_argval --text "$@")"
  bd note add "$id" "[$marker] $text" >/dev/null 2>&1 || tb_die "bd note add 실패"
  jq -nc --arg id "$id" '{task_id:$id, logged:true}'
}

be_materialize() {
  local id; id="$(_argval --task-id "$@")"
  local dir="$TB_ROOT/.autopilot/runs/$id"; mkdir -p "$dir"; local sp="$dir/SPEC.md"
  local j; j="$(bd show "$id" --json 2>/dev/null)" || tb_die "bd show 실패: $id"
  { printf '# %s\n\n' "$(printf '%s' "$j" | jq -r .title)"; printf '%s\n' "$(printf '%s' "$j" | jq -r '.description//""')"; } > "$sp"
  jq -nc --arg id "$id" --arg p "$sp" '{task_id:$id, spec_path:$p}'
}

be_renew_lease() {
  local id; id="$(_argval --task-id "$@")"; local now; now="$(tb_now_epoch)"
  bd note add "$id" "[lease] $now" >/dev/null 2>&1 || tb_die "bd note add 실패"
  jq -nc --arg id "$id" --arg t "$now" '{task_id:$id, lease_renewed_at:$t}'
}
