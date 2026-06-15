#!/usr/bin/env bash
# github.sh — task-backend github-project 백엔드 (gh CLI)
# adapter.sh 가 source 해 be_<verb> 를 호출한다. 계약: contract.md.
#
# 매핑(v1):
#   task_id    = Issue 번호 (예: "42")
#   status     = 라벨 `status:<state>` (단일 status 라벨 불변식)
#   depends_on = 본문 HTML 마커 `<!-- autopilot:depends_on: 12,13 -->`
#   title/body = Issue 제목/본문(본문 = SPEC, 섹션 구조는 contract.md)
#   lease      = 로컬 미러 .autopilot/leases/<id> (epoch) — API 빈발 호출 회피
#   list_ready = gh issue list(open) 클라이언트측 필터 (depends_on 모두 done + stale-lease in_progress)
# github_project_url 이 config 에 있으면 create 시 project item 추가(선택).
# gh 미설치 시 hard-abort.

be_require() { command -v gh >/dev/null 2>&1 || tb_die "github-project 백엔드는 gh CLI 가 필요합니다 (미설치)"; }

gh_lease_dir()  { printf '%s/.autopilot/leases' "$TB_ROOT"; }
gh_lease_file() { printf '%s/.autopilot/leases/%s' "$TB_ROOT" "$1"; }
gh_repo_args()  {  # config 에 owner/repo 있으면 -R owner/repo
  local o r; o="$(tb_cfg .github_owner)"; r="$(tb_cfg .github_repo)"
  [[ -n "$o" && -n "$r" ]] && printf -- '-R\n%s/%s' "$o" "$r"
}
gh_status_label() { gh issue view "$1" $(gh_repo_args) --json labels -q '.labels[].name' 2>/dev/null | sed -n 's/^status://p' | head -1; }
gh_deps()        { gh issue view "$1" $(gh_repo_args) --json body -q .body 2>/dev/null | sed -n 's/.*<!-- autopilot:depends_on: \(.*\) -->.*/\1/p' | tr ',' '\n' | sed '/^$/d'; }

be_create_task() {
  local title body deps; title="$(_argval --title "$@")"; body="$(_argval --body "$@")"; deps="$(_argval --depends-on "$@")"
  [[ -n "$title" ]] || tb_die "create_task: --title 필요"
  local full="$body"
  [[ -n "$deps" ]] && full+=$'\n\n'"<!-- autopilot:depends_on: $deps -->"
  local url; url="$(gh issue create $(gh_repo_args) --title "$title" --body "$full" 2>/dev/null)" || tb_die "gh issue create 실패"
  local id="${url##*/}"
  gh issue edit "$id" $(gh_repo_args) --add-label "status:backlog" >/dev/null 2>&1 || true
  local purl; purl="$(tb_cfg .github_project_url)"
  [[ -n "$purl" ]] && gh project item-add "${purl##*/}" --owner "$(tb_cfg .github_owner)" --url "$url" >/dev/null 2>&1 || true
  jq -nc --arg id "$id" --arg u "$url" '{task_id:$id, status:"backlog", url:$u}'
}

be_get_task() {
  local id; id="$(_argval --task-id "$@")"
  local t s djson; t="$(gh issue view "$id" $(gh_repo_args) --json title -q .title)"; s="$(gh_status_label "$id")"
  djson="$(gh_deps "$id" | jq -R . | jq -sc .)"
  jq -nc --arg id "$id" --arg t "$t" --arg s "${s:-backlog}" --argjson d "$djson" \
    --arg u "$(gh issue view "$id" $(gh_repo_args) --json url -q .url)" \
    '{task_id:$id, title:$t, status:$s, depends_on:$d, url:$u}'
}

be_get_body() {
  local id; id="$(_argval --task-id "$@")"
  jq -nc --arg id "$id" --arg t "$(gh issue view "$id" $(gh_repo_args) --json title -q .title)" \
    --arg b "$(gh issue view "$id" $(gh_repo_args) --json body -q .body)" '{task_id:$id, title:$t, body:$b}'
}

be_set_status() {
  local id s; id="$(_argval --task-id "$@")"; s="$(_argval --status "$@")"
  local old; old="$(gh_status_label "$id")"
  [[ -n "$old" ]] && gh issue edit "$id" $(gh_repo_args) --remove-label "status:$old" >/dev/null 2>&1 || true
  gh issue edit "$id" $(gh_repo_args) --add-label "status:$s" >/dev/null 2>&1 || tb_die "라벨 status:$s 설정 실패(라벨 존재 필요)"
  if [[ "$s" == "in_progress" ]]; then mkdir -p "$(gh_lease_dir)"; tb_now_epoch > "$(gh_lease_file "$id")"; fi
  [[ "$s" == "done" ]] && gh issue close "$id" $(gh_repo_args) >/dev/null 2>&1 || true
  jq -nc --arg id "$id" --arg s "$s" '{task_id:$id, status:$s}'
}

be_link_dependency() {
  local id dep; id="$(_argval --task-id "$@")"; dep="$(_argval --depends-on-id "$@")"
  local cur; cur="$(gh_deps "$id" | tr '\n' ',' | sed 's/,$//')"
  [[ ",$cur," == *",$dep,"* ]] || cur="${cur:+$cur,}$dep"
  local body; body="$(gh issue view "$id" $(gh_repo_args) --json body -q .body)"
  body="$(printf '%s' "$body" | sed '/<!-- autopilot:depends_on:/d')"
  body+=$'\n\n'"<!-- autopilot:depends_on: $cur -->"
  gh issue edit "$id" $(gh_repo_args) --body "$body" >/dev/null 2>&1 || tb_die "depends_on 갱신 실패"
  jq -nc --arg id "$id" --argjson d "$(printf '%s' "$cur" | tr ',' '\n' | jq -R . | jq -sc .)" '{task_id:$id, depends_on:$d}'
}

be_list_ready() {
  local now ttl; now="$(tb_now_epoch)"; ttl="${TB_LEASE_TTL:-300}"
  local out="[]" id s ready
  while IFS=$'\t' read -r id title; do
    [[ -z "$id" ]] && continue
    s="$(gh_status_label "$id")"; ready=0
    case "$s" in
      backlog|in_design|"")
        ready=1
        local d; while IFS= read -r d; do [[ -z "$d" ]] && continue
          [[ "$(gh_status_label "$d")" == "done" ]] || ready=0
        done < <(gh_deps "$id") ;;
      in_progress)
        local lf lr; lf="$(gh_lease_file "$id")"; lr="$( [[ -f "$lf" ]] && cat "$lf" || echo 0 )"
        (( now - lr > ttl )) && ready=1 ;;
    esac
    (( ready )) && out="$(printf '%s' "$out" | jq -c --arg id "$id" --arg t "$title" '. + [{task_id:$id, title:$t}]')"
  done < <(gh issue list $(gh_repo_args) --state open --json number,title -q '.[] | "\(.number)\t\(.title)"')
  printf '%s\n' "$out"
}

be_append_log() {
  local id marker text; id="$(_argval --task-id "$@")"; marker="$(_argval --marker "$@")"; text="$(_argval --text "$@")"
  gh issue comment "$id" $(gh_repo_args) --body "[$marker] $text" >/dev/null 2>&1 || tb_die "comment 실패"
  jq -nc --arg id "$id" '{task_id:$id, logged:true}'
}

be_materialize() {
  local id; id="$(_argval --task-id "$@")"
  local dir="$TB_ROOT/.task-work/$id"; mkdir -p "$dir"; local sp="$dir/SPEC.md"
  { printf '# %s\n\n' "$(gh issue view "$id" $(gh_repo_args) --json title -q .title)"
    gh issue view "$id" $(gh_repo_args) --json body -q .body; } > "$sp"
  jq -nc --arg id "$id" --arg p "$sp" '{task_id:$id, spec_path:$p}'
}

be_renew_lease() {
  local id; id="$(_argval --task-id "$@")"; mkdir -p "$(gh_lease_dir)"
  local now; now="$(tb_now_epoch)"; printf '%s\n' "$now" > "$(gh_lease_file "$id")"
  jq -nc --arg id "$id" --arg t "$now" '{task_id:$id, lease_renewed_at:$t}'
}
