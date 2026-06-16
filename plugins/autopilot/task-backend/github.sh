#!/usr/bin/env bash
# github.sh — task-backend github-project 백엔드 (gh CLI)
# adapter.sh 가 source 해 be_<verb> 를 호출한다. 계약: contract.md.
#
# 매핑(v1):
#   task_id    = Issue 번호 (예: "42")
#   status     = 라벨 `status:<state>` (단일 status 라벨 불변식)
#   depends_on = 본문 HTML 마커 `<!-- autopilot:depends_on: 12,13 -->`
#   title/body = Issue 제목/본문(본문 = SPEC, 섹션 구조는 contract.md)
#   lease      = **공유 전용 코멘트** `<!-- autopilot:lease at=<epoch> owner=<o> -->` (이슈당 1개,
#                in-place PATCH). 본문(SPEC·depends_on)과 독립이라 heartbeat 가 본문을 read-modify-write
#                하지 않는다 → 동시 본문 수정 clobber/데이터 유실 없음. 모든 체크아웃/머신이 같은 lease 를 본다.
#   list_ready = gh issue list(open) 클라이언트측 필터 (depends_on 모두 done + 공유 lease stale 회수)
# github_project_url 이 config 에 있으면 create 시 project item 추가(선택).
# gh 미설치 시 hard-abort. heartbeat 가 본문을 갱신하므로 github 은 heartbeat_interval 을 넉넉히 둘 것.

be_require() { command -v gh >/dev/null 2>&1 || tb_die "github-project 백엔드는 gh CLI 가 필요합니다 (미설치)"; }

gh_repo_args()  {  # config 에 owner/repo 있으면 -R owner/repo
  local o r; o="$(tb_cfg .github_owner)"; r="$(tb_cfg .github_repo)"
  [[ -n "$o" && -n "$r" ]] && printf -- '-R\n%s/%s' "$o" "$r"
}
gh_body()         { gh issue view "$1" $(gh_repo_args) --json body -q .body 2>/dev/null; }
gh_status_label() { gh issue view "$1" $(gh_repo_args) --json labels -q '.labels[].name' 2>/dev/null | sed -n 's/^status://p' | head -1; }
gh_deps()         { gh_body "$1" | sed -n 's/^<!-- autopilot:depends_on: \(.*\) -->$/\1/p' | head -1 | tr ',' '\n' | sed '/^$/d'; }
gh_owner_repo()   {  # "owner/repo" (config 우선, 없으면 gh 추론)
  local o r; o="$(tb_cfg .github_owner)"; r="$(tb_cfg .github_repo)"
  if [[ -n "$o" && -n "$r" ]]; then printf '%s/%s' "$o" "$r"; else gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null; fi
}

# ----- 공유 lease (이슈당 전용 코멘트, in-place PATCH — 본문과 독립) -----
# gh_lease_comment <id> → "<comment_id>\t<body>" (lease 코멘트, 없으면 빈 출력)
gh_lease_comment() {
  local nr; nr="$(gh_owner_repo)"
  gh api "repos/$nr/issues/$1/comments" --paginate \
    -q '.[] | select(.body|startswith("<!-- autopilot:lease ")) | "\(.id)\t\(.body)"' 2>/dev/null | tail -1
}
gh_get_lease() { gh_lease_comment "$1" | sed -n 's/.*at=\([0-9]*\) .*/\1/p' | tail -1; }
# gh_set_lease <id> <epoch> <owner> — lease 전용 코멘트를 in-place PATCH(없으면 생성). 본문 미변경.
gh_set_lease() {
  local id="$1" at="$2" owner="$3" nr cid
  nr="$(gh_owner_repo)"
  local b="<!-- autopilot:lease at=$at owner=$owner -->"
  cid="$(gh_lease_comment "$id" | cut -f1)"
  if [[ -n "$cid" ]]; then
    gh api --method PATCH "repos/$nr/issues/comments/$cid" -f body="$b" >/dev/null 2>&1 || tb_die "lease 코멘트 갱신 실패"
  else
    gh issue comment "$id" $(gh_repo_args) --body "$b" >/dev/null 2>&1 || tb_die "lease 코멘트 생성 실패"
  fi
}

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
  if [[ "$s" == "in_progress" ]]; then gh_set_lease "$id" "$(tb_now_epoch)" "$(_argval --owner "$@")"; fi
  [[ "$s" == "done" ]] && gh issue close "$id" $(gh_repo_args) >/dev/null 2>&1 || true
  jq -nc --arg id "$id" --arg s "$s" '{task_id:$id, status:$s}'
}

# be_claim — 실행권 획득(공유 lease 기준). in_progress 의 공유 lease 가 신선하면 양보(claimed:false),
# stale 면 탈취. lease 가 이슈 본문(공유)에 있어 다른 호스트의 실행 중 태스크를 오회수하지 않는다.
# 주의: 본문 read-modify-write 라 동시 claim 경쟁의 완전한 원자성은 원격 CAS 가 필요(드문 경합).
be_claim() {
  local id owner; id="$(_argval --task-id "$@")"; owner="$(_argval --owner "$@")"
  local s now ttl; s="$(gh_status_label "$id")"; now="$(tb_now_epoch)"; ttl="${TB_LEASE_TTL:-300}"
  if [[ "$s" == "in_progress" ]]; then
    local lr; lr="$(gh_get_lease "$id")"; [[ -n "$lr" ]] || lr=0
    (( now - lr <= ttl )) && { jq -nc --arg id "$id" '{task_id:$id, claimed:false}'; return 0; }
  fi
  be_set_status --task-id "$id" --status in_progress --owner "$owner" >/dev/null
  jq -nc --arg id "$id" '{task_id:$id, claimed:true}'
}

be_link_dependency() {
  local id dep; id="$(_argval --task-id "$@")"; dep="$(_argval --depends-on-id "$@")"
  local cur; cur="$(gh_deps "$id" | tr '\n' ',' | sed 's/,$//')"
  [[ ",$cur," == *",$dep,"* ]] || cur="${cur:+$cur,}$dep"
  local body; body="$(gh_body "$id")"
  # 우리가 생성한 마커 라인만 정밀 삭제(전체-라인 매칭) — 본문 중 유사 텍스트 오삭제 방지.
  body="$(printf '%s' "$body" | sed '/^<!-- autopilot:depends_on:.*-->$/d')"
  body+=$'\n'"<!-- autopilot:depends_on: $cur -->"
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
        # 공유 lease(이슈 본문)로 회수 판정. 실행 중 워커는 heartbeat 로 공유 lease 를 갱신하므로
        # 어느 호스트에서 보든 신선하면 회수하지 않는다. 크래시로 lease 가 stale 해지면(또는 없으면)
        # 어느 호스트든 회수 가능.
        local lr; lr="$(gh_get_lease "$id")"; [[ -n "$lr" ]] || lr=0
        (( now - lr > ttl )) && ready=1
        ;;
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
    # 내부 depends_on 마커는 spec 본문에서 제외(lease 는 본문이 아닌 전용 코멘트라 본문에 없음)
    gh_body "$id" | sed '/^<!-- autopilot:depends_on:.*-->$/d'; } > "$sp"
  jq -nc --arg id "$id" --arg p "$sp" '{task_id:$id, spec_path:$p}'
}

be_renew_lease() {
  local id owner now; id="$(_argval --task-id "$@")"; owner="$(_argval --owner "$@")"; now="$(tb_now_epoch)"
  gh_set_lease "$id" "$now" "$owner"   # 공유 lease(이슈 본문) 갱신
  jq -nc --arg id "$id" --arg t "$now" '{task_id:$id, lease_renewed_at:$t}'
}
