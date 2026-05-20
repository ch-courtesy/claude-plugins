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

# 단순 claude mock — stdin 소비 + DONE 작성 + (SPEC 175) loop:done label 시그널 발행
# + JSON 응답.
# 두 가지 호출 경로를 stdin 매칭으로 분기:
#  - 통상 task 이터: DONE 파일 + LOOP_DONE_LABEL 라벨 시그널 (SPEC 175 단일 검출 키).
#  - rebase/merge 충돌 자동 해소 (SPEC 169 rebase-phase.sh resolve_conflicts_via_claude):
#    stdin 에 "git rebase conflict" / "git merge conflict" prompt 가 포함됨. MOCK_CLAUDE_REBASE_FAIL=1
#    인 경우 비-zero exit (TEST 13 자동 해소 실패 경로), 아니면 unresolved 파일 ours 선택 + add
#    + GIT_CONFLICT_RESOLVED_FILE flag touch (mock git pass-through 트리거 — TEST 12).
# SPEC 175 이후 완료 검출은 task issue 의 LOOP_DONE_LABEL 단일 의존이므로, 단순히
# DONE 파일만 생성해서는 loop.sh 가 완료를 인지하지 못한다. mock gh (install_gh_record_mock)
# 가 GH_LABEL_FILE 에 라벨을 누적 기록하도록 `gh issue edit 99 --add-label loop:done` 호출.
install_claude_done_mock() {
  local mock_bin="$1"
  cat > "$mock_bin/claude" <<'CLAUDE_EOF'
#!/usr/bin/env bash
stdin_buf=$(cat)
if printf '%s' "$stdin_buf" | grep -qE "git rebase conflict|git merge conflict"; then
  # SPEC 169 rebase-phase 가 호출 — 자동 해소 1회 시뮬레이션.
  if [[ "${MOCK_CLAUDE_REBASE_FAIL:-0}" == "1" ]]; then
    echo "mock claude: 충돌 해소 실패 (시뮬레이션 — MOCK_CLAUDE_REBASE_FAIL=1)" >&2
    exit 1
  fi
  # unresolved 파일을 모두 ours 채택 + git add (real git 으로 passthrough — mock git 의
  # rebase 분기는 'rebase' subcommand 만 가로채므로 checkout/add 는 real git 이 처리).
  unresolved=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
  if [[ -n "$unresolved" ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      git checkout --ours -- "$f" 2>/dev/null || true
      git add -- "$f" 2>/dev/null || true
    done <<< "$unresolved"
  fi
  # mock git 의 rebase --continue pass-through 트리거 (TEST 12 만 export).
  [[ -n "${GIT_CONFLICT_RESOLVED_FILE:-}" ]] && touch "$GIT_CONFLICT_RESOLVED_FILE"
else
  # 통상 task 이터.
  touch DONE
  # SPEC 175 단일 검출 키 — mock gh 가 같은 PATH 에 설치되어 있어야 함 (테스트 setup 책임).
  gh issue edit 99 --add-label "${LOOP_DONE_LABEL:-loop:done}" >/dev/null 2>&1 || true
fi
echo '{"result": "mock", "usage": {"input_tokens": 1, "output_tokens": 1}}'
CLAUDE_EOF
  chmod +x "$mock_bin/claude"
}

# 각 테스트 setup 마다 호출 — GH_LABEL_FILE 환경 변수에 빈 파일 경로를 export 한다.
# mock claude 의 `gh issue edit` 가 라벨을 append 하고, mock gh 의 `issue view --json labels`
# 가 그 내용을 출력해 loop.sh task_status_is_done 이 완료를 인지한다.
# 사용: init_done_label_signal <TEST_NAME>  → 표준출력으로 라벨 파일 경로 (export 는 caller 책임).
init_done_label_signal() {
  local test_name="$1"
  local label_file="$WORK_DIR/${test_name}-labels"
  : > "$label_file"
  echo "$label_file"
}

# gh mock — 모든 호출의 argv를 LOG_FILE에 한 줄씩 기록. PR URL stub을 stdout으로 반환.
# 환경변수 GH_LOG_FILE 경로에 호출 인자 기록 (한 줄/호출 — 공백 join, multiline body는 잘림).
# 환경변수 GH_CALL_DIR 가 지정되면 호출별 argv 전체를 한 줄/인자 형식으로 디렉토리에 덤프
#   (multiline --body 보존 — 본 디렉토리 사용 필수 시 본문 inspection 가능).
# 환경변수 GH_OPEN_PR_NUMBER 가 비어있지 않으면 `pr list`·`pr view` 출력에 그 PR을 포함.
# 환경변수 GH_REPO_VIEW_FAIL=1 — `repo view` 호출 시 exit 1 (default branch 감지 실패 시뮬레이션).
# 환경변수 GH_FAIL_PR_CREATE=1 — `pr create` 호출 시 exit 1 + stderr 에러 (AC8 시뮬레이션).
# 환경변수 GH_FAIL_PR_EDIT=1 — `pr edit` 호출 시 exit 1 + stderr 에러 (AC8 시뮬레이션).
install_gh_record_mock() {
  local mock_bin="$1"
  cat > "$mock_bin/gh" <<'GH_EOF'
#!/usr/bin/env bash
# argv 기록 (단일 라인)
if [[ -n "${GH_LOG_FILE:-}" ]]; then
  # 공백·따옴표 보존을 위해 NUL 구분으로도 적지만, 단순 테스트 용도는 한 줄 join으로 충분
  printf '%s\n' "$*" >> "$GH_LOG_FILE"
fi

# 호출별 argv 덤프 (한 줄/인자 — multiline --body 보존)
if [[ -n "${GH_CALL_DIR:-}" ]]; then
  mkdir -p "$GH_CALL_DIR"
  __gh_idx=$(ls "$GH_CALL_DIR" 2>/dev/null | wc -l | tr -d ' ')
  __gh_idx=$((__gh_idx + 1))
  __gh_sub1="${1:-_}"
  __gh_sub2="${2:-_}"
  __gh_file=$(printf '%s/%03d-%s-%s.argv' "$GH_CALL_DIR" "$__gh_idx" "$__gh_sub1" "$__gh_sub2")
  printf '%s\n' "$@" > "$__gh_file"
fi

case "${1:-}" in
  issue)
    # SPEC 175: loop.sh task_status_is_done · task_issue_number · halt 의 gh issue 호출 처리.
    # `GH_LABEL_FILE` 환경 변수가 가리키는 파일에 라벨이 한 줄씩 누적되며 mock claude 의
    # `gh issue edit --add-label` 이 추가하고 `gh issue view --json labels` 가 출력한다.
    case "${2:-}" in
      list)
        # gh issue list --search <q> --json number [--jq '.[0].number']
        # task_issue_number 가 --jq '.[0].number' 로 단일 숫자만 추출하는 경로를 직접 모방.
        __want_first_num=0
        for __arg in "$@"; do
          case "$__arg" in
            ".[0].number"|"--jq=.[0].number") __want_first_num=1 ;;
          esac
        done
        if [[ $__want_first_num -eq 1 ]]; then
          echo "${GH_TASK_ISSUE_NUMBER:-99}"
        else
          printf '[{"number":%s}]\n' "${GH_TASK_ISSUE_NUMBER:-99}"
        fi
        exit 0
        ;;
      view)
        # gh issue view <num> [--json labels --jq '.labels[].name' | --comments | --json comments ...]
        __want_labels=0
        __want_comments=0
        for __arg in "$@"; do
          case "$__arg" in
            ".labels[].name"|"--jq=.labels[].name") __want_labels=1 ;;
            --comments) __want_comments=1 ;;
            ".comments"|"--jq=.comments"|".comments | last | .body"|"--jq=.comments | last | .body") __want_comments=1 ;;
          esac
        done
        if [[ $__want_labels -eq 1 ]]; then
          if [[ -n "${GH_LABEL_FILE:-}" && -f "${GH_LABEL_FILE}" ]]; then
            cat "$GH_LABEL_FILE"
          fi
          exit 0
        fi
        if [[ $__want_comments -eq 1 ]]; then
          # 빈 출력 — task_status_is_blocked / cmd_logs 무해 응답
          exit 0
        fi
        # 기본 view — 빈 본문
        echo ""
        exit 0
        ;;
      edit)
        # gh issue edit <num> --add-label <label>
        __next_label=0
        for __arg in "$@"; do
          if [[ $__next_label -eq 1 ]]; then
            [[ -n "${GH_LABEL_FILE:-}" ]] && printf '%s\n' "$__arg" >> "$GH_LABEL_FILE"
            __next_label=0
          elif [[ "$__arg" == "--add-label" ]]; then
            __next_label=1
          fi
        done
        exit 0
        ;;
      comment)
        # halt() 의 gh issue comment — argv 는 이미 위에서 LOG_FILE / CALL_DIR 에 덤프됨.
        exit 0
        ;;
    esac
    ;;
  label)
    # gh label list --search <l> --json name --jq '.[].name' | label create
    case "${2:-}" in
      list)
        # 빈 응답 — ensure_label_exists 가 create 시도하도록 (그리고 create 도 0 exit 으로 처리).
        exit 0
        ;;
      create)
        exit 0
        ;;
    esac
    ;;
  repo)
    # gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
    # 기본 branch 응답 (또는 GH_REPO_VIEW_FAIL=1 시 exit 1)
    if [[ "${2:-}" == "view" ]]; then
      if [[ "${GH_REPO_VIEW_FAIL:-0}" == "1" ]]; then
        echo "repo view error: forbidden (mock)" >&2
        exit 1
      fi
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
        # M4/AC5: state/reviewDecision 쿼리는 GH_OPEN_PR_NUMBER 여부와 무관하게 응답한다
        # (monitor 단계가 새 PR·기존 PR 양쪽에서 동일하게 호출).
        __want_state=0
        __want_review=0
        for __arg in "$@"; do
          case "$__arg" in
            .state|--jq=.state) __want_state=1;;
            .reviewDecision|--jq=.reviewDecision) __want_review=1;;
          esac
        done
        if [[ $__want_state -eq 1 ]]; then
          printf '%s\n' "${GH_PR_STATE:-OPEN}"
          exit 0
        fi
        if [[ $__want_review -eq 1 ]]; then
          # 빈 값(리뷰 미발생) 또는 GH_PR_REVIEW_DECISION (APPROVED/CHANGES_REQUESTED 등)
          printf '%s\n' "${GH_PR_REVIEW_DECISION:-}"
          exit 0
        fi
        if [[ -n "${GH_OPEN_PR_NUMBER:-}" ]]; then
          # --jq '.body' (또는 --jq=.body) 가 있으면 body 텍스트만 출력 (실제 gh의 jq 적용 모방).
          # 그래야 pr-phase.sh가 fence 마커 부분 교체 경로를 실제로 실행한다.
          want_body=0
          for arg in "$@"; do
            case "$arg" in
              .body|--jq=.body) want_body=1;;
            esac
          done
          if [[ $want_body -eq 1 ]]; then
            printf '%s\n' "${GH_OPEN_PR_BODY:-existing body}"
          else
            printf '{"number":%s,"url":"%s","title":"%s","body":"%s"}\n' \
              "$GH_OPEN_PR_NUMBER" "${GH_OPEN_PR_URL:-https://github.example/x/y/pull/$GH_OPEN_PR_NUMBER}" \
              "${GH_OPEN_PR_TITLE:-existing title}" "${GH_OPEN_PR_BODY:-existing body}"
          fi
          exit 0
        fi
        echo "no pr" >&2
        exit 1
        ;;
      checks)
        # M4/AC5: monitor PR check 쿼리·재트리거.
        # `--rerun` 포함 시 단순 exit 0 (실제 재트리거는 외부 — 테스트는 호출 행적만 검증).
        # 미포함 시 `--json state,conclusion` 쿼리 응답: GH_CHECKS_MODE=stuck 이면 모든 check가
        # COMPLETED 상태로 보고(=stuck 가능 상태), 그 외엔 빈 배열 (=stuck 아님 → monitor 종료).
        __is_rerun=0
        for __arg in "$@"; do
          [[ "$__arg" == "--rerun" ]] && __is_rerun=1
        done
        if [[ $__is_rerun -eq 1 ]]; then
          exit 0
        fi
        case "${GH_CHECKS_MODE:-}" in
          stuck)
            printf '[{"state":"COMPLETED","conclusion":"FAILURE"}]\n'
            ;;
          waiting)
            # 환경 보호 승인 대기 — stuck 아님 (regression: WAITING이 진행 상태 패턴에
            # 누락돼 stuck으로 오판되던 버그 보호)
            printf '[{"state":"WAITING","conclusion":null}]\n'
            ;;
          *)
            printf '[]\n'
            ;;
        esac
        exit 0
        ;;
      create)
        if [[ "${GH_FAIL_PR_CREATE:-0}" == "1" ]]; then
          echo "gh pr create failed (mock: boom-create)" >&2
          exit 1
        fi
        # PR URL을 stdout으로 출력 (실제 gh의 동작 모방)
        echo "${GH_PR_URL:-https://github.example/x/y/pull/1}"
        exit 0
        ;;
      edit)
        if [[ "${GH_FAIL_PR_EDIT:-0}" == "1" ]]; then
          echo "gh pr edit failed (mock: boom-edit)" >&2
          exit 1
        fi
        exit 0
        ;;
    esac
    ;;
esac
exit 0
GH_EOF
  chmod +x "$mock_bin/gh"
}

# git mock — argv를 GIT_LOG_FILE 환경변수 경로에 한 줄씩 기록한 뒤 실제 git으로 위임.
# pr-phase.sh가 push 직전에 origin base를 fetch + rebase하는지 행적 검증할 때 사용한다.
# 실제 git 절대경로를 install 시점에 baked in 해서 mock_bin이 PATH 앞에 와도 무한 recurse 안 됨.
#
# 추가 환경변수:
#   GIT_CONFLICT_MODE — rebase 충돌 시뮬레이션 모드 (M3/AC4 테스트용).
#     - 미설정·빈값: pass-through (충돌 없음 — 기존 TEST 11 회귀 보존)
#     - "auto-resolve": 평범한 `rebase origin/...`은 conflict로 실패시키지만, 재시도 인자 `-X`가
#         포함된 `rebase -X theirs origin/...`는 real git으로 위임해 성공 (M3 자동 해결 성공 경로)
#     - "abort": `-X` 포함 여부와 무관하게 모든 `rebase origin/...` 호출이 conflict로 실패
#         (M3 자동 해결 실패 → 사용자 좌절 경로)
#   `rebase --abort` 호출은 양 모드에서 stub 안에서 pass-through하며 real git이 rebase 진행
#   상태가 아니라 실패해도 무시한다 (실제 충돌 상태를 만들지 않으므로).
install_git_record_mock() {
  local mock_bin="$1"
  local real_git
  real_git="$(command -v git)"
  [[ -x "$real_git" ]] || { echo "FAIL: real git 경로 못 찾음 (command -v git 실패)"; exit 1; }
  cat > "$mock_bin/git" <<GIT_EOF
#!/usr/bin/env bash
if [[ -n "\${GIT_LOG_FILE:-}" ]]; then
  printf '%s\n' "\$*" >> "\$GIT_LOG_FILE"
fi

# rebase 충돌 시뮬레이션 (M3/AC4 — GIT_CONFLICT_MODE 설정 시)
if [[ "\${1:-}" == "rebase" && -n "\${GIT_CONFLICT_MODE:-}" ]]; then
  # --abort는 항상 pass-through (real git이 rebase 상태 아니라 fail해도 무시)
  is_abort=0
  is_x=0
  is_continue=0
  for a in "\$@"; do
    [[ "\$a" == "--abort" ]] && is_abort=1
    [[ "\$a" == "-X" ]] && is_x=1
    [[ "\$a" == "--continue" ]] && is_continue=1
  done

  if [[ \$is_abort -eq 1 ]]; then
    "$real_git" "\$@" 2>/dev/null || true
    exit 0
  fi

  # SPEC 169 mock 경로: mock claude 가 자동 해소 후 GIT_CONFLICT_RESOLVED_FILE 를 touch
  # 했으면 후속 rebase --continue 를 fake-success 로 처리. real git 의 rebase 상태가 없어
  # passthrough 가 실패하므로 mock 이 직접 0 exit (assertion 은 git log 호출 행적만 검사).
  if [[ -n "\${GIT_CONFLICT_RESOLVED_FILE:-}" && -f "\${GIT_CONFLICT_RESOLVED_FILE}" ]]; then
    if [[ \$is_continue -eq 1 ]]; then
      echo "Successfully rebased (mock — claude 해소 후 --continue)"
      exit 0
    fi
  fi

  case "\$GIT_CONFLICT_MODE" in
    auto-resolve)
      if [[ \$is_x -eq 1 ]]; then
        # SPEC 103 legacy 경로(-X theirs 재시도)는 real git으로 위임 — SPEC 169 이후엔
        # 사용되지 않지만 호환성 유지.
        exec "$real_git" "\$@"
      else
        # 첫 평범한 rebase는 충돌로 실패
        echo "CONFLICT (content): Merge conflict simulated (mock — auto-resolve mode)" >&2
        exit 1
      fi
      ;;
    abort)
      # 모든 rebase 시도가 실패 (자동 해결도 실패)
      echo "CONFLICT (content): Merge conflict simulated (mock — abort mode)" >&2
      exit 1
      ;;
  esac
fi

exec "$real_git" "\$@"
GIT_EOF
  chmod +x "$mock_bin/git"
}

# SPEC 110 + SPEC 116 단일 contract — feat/<child>-<slug> 브랜치에 SPEC.md를 commit해
# loop·pr-phase 모두 단일 contract 를 만족하도록 셋업한다.
# 사용: setup_feat_with_spec <PROJECT> <RAW_TASK_ID> [<SLUG=test>]
# 사전 조건: $PROJECT/milestones/<m>/loops/<child>-<slug>/SPEC.md 파일이 이미 존재
#            (호출자가 mkdir + cat<<EOF로 슬러그 경로에 생성).
# 동작:
#  - feat/<child>-<slug> 브랜치 생성·체크아웃
#  - 슬러그 경로 SPEC.md add+commit
#  - 원래 브랜치 복귀
# 주의:
#  - loop.sh find_feat_branch 는 child(슬래시 이후) 만으로 `feat/<child>-<slug>` 또는
#    `feat/<child>` 를 검색하므로 브랜치 이름에 milestone prefix 는 넣지 않는다 (SPEC 110 §AC1).
#  - pr-phase.sh 는 SPEC 116 단일 컨벤션으로 slug 가 비면 abort 하므로 slug 가 필수.
#    각 테스트는 호환을 위해 slug="test" 를 기본 사용 (호출자 override 허용).
setup_feat_with_spec() {
  local proj="$1"
  local task_id="$2"
  local slug="${3:-test}"
  local norm_id="$task_id"
  [[ "$norm_id" != */* ]] && norm_id="regular/$task_id"
  local mst="${norm_id%%/*}"
  local child="${norm_id#*/}"
  local loops_rel="milestones/$mst/loops/$child-$slug"
  local default_br
  default_br=$(git -C "$proj" rev-parse --abbrev-ref HEAD)
  local feat_br="feat/$child-$slug"
  if git -C "$proj" rev-parse --verify "$feat_br" >/dev/null 2>&1; then
    git -C "$proj" checkout -q "$feat_br"
  else
    git -C "$proj" checkout -q -b "$feat_br"
  fi
  git -C "$proj" add -f "$loops_rel/SPEC.md"
  git -C "$proj" commit -q -m "feat(spec): $task_id (test setup)" 2>/dev/null || true
  git -C "$proj" checkout -q "$default_br"
}

# argv 덤프 디렉토리에서 특정 subcommand 호출의 --body 인자 추출
# 사용: extract_body_from_call "<CALL_DIR>" "pr-create"  → 첫 매치 호출의 --body 값을 stdout
# gh mock은 각 argv를 한 줄씩 기록(multiline body는 여러 줄 차지)하므로 --body 라인 다음부터
# 다음 "--<flag>" 라인 또는 EOF 직전까지를 body로 본다.
extract_body_from_call() {
  local call_dir="$1"
  local pattern="$2"  # 예: "pr-create" 또는 "pr-edit"
  local f
  f=$(ls "$call_dir" 2>/dev/null | grep -F "$pattern" | head -1)
  [[ -n "$f" ]] || return 1
  awk '
    BEGIN { take = 0 }
    take == 1 {
      if (/^--[a-zA-Z]/) { exit }
      print
      next
    }
    /^--body$/ { take = 1; next }
  ' "$call_dir/$f"
}

# argv 덤프 디렉토리에서 특정 subcommand 호출의 --title 인자 추출
extract_title_from_call() {
  local call_dir="$1"
  local pattern="$2"
  local f
  f=$(ls "$call_dir" 2>/dev/null | grep -F "$pattern" | head -1)
  [[ -n "$f" ]] || return 1
  awk '
    /^--title$/ { take = 1; next }
    take == 1 { print; exit }
  ' "$call_dir/$f"
}

# argv 덤프 디렉토리에서 특정 subcommand 호출 횟수
count_calls() {
  local call_dir="$1"
  local pattern="$2"
  ls "$call_dir" 2>/dev/null | grep -cF "$pattern" || true
}

echo "=== TEST 1: AC1 — DONE 시 PR phase가 default로 실행 (request_review 키 없음) ==="
# AC1 (SPEC 103): task가 DONE 상태로 종결될 때, 시스템은 별도 opt-in 플래그 없이
# PR 생성 단계를 default로 수행한다. 기존 동작(키 미지정 → skip)은 역전됨.
T1_NAME="default-pr-on-done"
T1_PROJECT="$(make_project_with_remote "$T1_NAME")"
T1_MOCK="$(make_mock_bin "${T1_NAME}-mock")"
install_claude_done_mock "$T1_MOCK"
install_gh_record_mock "$T1_MOCK"
T1_GH_LOG="$WORK_DIR/${T1_NAME}-gh.log"
: > "$T1_GH_LOG"
T1_LABEL_FILE="$(init_done_label_signal "$T1_NAME")"

mkdir -p "$T1_PROJECT/milestones/regular/loops/default-task-test"
cat > "$T1_PROJECT/milestones/regular/loops/default-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Default PR Task

## 무엇을 만들 것인가
DONE 직후 PR 생성이 default로 실행되는지 검증.
EOF
setup_feat_with_spec "$T1_PROJECT" "default-task"

(
  cd "$T1_PROJECT"
  GH_LOG_FILE="$T1_GH_LOG" GH_LABEL_FILE="$T1_LABEL_FILE" PATH="$T1_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "default-task" > "$WORK_DIR/${T1_NAME}.out" 2>&1
)

# AC1: gh 호출이 ≥1회 (PR phase가 default로 실행됨)
[[ -f "$T1_GH_LOG" ]] || { echo "FAIL: gh log 파일 없음"; exit 1; }
gh_calls_t1=$(wc -l < "$T1_GH_LOG" | tr -d ' ')
[[ "$gh_calls_t1" -ge 1 ]] \
  || { echo "FAIL: default 동작인데 gh가 ${gh_calls_t1}회 호출 (≥1 기대). log:"; cat "$T1_GH_LOG"; echo "out:"; cat "$WORK_DIR/${T1_NAME}.out"; exit 1; }

# pr create가 호출됐어야 (PR 단계 진입 확인)
grep -qE '^pr create ' "$T1_GH_LOG" \
  || { echo "FAIL: default인데 pr create 호출 없음. log:"; cat "$T1_GH_LOG"; exit 1; }

# DONE은 정상 생성됐어야
[[ -f "$T1_PROJECT/milestones/regular/loops/default-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 1B: AC2 — --no-pr 플래그 사용 시 PR phase 건너뜀 ==="
# AC2 (SPEC 103): 사용자가 PR 자동 생성 opt-out 플래그(--no-pr)를 지정한 경우,
# 시스템은 PR 생성 단계를 건너뛴다.
T1B_NAME="no-pr-opt-out"
T1B_PROJECT="$(make_project_with_remote "$T1B_NAME")"
T1B_MOCK="$(make_mock_bin "${T1B_NAME}-mock")"
install_claude_done_mock "$T1B_MOCK"
install_gh_record_mock "$T1B_MOCK"
T1B_GH_LOG="$WORK_DIR/${T1B_NAME}-gh.log"
: > "$T1B_GH_LOG"
T1B_LABEL_FILE="$(init_done_label_signal "$T1B_NAME")"

mkdir -p "$T1B_PROJECT/milestones/regular/loops/nopr-task-test"
cat > "$T1B_PROJECT/milestones/regular/loops/nopr-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# No-PR Opt-out Task

## 무엇을 만들 것인가
--no-pr 플래그가 PR phase를 차단하는지 검증.
EOF
setup_feat_with_spec "$T1B_PROJECT" "nopr-task"

(
  cd "$T1B_PROJECT"
  GH_LOG_FILE="$T1B_GH_LOG" GH_LABEL_FILE="$T1B_LABEL_FILE" PATH="$T1B_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "nopr-task" --no-pr > "$WORK_DIR/${T1B_NAME}.out" 2>&1
)

# AC2: --no-pr이면 PR 관련 gh 호출(pr create / pr edit) 0회.
# (SPEC 175 이후 done 검출·label 보장 경로에서 issue/label gh 호출이 발생하므로
#  '전체 gh 호출 0회' assertion 은 부정확 — PR phase 진입 여부를 직접 검증한다.)
[[ -f "$T1B_GH_LOG" ]] || { echo "FAIL: gh log 파일 없음"; exit 1; }
if grep -qE '^(pr create|pr edit) ' "$T1B_GH_LOG"; then
  echo "FAIL: --no-pr인데 PR 호출(create/edit)이 기록됨. log:"; cat "$T1B_GH_LOG"; exit 1
fi

# DONE은 정상 생성됐어야
[[ -f "$T1B_PROJECT/milestones/regular/loops/nopr-task-test/.worktree/DONE" ]] \
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
T2_LABEL_FILE="$(init_done_label_signal "$T2_NAME")"

mkdir -p "$T2_PROJECT/milestones/regular/loops/optin-task-test"
cat > "$T2_PROJECT/milestones/regular/loops/optin-task-test/SPEC.md" <<'EOF'
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
setup_feat_with_spec "$T2_PROJECT" "optin-task"

(
  cd "$T2_PROJECT"
  GH_LOG_FILE="$T2_GH_LOG" GH_LABEL_FILE="$T2_LABEL_FILE" PATH="$T2_MOCK:$PATH" \
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
[[ -f "$T2_PROJECT/milestones/regular/loops/optin-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 3: AC10 — default 브랜치 감지 실패 시 push·pr create 호출 전 abort ==="
# gh repo view 가 exit 1 + git symbolic-ref refs/remotes/origin/HEAD 도 미설정 →
# detect_default_branch 가 빈 문자열 반환 → pr-phase.sh non-zero exit, push·pr create 호출 0회.
T3_NAME="default-branch-fail"
T3_PROJECT="$(make_project_with_remote "$T3_NAME")"
T3_MOCK="$(make_mock_bin "${T3_NAME}-mock")"
install_claude_done_mock "$T3_MOCK"
install_gh_record_mock "$T3_MOCK"
T3_GH_LOG="$WORK_DIR/${T3_NAME}-gh.log"
: > "$T3_GH_LOG"
T3_LABEL_FILE="$(init_done_label_signal "$T3_NAME")"

mkdir -p "$T3_PROJECT/milestones/regular/loops/dbfail-task-test"
cat > "$T3_PROJECT/milestones/regular/loops/dbfail-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Default Branch Fail Task

## 무엇을 만들 것인가
default branch 감지 실패 abort 검증.
EOF
setup_feat_with_spec "$T3_PROJECT" "dbfail-task"

set +e
(
  cd "$T3_PROJECT"
  GH_LOG_FILE="$T3_GH_LOG" GH_LABEL_FILE="$T3_LABEL_FILE" GH_REPO_VIEW_FAIL=1 PATH="$T3_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "dbfail-task" > "$WORK_DIR/${T3_NAME}.out" 2>&1
)
t3_exit=$?
set -e

# AC10: loop start exit ≠ 0 (PR phase가 abort했기 때문)
[[ $t3_exit -ne 0 ]] \
  || { echo "FAIL: default branch 감지 실패에도 exit 0. out:"; cat "$WORK_DIR/${T3_NAME}.out"; exit 1; }

# stderr/stdout 합본에 default branch 감지 실패 메시지
grep -q "default 브랜치 감지 실패" "$WORK_DIR/${T3_NAME}.out" \
  || { echo "FAIL: default 브랜치 감지 실패 메시지 없음. out:"; cat "$WORK_DIR/${T3_NAME}.out"; exit 1; }

# gh pr create / pr edit 호출 0회 (push도 0회지만 gh log로는 검사 불가 — 별도 git wrapper 필요).
# AC10 핵심은 PR 생성·갱신 시도 안 함.
if grep -qE '^pr (create|edit) ' "$T3_GH_LOG"; then
  echo "FAIL: default branch 감지 실패 후에도 pr create/edit 호출됨. log:"; cat "$T3_GH_LOG"; exit 1
fi

# DONE은 정상 생성됐어야 (PR 단계만 실패, 워커 본체는 성공)
[[ -f "$T3_PROJECT/milestones/regular/loops/dbfail-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 4: AC6 — 숫자 task-id 시 PR body 마지막에 'Closes #<id>' 추가 ==="
T4_NAME="closes-numeric"
T4_PROJECT="$(make_project_with_remote "$T4_NAME")"
T4_MOCK="$(make_mock_bin "${T4_NAME}-mock")"
install_claude_done_mock "$T4_MOCK"
install_gh_record_mock "$T4_MOCK"
T4_GH_LOG="$WORK_DIR/${T4_NAME}-gh.log"
T4_CALL_DIR="$WORK_DIR/${T4_NAME}-calls"
: > "$T4_GH_LOG"
T4_LABEL_FILE="$(init_done_label_signal "$T4_NAME")"

mkdir -p "$T4_PROJECT/milestones/regular/loops/42-test"
cat > "$T4_PROJECT/milestones/regular/loops/42-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Numeric Task ID

## 무엇을 만들 것인가
숫자 task-id의 Closes 자동 링크.
EOF
setup_feat_with_spec "$T4_PROJECT" "42"

(
  cd "$T4_PROJECT"
  GH_LOG_FILE="$T4_GH_LOG" GH_LABEL_FILE="$T4_LABEL_FILE" GH_CALL_DIR="$T4_CALL_DIR" PATH="$T4_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "42" > "$WORK_DIR/${T4_NAME}.out" 2>&1
)

# pr create 호출의 --body 인자에 'Closes #42' 포함
t4_body="$(extract_body_from_call "$T4_CALL_DIR" "pr-create")"
[[ -n "$t4_body" ]] \
  || { echo "FAIL: pr create의 --body 추출 불가. call dir:"; ls "$T4_CALL_DIR"; exit 1; }
echo "$t4_body" | grep -qF "Closes #42" \
  || { echo "FAIL: 숫자 task-id인데 body에 'Closes #42' 없음. body:"; echo "$t4_body"; exit 1; }

# SPEC 194 AC1: 숫자 task-id 시 PR 제목이 '#<task-id>: <SPEC H1>' 포맷
t4_title="$(extract_title_from_call "$T4_CALL_DIR" "pr-create")"
[[ "$t4_title" == "#42: Numeric Task ID" ]] \
  || { echo "FAIL: SPEC 194 AC1 — 숫자 task-id 제목 포맷 불일치. expected='#42: Numeric Task ID' got='$t4_title'"; exit 1; }
echo "OK"

echo "=== TEST 5: AC6 — 비숫자 task-id 시 'Closes #' 자동 링크 생략 ==="
T5_NAME="closes-nonnumeric"
T5_PROJECT="$(make_project_with_remote "$T5_NAME")"
T5_MOCK="$(make_mock_bin "${T5_NAME}-mock")"
install_claude_done_mock "$T5_MOCK"
install_gh_record_mock "$T5_MOCK"
T5_GH_LOG="$WORK_DIR/${T5_NAME}-gh.log"
T5_CALL_DIR="$WORK_DIR/${T5_NAME}-calls"
: > "$T5_GH_LOG"
T5_LABEL_FILE="$(init_done_label_signal "$T5_NAME")"

mkdir -p "$T5_PROJECT/milestones/regular/loops/foo-task-test"
cat > "$T5_PROJECT/milestones/regular/loops/foo-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Non-numeric Task ID

## 무엇을 만들 것인가
비숫자 task-id 검증.
EOF
setup_feat_with_spec "$T5_PROJECT" "foo-task"

(
  cd "$T5_PROJECT"
  GH_LOG_FILE="$T5_GH_LOG" GH_LABEL_FILE="$T5_LABEL_FILE" GH_CALL_DIR="$T5_CALL_DIR" PATH="$T5_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "foo-task" > "$WORK_DIR/${T5_NAME}.out" 2>&1
)

t5_body="$(extract_body_from_call "$T5_CALL_DIR" "pr-create")"
[[ -n "$t5_body" ]] \
  || { echo "FAIL: pr create의 --body 추출 불가"; ls "$T5_CALL_DIR"; exit 1; }
if echo "$t5_body" | grep -qE 'Closes #[0-9]+'; then
  echo "FAIL: 비숫자 task-id인데 body에 'Closes #<num>' 있음 (AC6 위반). body:"
  echo "$t5_body"; exit 1
fi

# SPEC 194 AC3: 비숫자 task-id 시 PR 제목이 '<task-id>: <SPEC H1>' 포맷 ('#' 없이)
t5_title="$(extract_title_from_call "$T5_CALL_DIR" "pr-create")"
[[ "$t5_title" == "foo-task: Non-numeric Task ID" ]] \
  || { echo "FAIL: SPEC 194 AC3 — 비숫자 task-id 제목 포맷 불일치. expected='foo-task: Non-numeric Task ID' got='$t5_title'"; exit 1; }
# '#' prefix 없음 보장
if [[ "$t5_title" == "#"* ]]; then
  echo "FAIL: SPEC 194 AC3 — 비숫자 task-id 제목에 '#' prefix 있음. got='$t5_title'"; exit 1
fi
echo "OK"

echo "=== TEST 6: AC3+AC4+AC5 — 기존 open PR 재사용 (pr edit) + 제목·본문 동기화 ==="
T6_NAME="reuse-existing-pr"
T6_PROJECT="$(make_project_with_remote "$T6_NAME")"
T6_MOCK="$(make_mock_bin "${T6_NAME}-mock")"
install_claude_done_mock "$T6_MOCK"
install_gh_record_mock "$T6_MOCK"
T6_GH_LOG="$WORK_DIR/${T6_NAME}-gh.log"
T6_CALL_DIR="$WORK_DIR/${T6_NAME}-calls"
: > "$T6_GH_LOG"
T6_LABEL_FILE="$(init_done_label_signal "$T6_NAME")"

mkdir -p "$T6_PROJECT/milestones/regular/loops/reuse-task-test"
cat > "$T6_PROJECT/milestones/regular/loops/reuse-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Reuse Existing PR Title

## 무엇을 만들 것인가
기존 open PR을 in-place로 갱신하는 경로.
EOF
setup_feat_with_spec "$T6_PROJECT" "reuse-task"

(
  cd "$T6_PROJECT"
  GH_LOG_FILE="$T6_GH_LOG" GH_LABEL_FILE="$T6_LABEL_FILE" GH_CALL_DIR="$T6_CALL_DIR" \
    GH_OPEN_PR_NUMBER=99 \
    PATH="$T6_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "reuse-task" > "$WORK_DIR/${T6_NAME}.out" 2>&1
)

# AC3: pr create 호출 0회
if grep -qE '^pr create ' "$T6_GH_LOG"; then
  echo "FAIL: 기존 PR 있는데 pr create 호출됨 (AC3 위반). log:"; cat "$T6_GH_LOG"; exit 1
fi

# pr edit 99 호출 1회 이상
grep -qE '^pr edit 99( |$)' "$T6_GH_LOG" \
  || { echo "FAIL: pr edit 99 호출 기록 없음. log:"; cat "$T6_GH_LOG"; exit 1; }

# AC4 + SPEC 194 AC2: 갱신 경로에서도 제목 = '<task-id>: <SPEC H1>' (task-id 'reuse-task'는 비숫자 → fallback)
t6_title="$(extract_title_from_call "$T6_CALL_DIR" "pr-edit")"
[[ "$t6_title" == "reuse-task: Reuse Existing PR Title" ]] \
  || { echo "FAIL: SPEC 194 AC2 — 갱신 경로 제목 포맷 불일치. expected='reuse-task: Reuse Existing PR Title' got='$t6_title'"; exit 1; }

# AC5: body가 SPEC '무엇을 만들 것인가' 본문 포함
t6_body="$(extract_body_from_call "$T6_CALL_DIR" "pr-edit")"
echo "$t6_body" | grep -qF "기존 open PR을 in-place로 갱신하는 경로" \
  || { echo "FAIL: pr edit body가 SPEC 본문을 포함하지 않음. body:"; echo "$t6_body"; exit 1; }
echo "$t6_body" | grep -qF "## Commits" \
  || { echo "FAIL: pr edit body가 commit log 섹션을 포함하지 않음. body:"; echo "$t6_body"; exit 1; }

# AC7: 메타 플래그 미지정 (재사용 경로에도 동일)
if grep -qE '(--reviewer|--label|--assignee)' "$T6_GH_LOG"; then
  echo "FAIL: 재사용 경로에 메타 플래그 포함됨. log:"; cat "$T6_GH_LOG"; exit 1
fi
echo "OK"

echo "=== TEST 7: AC8 — gh pr create 실패 시 loop non-zero exit + stderr passthrough ==="
T7_NAME="create-fail"
T7_PROJECT="$(make_project_with_remote "$T7_NAME")"
T7_MOCK="$(make_mock_bin "${T7_NAME}-mock")"
install_claude_done_mock "$T7_MOCK"
install_gh_record_mock "$T7_MOCK"
T7_GH_LOG="$WORK_DIR/${T7_NAME}-gh.log"
: > "$T7_GH_LOG"
T7_LABEL_FILE="$(init_done_label_signal "$T7_NAME")"

mkdir -p "$T7_PROJECT/milestones/regular/loops/createfail-task-test"
cat > "$T7_PROJECT/milestones/regular/loops/createfail-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Create Fail Task

## 무엇을 만들 것인가
pr create 실패 시 abort 검증.
EOF
setup_feat_with_spec "$T7_PROJECT" "createfail-task"

set +e
(
  cd "$T7_PROJECT"
  GH_LOG_FILE="$T7_GH_LOG" GH_LABEL_FILE="$T7_LABEL_FILE" GH_FAIL_PR_CREATE=1 PATH="$T7_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "createfail-task" > "$WORK_DIR/${T7_NAME}.out" 2>&1
)
t7_exit=$?
set -e

# AC8: loop start exit ≠ 0
[[ $t7_exit -ne 0 ]] \
  || { echo "FAIL: pr create 실패에도 loop exit 0. out:"; cat "$WORK_DIR/${T7_NAME}.out"; exit 1; }

# stderr passthrough: mock의 'boom-create' 문자열이 출력에 포함돼야
grep -q "boom-create" "$WORK_DIR/${T7_NAME}.out" \
  || { echo "FAIL: gh stderr passthrough 미동작 ('boom-create' 없음). out:"; cat "$WORK_DIR/${T7_NAME}.out"; exit 1; }

# 워크트리·DONE 보존 (AC9 정신 — 워크트리는 유지)
[[ -d "$T7_PROJECT/milestones/regular/loops/createfail-task-test/.worktree" ]] \
  || { echo "FAIL: 워크트리 미보존"; exit 1; }
[[ -f "$T7_PROJECT/milestones/regular/loops/createfail-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미보존"; exit 1; }
echo "OK"

echo "=== TEST 8: AC9 — 성공 시 PR URL·state stdout 출력 + worktree·local 브랜치 보존 ==="
T8_NAME="success-stdout"
T8_PROJECT="$(make_project_with_remote "$T8_NAME")"
T8_MOCK="$(make_mock_bin "${T8_NAME}-mock")"
install_claude_done_mock "$T8_MOCK"
install_gh_record_mock "$T8_MOCK"
T8_GH_LOG="$WORK_DIR/${T8_NAME}-gh.log"
: > "$T8_GH_LOG"
T8_LABEL_FILE="$(init_done_label_signal "$T8_NAME")"

mkdir -p "$T8_PROJECT/milestones/regular/loops/success-task-test"
cat > "$T8_PROJECT/milestones/regular/loops/success-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Success Task

## 무엇을 만들 것인가
AC9 성공 출력·보존 검증.
EOF
setup_feat_with_spec "$T8_PROJECT" "success-task"

T8_PR_URL="https://github.example/x/y/pull/777"
(
  cd "$T8_PROJECT"
  GH_LOG_FILE="$T8_GH_LOG" GH_LABEL_FILE="$T8_LABEL_FILE" GH_PR_URL="$T8_PR_URL" PATH="$T8_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "success-task" > "$WORK_DIR/${T8_NAME}.out" 2>&1
)

# AC9: PR URL stdout 출력
grep -qF "$T8_PR_URL" "$WORK_DIR/${T8_NAME}.out" \
  || { echo "FAIL: PR URL ($T8_PR_URL) stdout 미출력. out:"; cat "$WORK_DIR/${T8_NAME}.out"; exit 1; }

# AC9: PR state(open) stdout 출력
grep -qE "PR state:[[:space:]]*open" "$WORK_DIR/${T8_NAME}.out" \
  || { echo "FAIL: PR state stdout 미출력. out:"; cat "$WORK_DIR/${T8_NAME}.out"; exit 1; }

# AC9: 워크트리 보존
[[ -d "$T8_PROJECT/milestones/regular/loops/success-task-test/.worktree" ]] \
  || { echo "FAIL: 워크트리 미보존"; exit 1; }

# AC9: local 브랜치 보존 (워크트리에 체크아웃된 브랜치 = HEAD 참조 정상)
(
  cd "$T8_PROJECT/milestones/regular/loops/success-task-test/.worktree"
  git rev-parse --abbrev-ref HEAD > /dev/null 2>&1
) || { echo "FAIL: 워크트리의 HEAD 브랜치 미보존"; exit 1; }
echo "OK"

echo "=== TEST 9: AC2 — --no-pr 플래그가 SKILL.md 문서·loop.sh driver 사이 동기화 ==="
# AC2 (SPEC 103): --no-pr이 PR phase를 건너뛰는 공식 opt-out 인터페이스. SKILL.md
# 문서·driver 모두에서 동일한 플래그 토큰이 등장해야 (오타·누락 방지).
T9_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/loop/SKILL.md"
T9_DRIVER_LOOP="$REPO_ROOT/plugins/autopilot/skills/loop/references/loop.sh"
T9_DRIVER_PR="$REPO_ROOT/plugins/autopilot/skills/loop/references/pr-phase.sh"

for f in "$T9_SKILL_MD" "$T9_DRIVER_LOOP"; do
  [[ -f "$f" ]] || { echo "FAIL: 파일 없음: $f"; exit 1; }
  grep -qF -- '--no-pr' "$f" \
    || { echo "FAIL: $f 에 '--no-pr' 토큰 누락 (AC2 동기화 실패)"; exit 1; }
done

# pr-phase.sh는 caller가 PR 진입 여부를 결정하므로 토큰 등장 불필요 — 존재만 확인.
[[ -f "$T9_DRIVER_PR" ]] || { echo "FAIL: pr-phase.sh 없음"; exit 1; }
echo "OK"

echo "=== TEST 10: AC3+M4 — fence 마커 부분 교체 (멀티라인 PR_BODY 이식성 회귀) ==="
# pr-phase.sh의 fence-only 교체 경로(awk + ENVIRON)가 실제 실행되는지 회귀.
# 기존 PR body에 fence 마커 + 사용자 수기 텍스트가 있을 때, fence 안만 새 PR_BODY로 교체되고
# 바깥 사용자 텍스트는 그대로 보존돼야 한다. PR_BODY는 항상 멀티라인이므로 awk -v 이식성 결함이
# 있으면 fence 내용이 잘리거나 누락되어 본 테스트가 RED가 된다.
T10_NAME="fence-replace"
T10_PROJECT="$(make_project_with_remote "$T10_NAME")"
T10_MOCK="$(make_mock_bin "${T10_NAME}-mock")"
install_claude_done_mock "$T10_MOCK"
install_gh_record_mock "$T10_MOCK"
T10_GH_LOG="$WORK_DIR/${T10_NAME}-gh.log"
T10_CALL_DIR="$WORK_DIR/${T10_NAME}-gh-calls"
: > "$T10_GH_LOG"
rm -rf "$T10_CALL_DIR"
T10_LABEL_FILE="$(init_done_label_signal "$T10_NAME")"

mkdir -p "$T10_PROJECT/milestones/regular/loops/fence-task-test"
cat > "$T10_PROJECT/milestones/regular/loops/fence-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Fence Replace Task

## 무엇을 만들 것인가
fence 안 영역만 새 body로 교체되고 바깥은 보존되는 회귀.
EOF

# 기존 PR body: 사용자 수기 prelude + fence + 옛 자동 body + fence + 사용자 epilogue.
T10_OLD_BODY=$'사용자 수기 prelude — 보존돼야 함.\n<!-- autopilot:pr-body:begin -->\n## 무엇을 만들 것인가\n옛 자동 body (교체 대상)\n\n## Commits\n- old commit\n<!-- autopilot:pr-body:end -->\n사용자 수기 epilogue — 보존돼야 함.'
setup_feat_with_spec "$T10_PROJECT" "fence-task"

(
  cd "$T10_PROJECT"
  GH_LOG_FILE="$T10_GH_LOG" GH_LABEL_FILE="$T10_LABEL_FILE" GH_CALL_DIR="$T10_CALL_DIR" \
    GH_OPEN_PR_NUMBER=77 GH_OPEN_PR_BODY="$T10_OLD_BODY" \
    PATH="$T10_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "fence-task" > "$WORK_DIR/${T10_NAME}.out" 2>&1
)

# pr edit 호출 1회 이상
grep -qE '^pr edit 77( |$)' "$T10_GH_LOG" \
  || { echo "FAIL: pr edit 77 호출 기록 없음. log:"; cat "$T10_GH_LOG"; exit 1; }

t10_body="$(extract_body_from_call "$T10_CALL_DIR" "pr-edit")"

# 사용자 수기 prelude·epilogue 보존
echo "$t10_body" | grep -qF "사용자 수기 prelude" \
  || { echo "FAIL: fence 바깥 prelude 보존 실패. body:"; printf '%s\n' "$t10_body"; exit 1; }
echo "$t10_body" | grep -qF "사용자 수기 epilogue" \
  || { echo "FAIL: fence 바깥 epilogue 보존 실패. body:"; printf '%s\n' "$t10_body"; exit 1; }

# 옛 자동 body는 사라져야 함 (fence 안 교체됨)
if echo "$t10_body" | grep -qF "옛 자동 body (교체 대상)"; then
  echo "FAIL: fence 안 옛 자동 body가 교체되지 않음 (awk -v 멀티라인 이식성 결함 의심). body:"
  printf '%s\n' "$t10_body"; exit 1
fi

# 새 PR_BODY의 SPEC 본문이 fence 안에 들어왔어야 함
echo "$t10_body" | grep -qF "fence 안 영역만 새 body로 교체되고 바깥은 보존되는 회귀" \
  || { echo "FAIL: fence 안에 새 SPEC 본문 미반영. body:"; printf '%s\n' "$t10_body"; exit 1; }

# fence 마커는 정확히 1쌍씩 유지
fence_begin_count=$(printf '%s\n' "$t10_body" | grep -cF '<!-- autopilot:pr-body:begin -->' || true)
fence_end_count=$(printf '%s\n' "$t10_body" | grep -cF '<!-- autopilot:pr-body:end -->' || true)
[[ "$fence_begin_count" == "1" && "$fence_end_count" == "1" ]] \
  || { echo "FAIL: fence 마커 개수 이상 (begin=$fence_begin_count, end=$fence_end_count). body:"; printf '%s\n' "$t10_body"; exit 1; }
echo "OK"

echo "=== TEST 11: AC3 — PR push 직전 origin/<base> fetch + rebase 수행 ==="
# AC3 (SPEC 103): PR 생성을 수행할 때, 시스템은 그 직전에 PR base branch(default `main`)로부터
# rebase를 수행한 뒤 PR을 생성한다. base가 최신일 때 fast-forward는 no-op으로 통과,
# conflict 시 별도 충돌 핸들러(M3) 경로로 위임된다 (본 테스트는 fast-forward 경로만 검증).
T11_NAME="rebase-before-push"
T11_PROJECT="$(make_project_with_remote "$T11_NAME")"
T11_MOCK="$(make_mock_bin "${T11_NAME}-mock")"
install_claude_done_mock "$T11_MOCK"
install_gh_record_mock "$T11_MOCK"
install_git_record_mock "$T11_MOCK"
T11_GH_LOG="$WORK_DIR/${T11_NAME}-gh.log"
T11_GIT_LOG="$WORK_DIR/${T11_NAME}-git.log"
: > "$T11_GH_LOG"
: > "$T11_GIT_LOG"
T11_LABEL_FILE="$(init_done_label_signal "$T11_NAME")"

mkdir -p "$T11_PROJECT/milestones/regular/loops/rebase-task-test"
cat > "$T11_PROJECT/milestones/regular/loops/rebase-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Rebase Before Push

## 무엇을 만들 것인가
PR push 직전 origin base 브랜치 fetch + rebase가 실행되는 회귀.
EOF
setup_feat_with_spec "$T11_PROJECT" "rebase-task"

(
  cd "$T11_PROJECT"
  GH_LOG_FILE="$T11_GH_LOG" GH_LABEL_FILE="$T11_LABEL_FILE" GIT_LOG_FILE="$T11_GIT_LOG" PATH="$T11_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "rebase-task" > "$WORK_DIR/${T11_NAME}.out" 2>&1
)

# AC3: fetch + rebase 행적 (PR phase 안에서 호출됐어야)
grep -qE '^fetch origin( |$)' "$T11_GIT_LOG" \
  || { echo "FAIL: 'git fetch origin <base>' 호출 기록 없음 (AC3 위반). git log tail:"; tail -30 "$T11_GIT_LOG"; exit 1; }
grep -qE '^rebase origin/' "$T11_GIT_LOG" \
  || { echo "FAIL: 'git rebase origin/<base>' 호출 기록 없음 (AC3 위반). git log tail:"; tail -30 "$T11_GIT_LOG"; exit 1; }

# rebase가 push보다 먼저 — pr-phase가 정확한 순서로 호출해야 한다.
rebase_line=$(grep -nE '^rebase origin/' "$T11_GIT_LOG" | head -1 | cut -d: -f1)
push_line=$(grep -nE '^push .*origin' "$T11_GIT_LOG" | head -1 | cut -d: -f1)
[[ -n "$rebase_line" && -n "$push_line" && "$rebase_line" -lt "$push_line" ]] \
  || { echo "FAIL: rebase가 push보다 먼저여야 함 (rebase_line=$rebase_line push_line=$push_line). git log tail:"; tail -50 "$T11_GIT_LOG"; exit 1; }

# rebase 후 PR 생성 정상 흐름 유지
grep -qE '^pr create ' "$T11_GH_LOG" \
  || { echo "FAIL: rebase 후 pr create 호출 안 됨. gh log:"; cat "$T11_GH_LOG"; exit 1; }
[[ -f "$T11_PROJECT/milestones/regular/loops/rebase-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 12: AC4 — rebase 충돌 1회 자동 해결 성공 (-X theirs) + 정상 PR 생성 ==="
# AC4 (SPEC 103): rebase 또는 머지 중 충돌이 발생하면, 시스템은 1회의 자동 해결을 시도한다.
# 본 케이스: 평범한 rebase가 충돌로 실패하고, `-X theirs` 재시도가 성공해서 push·PR 생성으로 진행.
T12_NAME="rebase-conflict-auto-resolve"
T12_PROJECT="$(make_project_with_remote "$T12_NAME")"
T12_MOCK="$(make_mock_bin "${T12_NAME}-mock")"
install_claude_done_mock "$T12_MOCK"
install_gh_record_mock "$T12_MOCK"
install_git_record_mock "$T12_MOCK"
T12_GH_LOG="$WORK_DIR/${T12_NAME}-gh.log"
T12_GIT_LOG="$WORK_DIR/${T12_NAME}-git.log"
: > "$T12_GH_LOG"
: > "$T12_GIT_LOG"
T12_LABEL_FILE="$(init_done_label_signal "$T12_NAME")"

mkdir -p "$T12_PROJECT/milestones/regular/loops/conflict-auto-task-test"
cat > "$T12_PROJECT/milestones/regular/loops/conflict-auto-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Rebase Conflict Auto-Resolve

## 무엇을 만들 것인가
첫 rebase 충돌 후 1회 자동 해결되는 회귀 (SPEC 169 claude-based resolution).
EOF
setup_feat_with_spec "$T12_PROJECT" "conflict-auto-task"

# SPEC 169 mock 경로 — mock claude 가 rebase prompt 감지 시 unresolved 파일 ours 채택 +
# 이 flag 파일을 touch. mock git 은 후속 rebase --continue 를 fake-success.
T12_RESOLVED_FILE="$WORK_DIR/${T12_NAME}-resolved-flag"
(
  cd "$T12_PROJECT"
  GH_LOG_FILE="$T12_GH_LOG" GH_LABEL_FILE="$T12_LABEL_FILE" GIT_LOG_FILE="$T12_GIT_LOG" \
    GIT_CONFLICT_MODE=auto-resolve \
    GIT_CONFLICT_RESOLVED_FILE="$T12_RESOLVED_FILE" \
    PATH="$T12_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "conflict-auto-task" > "$WORK_DIR/${T12_NAME}.out" 2>&1
)

# AC4 (SPEC 169 — claude-based resolution):
#   1) 첫 plain `rebase origin/<base>` 호출 1회 (mock 이 CONFLICT 로 실패)
#   2) rebase-phase 가 claude 자동 해소 호출 → mock claude 가 GIT_CONFLICT_RESOLVED_FILE touch
#   3) `rebase --continue` 호출 1회 (mock 이 flag 보고 fake-success)
rebase_plain_t12=$(grep -cE '^rebase origin/' "$T12_GIT_LOG" || true)
rebase_continue_t12=$(grep -cE '^rebase --continue' "$T12_GIT_LOG" || true)
[[ "$rebase_plain_t12" -ge 1 ]] \
  || { echo "FAIL: 첫 plain 'rebase origin/<base>' 호출 기록 없음. git log tail:"; tail -50 "$T12_GIT_LOG"; exit 1; }
[[ "$rebase_continue_t12" -ge 1 ]] \
  || { echo "FAIL: claude 해소 후 'rebase --continue' 호출 기록 없음 (AC4 위반). git log tail:"; tail -50 "$T12_GIT_LOG"; echo "out:"; cat "$WORK_DIR/${T12_NAME}.out"; exit 1; }

# claude 가 실제로 자동 해소를 시도했는지 — RESOLVED flag 파일 생성 확인.
[[ -f "$T12_RESOLVED_FILE" ]] \
  || { echo "FAIL: mock claude 가 자동 해소 호출되지 않음 (RESOLVED flag 부재 — AC4 위반)."; exit 1; }

# 자동 해결 시도 메시지가 출력에 있어야 (rebase-phase 가 claude CLI 호출 로깅)
grep -qE "(자동 해소|충돌 감지)" "$WORK_DIR/${T12_NAME}.out" \
  || { echo "FAIL: 자동 해소 시도 안내 메시지 없음. out:"; cat "$WORK_DIR/${T12_NAME}.out"; exit 1; }

# 자동 해결 성공 후 정상 PR 생성 흐름이 이어져야
grep -qE '^pr create ' "$T12_GH_LOG" \
  || { echo "FAIL: 자동 해결 후 pr create 호출 안 됨. gh log:"; cat "$T12_GH_LOG"; echo "out:"; cat "$WORK_DIR/${T12_NAME}.out"; exit 1; }

# DONE 보존
[[ -f "$T12_PROJECT/milestones/regular/loops/conflict-auto-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 13: AC4 — rebase 충돌 자동 해결 실패(1회 시도 후 좌절) + abort + 사용자 알림 ==="
# AC4 (SPEC 103): 자동 해결 시도가 실패한 경우 진행을 중단하고 사용자에게 명시적으로 알린다.
# 본 케이스: plain rebase + -X theirs 재시도 모두 충돌 → loop abort + 명시 알림 + pr create 미호출.
T13_NAME="rebase-conflict-abort"
T13_PROJECT="$(make_project_with_remote "$T13_NAME")"
T13_MOCK="$(make_mock_bin "${T13_NAME}-mock")"
install_claude_done_mock "$T13_MOCK"
install_gh_record_mock "$T13_MOCK"
install_git_record_mock "$T13_MOCK"
T13_GH_LOG="$WORK_DIR/${T13_NAME}-gh.log"
T13_GIT_LOG="$WORK_DIR/${T13_NAME}-git.log"
: > "$T13_GH_LOG"
: > "$T13_GIT_LOG"
T13_LABEL_FILE="$(init_done_label_signal "$T13_NAME")"

mkdir -p "$T13_PROJECT/milestones/regular/loops/conflict-abort-task-test"
cat > "$T13_PROJECT/milestones/regular/loops/conflict-abort-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Rebase Conflict Abort

## 무엇을 만들 것인가
rebase 충돌 자동 해결 1회 시도가 실패해 사용자에게 위임되는 회귀 (SPEC 169 claude-based).
EOF
setup_feat_with_spec "$T13_PROJECT" "conflict-abort-task"

# SPEC 169 mock 경로 — MOCK_CLAUDE_REBASE_FAIL=1 로 mock claude 가 충돌 해소를 시도하지만
# 비-zero exit 으로 실패. rebase-phase 가 escalation + abort + push·pr 단계 미진입.
set +e
(
  cd "$T13_PROJECT"
  GH_LOG_FILE="$T13_GH_LOG" GH_LABEL_FILE="$T13_LABEL_FILE" GIT_LOG_FILE="$T13_GIT_LOG" \
    GIT_CONFLICT_MODE=abort \
    MOCK_CLAUDE_REBASE_FAIL=1 \
    PATH="$T13_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "conflict-abort-task" > "$WORK_DIR/${T13_NAME}.out" 2>&1
)
t13_exit=$?
set -e

# AC4: loop start exit ≠ 0 (rebase 충돌 자동 해결 실패로 PR phase가 abort)
[[ $t13_exit -ne 0 ]] \
  || { echo "FAIL: 자동 해결 실패에도 loop exit 0. out:"; cat "$WORK_DIR/${T13_NAME}.out"; exit 1; }

# AC4 (SPEC 169): 첫 plain rebase 실패 → claude 호출 실패 → abort.
#   rebase 호출은 plain 1회만 (claude 실패로 --continue 미시도).
#   rebase --abort 1회 (escalation 복구).
rebase_plain_t13=$(grep -cE '^rebase origin/' "$T13_GIT_LOG" || true)
rebase_abort_t13=$(grep -cE '^rebase --abort' "$T13_GIT_LOG" || true)
rebase_continue_t13=$(grep -cE '^rebase --continue' "$T13_GIT_LOG" || true)
[[ "$rebase_plain_t13" -eq 1 ]] \
  || { echo "FAIL: plain rebase 가 ${rebase_plain_t13}회 호출 (정확히 1회 기대 — claude 실패로 재시도 없음). git log tail:"; tail -50 "$T13_GIT_LOG"; exit 1; }
[[ "$rebase_abort_t13" -ge 1 ]] \
  || { echo "FAIL: 'rebase --abort' 호출 기록 없음 (워크트리 복구 위반). git log tail:"; tail -50 "$T13_GIT_LOG"; exit 1; }
[[ "$rebase_continue_t13" -eq 0 ]] \
  || { echo "FAIL: claude 실패에도 'rebase --continue' 호출됨 (${rebase_continue_t13}회). git log tail:"; tail -50 "$T13_GIT_LOG"; exit 1; }

# 자동 해결 실패·escalation 안내 메시지
grep -qE "(ESCALATION|자동 해소 실패|충돌 해소 실패)" "$WORK_DIR/${T13_NAME}.out" \
  || { echo "FAIL: 자동 해소 실패 escalation 메시지 없음 (사용자 위임 위반). out:"; cat "$WORK_DIR/${T13_NAME}.out"; exit 1; }

# pr create 호출 0회 (rebase 좌절 후 push·pr 단계 미진입)
if grep -qE '^pr (create|edit) ' "$T13_GH_LOG"; then
  echo "FAIL: rebase 좌절 후에도 pr create/edit 호출됨. gh log:"; cat "$T13_GH_LOG"; exit 1
fi

# 워크트리·DONE 보존 (사용자 수동 해결 가능하도록)
[[ -d "$T13_PROJECT/milestones/regular/loops/conflict-abort-task-test/.worktree" ]] \
  || { echo "FAIL: 워크트리 미보존"; exit 1; }
[[ -f "$T13_PROJECT/milestones/regular/loops/conflict-abort-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미보존"; exit 1; }
echo "OK"

echo "=== TEST 14: AC5 — Monitor stuck PR check 재트리거 ≤3회 후 상한 알림 ==="
# AC5 (SPEC 103): PR check가 success/failure로 완료됐으나 PR 상태가 review·done이 아닌
# stuck 상태를 Monitor가 감지할 때, 시스템은 최대 3회 이내에서 check를 재트리거하며,
# 상한에 도달하면 사용자에게 알린다.
# 본 케이스: stub gh가 항상 "stuck" 응답 (state=OPEN, reviewDecision=빈값, checks=COMPLETED)을
# 반환 → 드라이버가 `pr checks --rerun`을 정확히 3회 호출 + 상한 알림 메시지 + loop 정상 종료.
T14_NAME="monitor-stuck-rerun"
T14_PROJECT="$(make_project_with_remote "$T14_NAME")"
T14_MOCK="$(make_mock_bin "${T14_NAME}-mock")"
install_claude_done_mock "$T14_MOCK"
install_gh_record_mock "$T14_MOCK"
T14_GH_LOG="$WORK_DIR/${T14_NAME}-gh.log"
: > "$T14_GH_LOG"
T14_LABEL_FILE="$(init_done_label_signal "$T14_NAME")"

mkdir -p "$T14_PROJECT/milestones/regular/loops/stuck-task-test"
cat > "$T14_PROJECT/milestones/regular/loops/stuck-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Monitor Stuck Rerun

## 무엇을 만들 것인가
PR check가 stuck 상태일 때 Monitor가 최대 3회 재트리거 후 상한 알림.
EOF
setup_feat_with_spec "$T14_PROJECT" "stuck-task"

(
  cd "$T14_PROJECT"
  GH_LOG_FILE="$T14_GH_LOG" GH_LABEL_FILE="$T14_LABEL_FILE" \
    GH_PR_STATE=OPEN \
    GH_PR_REVIEW_DECISION="" \
    GH_CHECKS_MODE=stuck \
    LOOP_PR_RERUN_SLEEP_SECONDS=0 \
    PATH="$T14_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "stuck-task" > "$WORK_DIR/${T14_NAME}.out" 2>&1
)

# AC5: pr checks --rerun 호출이 정확히 3회 (상한). 4회 이상이면 무한 루프 위험.
rerun_count_t14=$(grep -cE '^pr checks .*--rerun' "$T14_GH_LOG" || true)
[[ "$rerun_count_t14" -eq 3 ]] \
  || { echo "FAIL: pr checks --rerun이 ${rerun_count_t14}회 호출 (정확히 3회 기대 — AC5 상한 위반). gh log:"; cat "$T14_GH_LOG"; echo "out:"; cat "$WORK_DIR/${T14_NAME}.out"; exit 1; }

# AC5: 상한 도달 알림 메시지 — "재트리거 상한" 또는 "3회" 또는 "사용자 개입" 토큰 포함
grep -qE "(재트리거 상한|3회|상한 도달|사용자 개입)" "$WORK_DIR/${T14_NAME}.out" \
  || { echo "FAIL: 상한 도달 알림 메시지 없음 (AC5 위반). out:"; cat "$WORK_DIR/${T14_NAME}.out"; exit 1; }

# pr create는 정상 호출됐어야 (Monitor는 PR 생성 이후 단계)
grep -qE '^pr create ' "$T14_GH_LOG" \
  || { echo "FAIL: stuck 진입 전 pr create 호출 없음. gh log:"; cat "$T14_GH_LOG"; exit 1; }

# DONE 보존 + 정상 종료 (상한 도달은 에러가 아니라 경고 — loop 자체는 정상 종료)
[[ -f "$T14_PROJECT/milestones/regular/loops/stuck-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 15: AC6 — PR MERGED 감지 시 cleanup 후보 안내 + 자동 삭제 안 함 ==="
# AC6 (SPEC 103): PR이 merged 또는 closed 상태로 전이할 때, 시스템은 worktree·feat 브랜치
# cleanup 여부를 사용자에게 명시적으로 확인하고, 명시적 승인이 없는 경우 어떤 항목도
# 자동 삭제하지 않는다.
# 본 케이스: stub gh가 state=MERGED 응답 → Monitor가 즉시 break하면서 cleanup 후보 안내
# 메시지(승인 필요·자동 삭제 금지)를 명시 출력. worktree·feat 브랜치는 보존.
T15_NAME="monitor-merged-cleanup-notice"
T15_PROJECT="$(make_project_with_remote "$T15_NAME")"
T15_MOCK="$(make_mock_bin "${T15_NAME}-mock")"
install_claude_done_mock "$T15_MOCK"
install_gh_record_mock "$T15_MOCK"
T15_GH_LOG="$WORK_DIR/${T15_NAME}-gh.log"
: > "$T15_GH_LOG"
T15_LABEL_FILE="$(init_done_label_signal "$T15_NAME")"

mkdir -p "$T15_PROJECT/milestones/regular/loops/merged-task-test"
cat > "$T15_PROJECT/milestones/regular/loops/merged-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Monitor Merged Cleanup Notice

## 무엇을 만들 것인가
PR이 MERGED 상태로 전이될 때 cleanup 후보 안내만 출력하고 자동 삭제는 하지 않는 회귀.
EOF
setup_feat_with_spec "$T15_PROJECT" "merged-task"

(
  cd "$T15_PROJECT"
  GH_LOG_FILE="$T15_GH_LOG" GH_LABEL_FILE="$T15_LABEL_FILE" \
    GH_PR_STATE=MERGED \
    PATH="$T15_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "merged-task" > "$WORK_DIR/${T15_NAME}.out" 2>&1
)

# AC6: cleanup 후보 안내 메시지 — "cleanup 후보" 또는 "loop.sh cleanup" 또는 "cleanup 승인" 토큰
grep -qE "(cleanup 후보|loop\.sh cleanup|cleanup 승인)" "$WORK_DIR/${T15_NAME}.out" \
  || { echo "FAIL: MERGED 상태인데 cleanup 후보 안내 메시지 없음 (AC6 위반). out:"; cat "$WORK_DIR/${T15_NAME}.out"; exit 1; }

# AC6: 자동 삭제 차단 명시 — "자동 삭제하지 않" 또는 "수동" 또는 "명시 승인" 토큰
grep -qE "(자동 삭제하지 않|수동|명시 승인)" "$WORK_DIR/${T15_NAME}.out" \
  || { echo "FAIL: 자동 삭제 차단 안내 없음 (AC6 위반). out:"; cat "$WORK_DIR/${T15_NAME}.out"; exit 1; }

# AC6: 자동 삭제 안 함 — worktree·DONE 보존
[[ -d "$T15_PROJECT/milestones/regular/loops/merged-task-test/.worktree" ]] \
  || { echo "FAIL: MERGED 감지 후 워크트리가 삭제됨 (AC6 위반 — 자동 삭제 금지)"; exit 1; }
[[ -f "$T15_PROJECT/milestones/regular/loops/merged-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미보존"; exit 1; }

# Monitor 진입 후 MERGED 감지로 즉시 break — pr checks --rerun 호출 0회
if grep -qE '^pr checks .*--rerun' "$T15_GH_LOG"; then
  echo "FAIL: MERGED 상태인데 pr checks --rerun 호출됨 (즉시 break 위반). gh log:"; cat "$T15_GH_LOG"; exit 1
fi
echo "OK"

echo "=== TEST 16: AC5 회귀 — WAITING(환경 승인 대기)은 stuck 아님 → --rerun 0회 ==="
# AC5 회귀 (PR #109 NIT 대응): gh pr checks의 state 값에 WAITING(환경 보호 승인 대기)이
# 포함될 수 있는데, 이전 코드는 진행 상태 화이트리스트(PENDING|IN_PROGRESS|QUEUED|RUNNING)에
# WAITING이 빠져 있어 stuck으로 오판해 불필요한 --rerun이 발생했다. 본 회귀: 화이트리스트
# 대신 'COMPLETED만 stuck 후보' 블랙리스트로 판정하므로 WAITING 응답 시 --rerun 0회 + 정상 break.
T16_NAME="monitor-waiting-not-stuck"
T16_PROJECT="$(make_project_with_remote "$T16_NAME")"
T16_MOCK="$(make_mock_bin "${T16_NAME}-mock")"
install_claude_done_mock "$T16_MOCK"
install_gh_record_mock "$T16_MOCK"
T16_GH_LOG="$WORK_DIR/${T16_NAME}-gh.log"
: > "$T16_GH_LOG"
T16_LABEL_FILE="$(init_done_label_signal "$T16_NAME")"

mkdir -p "$T16_PROJECT/milestones/regular/loops/waiting-task-test"
cat > "$T16_PROJECT/milestones/regular/loops/waiting-task-test/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Monitor Waiting Not Stuck

## 무엇을 만들 것인가
WAITING(환경 승인 대기) 상태는 stuck 아님 — --rerun 호출 0회.
EOF
setup_feat_with_spec "$T16_PROJECT" "waiting-task"

(
  cd "$T16_PROJECT"
  GH_LOG_FILE="$T16_GH_LOG" GH_LABEL_FILE="$T16_LABEL_FILE" \
    GH_PR_STATE=OPEN \
    GH_PR_REVIEW_DECISION="" \
    GH_CHECKS_MODE=waiting \
    LOOP_PR_RERUN_SLEEP_SECONDS=0 \
    PATH="$T16_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "waiting-task" > "$WORK_DIR/${T16_NAME}.out" 2>&1
)

# AC5 회귀: WAITING은 진행 상태 → stuck 아님 → --rerun 호출 0회
rerun_count_t16=$(grep -cE '^pr checks .*--rerun' "$T16_GH_LOG" || true)
[[ "$rerun_count_t16" -eq 0 ]] \
  || { echo "FAIL: WAITING 상태인데 pr checks --rerun ${rerun_count_t16}회 호출 (0회 기대). gh log:"; cat "$T16_GH_LOG"; echo "out:"; cat "$WORK_DIR/${T16_NAME}.out"; exit 1; }

# Monitor 종료 메시지 (stuck 아님)
grep -qE "(check 진행 중|stuck 아님)" "$WORK_DIR/${T16_NAME}.out" \
  || { echo "FAIL: WAITING 시 'stuck 아님' 안내 메시지 없음. out:"; cat "$WORK_DIR/${T16_NAME}.out"; exit 1; }

# DONE 보존 + 정상 종료
[[ -f "$T16_PROJECT/milestones/regular/loops/waiting-task-test/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 PR phase 테스트 통과 ==="
