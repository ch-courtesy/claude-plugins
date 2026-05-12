#!/usr/bin/env bash
# test-loop-pr-phase.sh — loop DONE 이후 PR 생성·재사용 phase 단위·e2e 테스트
#
# 검증 대상:
# - `request_review` opt-in 감지 + skip 경로 (AC1)
# - 메타 플래그 미지정: --reviewer/--label/--assignee 없음 (AC7)
# - (후속 이터: default branch 감지 실패 abort, body 합성, open PR 재사용, push 실패 등)
#
# 모든 외부 호출(gh·git push)은 stub binary로 격리해 네트워크·원격 접근을 발생시키지 않음.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_REFS="$REPO_ROOT/plugins/autopilot/skills/loop/references"
LOOP_SH_SRC="$SKILL_REFS/loop.sh"

[[ -x "$LOOP_SH_SRC" ]] || { echo "FAIL: loop.sh 실행 불가"; exit 1; }

# 임시 작업 공간
WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf $WORK_DIR" EXIT

command -v yq >/dev/null || { echo "SKIP: yq 미설치"; exit 0; }

# ----- 공용 헬퍼 -----

# 가짜 프로젝트 repo 생성 (bare repo를 origin으로 부착해 push가 실제 네트워크에 안 나감)
make_project_with_remote() {
  local name="$1"
  local project="$WORK_DIR/$name"
  local bare="$WORK_DIR/$name.git"

  git init -q --bare "$bare"
  mkdir -p "$project"
  cd "$project"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git remote add origin "$bare"
  git commit --allow-empty -q -m "initial"
  git commit --allow-empty -q -m "chore: baseline"
  git push -q origin master 2>/dev/null || git push -q origin main 2>/dev/null || git push -q origin HEAD
  cd - >/dev/null

  echo "$project"
}

# 매번 새 mock bin 디렉토리 — claude·gh·git push wrapper를 자유롭게 분리 설치
make_mock_bin() {
  local name="$1"
  local d="$WORK_DIR/$name"
  mkdir -p "$d"
  echo "$d"
}

# 단순 claude mock — stdin 소비 + DONE 작성 + JSON 응답
install_claude_done_mock() {
  local mock_bin="$1"
  cat > "$mock_bin/claude" <<'CLAUDE_EOF'
#!/usr/bin/env bash
cat > /dev/null
touch DONE
echo '{"result": "mock", "usage": {"input_tokens": 1, "output_tokens": 1}}'
CLAUDE_EOF
  chmod +x "$mock_bin/claude"
}

# gh mock — 모든 호출의 argv를 LOG_FILE에 한 줄씩 기록. PR URL stub을 stdout으로 반환.
# 환경변수 GH_LOG_FILE 경로에 호출 인자 기록.
# 환경변수 GH_OPEN_PR_NUMBER 가 비어있지 않으면 `pr list` 출력에 그 PR을 포함시킴.
install_gh_record_mock() {
  local mock_bin="$1"
  cat > "$mock_bin/gh" <<'GH_EOF'
#!/usr/bin/env bash
# argv 기록
if [[ -n "${GH_LOG_FILE:-}" ]]; then
  # 공백·따옴표 보존을 위해 NUL 구분으로도 적지만, 단순 테스트 용도는 한 줄 join으로 충분
  printf '%s\n' "$*" >> "$GH_LOG_FILE"
fi

case "${1:-}" in
  repo)
    # gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
    # 기본 brach 응답
    if [[ "${2:-}" == "view" ]]; then
      echo "${GH_DEFAULT_BRANCH:-main}"
      exit 0
    fi
    ;;
  pr)
    case "${2:-}" in
      list)
        # pr list --head <branch> --state open --json number,url
        if [[ -n "${GH_OPEN_PR_NUMBER:-}" ]]; then
          printf '[{"number":%s,"url":"%s","title":"%s","body":"%s"}]\n' \
            "$GH_OPEN_PR_NUMBER" "${GH_OPEN_PR_URL:-https://github.example/x/y/pull/$GH_OPEN_PR_NUMBER}" \
            "${GH_OPEN_PR_TITLE:-existing title}" "${GH_OPEN_PR_BODY:-existing body}"
        else
          echo '[]'
        fi
        exit 0
        ;;
      view)
        if [[ -n "${GH_OPEN_PR_NUMBER:-}" ]]; then
          printf '{"number":%s,"url":"%s","title":"%s","body":"%s"}\n' \
            "$GH_OPEN_PR_NUMBER" "${GH_OPEN_PR_URL:-https://github.example/x/y/pull/$GH_OPEN_PR_NUMBER}" \
            "${GH_OPEN_PR_TITLE:-existing title}" "${GH_OPEN_PR_BODY:-existing body}"
          exit 0
        fi
        echo "no pr" >&2
        exit 1
        ;;
      create)
        # PR URL을 stdout으로 출력 (실제 gh의 동작 모방)
        echo "${GH_PR_URL:-https://github.example/x/y/pull/1}"
        exit 0
        ;;
      edit)
        exit 0
        ;;
    esac
    ;;
esac
exit 0
GH_EOF
  chmod +x "$mock_bin/gh"
}

echo "=== TEST 1: AC1 — request_review 미지정 시 PR phase skip (gh 호출 0회) ==="
T1_NAME="optout-no-key"
T1_PROJECT="$(make_project_with_remote "$T1_NAME")"
T1_MOCK="$(make_mock_bin "${T1_NAME}-mock")"
install_claude_done_mock "$T1_MOCK"
install_gh_record_mock "$T1_MOCK"
T1_GH_LOG="$WORK_DIR/${T1_NAME}-gh.log"
: > "$T1_GH_LOG"

mkdir -p "$T1_PROJECT/milestones/regular/loops/optout-task"
cat > "$T1_PROJECT/milestones/regular/loops/optout-task/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Opt-out Task

## 무엇을 만들 것인가
opt-out 검증용.
EOF

(
  cd "$T1_PROJECT"
  GH_LOG_FILE="$T1_GH_LOG" PATH="$T1_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "optout-task" > "$WORK_DIR/${T1_NAME}.out" 2>&1
)

# gh 호출이 0회여야 함
[[ -f "$T1_GH_LOG" ]] || { echo "FAIL: gh log 파일 없음"; exit 1; }
gh_calls_t1=$(wc -l < "$T1_GH_LOG" | tr -d ' ')
[[ "$gh_calls_t1" -eq 0 ]] \
  || { echo "FAIL: opt-out인데 gh가 ${gh_calls_t1}회 호출됨. log:"; cat "$T1_GH_LOG"; exit 1; }

# DONE은 정상 생성됐어야 (기존 동작 회귀)
[[ -f "$T1_PROJECT/milestones/regular/loops/optout-task/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 2: AC2 + AC7 — request_review: true 시 gh pr create 호출 + 메타 플래그 미지정 ==="
T2_NAME="optin-meta-clean"
T2_PROJECT="$(make_project_with_remote "$T2_NAME")"
T2_MOCK="$(make_mock_bin "${T2_NAME}-mock")"
install_claude_done_mock "$T2_MOCK"
install_gh_record_mock "$T2_MOCK"
T2_GH_LOG="$WORK_DIR/${T2_NAME}-gh.log"
: > "$T2_GH_LOG"

mkdir -p "$T2_PROJECT/milestones/regular/loops/optin-task"
cat > "$T2_PROJECT/milestones/regular/loops/optin-task/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Opt-in Task

## 무엇을 만들 것인가
opt-in 검증용 task.
EOF

(
  cd "$T2_PROJECT"
  GH_LOG_FILE="$T2_GH_LOG" PATH="$T2_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "optin-task" > "$WORK_DIR/${T2_NAME}.out" 2>&1
)

# gh가 호출됐어야 (≥1회)
[[ -f "$T2_GH_LOG" ]] || { echo "FAIL: gh log 없음"; exit 1; }
gh_calls_t2=$(wc -l < "$T2_GH_LOG" | tr -d ' ')
[[ "$gh_calls_t2" -ge 1 ]] \
  || { echo "FAIL: opt-in인데 gh 미호출. log empty"; exit 1; }

# gh pr create 가 최소 1번 호출됐어야
grep -qE '^pr create ' "$T2_GH_LOG" \
  || { echo "FAIL: gh pr create 호출 기록 없음. log:"; cat "$T2_GH_LOG"; exit 1; }

# 메타 플래그 미지정 — AC7
if grep -qE '(--reviewer|--label|--assignee)' "$T2_GH_LOG"; then
  echo "FAIL: gh 호출에 메타 플래그가 포함됨 (AC7 위반). log:"; cat "$T2_GH_LOG"; exit 1
fi

# DONE 유지
[[ -f "$T2_PROJECT/milestones/regular/loops/optin-task/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 PR phase 테스트 통과 ==="
