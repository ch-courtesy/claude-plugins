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

# materialize 본문 + H1 title (경로: .autopilot/runs/<id>/SPEC.md — #580 통합)
sp="$(bash "$A" materialize --task-id "$b" | jq -r .spec_path)"
chk "materialize 경로 .autopilot/runs" "$sp" "$TMP/.autopilot/runs/$b/SPEC.md"
chk "materialize H1" "$(head -1 "$sp")" "# B"
grep -q '## 목표' "$sp" && ok "materialize 본문 포함" || bad "materialize 본문 포함"

# append_log
bash "$A" append_log --task-id "$b" --marker handoff --text "넘김" >/dev/null
grep -q '\[handoff\] 넘김' "$(cd "$TMP"; ls .tasks/$b.md)" && ok "append_log 기록" || bad "append_log 기록"

# link_dependency 추가
c="$(bash "$A" create_task --title "C" --body "## 목표"$'\n'"씨" | jq -r .task_id)"
bash "$A" link_dependency --task-id "$b" --depends-on-id "$c" >/dev/null
chk "link_dependency 추가" "$(bash "$A" get_task --task-id "$b" | jq -r '.depends_on | length')" "2"

# set_body: 본문만 교체, status·frontmatter(depends_on)·title 보존
e="$(bash "$A" create_task --title "E" --body $'## 목표\n원본본문' --depends-on "$a" | jq -r .task_id)"
bash "$A" set_status --task-id "$e" --status in_design >/dev/null
bash "$A" set_body --task-id "$e" --body $'## 목표\n교체된본문' >/dev/null
chk "set_body 새 본문 반환" "$(bash "$A" get_body --task-id "$e" | jq -r .body | grep -c '교체된본문')" "1"
chk "set_body 원본 제거" "$(bash "$A" get_body --task-id "$e" | jq -r .body | grep -c '원본본문')" "0"
chk "set_body status 보존" "$(bash "$A" get_task --task-id "$e" | jq -r .status)" "in_design"
chk "set_body depends_on 보존" "$(bash "$A" get_task --task-id "$e" | jq -r '.depends_on[0]')" "$a"
chk "set_body title 보존" "$(bash "$A" get_body --task-id "$e" | jq -r .title)" "E"

# 원자적 claim: 첫 획득 true, 신선 점유 중 재획득 false (락: .autopilot/runs/.claims/<id> — #580 통합)
d="$(bash "$A" create_task --title D --body '## 목표'$'\n'디 | jq -r .task_id)"
chk "claim 1회 true" "$(bash "$A" claim --task-id "$d" --owner w1 | jq -r .claimed)" "true"
[[ -d "$TMP/.autopilot/runs/.claims/$d" ]] && ok "claim 락 .autopilot/runs/.claims" || bad "claim 락 .autopilot/runs/.claims"
chk "claim 신선 점유 false" "$(bash "$A" claim --task-id "$d" --owner w2 | jq -r .claimed)" "false"
chk "claim 후 in_progress" "$(bash "$A" get_task --task-id "$d" | jq -r .status)" "in_progress"
bash "$A" set_status --task-id "$d" --status done >/dev/null
[[ -d "$TMP/.autopilot/runs/.claims/$d" ]] && bad "done 시 claim 해제" || ok "done 시 claim 해제"

# --- #471: 본문 frontmatter(scope) 보존 + frontmatter-first materialize ---
fmbody=$'---\nscope:\n  include:\n    - src/**\n  exclude:\n    - rules/**\n---\n\n## 무엇을 만들 것인가\n바디 본문\n'
g="$(bash "$A" create_task --title "G" --body "$fmbody" | jq -r .task_id)"
# fs_body 왕복: 본문 frontmatter --- 가 get_body 에서 보존
chk "get_body 본문 frontmatter 보존(여는 ---)" "$(bash "$A" get_body --task-id "$g" | jq -r .body | head -1)" "---"
chk "get_body scope.include 라인 보존" "$(bash "$A" get_body --task-id "$g" | jq -r .body | grep -c 'src/\*\*')" "1"
# materialize frontmatter-first: 1번째 줄 ---, frontmatter 뒤 # title, 제목 H1 중복 0
spg="$(bash "$A" materialize --task-id "$g" | jq -r .spec_path)"
chk "materialize 1번째 줄 ---" "$(head -1 "$spg")" "---"
grep -qx '# G' "$spg" && ok "materialize 제목 포함" || bad "materialize 제목 포함"
chk "제목 H1 중복 없음" "$(grep -c '^# G$' "$spg")" "1"
# loop read_scope_yaml(sed) 가 scope.include 를 비우지 않음
chk "scope include 추출(loop sed)" "$(sed -n '1,/^---$/{1d;/^---$/d;p}' "$spg" | grep -c 'src/\*\*')" "1"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
