#!/usr/bin/env bash
# test-workflow-task-overlap-serialize.sh — 드레이너 산출물(버전 표면) 겹침 직렬화 (#628)
#
# 같은 scope.include 항목(예: CHANGELOG.md·plugin.json)을 산출물로 갖는 ready 태스크가
# 한 패스에 둘 이상이면 동시에 fan-out 하지 않는다 — 첫 태스크만 실행하고 나머지는
# deferred_ids 로 보고(조용한 누락 금지)하며 다음 틱 드레인이 집는다.
# 산출물이 겹치지 않는 태스크는 기존대로 같은 패스에서 병렬 실행된다.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
WT="$REPO_ROOT/plugins/autopilot/skills/workflow-task/references/workflow-task.sh"
ADAPTER="$REPO_ROOT/plugins/autopilot/lib/task-backend/adapter.sh"
FLOW="$REPO_ROOT/plugins/autopilot/skills/flow/references/flow.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q; git config user.email t@t; git config user.name t
bash "$ADAPTER" init --backend filesystem >/dev/null

# mock execute-task: 'start <id>' → done 전이 + 실행 기록.
mkdir -p bin
cat > bin/exec-mock <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$2" >> "$TMP/execlog"
bash "$ADAPTER" set_status --task-id "\$2" --status done >/dev/null
EOF
chmod +x bin/exec-mock
: > execlog

mkbody() { # mkbody <include-항목...> — scope frontmatter 본문 생성.
  printf -- '---\nscope:\n  include:\n'
  local e; for e in "$@"; do printf -- '    - %s\n' "$e"; done
  printf -- '  exclude:\n    - rules/**\n---\n\n# t\n\n## 목표\nx\n'
}

# T1·T2 는 버전 표면(plugin.json·CHANGELOG.md) 공유, T3 은 겹침 없음.
t1="$(bash "$ADAPTER" create_task --title T1 \
  --body "$(mkbody 'plugins/autopilot/skills/a/SKILL.md' 'plugins/autopilot/.claude-plugin/plugin.json' 'CHANGELOG.md')" | jq -r .task_id)"
t2="$(bash "$ADAPTER" create_task --title T2 \
  --body "$(mkbody 'plugins/autopilot/skills/b/SKILL.md' 'plugins/autopilot/.claude-plugin/plugin.json' 'CHANGELOG.md')" | jq -r .task_id)"
t3="$(bash "$ADAPTER" create_task --title T3 \
  --body "$(mkbody 'docs/other.md')" | jq -r .task_id)"

drain() { ADAPTER_CMD="bash $ADAPTER" FLOW_CMD="bash $FLOW" EXECUTE_CMD="bash $TMP/bin/exec-mock" bash "$WT" start; }

# ---- 1패스: 겹침 그룹(T1·T2)은 하나만 실행, T3 은 병렬 실행, 나머지는 deferred 보고 ----
out1="$(drain)"
chk "1패스 ready=3" "$(printf '%s' "$out1" | jq -r .ready)" "3"
chk "1패스 deferred=1(겹침 그룹서 1건 유예)" "$(printf '%s' "$out1" | jq -r .deferred)" "1"
d1="$(printf '%s' "$out1" | jq -r '.deferred_ids[0]')"
case "$d1" in "$t1"|"$t2") ok "1패스 deferred_ids 가 겹침 그룹 소속";; *) bad "1패스 deferred_ids 가 겹침 그룹 소속 (got '$d1')";; esac
exec_n="$(wc -l < execlog | tr -d ' ')"
chk "1패스 실행 2건(겹침 1 + 비겹침 1)" "$exec_n" "2"
grep -Fxq "$t3" execlog && ok "1패스 비겹침 T3 병렬 실행" || bad "1패스 비겹침 T3 병렬 실행"
grep -Fxq "$d1" execlog && bad "1패스 유예 태스크 미실행" || ok "1패스 유예 태스크 미실행"
chk "1패스 유예 태스크 상태 보존(backlog)" "$(bash "$ADAPTER" get_task --task-id "$d1" | jq -r .status)" "backlog"

# ---- 2패스: 유예분이 다음 틱에 흡수된다 ----
out2="$(drain)"
chk "2패스 ready=1(유예분)" "$(printf '%s' "$out2" | jq -r .ready)" "1"
chk "2패스 deferred=0" "$(printf '%s' "$out2" | jq -r .deferred)" "0"
chk "2패스 유예분 done" "$(bash "$ADAPTER" get_task --task-id "$d1" | jq -r .status)" "done"

# ---- 겹침 없음(전부 disjoint) → 기존 병렬 동작·deferred_ids=[] 키 상시 노출 ----
: > execlog
t4="$(bash "$ADAPTER" create_task --title T4 --body "$(mkbody 'a/1.md')" | jq -r .task_id)"
t5="$(bash "$ADAPTER" create_task --title T5 --body "$(mkbody 'b/2.md')" | jq -r .task_id)"
out3="$(drain)"
chk "disjoint 패스 deferred=0" "$(printf '%s' "$out3" | jq -r .deferred)" "0"
chk "disjoint 패스 deferred_ids=[]" "$(printf '%s' "$out3" | jq -c '.deferred_ids')" "[]"
chk "disjoint 패스 실행 2건" "$(wc -l < execlog | tr -d ' ')" "2"

# ---- 의미 겹침(#637): 후행 '/' prefix·글롭이 문자열 불일치라도 같은 산출물을 덮으면 유예 ----
# loop path_matches_pattern 의미론과 동일: 'dir/'는 하위 전체 prefix, 그 외는 bash 글롭.
# 양방향 — 선점 항목이 새 항목을 덮는 경우(T8→T9)와 새 항목이 선점 항목을 덮는 경우(T10→T11) 모두 차단.
: > execlog
t8="$(bash "$ADAPTER" create_task --title T8 --body "$(mkbody 'plugins/autopilot/')" | jq -r .task_id)"
t9="$(bash "$ADAPTER" create_task --title T9 --body "$(mkbody 'plugins/autopilot/.claude-plugin/plugin.json')" | jq -r .task_id)"
t10="$(bash "$ADAPTER" create_task --title T10 --body "$(mkbody 'src/foo.sh')" | jq -r .task_id)"
t11="$(bash "$ADAPTER" create_task --title T11 --body "$(mkbody 'src/**')" | jq -r .task_id)"
out5="$(drain)"
chk "의미겹침 패스 deferred=2(prefix 1 + 글롭 1)" "$(printf '%s' "$out5" | jq -r .deferred)" "2"
printf '%s' "$out5" | jq -r '.deferred_ids[]' | grep -Fxq "$t9" \
  && ok "prefix: 선점 'plugins/autopilot/'가 하위 파일 태스크 유예" \
  || bad "prefix: 선점 'plugins/autopilot/'가 하위 파일 태스크 유예"
printf '%s' "$out5" | jq -r '.deferred_ids[]' | grep -Fxq "$t11" \
  && ok "글롭 역방향: 새 'src/**'가 선점 'src/foo.sh'를 덮으면 유예" \
  || bad "글롭 역방향: 새 'src/**'가 선점 'src/foo.sh'를 덮으면 유예"
chk "의미겹침 패스 실행 2건(T8·T10)" "$(wc -l < execlog | tr -d ' ')" "2"
out6="$(drain)"
chk "의미겹침 유예분 다음 틱 흡수(ready=2)" "$(printf '%s' "$out6" | jq -r .ready)" "2"
chk "의미겹침 유예분 다음 틱 deferred=0" "$(printf '%s' "$out6" | jq -r .deferred)" "0"

# ---- 글롭 부분 겹침(PR 641 리뷰): 서로의 패턴은 못 덮어도 파일 집합이 교차하면 유예 ----
# 'src/*.sh' 와 'src/foo.*' 는 둘 다 'src/foo.sh' 를 포함한다(어느 쪽도 상대 패턴 문자열은 미매치).
: > execlog
t12="$(bash "$ADAPTER" create_task --title T12 --body "$(mkbody 'src/*.sh')" | jq -r .task_id)"
t13="$(bash "$ADAPTER" create_task --title T13 --body "$(mkbody 'src/foo.*')" | jq -r .task_id)"
out7="$(drain)"
chk "글롭 부분겹침 deferred=1" "$(printf '%s' "$out7" | jq -r .deferred)" "1"
chk "글롭 부분겹침 실행 1건" "$(wc -l < execlog | tr -d ' ')" "1"
bash "$ADAPTER" set_status --task-id "$(printf '%s' "$out7" | jq -r '.deferred_ids[0]')" --status done >/dev/null

# ---- 서로 다른 디렉터리 글롭은 겹치지 않는다(과유예 방지) ----
: > execlog
t14="$(bash "$ADAPTER" create_task --title T14 --body "$(mkbody 'alpha/*.sh')" | jq -r .task_id)"
t15="$(bash "$ADAPTER" create_task --title T15 --body "$(mkbody 'beta/*.sh')" | jq -r .task_id)"
out8="$(drain)"
chk "다른 디렉터리 글롭 deferred=0" "$(printf '%s' "$out8" | jq -r .deferred)" "0"
chk "다른 디렉터리 글롭 실행 2건" "$(wc -l < execlog | tr -d ' ')" "2"

# ---- scope frontmatter 없는 본문 → 겹침 판정 없이 기존대로 실행 ----
: > execlog
t6="$(bash "$ADAPTER" create_task --title T6 --body '## 목표'$'\n'x | jq -r .task_id)"
t7="$(bash "$ADAPTER" create_task --title T7 --body '## 목표'$'\n'y | jq -r .task_id)"
out4="$(drain)"
chk "scope 없음 deferred=0" "$(printf '%s' "$out4" | jq -r .deferred)" "0"
chk "scope 없음 실행 2건" "$(wc -l < execlog | tr -d ' ')" "2"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
