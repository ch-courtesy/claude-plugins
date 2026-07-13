#!/usr/bin/env bash
# test-loop-scope-dir-notation.sh
#
# 회귀 가드 (#584): loop scope 게이트가 후행 '/' 디렉토리 표기 include/exclude 항목을
# prefix(디렉토리 하위 전체) 매칭으로 수용해야 한다. 그래야 scope-coverage 검사가 제안하는
# 디렉토리 표기(`plugins/autopilot/task-backend/tests/` 등)를 그대로 scope.include 에 넣어도
# 그 아래 파일 수정이 false scope-violation HALT 를 내지 않는다.
#
# 동시에 기존 표기(글롭 `**`·정확 파일 경로)의 판정 동작은 회귀 없이 유지되어야 한다.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SH="$SCRIPT_DIR/../../../plugins/autopilot/skills/loop/references/loop.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git 미설치"; exit 0; }
command -v yq  >/dev/null 2>&1 || { echo "SKIP: yq 미설치"; exit 0; }

# loop.sh 를 source 해 함수만 사용 (dispatcher 는 BASH_SOURCE guard 로 비실행).
# shellcheck source=../../../plugins/autopilot/skills/loop/references/loop.sh
source "$LOOP_SH"
set +e   # loop.sh 가 켠 errexit 해제 — 테스트가 조건 분기를 직접 제어

fail() { echo "FAIL: $1"; exit 1; }

# --- Part A: path_matches_pattern 단위 판정 -------------------------------------
# in(0)/out(1) 판정을 문자열로 단정.
check() {
  local file="$1" pat="$2" want="$3" desc="$4"
  path_matches_pattern "$file" "$pat"; local got=$?
  [[ "$got" -eq "$want" ]] || fail "$desc — path_matches_pattern '$file' '$pat' = $got, 기대 $want"
}

# 후행 '/' 디렉토리 표기: 직속·하위 깊이 파일 모두 매치.
check "plugins/autopilot/task-backend/tests/test-filesystem.sh" "plugins/autopilot/task-backend/tests/" 0 "디렉토리 직속 파일"
check "tests/autopilot/execute-task/sub/deep.sh"                "tests/autopilot/execute-task/"          0 "디렉토리 하위 깊이 파일"
# 후행 '/' 디렉토리는 접두 문자열만 같은 형제 경로를 매치하지 않음.
check "tests-foo/x.sh"                                          "tests/"                                 1 "형제 디렉토리 비매치"
check "tests"                                                  "tests/"                                 1 "디렉토리명 자체(파일 아님) 비매치"

# 기존 글롭 표기 회귀: '**' 는 하위 매치, 비매치는 out.
check "app/main.py"        "app/**" 0 "글롭 ** 하위 매치"
check "other/main.py"      "app/**" 1 "글롭 ** 범위 밖 비매치"
# 기존 정확 파일 경로 회귀.
check "lib/beta.py"        "lib/beta.py" 0 "정확 경로 매치"
check "lib/other.py"       "lib/beta.py" 1 "정확 경로 비매치"

echo "PASS(A): path_matches_pattern 디렉토리 표기 prefix + 글롭·정확경로 회귀"

# --- Part B: diff_vs_scope 통합 — 디렉토리 표기 include 아래 커밋은 위반 아님 ------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo"
( cd "$repo"
  git init -q
  git config user.email t@e.com
  git config user.name T
  mkdir -p pkg/tests
  echo "base" > README.md
  git add README.md
  git commit -q -m "base" --no-verify
) || fail "repo 셋업 실패"

base_sha="$(cd "$repo" && git rev-parse HEAD)"

SPEC_PATH="$tmp/spec.md"
cat > "$SPEC_PATH" <<'SPEC'
---
scope:
  include:
    - pkg/tests/
  exclude:
    - rules/**
---
# 제목
SPEC

# diff_vs_scope 가 참조하는 워크트리 전역.
WT="$repo"

# 디렉토리 표기 include 아래 파일을 커밋 → in-scope 여야 함(위반 출력 없음).
( cd "$repo"
  echo "print('x')" > pkg/tests/test_x.py
  git add pkg/tests/test_x.py
  git commit -q -m "feat: in-dir file" --no-verify
) || fail "in-scope 커밋 실패"

_SCOPE_YAML_KEY=""   # 캐시 무효화
viol="$(diff_vs_scope "$base_sha")"
[[ -z "$viol" ]] || fail "디렉토리 표기 include 아래 파일이 scope 위반으로 오탐: [$viol]"

echo "PASS(B): diff_vs_scope 디렉토리 표기 include 아래 파일 in-scope"
echo "PASS: #584 scope 게이트 디렉토리 표기 수용"
