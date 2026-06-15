#!/usr/bin/env bash
# filesystem.sh — task-backend filesystem 백엔드 (.tasks/T-NNN.md, 의존성 없는 참조 구현)
# adapter.sh 가 source 해 be_<verb> 를 호출한다. 계약: contract.md.
# 외부 CLI 의존 없음(jq/awk/git 만 사용).

be_require() { :; }   # 외부 의존 없음

fs_tasks_dir() { printf '%s/.tasks' "$TB_ROOT"; }
fs_file()      { printf '%s/.tasks/%s.md' "$TB_ROOT" "$1"; }

# fs_fm_get <file> <key>  → frontmatter 값
fs_fm_get() {
  awk -v k="$2" '
    BEGIN{n=0}
    /^---[[:space:]]*$/{n++; next}
    n==1 && $0 ~ "^"k":" { sub("^"k":[[:space:]]*",""); print; exit }
  ' "$1"
}

# fs_fm_set <file> <key> <value>  (있으면 교체, 없으면 닫는 --- 앞에 삽입)
fs_fm_set() {
  local f="$1" k="$2" v="$3"
  awk -v k="$k" -v val="$v" '
    BEGIN{n=0; done=0}
    /^---[[:space:]]*$/{ n++; if(n==2 && !done){ print k": "val; done=1 } print; next }
    { if(n==1 && $0 ~ "^"k":"){ print k": "val; done=1; next } print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# fs_body <file>  → frontmatter 뒤 본문
fs_body() { awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n>=2{print}' "$1"; }

# fs_deps <file>  → depends_on id 한 줄씩
fs_deps() {
  local v; v="$(fs_fm_get "$1" depends_on)"
  v="${v#[}"; v="${v%]}"; v="${v// /}"
  [[ -n "$v" ]] && tr ',' '\n' <<<"$v" || true
}

fs_set_deps() {  # fs_set_deps <file> <id1> <id2>...
  local f="$1"; shift
  local joined; joined="$(printf '%s, ' "$@")"; joined="[${joined%, }]"
  fs_fm_set "$f" depends_on "$joined"
}

fs_exists() { [[ -f "$(fs_file "$1")" ]]; }
fs_status() { fs_fm_get "$(fs_file "$1")" status; }

# ----- 동사 -----

be_create_task() {
  local title body deps
  title="$(_argval --title "$@")"; body="$(_argval --body "$@")"; deps="$(_argval --depends-on "$@")"
  [[ -n "$title" ]] || tb_die "create_task: --title 필요"
  mkdir -p "$(fs_tasks_dir)"
  local max=0 f n
  for f in "$(fs_tasks_dir)"/T-*.md; do
    [[ -e "$f" ]] || continue
    n="$(basename "$f" .md)"; n="${n#T-}"; n="$((10#$n))"
    (( n > max )) && max=$n
  done
  local id; id="$(printf 'T-%03d' "$((max+1))")"
  local dline="[]"
  [[ -n "$deps" ]] && dline="[${deps//,/, }]"
  { printf -- '---\n'
    printf 'id: %s\n' "$id"
    printf 'title: %s\n' "$title"
    printf 'status: backlog\n'
    printf 'depends_on: %s\n' "$dline"
    printf 'parent:\n'
    printf 'owner:\n'
    printf 'created: %s\n' "$(tb_now_iso)"
    printf 'lease_renewed_at:\n'
    printf 'lease_owner:\n'
    printf -- '---\n'
    printf '%s\n' "$body"
  } > "$(fs_file "$id")"
  jq -nc --arg id "$id" '{task_id:$id, status:"backlog", url:null}'
}

be_get_task() {
  local id; id="$(_argval --task-id "$@")"; fs_exists "$id" || tb_die "get_task: 없음 $id"
  local f; f="$(fs_file "$id")"
  local deps_json; deps_json="$(fs_deps "$f" | jq -R . | jq -sc .)"
  jq -nc --arg id "$id" --arg t "$(fs_fm_get "$f" title)" --arg s "$(fs_status "$id")" \
    --argjson d "$deps_json" '{task_id:$id, title:$t, status:$s, depends_on:$d, url:null}'
}

be_get_body() {
  local id; id="$(_argval --task-id "$@")"; fs_exists "$id" || tb_die "get_body: 없음 $id"
  local f; f="$(fs_file "$id")"
  jq -nc --arg id "$id" --arg t "$(fs_fm_get "$f" title)" --arg b "$(fs_body "$f")" \
    '{task_id:$id, title:$t, body:$b}'
}

be_set_status() {
  local id s; id="$(_argval --task-id "$@")"; s="$(_argval --status "$@")"
  fs_exists "$id" || tb_die "set_status: 없음 $id"
  local f; f="$(fs_file "$id")"
  fs_fm_set "$f" status "$s"
  if [[ "$s" == "in_progress" ]]; then
    fs_fm_set "$f" lease_renewed_at "$(tb_now_epoch)"
    fs_fm_set "$f" lease_owner "$(_argval --owner "$@")"
  fi
  jq -nc --arg id "$id" --arg s "$s" '{task_id:$id, status:$s}'
}

be_link_dependency() {
  local id dep; id="$(_argval --task-id "$@")"; dep="$(_argval --depends-on-id "$@")"
  fs_exists "$id" || tb_die "link_dependency: 없음 $id"
  local f; f="$(fs_file "$id")"
  local cur; mapfile -t cur < <(fs_deps "$f")
  local x; for x in "${cur[@]}"; do [[ "$x" == "$dep" ]] && { be_get_task --task-id "$id"; return; }; done
  cur+=("$dep"); fs_set_deps "$f" "${cur[@]}"
  local deps_json; deps_json="$(fs_deps "$f" | jq -R . | jq -sc .)"
  jq -nc --arg id "$id" --argjson d "$deps_json" '{task_id:$id, depends_on:$d}'
}

be_list_ready() {
  local now; now="$(tb_now_epoch)"; local ttl="${TB_LEASE_TTL:-300}"
  local out="[]" f id st ready
  for f in "$(fs_tasks_dir)"/T-*.md; do
    [[ -e "$f" ]] || continue
    id="$(basename "$f" .md)"; st="$(fs_fm_get "$f" status)"; ready=0
    case "$st" in
      backlog|in_design)
        ready=1
        local d; while IFS= read -r d; do [[ -z "$d" ]] && continue
          [[ "$(fs_status "$d" 2>/dev/null)" == "done" ]] || ready=0
        done < <(fs_deps "$f")
        ;;
      in_progress)
        local lr; lr="$(fs_fm_get "$f" lease_renewed_at)"
        if [[ -z "$lr" ]] || (( now - lr > ttl )); then ready=1; fi
        ;;
    esac
    if (( ready )); then
      out="$(printf '%s' "$out" | jq -c --arg id "$id" --arg t "$(fs_fm_get "$f" title)" '. + [{task_id:$id, title:$t}]')"
    fi
  done
  printf '%s\n' "$out"
}

be_append_log() {
  local id marker text; id="$(_argval --task-id "$@")"; marker="$(_argval --marker "$@")"; text="$(_argval --text "$@")"
  fs_exists "$id" || tb_die "append_log: 없음 $id"
  printf -- '- %s [%s] %s\n' "$(tb_now_iso)" "$marker" "$text" >> "$(fs_file "$id")"
  jq -nc --arg id "$id" '{task_id:$id, logged:true}'
}

be_materialize() {
  local id; id="$(_argval --task-id "$@")"; fs_exists "$id" || tb_die "materialize: 없음 $id"
  local f; f="$(fs_file "$id")"
  local dir="$TB_ROOT/.task-work/$id"; mkdir -p "$dir"
  local sp="$dir/SPEC.md"
  { printf '# %s\n\n' "$(fs_fm_get "$f" title)"; fs_body "$f"; } > "$sp"
  jq -nc --arg id "$id" --arg p "$sp" '{task_id:$id, spec_path:$p}'
}

be_renew_lease() {
  local id; id="$(_argval --task-id "$@")"; fs_exists "$id" || tb_die "renew_lease: 없음 $id"
  local f now; f="$(fs_file "$id")"; now="$(tb_now_epoch)"
  fs_fm_set "$f" lease_renewed_at "$now"
  local owner; owner="$(_argval --owner "$@")"; [[ -n "$owner" ]] && fs_fm_set "$f" lease_owner "$owner"
  jq -nc --arg id "$id" --arg t "$now" '{task_id:$id, lease_renewed_at:$t}'
}
