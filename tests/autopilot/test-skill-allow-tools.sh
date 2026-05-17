#!/usr/bin/env bash
# autopilot:spec·autopilot:loop SKILL.md frontmatter 권한 허용 패턴 정적 검증
#
# SPEC `milestones/regular/loops/113-spec-loop-skill-md-frontmatter/SPEC.md` AC1~AC8.
# enumerate 패턴 frozen reference는 issue #113 본문(SPEC 작성 시점) 그대로 임베드.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SPEC_MD="$REPO_ROOT/plugins/autopilot/skills/spec/SKILL.md"
LOOP_MD="$REPO_ROOT/plugins/autopilot/skills/loop/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

# 의존 도구
command -v yq      >/dev/null || { echo "SKIP: yq 미설치"; exit 0; }
command -v python3 >/dev/null || { echo "SKIP: python3 미설치"; exit 0; }

[[ -f "$SPEC_MD" ]] || fail "spec/SKILL.md 부재: $SPEC_MD"
[[ -f "$LOOP_MD" ]] || fail "loop/SKILL.md 부재: $LOOP_MD"

# ---------------------------------------------------------------------------
# frontmatter 추출 (첫 `---` 다음 ~ 두 번째 `---` 직전)
extract_frontmatter() {
  awk 'BEGIN{c=0} /^---$/{c++; if(c>=2) exit; next} c==1{print}' "$1"
}

# allowed-tools를 line별 항목으로 반환. 입력이 배열이 아니면 비어 있을 수 있다.
list_tools() {
  extract_frontmatter "$1" | yq -o=json '.allowed-tools' 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
if not isinstance(data, list):
    sys.exit(0)
for item in data:
    print(item)
'
}

# allowed-tools가 YAML 배열인지 확인
is_array() {
  extract_frontmatter "$1" | yq -o=json '.allowed-tools' 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if isinstance(data, list) else 1)
'
}

# ---------------------------------------------------------------------------
echo "=== TEST: AC3 (YAML parse 성공) + AC1·AC2 (frontmatter 배열 포함) ==="
is_array "$SPEC_MD" || fail "AC1·AC3: spec/SKILL.md frontmatter의 allowed-tools가 YAML 배열로 parse되지 않음"
ok "AC1·AC3: spec/SKILL.md allowed-tools가 YAML 배열로 parse됨"

is_array "$LOOP_MD" || fail "AC2·AC3: loop/SKILL.md frontmatter의 allowed-tools가 YAML 배열로 parse되지 않음"
ok "AC2·AC3: loop/SKILL.md allowed-tools가 YAML 배열로 parse됨"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST: AC4 (catch-all 패턴 없음) ==="
check_no_catchall() {
  local md="$1" label="$2"
  local tools; tools=$(list_tools "$md")
  if grep -qFx 'Bash(*)' <<< "$tools"; then
    fail "$label: 'Bash(*)' catch-all 패턴 포함"
  fi
  if grep -qFx '*' <<< "$tools"; then
    fail "$label: '*' 단독 catch-all 패턴 포함"
  fi
  ok "$label: catch-all 패턴 없음"
}
check_no_catchall "$SPEC_MD" "spec/SKILL.md"
check_no_catchall "$LOOP_MD" "loop/SKILL.md"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST: AC5 (gh pr 외 모든 gh prefix 패턴 없음) ==="
check_no_gh_except_pr() {
  local md="$1" label="$2"
  local tools; tools=$(list_tools "$md")
  while IFS= read -r tool; do
    [[ -z "$tool" ]] && continue
    # Bash(gh ...) 또는 Bash(gh:...) 형식 검출
    if [[ "$tool" =~ Bash\(gh[\ :] ]]; then
      # gh pr 인지 확인 (Bash(gh pr ...) 또는 Bash(gh pr))
      if ! [[ "$tool" =~ Bash\(gh\ pr(\ |\)) ]]; then
        fail "$label: gh pr 외 gh 패턴 포함 — $tool"
      fi
    fi
  done <<< "$tools"
  ok "$label: gh pr 외 gh 패턴 없음"
}
check_no_gh_except_pr "$SPEC_MD" "spec/SKILL.md"
check_no_gh_except_pr "$LOOP_MD" "loop/SKILL.md"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST: AC6 (배열 내 중복 없음) ==="
check_no_dupes() {
  local md="$1" label="$2"
  local tools; tools=$(list_tools "$md")
  local dup; dup=$(echo "$tools" | sort | uniq -d)
  if [[ -n "$dup" ]]; then
    fail "$label: 중복 항목 — $dup"
  fi
  ok "$label: 중복 없음"
}
check_no_dupes "$SPEC_MD" "spec/SKILL.md"
check_no_dupes "$LOOP_MD" "loop/SKILL.md"

# ---------------------------------------------------------------------------
# AC7·AC8: issue #113 본문 enumerate 패턴 (frozen reference)

# autopilot:spec 섹션
SPEC_SECTION=(
  'Bash(git -C * rev-parse *)'
  'Bash(git -C * status --porcelain)'
  'Bash(git -C * log *)'
  'Bash(git -C * branch *)'
  'Bash(git -C * show-ref *)'
  'Bash(git -C * for-each-ref *)'
  'Bash(git -C * ls-files *)'
  'Bash(git -C * diff *)'
  'Bash(git -C * checkout *)'
  'Bash(git -C * checkout -b *)'
  'Bash(git -C * add *)'
  'Bash(git -C * commit *)'
  'Bash(git update-ref *)'
  'Bash(git branch *)'
  'Bash(git -C * hash-object -w *)'
  'Bash(GIT_INDEX_FILE=* git -C * read-tree *)'
  'Bash(GIT_INDEX_FILE=* git -C * update-index --add --cacheinfo *)'
  'Bash(GIT_INDEX_FILE=* git -C * write-tree)'
  'Bash(git -C * commit-tree * -p *)'
  'Bash(mkdir -p milestones/**)'
  'Bash(awk *)'
  'Bash(sed *)'
  'Bash(tr *)'
  'Bash(grep -rE * plugins/autopilot/**)'
  'Bash(grep -rln * plugins/autopilot/**)'
)

# autopilot:loop 섹션
LOOP_SECTION=(
  'Bash(bash * loop.sh start *)'
  'Bash(bash * loop.sh status *)'
  'Bash(bash * loop.sh stop *)'
  'Bash(bash * loop.sh list)'
  'Bash(bash * loop.sh cleanup *)'
  'Bash(bash * loop.sh logs *)'
  'Bash(tail -F /private/tmp/* | grep -E --line-buffered *)'
)

# 공통·보조 섹션 (spec·loop 모두 필요)
COMMON_SECTION=(
  'Bash(git -C * stash list)'
  'Bash(git -C * stash pop *)'
  'Bash(git -C * stash show *)'
  'Bash(rm */ESCALATION.md)'
  'Bash(rm */DONE)'
  'Bash(ps -p *)'
  'Bash(cat */*.lock)'
)

check_required_patterns() {
  local md="$1" label="$2"
  shift 2
  local required=("$@")
  local tools; tools=$(list_tools "$md")
  local missing=()
  for pattern in "${required[@]}"; do
    if ! grep -qFx "$pattern" <<< "$tools"; then
      missing+=("$pattern")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    printf 'FAIL: %s 누락 패턴:\n' "$label" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
  fi
  ok "$label: 필수 패턴 ${#required[@]}개 모두 포함"
}

echo ""
echo "=== TEST: AC7 (spec/SKILL.md = spec 섹션 + 공통·보조) ==="
check_required_patterns "$SPEC_MD" "spec/SKILL.md" \
  "${SPEC_SECTION[@]}" "${COMMON_SECTION[@]}"

echo ""
echo "=== TEST: AC8 (loop/SKILL.md = loop 섹션 + 공통·보조) ==="
check_required_patterns "$LOOP_MD" "loop/SKILL.md" \
  "${LOOP_SECTION[@]}" "${COMMON_SECTION[@]}"

echo ""
echo "PASS"
