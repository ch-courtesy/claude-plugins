#!/usr/bin/env bash
# adapter.sh — autopilot 태스크 백엔드 어댑터 라우터 (플러그인 자체 소유)
#
# 책임:
#   - 컨슈밍 프로젝트 루트의 .autopilot/task-backend.json 을 읽어 백엔드를 고르고,
#     선택된 백엔드 구현(filesystem.sh/github.sh/beads.sh)의 be_<verb> 함수로 위임.
#   - 동사·입출력(JSON) 계약·상태 집합·본문 구조·lease 규약의 단일 출처는 contract.md.
#
# 하지 않는 일:
#   - rules/ 프로젝트 지침이나 다른 스킬 참조(플러그인 자기완결). forge·loop 연동(별도).
#
# 호출: bash adapter.sh <verb> [args...]   (출력: 한 줄 JSON)
set -euo pipefail

TB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tb_die() { echo "adapter: $*" >&2; exit 1; }
tb_now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
tb_now_epoch() { date -u +%s; }

# 프로젝트 루트 (git 우선, 아니면 cwd)
tb_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

TB_CONFIG="$(tb_root)/.autopilot/task-backend.json"

# tb_cfg <jq-filter> [default]
tb_cfg() {
  local filter="$1" def="${2:-}"
  [[ -f "$TB_CONFIG" ]] || { printf '%s' "$def"; return; }
  local v; v="$(jq -r "$filter // empty" "$TB_CONFIG" 2>/dev/null || true)"
  [[ -n "$v" ]] && printf '%s' "$v" || printf '%s' "$def"
}

# _argval <flag-name> "$@"  → --flag 다음 값 출력 (없으면 빈 문자열)
_argval() {
  local want="$1"; shift
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "$want" ]]; then printf '%s' "${2:-}"; return; fi
    shift
  done
}

# ----- init: config 생성/갱신 (백엔드 선택은 호출자가 인자로) -----
tb_init() {
  local backend; backend="$(_argval --backend "$@")"
  [[ -n "$backend" ]] || tb_die "init: --backend <filesystem|github-project|beads> 필요"
  case "$backend" in filesystem|github-project|beads) ;; *) tb_die "init: 알 수 없는 backend '$backend'";; esac
  mkdir -p "$(dirname "$TB_CONFIG")"
  local url owner repo
  url="$(_argval --github-project-url "$@")"
  owner="$(_argval --github-owner "$@")"
  repo="$(_argval --github-repo "$@")"
  jq -n --arg b "$backend" --arg url "$url" --arg owner "$owner" --arg repo "$repo" \
    '{backend:$b, lease_ttl_seconds:300, heartbeat_interval_seconds:60}
     + (if $url   != "" then {github_project_url:$url} else {} end)
     + (if $owner != "" then {github_owner:$owner} else {} end)
     + (if $repo  != "" then {github_repo:$repo} else {} end)' > "$TB_CONFIG"
  jq -c '{backend, config_path:"'"$TB_CONFIG"'"}' "$TB_CONFIG"
}

# ----- 백엔드 로딩 -----
tb_load_backend() {
  [[ -f "$TB_CONFIG" ]] || tb_die "백엔드 미설정: 'adapter.sh init --backend <name>' 을 먼저 실행하세요 ($TB_CONFIG 없음)"
  TB_BACKEND="$(tb_cfg .backend)"
  [[ -n "$TB_BACKEND" ]] || tb_die "config 에 backend 키가 없습니다: $TB_CONFIG"
  export TB_LEASE_TTL="$(tb_cfg .lease_ttl_seconds 300)"
  export TB_ROOT; TB_ROOT="$(tb_root)"
  local impl="$TB_DIR/${TB_BACKEND/github-project/github}.sh"
  [[ -f "$impl" ]] || tb_die "백엔드 구현 없음: $impl"
  # shellcheck disable=SC1090
  source "$impl"
  be_require 2>/dev/null || true   # 백엔드별 의존성 hard-abort (gh/bd)
}

main() {
  local verb="${1:-}"; shift || true
  case "$verb" in
    init)     tb_init "$@";;
    selftest) tb_selftest;;
    backend)  tb_load_backend; jq -nc --arg b "$TB_BACKEND" '{backend:$b}';;
    create_task|get_task|get_body|set_body|set_status|link_dependency|list_ready|append_log|materialize|renew_lease|claim)
      tb_load_backend; "be_$verb" "$@";;
    ""|-h|--help|help)
      cat >&2 <<'EOF'
usage: adapter.sh <verb> [args]
  init --backend <filesystem|github-project|beads> [--github-project-url U --github-owner O --github-repo R]
  create_task --title T --body B [--depends-on a,b]
  get_task|get_body|materialize|renew_lease --task-id ID
  set_body --task-id ID --body B
  set_status --task-id ID --status S [--reason R]
  link_dependency --task-id ID --depends-on-id ID
  append_log --task-id ID --marker decision|handoff|blocked --text T
  list_ready | backend | selftest
EOF
      exit 2;;
    *) tb_die "알 수 없는 동사: $verb";;
  esac
}

# ----- selftest: filesystem 백엔드로 계약 왕복 검증 (임시 repo) -----
tb_selftest() {
  local TMP; TMP="$(mktemp -d)"
  ( cd "$TMP" && git init -q && git config user.email t@t && git config user.name t )
  local fail=0
  ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
  chk(){ if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
  local A="$TB_DIR/adapter.sh"
  ( cd "$TMP" && bash "$A" init --backend filesystem >/dev/null )
  local r1; r1="$(cd "$TMP" && bash "$A" create_task --title "First" --body $'## 목표\n달성' )"
  local id1; id1="$(printf '%s' "$r1" | jq -r .task_id)"
  chk "create status backlog" "$(printf '%s' "$r1" | jq -r .status)" "backlog"
  local r2; r2="$(cd "$TMP" && bash "$A" create_task --title "Second" --body $'## 목표\n둘' --depends-on "$id1" )"
  local id2; id2="$(printf '%s' "$r2" | jq -r .task_id)"
  # list_ready: 선행만 (id1), id2 는 depends_on 미충족
  local ready; ready="$(cd "$TMP" && bash "$A" list_ready | jq -r '.[].task_id' | sort | tr '\n' ' ')"
  chk "list_ready 선행만" "$ready" "$id1 "
  # id1 done → id2 ready
  ( cd "$TMP" && bash "$A" set_status --task-id "$id1" --status done >/dev/null )
  ready="$(cd "$TMP" && bash "$A" list_ready | jq -r '.[].task_id' | tr '\n' ' ')"
  chk "dep 해제 후 후행 ready" "$ready" "$id2 "
  # set_body: 본문만 교체, status·depends_on 보존
  ( cd "$TMP" && bash "$A" set_body --task-id "$id2" --body $'## 목표\n교체본문' >/dev/null )
  chk "set_body 새 본문" "$(cd "$TMP" && bash "$A" get_body --task-id "$id2" | jq -r .body | grep -c '교체본문')" "1"
  chk "set_body depends_on 보존" "$(cd "$TMP" && bash "$A" get_task --task-id "$id2" | jq -r '.depends_on[0]')" "$id1"
  # materialize
  local mr; mr="$(cd "$TMP" && bash "$A" materialize --task-id "$id2")"
  local sp; sp="$(printf '%s' "$mr" | jq -r .spec_path)"
  [[ -f "$TMP/$sp" || -f "$sp" ]] && ok "materialize 파일 생성" || bad "materialize 파일 생성 ($sp)"
  echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  rm -rf "$TMP"
  return $fail
}

main "$@"
