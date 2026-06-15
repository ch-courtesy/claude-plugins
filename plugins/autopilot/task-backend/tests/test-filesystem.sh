#!/usr/bin/env bash
# test-filesystem.sh — filesystem 백엔드 CRUD + depends_on 게이팅 + materialize + append_log.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A="$HERE/../adapter.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

bash "$A" init --backend filesystem >/dev/null
chk "backend 확인" "$(bash "$A" backend | jq -r .backend)" "filesystem"

a="$(bash "$A" create_task --title "A" --body $'## 목표\n에이' | jq -r .task_id)"
b="$(bash "$A" create_task --title "B" --body $'## 목표\n비' --depends-on "$a" | jq -r .task_id)"
chk "id 순번 a" "$a" "T-001"
chk "id 순번 b" "$b" "T-002"

# get_task depends_on
chk "b depends_on a" "$(bash "$A" get_task --task-id "$b" | jq -r '.depends_on[0]')" "$a"

# get_body 본문 보존
chk "get_body" "$(bash "$A" get_body --task-id "$a" | jq -r .body | head -1)" "## 목표"

# list_ready: a 만 (b 는 미충족)
chk "ready=a" "$(bash "$A" list_ready | jq -r '.[].task_id' | tr '\n' ' ')" "$a "

# a done → b ready
bash "$A" set_status --task-id "$a" --status done >/dev/null
chk "a done 후 ready=b" "$(bash "$A" list_ready | jq -r '.[].task_id' | tr '\n' ' ')" "$b "

# materialize 본문 + H1 title
sp="$(bash "$A" materialize --task-id "$b" | jq -r .spec_path)"
chk "materialize H1" "$(head -1 "$sp")" "# B"
grep -q '## 목표' "$sp" && ok "materialize 본문 포함" || bad "materialize 본문 포함"

# append_log
bash "$A" append_log --task-id "$b" --marker handoff --text "넘김" >/dev/null
grep -q '\[handoff\] 넘김' "$(cd "$TMP"; ls .tasks/$b.md)" && ok "append_log 기록" || bad "append_log 기록"

# link_dependency 추가
c="$(bash "$A" create_task --title "C" --body "## 목표"$'\n'"씨" | jq -r .task_id)"
bash "$A" link_dependency --task-id "$b" --depends-on-id "$c" >/dev/null
chk "link_dependency 추가" "$(bash "$A" get_task --task-id "$b" | jq -r '.depends_on | length')" "2"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
