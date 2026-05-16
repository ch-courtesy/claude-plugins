#!/usr/bin/env bash
# loop.sh — 자율 루프 외부 셸 드라이버 (subcommand 기반)
#
# 사용:
#   bash /path/to/autopilot/skills/loop/references/loop.sh start   <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>]
#   (SPEC.md 생성: Skill(skill: "spec", args: "<task-id>")  — prepare 서브커맨드는 deprecated)
#   bash /path/to/autopilot/skills/loop/references/loop.sh status  [<task-id>]
#   bash /path/to/autopilot/skills/loop/references/loop.sh stop    <task-id>
#   bash /path/to/autopilot/skills/loop/references/loop.sh list
#   bash /path/to/autopilot/skills/loop/references/loop.sh cleanup <task-id> [--force]
#   bash /path/to/autopilot/skills/loop/references/loop.sh logs    <task-id> [--tail] [--iter N]
#
# 워크트리·lock 위치: 메인 레포 내부의 milestones/<m>/loops/<c>/ 단일 트리.
# 단일 task는 normalize 과정에서 <m>=regular로 정규화. 외부 sibling 디렉터리·
# .loops/ 별도 디렉터리는 더 이상 사용하지 않음 (v0.2 cutover).
#
# 환경 변수:
#   MAX_CONCURRENT         동시 실행 task 수 (기본: 3)
#   MAX_ITERATIONS         이터 상한 (기본: 30)
#   WALL_CLOCK_MINUTES     시계 캡 (기본: 120)

set -euo pipefail

# ----- 스크립트 자신의 디렉토리 (references/) -----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----- allowed-tools (SPEC 123 AC18) -----
#
# DONE 이후 PR 생애주기 자동화 phase 그룹(rebase·review-fix·cleanup)의 *자식 claude CLI
# 세션*(rebase 충돌 자동 해소, review-fix iter) 전용 도구 권한. review-fix-phase가
# `--allowed-tools "$AUTOPILOT_REVIEW_FIX_ALLOWED_TOOLS"` 형태로 전달한다.
#
# 범위 최소화 원칙 (claude 세션 관점):
#   - phase 셸 스크립트가 직접 실행하는 파괴적 명령(gh pr merge·gh pr comment·
#     gh project item-edit·git rebase·git commit·git push·git push --delete·
#     git branch -D·git worktree remove)은 claude 세션이 사용해선 안 되므로 *제거*.
#   - claude 세션은 fix 코드 변경(Read·Edit·Write) + staging/진단(git add·status·diff)
#     + PR 컨텍스트 조회(gh pr view·gh api repos/) 만 필요.
#   - 와일드카드(gh *, git *) 사용 금지.
AUTOPILOT_REVIEW_FIX_ALLOWED_TOOLS="\
Bash(git add:*),\
Bash(git status:*),\
Bash(git diff:*),\
Bash(gh pr view:*),\
Bash(gh api repos/:*),\
Read,Edit,Write,Glob,Grep"
export AUTOPILOT_REVIEW_FIX_ALLOWED_TOOLS

# 충돌 자동 해소 세션 전용(rebase-phase): 더 좁은 범위.
AUTOPILOT_REBASE_ALLOWED_TOOLS="\
Bash(git add:*),\
Bash(git status:*),\
Bash(git diff:*),\
Bash(cat:*),\
Bash(ls:*),\
Read,Edit,Write,Glob,Grep"
export AUTOPILOT_REBASE_ALLOWED_TOOLS

# ----- task storage 검출 키 (SPEC 134 AC4) -----
#
# 완료 신호의 검출 키는 task 식별자에 부속된 label 이름이다 (헌법 §12, SKILL.md).
# 워커가 완료 시 `[done]` prefix comment(가독·로그)와 본 label 추가(검출 키)를 모두
# 수행해야 드라이버가 done으로 판정한다. comment 본문은 더 이상 단일 검출 키가 아니다.
# 환경 변수 override 허용 — 단, label 이름은 프로젝트 수준에서 단일 위치에 고정되어
# task storage adapter 다중 분기를 만들지 않는다 (SPEC 134 §비-목표).
LOOP_DONE_LABEL="${LOOP_DONE_LABEL:-loop:done}"

# ----- 헬퍼 -----

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1이(가) 필요합니다. 설치 후 다시 실행하세요."
}

# task-id 유효성 검사 (공통). compute_paths·cmd_status filter에서 호출.
validate_task_id() {
  local task_id="$1"
  [[ "$task_id" == *..* ]] && die "task-id에 '..' 사용 불가 (path traversal 방지)"
  # '.' 단독 컴포넌트 거부 — '.', './foo', 'foo/.', 'a/./b' 모두 워크트리 경로
  # 또는 git 브랜치명에 부적절 (예: WT_BASE/. = WT_BASE 자체)
  case "$task_id" in
    .|./*|*/.|*/./*) die "task-id에 '.' 단독 컴포넌트 사용 불가" ;;
  esac
  [[ "$task_id" == *__* ]] && die "task-id에 '__' 사용 불가 (slash 인코딩 예약 시퀀스 — lock 파일명 충돌 방지)"
  [[ "$task_id" == *' '* ]] && die "task-id에 공백 사용 불가"
  return 0  # set -e: 마지막 [[ ... ]] && die가 false일 때 함수 exit 1 방지
}

# 단일 컴포넌트 task-id에 'regular/' prefix 자동 추가.
# 이미 슬래시가 있으면(예: 'goal-x/sub-task', 'm1/c1') 그대로.
# M1 cutover: SPEC은 항상 milestones/<m>/loops/<c>/SPEC.md에서 읽힘.
normalize_task_id() {
  local task_id="$1"
  if [[ "$task_id" == */* ]]; then
    echo "$task_id"
  else
    echo "regular/$task_id"
  fi
}

# ----- task ↔ GitHub issue 매핑 (헌법 §11, rules/context.md) -----
# task-id의 마지막 컴포넌트(예: 'regular/124' → '124')가 숫자면 issue number로 직접 사용.
# 그 외 문자열이면 `gh issue list --search`로 첫 매칭 lookup. 실패 시 빈 출력 + return 1.
# 호출자(halt·iterate·cmd_status)는 매핑 실패 시 graceful degrade한다.
# M4-b 인라인 — M4-c에서 재시도/backoff 추가.
task_issue_number() {
  local task_id="${1:-$TASK_ID}"
  local child="${task_id##*/}"
  if [[ "$child" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$child"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  local n
  n=$(gh issue list --search "$task_id" --json number --jq '.[0].number' 2>/dev/null || true)
  if [[ -n "$n" && "$n" != "null" ]]; then
    printf '%s\n' "$n"
    return 0
  fi
  return 1
}

# task issue에 특정 label이 붙어 있는지 boolean 검사 (SPEC 134 AC3).
# 인자: $1=task-id (생략 시 $TASK_ID), $2=label 이름 (필수).
# 반환: 0=label 존재, 1=label 부재 또는 판정 불가 (issue 매핑 실패·gh 부재 포함).
# 구현은 단일 GitHub 호출(`gh issue view --json labels`)로 한정 — adapter 인터페이스
# 신설 없음 (SPEC 134 §비-목표).
task_label_present() {
  local task_id="${1:-$TASK_ID}"
  local label="${2:-}"
  [[ -z "$label" ]] && return 1
  local issue
  issue=$(task_issue_number "$task_id" 2>/dev/null) || return 1
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  # gh CLI의 `--jq`는 단일 expression 인자만 받아 jq의 `--arg`를 통과시키지 않으므로
  # name 목록만 추출해 셸에서 정확 일치 비교 (grep -F -x).
  local names
  names=$(gh issue view "$issue" --json labels \
    --jq '.labels[].name' 2>/dev/null || true)
  [[ -z "$names" ]] && return 1
  printf '%s\n' "$names" | grep -qxF "$label" && return 0
  return 1
}

# task storage에 label이 존재하는지 확인하고, 없으면 자동 생성 (SPEC 134 AC5).
# 인자: $1=label 이름 (필수).
# 권한 부족·gh 부재 시 best-effort로 stderr WARN + 비-0 반환 (비차단 진행).
# SPEC 134 §위험 "label 자동 생성 권한 부족" — runtime 실패는 verify 범위 밖.
ensure_label_exists() {
  local label="${1:-}"
  [[ -z "$label" ]] && return 1
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  # 존재 여부 확인 — `gh label list --search`는 prefix·substring을 함께 반환할 수
  # 있으므로 name 목록만 추출 후 셸에서 정확 일치 비교 (gh `--jq`는 jq `--arg`를
  # 통과시키지 않아 셸 비교가 안전).
  local names
  names=$(gh label list --search "$label" --json name \
    --jq '.[].name' 2>/dev/null || true)
  if [[ -n "$names" ]] && printf '%s\n' "$names" | grep -qxF "$label"; then
    return 0
  fi
  # 미존재 — 생성 시도. race 또는 권한 부족 시 WARN.
  if ! gh label create "$label" \
        --description "autopilot loop 완료 신호 (드라이버 검출 키)" \
        >/dev/null 2>&1; then
    echo "[$(now_iso)] WARN: label '$label' 자동 생성 실패 — 권한 부족·race·gh 응답 비정상. 수동 생성 필요." >&2
    return 1
  fi
  echo "[$(now_iso)] label '$label' 자동 생성 완료." >&2
  return 0
}

# task issue의 완료 신호 검사 (헌법 §12, SPEC 134 AC2).
# 정식 검출 키: task issue에 LOOP_DONE_LABEL 값과 일치하는 label이 붙어 있는지.
# comment 본문은 가독·로그 채널이며 판정에 사용되지 않는다 — 워커가 [done] prefix
# comment 발행과 함께 label 추가 두 동작을 모두 수행해야 0(done)을 반환한다.
# 반환: 0=done, 1=done 아님(판정 불가 포함).
task_status_is_done() {
  local task_id="${1:-$TASK_ID}"
  task_label_present "$task_id" "$LOOP_DONE_LABEL"
}

# task issue의 차단 신호 검사 (헌법 §5·§12, SPEC 134 §제약).
# 정식 검출 키: Project Status field 값(`Blocked`) 단일 의존. comment 본문은 가독·
# 로그 채널이며 판정에 사용되지 않는다 — 워커가 [blocked] prefix comment 발행과
# 함께 Status=Blocked 전이 두 동작을 모두 수행해야 0(blocked)을 반환한다.
# graceful degradation: AUTOPILOT_PROJECT_ITEM_ID 미설정·gh 부재·GraphQL 실패는
# best-effort로 stderr WARN + 1(판정 불가) 반환 — 검출 키를 comment로 이중화하지
# 않는다 (SPEC 134 §제약 "판정 키는 label·status 단일 의존을 깨지 않는다").
# 반환: 0=blocked, 1=blocked 아님(판정 불가 포함).
task_status_is_blocked() {
  # task-id 매개변수는 시그니처 유지 위해 받지만 Status는 ITEM_ID 기반이라 직접
  # 사용하지 않는다 (label·issue 매핑 없음).
  : "${1:-${TASK_ID:-}}"
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  if [[ -z "${AUTOPILOT_PROJECT_ITEM_ID:-}" ]]; then
    return 1
  fi
  local status
  status=$(gh api graphql -f query='
    query($id:ID!){ node(id:$id){ ... on ProjectV2Item {
      fieldValueByName(name:"Status"){ ... on ProjectV2ItemFieldSingleSelectValue { name } } } } }' \
    -f id="$AUTOPILOT_PROJECT_ITEM_ID" \
    --jq '.data.node.fieldValueByName.name // empty' 2>/dev/null || true)
  [[ "$status" == "Blocked" ]] && return 0
  return 1
}

# 자동 `[blocked]` prefix comment 발행 + Project Status=Blocked 전이 시도 (헌법 §5.2).
# AUTOPILOT_PROJECT_ITEM_ID env가 있으면 Status 전이도 시도, 없으면 comment만.
# 둘 다 best-effort — gh 미설치·실패 시 stderr WARN으로 알리고 비차단 진행.
gh_post_blocked_comment() {
  local task_id="$1"
  local body="$2"
  local issue
  if ! issue=$(task_issue_number "$task_id" 2>/dev/null); then
    echo "[$(now_iso)] WARN: task '$task_id' issue 매핑 실패 — [blocked] comment 건너뜀 (수동 보고 필요)" >&2
    return 1
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "[$(now_iso)] WARN: gh CLI 부재 — issue #$issue [blocked] comment 건너뜀" >&2
    return 1
  fi
  if ! gh issue comment "$issue" --body "$body" >/dev/null 2>&1; then
    echo "[$(now_iso)] WARN: gh issue comment 실패 (issue #$issue) — 수동 발행 필요" >&2
    return 1
  fi
  echo "[$(now_iso)] [blocked] prefix comment 발행: issue #$issue" >&2
  # NOTE: Project Status=Blocked 자동 전이는 미구현 (추후 도입). GraphQL mutation
  # `updateProjectV2ItemFieldValue`에는 project_id·field_id·option_id 세 추가 식별자가
  # 필요해 best-effort 수준의 env 한 개로는 호출 불가. 이전 구현의 `--field Status
  # --value Blocked`는 gh CLI의 정식 플래그가 아니어서 항상 실패했으므로 정직하게 제거.
  # 본 호출은 [blocked] comment 발행으로 차단 신호를 남기는 데 한정한다 — Status 전이는
  # 사람이 수동으로 (또는 추후 도입할 별도 헬퍼로) 처리.
  echo "[$(now_iso)] INFO: Project Status=Blocked 자동 전이는 미구현 — 수동 전이 필요 (issue #$issue)" >&2
  return 0
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# ----- 의존성 검사 -----

require_tool git
require_tool yq
require_tool claude

# ----- 시그널 처리: SIGTERM/SIGINT 시 자식 트리 정리 (orphan 방지) -----
# bash가 종료되면 EXIT trap으로 lock은 즉시 삭제되지만 subshell 내 claude는 orphan이 됨.
# 두 번째 start가 새 lock·새 워크트리 동시 수정 시도 → race. 이를 막기 위해 시그널을
# 받으면 descendants 전체 종료 후 exit. SIGKILL은 trap이 안 통하므로 미커버.

kill_descendants() {
  local parent="$1"
  # pgrep -P는 macOS·Linux 양쪽 동작
  local children
  children=$(pgrep -P "$parent" 2>/dev/null || true)
  local child
  # shellcheck disable=SC2086 # $children은 PID 공백 분리 — 의도적 word splitting
  for child in $children; do
    kill_descendants "$child"
    kill -TERM "$child" 2>/dev/null || true
  done
}

on_signal_exit() {
  kill_descendants "$$"
  exit 143  # 128 + SIGTERM(15) — EXIT trap이 lock 정리
}

trap 'on_signal_exit' TERM INT

# 해시 유틸 — macOS 기본 환경은 sha256sum·md5sum 미지원, shasum이 표준
if command -v sha256sum >/dev/null 2>&1; then
  HASH_BIN="sha256sum"
  HASH_ARGS=()
elif command -v shasum >/dev/null 2>&1; then
  HASH_BIN="shasum"
  HASH_ARGS=(-a 256)
else
  die "sha256sum 또는 shasum이 필요합니다 (macOS: shasum 기본 제공)"
fi

# ----- 첫 호출 setup (.gitignore 자동 관리) -----

# .gitignore에 새 nested 경로 패턴을 idempotent하게 추가하고, 기존 .loops/locks/
# 라인이 있으면 제거. 변경 발생 시 .gitignore 단일 파일만 staging해 단독 chore
# commit으로 격리 — 사용자의 staged/unstaged 변경과 commit 단위를 침범하지 않는다.
# 갱신·commit 실패 시 die (워크트리·lock 생성 진입 전 차단).
ensure_loops_setup() {
  local gitignore="$PROJECT_ROOT/.gitignore"
  local entry_wt='milestones/**/loops/**/.worktree/'
  local entry_lock='milestones/**/loops/**/.lock'
  local entry_legacy='.loops/locks/'

  local needs_wt=1 needs_lock=1 has_legacy=0
  if [[ -f "$gitignore" ]]; then
    grep -qxF "$entry_wt" "$gitignore" && needs_wt=0
    grep -qxF "$entry_lock" "$gitignore" && needs_lock=0
    grep -qxF "$entry_legacy" "$gitignore" && has_legacy=1
  fi

  if [[ $needs_wt -eq 0 ]] && [[ $needs_lock -eq 0 ]] && [[ $has_legacy -eq 0 ]]; then
    return 0
  fi

  # 기존 legacy 라인 제거 (텍스트 매칭으로 정확히)
  if [[ $has_legacy -eq 1 ]]; then
    local tmp
    tmp=$(mktemp 2>/dev/null) || die ".gitignore 임시 파일 생성 실패"
    # grep -v 는 매칭 라인이 전부라 출력이 비면 exit 1 — 정상 케이스(.gitignore가
    # legacy 라인 하나뿐)이므로 die 트리거 금지. 실제 오류(exit ≥2)만 die.
    local grc=0
    grep -vxF "$entry_legacy" "$gitignore" > "$tmp" || grc=$?
    if [[ $grc -ge 2 ]]; then
      rm -f "$tmp"
      die ".gitignore에서 기존 $entry_legacy 라인 제거 실패 (grep exit $grc)"
    fi
    mv "$tmp" "$gitignore" \
      || die ".gitignore 갱신 실패 (rename)"
  fi

  # 끝 newline 보장 (파서 호환)
  if [[ -s "$gitignore" ]]; then
    local last_byte
    last_byte=$(tail -c1 "$gitignore" 2>/dev/null)
    [[ "$last_byte" != "" ]] && echo "" >> "$gitignore"
  fi

  if [[ $needs_wt -eq 1 ]]; then
    echo "$entry_wt" >> "$gitignore" \
      || die ".gitignore 갱신 실패 ($entry_wt 추가)"
  fi
  if [[ $needs_lock -eq 1 ]]; then
    echo "$entry_lock" >> "$gitignore" \
      || die ".gitignore 갱신 실패 ($entry_lock 추가)"
  fi

  # .gitignore 단독 chore commit으로 격리.
  # `git commit -- <pathspec>`은 명시된 경로만 commit하므로, 사용자가 다른
  # 파일을 staging 중이어도 commit 단위가 섞이지 않는다.
  local commit_msg='chore: .gitignore — autopilot 워크트리·lock 패턴 자동 관리'
  ( cd "$PROJECT_ROOT" \
    && git add .gitignore >/dev/null 2>&1 \
    && git commit -q -m "$commit_msg" -- .gitignore >/dev/null 2>&1 ) \
    || die ".gitignore 자동 chore commit 실패 — 워크트리·lock 생성 중단"

  local legacy_msg=""
  [[ $has_legacy -eq 1 ]] && legacy_msg=" + legacy 라인 제거"
  echo "[$(now_iso)] .gitignore 갱신: 새 nested 패턴 추가${legacy_msg} (단독 chore commit)" >&2
}

# ----- 경로 계산 헬퍼 -----

compute_paths() {
  local raw_task_id="$1"
  validate_task_id "$raw_task_id"
  # 단일 컴포넌트 입력 시 'regular/' prefix 자동 추가. 이미 슬래시 있으면 그대로.
  local task_id
  task_id="$(normalize_task_id "$raw_task_id")"
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  local milestone="${task_id%%/*}"
  local child="${task_id#*/}"

  # SPEC 116 단일 컨벤션: feat 브랜치 이름의 slug 가 디렉토리 이름의 suffix.
  # find_feat_branch 가 input-id (child) 만으로 `feat/<child>-<slug>` 또는 `feat/<child>` 를 찾는다.
  # 매칭 없음(rc=1)은 legacy/uninitialized 상태로 간주해 slug-less fallback.
  # 매칭 2+ (rc=2)는 모호성으로 즉시 die.
  local feat_branch=""
  local ffb_rc=0
  set +e
  feat_branch=$(find_feat_branch "$child")
  ffb_rc=$?
  set -e
  case $ffb_rc in
    0) ;;                     # 단일 매칭
    1) feat_branch="" ;;      # 매칭 없음 — slug-less fallback
    2) die "여러 feat 브랜치가 input-id '$child' 와 매칭됩니다 (위 stderr 참조)." ;;
    *) die "find_feat_branch 비정상 종료 (rc=$ffb_rc)" ;;
  esac

  # feat 브랜치 이름에서 slug 추출 — `feat/<child>-<slug>` 패턴의 suffix.
  local slug=""
  if [[ -n "$feat_branch" ]]; then
    slug=$(slug_from_feat_branch "$child" "$feat_branch")
  fi

  local loop_dir_name="$child"
  if [[ -n "$slug" ]]; then
    loop_dir_name="$child-$slug"
  fi

  # v0.2 cutover: 워크트리·lock·메타 파일이 모두 milestones/<m>/loops/<c>[-<slug>]/ 단일 트리.
  LOOPS_DIR="$PROJECT_ROOT/milestones/$milestone/loops/$loop_dir_name"
  # LOOPS_DIR_REL: worktree 안의 SPEC.md canonical 경로 prefix.
  # SPEC.md 는 feat 브랜치에 동일 slug-bearing 경로로 commit 되어 worktree 에서
  # <wt>/$LOOPS_DIR_REL/SPEC.md 로 자연 노출된다.
  LOOPS_DIR_REL="milestones/$milestone/loops/$loop_dir_name"
  WT="$LOOPS_DIR/.worktree"
  LOCK_FILE="$LOOPS_DIR/.lock"
  # 정규화된 task-id 와 발견된 feat 브랜치를 caller 에게 노출.
  TASK_ID_NORMALIZED="$task_id"
  FEAT_BRANCH="$feat_branch"
}

# feat 브랜치 검색: input-id (정규화된 task-id 의 child 컴포넌트) 만으로 `feat/<id>` 또는
# `feat/<id>-<slug>` 패턴을 찾는다. SPEC 116 단일 컨벤션 — milestone prefix 는 사용하지 않는다.
#
# 반환:
#   0 + stdout 에 단일 브랜치 이름     — 매칭 정확히 1개
#   1 + stdout 빈 출력                — 매칭 없음 (legacy/uninitialized)
#   2 + stderr 모호성 안내            — 매칭 2개 이상 (caller 가 die 결정)
find_feat_branch() {
  local input_id="$1"
  local matches count
  matches=$(git -C "$PROJECT_ROOT" for-each-ref \
    --format='%(refname:short)' \
    "refs/heads/feat/$input_id" \
    "refs/heads/feat/$input_id-*" 2>/dev/null)
  if [[ -z "$matches" ]]; then
    return 1
  fi
  count=$(printf '%s\n' "$matches" | grep -c .)
  if [[ $count -ge 2 ]]; then
    echo "ERROR: 여러 feat 브랜치가 input-id '$input_id' 와 매칭됨 (모호):" >&2
    printf '%s\n' "$matches" >&2
    echo "수동으로 하나 남기고 다른 것 정리 후 재시도." >&2
    return 2
  fi
  printf '%s\n' "$matches"
  return 0
}

# feat 브랜치 이름에서 slug 추출. SPEC 116 단일 컨벤션 — `feat/<child>-<slug>` 패턴의 suffix.
# 인자: $1 = child(input-id), $2 = branch 이름.
# stdout: slug, 또는 빈 문자열(slug-less 브랜치·형식 불일치 시).
slug_from_feat_branch() {
  local child="$1"
  local branch="$2"
  local prefix="feat/$child"
  if [[ "$branch" == "${prefix}-"* ]]; then
    printf '%s\n' "${branch#${prefix}-}"
  fi
}

# ----- 동시성 락 -----

acquire_lock() {
  mkdir -p "$LOOPS_DIR"

  # 우리 task에 stale lock(죽은/무효 PID)이 있으면 자동 정리
  if [[ -f "$LOCK_FILE" ]]; then
    local stale_pid
    stale_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -z "$stale_pid" ]] || ! [[ "$stale_pid" =~ ^[0-9]+$ ]] \
       || ! kill -0 "$stale_pid" 2>/dev/null; then
      echo "[$(now_iso)] WARN: stale lock 자동 정리: $LOCK_FILE (PID '$stale_pid' 무효)" >&2
      rm -f "$LOCK_FILE"
    fi
    # else: PID 살아있음 — 아래 atomic create가 실패하며 die (정상 거부)
  fi

  # 새 nested 정책에서 lock 파일은 milestones/<m>/loops/<c>/.lock으로 분산.
  # MAX_CONCURRENT 카운트는 milestones/ 하위 모든 .lock 파일을 합산.
  local running=0
  if [[ -d "$PROJECT_ROOT/milestones" ]]; then
    running=$(find "$PROJECT_ROOT/milestones" -mindepth 4 -maxdepth 4 -type f -name '.lock' 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ $running -ge $MAX_CONCURRENT ]]; then
    die "이미 ${running}개 loop이 동작 중 (최대: $MAX_CONCURRENT). 새 loop 거부."
  fi

  # 원자적 락 생성 (noclobber로 race 방지)
  if ! ( set -C; echo $$ > "$LOCK_FILE" ) 2>/dev/null; then
    local existing_pid
    existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "?")
    die "task ${TASK_ID}가 이미 동작 중 (PID: $existing_pid). 종료 후 재실행."
  fi

  # shellcheck disable=SC2064  # $LOCK_FILE은 trap-set 시점에 확정된 값으로 고정 의도
  trap "rm -f $LOCK_FILE" EXIT
}

# ----- 게이트 헬퍼 -----

list_test_files() {
  # SPEC.md frontmatter test_paths가 있으면 override
  local override_paths
  override_paths=$(read_scope_yaml | yq '.test_paths[]' 2>/dev/null || true)

  local pathspecs=()
  if [[ -n "${override_paths// }" ]]; then
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      pathspecs+=("$p")
    done <<< "$override_paths"
  else
    # 기본: 일반 컨벤션 디렉토리 + co-located 파일명 패턴
    pathspecs=(
      'tests/**' 'test/**' '__tests__/**' 'src/**/__tests__/**' 'spec/**' 'src/test/**'
      '**/*.test.js' '**/*.test.ts' '**/*.test.jsx' '**/*.test.tsx' '**/*.test.py'
      '**/*.spec.js' '**/*.spec.ts' '**/*.spec.rb'
      '**/*_test.go' '**/*_test.py' '**/*_test.rb'
      '**/test_*.py' '**/*_spec.rb'
    )
  fi

  local tracked
  tracked=$(cd "$WT" 2>/dev/null && git ls-files -- "${pathspecs[@]}" 2>/dev/null | sort -u)

  # test_sweep_paths 선언 시 매칭 파일을 weakening 비교 셋에서 제외 (issue #66).
  # 합법적 sweep(예: 단순 rename, 광범위 cleanup 후 신규 파일 추가)을 SPEC 작성 시점에
  # 사용자 승인으로 화이트리스트화. 워커가 워크트리의 SPEC.md를 수정하면 scope.exclude
  # 게이트가 차단(헌법 §7) — 안전.
  local sweep_files
  sweep_files=$(list_sweep_files)
  if [[ -z "$sweep_files" ]]; then
    echo "$tracked"
  else
    # subtract sweep_files from tracked. awk associative array로 O(n+m) 비교.
    # ENVIRON 경유: awk -v는 값의 백슬래시를 이스케이프로 해석(예: '\b'→backspace)해
    # 백슬래시 포함 경로(Linux 합법)에서 오동작. ENVIRON은 원시 문자열 전달.
    sweep_files="$sweep_files" awk '
      BEGIN { n = split(ENVIRON["sweep_files"], lines, "\n"); for (i=1; i<=n; i++) if (lines[i] != "") seen[lines[i]] = 1 }
      !seen[$0]
    ' <<< "$tracked"
  fi
}

list_sweep_files() {
  # SPEC.md frontmatter test_sweep_paths에 매칭되는 git-tracked 파일 (sorted unique).
  # 미선언·매칭 0건 시 빈 출력.
  local sweep_paths
  sweep_paths=$(read_scope_yaml | yq '.test_sweep_paths[]' 2>/dev/null || true)
  [[ -z "${sweep_paths// }" ]] && return 0

  local pathspecs=()
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    pathspecs+=("$p")
  done <<< "$sweep_paths"
  [[ ${#pathspecs[@]} -eq 0 ]] && return 0

  # bash 3.2: 빈 배열 우회는 위에서 ${#pathspecs[@]} -eq 0 가드로 이미 처리.
  cd "$WT" 2>/dev/null && git ls-files -- "${pathspecs[@]}" 2>/dev/null | sort -u
}

# test_sweep_paths가 선언됐으나 이터 시작 시점에 매칭 파일이 0건이면 stderr 경고.
# halt하지 않음 — 패턴 오타·신규 파일 추가 전 상태 등 정당한 케이스 보존.
warn_sweep_no_match() {
  local sweep_declared
  sweep_declared=$(read_scope_yaml | yq 'has("test_sweep_paths")' 2>/dev/null || echo "false")
  [[ "$sweep_declared" != "true" ]] && return 0

  local sweep_files
  sweep_files=$(list_sweep_files)
  if [[ -z "$sweep_files" ]]; then
    echo "[$(now_iso)] WARN: SPEC.md의 test_sweep_paths가 선언됐으나 매칭 파일 없음 — 패턴 오타 또는 신규 파일 추가 전 상태 가능" >&2
  fi
}

# 주어진 파일 목록의 결합 해시. 누락된 파일은 sha256sum이 silent 실패하므로 자연스레
# 결합 해시가 변함 → 삭제 감지. 헌법 §0 TDD Iron Law(RED→GREEN)를 깨뜨리지 않기 위해
# "이터 시작 시점에 존재한 파일들"의 해시만 비교 — 새 테스트 추가는 weakening 아님.
hash_listed_files() {
  local files="$1"
  if [[ -z "$files" ]]; then
    echo "no-files"
    return
  fi
  # bash 3.2: 빈 배열 "${arr[@]}"는 set -u에서 unbound 에러 → ${arr[@]+"${arr[@]}"}로 우회
  echo "$files" \
    | xargs -I{} "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} "$WT/{}" 2>/dev/null \
    | "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} \
    | awk '{print $1}'
}

hash_deps() {
  local manifests
  manifests=$(find "$WT" -maxdepth 2 -type f \
    \( -name 'package.json' -o -name 'requirements.txt' -o -name 'Cargo.toml' \
       -o -name 'go.mod' -o -name 'pyproject.toml' -o -name 'Gemfile' \
       -o -name 'pom.xml' -o -name 'build.gradle' \) 2>/dev/null | sort)
  if [[ -z "$manifests" ]]; then
    echo "no-manifests"
  else
    # bash 3.2 빈 배열 우회 (hash_listed_files 동일 패턴)
    echo "$manifests" | xargs -I{} "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} {} 2>/dev/null \
      | "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} | awk '{print $1}'
  fi
}

read_scope_yaml() {
  # SPEC.md 단일 contract 경로: <WT>/<LOOPS_DIR_REL>/SPEC.md
  # (feat 브랜치 commit으로 자연 포함)
  local spec_path="$WT/$LOOPS_DIR_REL/SPEC.md"
  sed -n '1,/^---$/{
    1d
    /^---$/d
    p
  }' "$spec_path" 2>/dev/null
}

diff_vs_scope() {
  local base_sha="$1"
  local scope_yaml include_patterns exclude_patterns committed working changed
  scope_yaml=$(read_scope_yaml)
  include_patterns=$(echo "$scope_yaml" | yq '.scope.include[]' 2>/dev/null || true)
  exclude_patterns=$(echo "$scope_yaml" | yq '.scope.exclude[]' 2>/dev/null || true)
  # 커밋된 diff: BASE..HEAD (워크트리 생성 시점부터 누적 변경) — HEAD~1..HEAD는 한 이터에 commit이
  # 2개 이상(워커 코드 commit + 드라이버 메타 commit) 발생할 때 가장 최근 commit만 보여 직전 commit의
  # 위반을 false-negative로 통과시키는 결함이 있다 (SPEC 81). BASE..HEAD는 누적이라 모든 이터의
  # 모든 commit을 포함하지만, 이전 이터의 in-scope commit은 재검사돼도 동일하게 통과한다.
  # 작업 트리 변경: claude 비정상 종료로 미커밋 변경이 남는 경우 추가로 차단.
  committed=$(cd "$WT" && git diff --name-only "$base_sha" HEAD 2>/dev/null || true)
  working=$(cd "$WT" && git diff --name-only HEAD 2>/dev/null || true)
  changed=$(printf '%s\n%s\n' "$committed" "$working" | sort -u | grep -v '^$' || true)

  [[ -z "$changed" ]] && return 0

  local out_of_scope=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    # 프레임워크 파일은 항상 scope 검사에서 제외 (워커 프레임워크 메타파일)
    # CLAUDE.md는 SPEC scope.exclude로 통제 — skip-worktree로 보통은 diff에 안 잡히지만,
    # 워커가 unskip + commit하면 여기서 정상 catch되어야 함 (워크트리 셋업 직후 자동 skip 처리).
    # SPEC.md(워커 명세)와 DONE(종료 신호)은 milestones/<m>/loops/<c>/ 단일 트리 안에 있으므로
    # 그 경로 패턴으로 제외. 이터간 메타(handoff/notes/done/blocked)는 task issue
    # body·prefix comments로 위임됐으므로 워크트리 파일이 존재하지 않는다 (헌법 §11).
    case "$file" in
      milestones/*/loops/*/SPEC.md|DONE) continue ;;
    esac

    # exclude 패턴 매칭 → 위반
    local excluded=0
    while IFS= read -r exc; do
      [[ -z "$exc" ]] && continue
      # shellcheck disable=SC2053  # 의도적 glob 매칭: scope 패턴은 src/** 같은 와일드카드
      if [[ "$file" == $exc ]]; then
        out_of_scope+="$file (excluded by $exc)\n"
        excluded=1
        break
      fi
    done <<< "$exclude_patterns"
    [[ $excluded -eq 1 ]] && continue

    # include 패턴 중 하나에도 매칭 안 되면 위반
    local matched=0
    while IFS= read -r inc; do
      [[ -z "$inc" ]] && continue
      # shellcheck disable=SC2053  # 의도적 glob 매칭
      if [[ "$file" == $inc ]]; then
        matched=1
        break
      fi
    done <<< "$include_patterns"

    if [[ $matched -eq 0 ]]; then
      out_of_scope+="$file (not in include)\n"
    fi
  done <<< "$changed"

  if [[ -n "$out_of_scope" ]]; then
    printf "%b" "$out_of_scope"
  fi
}

grep_new_suppressors() {
  # 커밋된 diff(BASE..HEAD) + working tree 변경 양쪽 검사 (미커밋 suppressor도 catch).
  # SPEC.md는 워커 명세(헌법 인용 등 false positive 발생)이므로 검사 제외.
  # 이터간 메타는 task issue body·prefix comments로 위임됐으므로 워크트리 파일 검사 대상 아님 (헌법 §11).
  # BASE..HEAD 근거는 diff_vs_scope 주석 참조 (SPEC 81).
  local base_sha="$1"
  cd "$WT" || return
  local meta_exclude=(
    ':(exclude)milestones/*/loops/*/SPEC.md'
  )
  {
    git diff "$base_sha" HEAD -- "${meta_exclude[@]}" 2>/dev/null
    git diff HEAD -- "${meta_exclude[@]}" 2>/dev/null
  } \
    | grep -E '^\+' \
    | grep -E '#[[:space:]]*noqa|@ts-ignore|eslint-disable|#pragma[[:space:]]+warning[[:space:]]+disable' \
    || true
}

check_secrets() {
  command -v gitleaks >/dev/null 2>&1 || return 0
  # BASE..HEAD 누적 commit + 미커밋 staged 양쪽 검사. BASE..HEAD 근거는 diff_vs_scope 주석 참조 (SPEC 81).
  # 비고: gitleaks는 unstaged-tracked 변경의 직접 스캔 옵션이 없음 (--no-git은 워크트리
  #       전체 스캔이라 노이즈 큼) → unstaged-tracked는 본 게이트의 의도된 미커버.
  #       헌법이 매 이터 commit 강제하므로 일반 흐름에선 gap 없음.
  local base_sha="$1"
  {
    cd "$WT" && gitleaks detect --log-opts="$base_sha..HEAD" --no-banner 2>&1 || true
    cd "$WT" && gitleaks detect --staged --no-banner 2>&1 || true
  }
}

# 워크트리 생성 시점의 부모 브랜치 HEAD SHA를 읽어 반환. 부재·빈값이면 비-0 exit.
# BASE 메타는 `$WT/.iterations/BASE_SHA` 단일 파일 (info/exclude로 자기 참조 회피).
# 워크트리 생성 시 1회 기록되며 이후 변경되지 않는다 (SPEC 81 AC1).
read_base_sha() {
  local f="$WT/.iterations/BASE_SHA"
  [[ -f "$f" ]] || return 1
  local sha
  sha=$(tr -d '[:space:]' < "$f" 2>/dev/null)
  [[ -n "$sha" ]] || return 1
  printf '%s' "$sha"
}

count_fix_symptom_streak() {
  cd "$WT" && git log --pretty=format:%s -2 2>/dev/null \
    | { grep -c '^fix:symptom' || true; }
}

detect_oscillation() {
  local commits
  commits=$(cd "$WT" && git log --pretty=tformat:%H -4 2>/dev/null || true)
  [[ $(echo "$commits" | wc -l | tr -d ' ') -lt 4 ]] && return 0

  local sets=()
  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    sets+=("$(cd "$WT" && git diff-tree --no-commit-id --name-only -r "$commit" 2>/dev/null | sort | "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} | awk '{print $1}')")
  done <<< "$commits"

  if [[ ${#sets[@]} -eq 4 ]] \
     && [[ "${sets[0]}" == "${sets[2]}" ]] \
     && [[ "${sets[1]}" == "${sets[3]}" ]] \
     && [[ "${sets[0]}" != "${sets[1]}" ]]; then
    echo "최근 4 커밋이 두 상태로 토글됨"
  fi
}

elapsed_minutes() {
  echo $(( ( $(date +%s) - START_TIME ) / 60 ))
}

# ----- halt (게이트 위반 시 자동 ESCALATION) -----

halt() {
  local reason="$1"
  echo "[$(now_iso)] HALT: $reason" >&2

  # 진행 중 변경을 stash (있으면) — stash list 카운트 비교로 성공 판정 (git locale 독립)
  local stash_before stash_after
  stash_before=$(cd "$WT" && git stash list 2>/dev/null | wc -l | tr -d ' ')
  (cd "$WT" && git add -A && git stash push -m "auto-stash by loop.sh halt: $reason" >/dev/null 2>&1) || true
  stash_after=$(cd "$WT" && git stash list 2>/dev/null | wc -l | tr -d ' ')
  if [[ $stash_after -gt $stash_before ]]; then
    echo "[$(now_iso)] WARN: 미커밋 변경이 stash에 보관됨" >&2
    echo "  복구: cd $WT && git stash list / git stash pop" >&2
  fi

  # 자동 [blocked] prefix comment 발행 + Project Status=Blocked 전이 시도 (헌법 §5.2, SPEC AC5).
  # 워크트리에 메타 파일을 쓰지 않는다 — 이터간 상태는 task issue body·comments에 위임.
  local blocked_body
  blocked_body=$(cat <<EOF
[blocked] 에스컬레이션 보고 (드라이버 자동 작성)

**작업**: $TASK_ID
**이터레이션**: 자동 정지
**카테고리**: config-gap | spec-gap | architecture-gap | environment-gap | other (사람 분류)
**트리거**: 객관 게이트 위반 — $reason

### 현재 상태

드라이버가 매 이터 후 게이트를 검사한 결과 위반이 감지되어 자동 정지함.

### 문제

$reason

### 처리

다음 중 하나:
1. 가설 점검 후 작업 명세(scope·verify) 조정
2. 후속 메모를 \`[notes]\` prefix comment로 누적
3. \`gh issue comment <task-issue> --body '[unblocked] <해제 사유>'\` 발행해 Blocked 해제 후 재시작 (\`[resume]\` prefix도 동등)

자세한 내용은 워크트리 루트의 .iterations/ 디렉토리 최근 로그 참조.
EOF
)
  gh_post_blocked_comment "$TASK_ID" "$blocked_body" || true

  exit 1
}

# ----- 이터레이션 호출 -----

iterate() {
  local n
  n=$(($(find "$WT/.iterations" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ') + 1))

  echo "[$(now_iso)] 이터 #$n 시작"

  # test_sweep_paths 선언됐으나 매칭 0건이면 경고 (issue #66, AC2).
  warn_sweep_no_match

  # 시작 시점의 테스트 파일 set 캡처. 종료 시점에 같은 set만 다시 해시해 비교 →
  # 삭제·수정만 감지, 신규 추가는 통과 (TDD RED 단계 보호).
  # list_test_files()는 test_sweep_paths 매칭 파일을 결과에서 제외하므로
  # 자동으로 weakening 비교 셋에서 sweep 영역이 빠진다 (AC1·5).
  local start_test_files start_hash_tests start_hash_deps
  start_test_files=$(list_test_files)
  start_hash_tests=$(hash_listed_files "$start_test_files")
  start_hash_deps=$(hash_deps)

  # 비동기 실행 + wait — bash trap은 동기 명령 안에서 deferred되므로 wait를 써야
  # SIGTERM/SIGINT가 즉시 처리돼 자식 트리 정리 가능 (orphan 방지)
  # SPEC.md stdin 경로: 단일 contract — worktree의 milestones/<m>/loops/<c>/SPEC.md.
  local spec_stdin_path="$LOOPS_DIR_REL/SPEC.md"
  local exit_code=0
  (
    cd "$WT"
    exec claude \
      --print \
      --no-session-persistence \
      --dangerously-skip-permissions \
      --system-prompt-file CLAUDE.md \
      --add-dir . \
      --output-format json \
      < "$spec_stdin_path" \
      > ".iterations/$n.log" 2>&1
  ) &
  local claude_pid=$!
  wait "$claude_pid" || exit_code=$?

  echo "[$(now_iso)] 이터 #$n 종료 (exit: $exit_code). 게이트 검사..."

  # 이터간 메타(handoff/notes/done/blocked)는 task issue body·prefix comments로 발행됨 (헌법 §11).
  # 워크트리에는 메타 파일이 생성되지 않으므로 드라이버 자동 메타 commit 단계가 없다.

  if [[ $exit_code -ne 0 ]]; then
    CLAUDE_FAIL_STREAK=$((CLAUDE_FAIL_STREAK + 1))
    echo "WARN: claude 호출이 0이 아닌 exit code 반환 (연속 실패: $CLAUDE_FAIL_STREAK). .iterations/$n.log 확인 권장."
    if [[ $CLAUDE_FAIL_STREAK -ge ${CLAUDE_FAIL_STREAK_LIMIT:-3} ]]; then
      halt "claude 비정상 exit ${CLAUDE_FAIL_STREAK}회 연속 (rate limit·네트워크·인증 의심). .iterations/$n.log 확인."
    fi
  else
    CLAUDE_FAIL_STREAK=0
  fi

  # 종료 신호 검사 (먼저) — 헌법 §12, SPEC 134 AC2.
  # 정식 검출 키: task issue에 LOOP_DONE_LABEL이 붙어 있는지 (task_status_is_done).
  # 호환 OR 결합: 0.2.0 잔존 $WT/DONE 파일 신호도 수용 — milestone 종료 후
  # 사용자 결정으로 제거 예정 (SPEC 134 §제약 "호환 OR 결합 유지").
  if task_status_is_done "$TASK_ID" || [[ -f "$WT/DONE" ]]; then
    return 100   # 메인 루프에서 정상 종료 처리
  fi
  # 워커가 진행 불가 보고 시 task issue에 [blocked] prefix comment + Status=Blocked 전이 (헌법 §5.2, SPEC AC5).
  # 드라이버는 Project Status 또는 최신 comment prefix로 차단 신호를 감지한다 (SPEC AC4).
  if task_status_is_blocked "$TASK_ID"; then
    return 101   # 메인 루프에서 [blocked] 처리
  fi

  # 객관 게이트 9종
  # 테스트 약화: 시작 시점의 파일 set만 다시 해시. 신규 추가는 무시 (TDD RED 보호).
  if [[ "$start_hash_tests" != "no-files" ]] \
     && [[ "$(hash_listed_files "$start_test_files")" != "$start_hash_tests" ]]; then
    halt "테스트 약화 — 기존 테스트 파일 변경 감지 (삭제·수정 의심)"
  fi
  if [[ "$start_hash_deps" != "no-manifests" ]] \
     && [[ "$(hash_deps)" != "$start_hash_deps" ]]; then
    halt "의존성 변경 — 매니페스트 해시 변경"
  fi

  # BASE SHA 메타 — 워크트리 생성 시점의 부모 브랜치 HEAD. 게이트 diff 비교 기준 (SPEC 81 AC2).
  # 부재 시 명확한 에러로 halt (AC6: false-positive 통과 차단).
  local base_sha
  if ! base_sha=$(read_base_sha); then
    halt "BASE SHA 메타 부재 — 워크트리 ${WT}의 .iterations/BASE_SHA 파일이 없습니다. 본 변경 이전에 생성된 pre-existing 워크트리로 의심됩니다. cleanup 후 재생성 필요 (loop.sh cleanup ${TASK_ID})."
  fi

  local out_of_scope new_supp streak osc
  out_of_scope=$(diff_vs_scope "$base_sha")
  [[ -n "$out_of_scope" ]] && halt "Scope 위반: $out_of_scope"

  new_supp=$(grep_new_suppressors "$base_sha")
  [[ -n "$new_supp" ]] && halt "Suppressor 신규 추가: $new_supp"

  if command -v gitleaks >/dev/null 2>&1; then
    local secrets
    secrets=$(check_secrets "$base_sha")
    [[ -n "$secrets" ]] && halt "Secrets 의심: $secrets"
  fi

  streak=$(count_fix_symptom_streak)
  [[ $streak -ge 2 ]] && halt "fix:symptom streak (2회 연속)"

  osc=$(detect_oscillation)
  [[ -n "$osc" ]] && halt "진동 패턴: $osc"

  return 0
}

# ----- subcommand: prepare -----

cmd_prepare() {
  cat >&2 <<'EOF'
prepare 서브커맨드는 제거되었습니다.
새 spec 스킬을 사용하세요:

  Skill(skill: "spec", args: "<task-id>")

대화형으로 SPEC.md를 생성합니다. 자세한 내용:
  plugins/autopilot/skills/spec/SKILL.md
EOF
  exit 2
}

# ----- subcommand: start -----

cmd_start() {
  local task_id="$1"
  shift || true
  [[ -z "$task_id" ]] && die "사용: $0 start <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>] [--no-pr]"

  local max_iterations_override="" wall_clock_minutes_override="" watch_mode=0 spec_path="" no_pr=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-iterations)
        max_iterations_override="$2"
        shift 2
        ;;
      --wall-clock-minutes)
        wall_clock_minutes_override="$2"
        shift 2
        ;;
      --watch)
        watch_mode=1
        shift
        ;;
      --spec)
        spec_path="$2"
        shift 2
        ;;
      --no-pr)
        # AC2 (SPEC 103): PR 자동 생성 opt-out. 지정 시 DONE 직후 PR phase 건너뜀.
        # default(없음): PR phase가 실행됨 (AC1).
        no_pr=1
        shift
        ;;
      *)
        die "알 수 없는 옵션: $1"
        ;;
    esac
  done

  compute_paths "$task_id"
  # 정규화된 task-id를 이후 출력·logging에 사용 (regular/ prefix 포함)
  task_id="$TASK_ID_NORMALIZED"
  TASK_ID="$task_id"
  ensure_loops_setup

  MAX_ITERATIONS="${max_iterations_override:-${MAX_ITERATIONS:-30}}"
  WALL_CLOCK_MINUTES="${wall_clock_minutes_override:-${WALL_CLOCK_MINUTES:-120}}"
  MAX_CONCURRENT="${MAX_CONCURRENT:-3}"
  WATCH_MODE="$watch_mode"

  # 1. --spec 외부 SPEC 전달 처리 (legacy 진입로 — main 작업트리에 SPEC을 직접 둠)
  if [[ -n "$spec_path" ]]; then
    [[ -f "$spec_path" ]] || die "외부 SPEC 파일을 찾을 수 없음: $spec_path"
    mkdir -p "$LOOPS_DIR"
    cp "$spec_path" "$LOOPS_DIR/SPEC.md"
    echo "외부 SPEC 파일 복사: $spec_path → $LOOPS_DIR/SPEC.md"
  fi

  # 1.5. 단일 contract: feat/<input-id>[-<slug>] 브랜치를 compute_paths 에서 이미 검색·캐시 (FEAT_BRANCH).
  # 없으면 즉시 abort — legacy task-branch fallback 분기는 제거됨 (v0.3 cutover).
  if [[ -z "${FEAT_BRANCH:-}" ]]; then
    local _child="${task_id#*/}"
    die "feat 브랜치 부재 — 'feat/${_child}' 또는 'feat/${_child}-<slug>' 브랜치가 main repo에 없음.\n먼저 실행하세요: Skill(skill: \"spec\", args: \"$_child\")"
  fi
  BRANCH="$FEAT_BRANCH"

  # 2. SPEC.md 존재·내용 검증 — feat 브랜치 commit에서 읽음.
  local spec_content=""
  spec_content=$(git -C "$PROJECT_ROOT" show "${BRANCH}:${LOOPS_DIR_REL}/SPEC.md" 2>/dev/null) \
    || die "feat 브랜치 '${BRANCH}'의 HEAD에 SPEC.md(${LOOPS_DIR_REL}/SPEC.md) 부재 — spec 스킬로 SPEC 작성·commit 필요."

  # 2.5. [NEEDS CLARIFICATION] 마커 검사 (락 획득 전, 양 contract 공통)
  if grep -q '\[NEEDS CLARIFICATION' <<< "$spec_content"; then
    die "SPEC.md에 미해결 [NEEDS CLARIFICATION] 마커가 있습니다.\n해결: Skill(skill: \"spec\", args: \"$task_id --resume\")"
  fi

  # 3. placeholder 검사
  local placeholders
  placeholders=$(grep -oE '\{\{[^}]+\}\}' <<< "$spec_content" 2>/dev/null || true)
  if [[ -n "$placeholders" ]]; then
    die "채워지지 않은 placeholder가 있습니다: $(echo "$placeholders" | tr '\n' ' ')\nSPEC.md를 편집하세요."
  fi

  # 4. scope.include 비어있으면 거부 (start에서)
  local include_count
  include_count=$(sed -n '1,/^---$/{
    1d
    /^---$/d
    p
  }' <<< "$spec_content" | yq '.scope.include | length' 2>/dev/null)
  if [[ "${include_count:-0}" -eq 0 ]]; then
    die "SPEC.md의 scope.include가 비어 있습니다. 최소 한 패턴 명시 필요 (예: 'src/**'·'**/*')"
  fi

  # 5. 락 획득
  acquire_lock

  # 5.5. 완료 신호 label self-bootstrap (SPEC 134 AC5).
  # task storage에 LOOP_DONE_LABEL이 없으면 자동 생성. 권한 부족·gh 부재 시
  # WARN 후 비차단 — 워커가 label 추가에 실패해도 $WT/DONE 호환 OR 결합으로
  # 완료 감지가 깨지지 않는다.
  ensure_label_exists "$LOOP_DONE_LABEL" || true

  # 6. 워크트리 생성 (없는 경우)
  if [[ ! -d "$WT" ]]; then
    echo "[$(now_iso)] 워크트리 생성 시작: $WT"

    # 새 nested 정책: WT 부모(loops_dir)는 이미 SPEC.md 존재 시 만들어짐.
    # 일관성을 위해 mkdir -p로 보장.
    mkdir -p "$(dirname "$WT")"

    # 단일 contract: 기존 feat 브랜치를 base로 worktree 체크아웃 (-b 없음).
    git -C "$PROJECT_ROOT" worktree add "$WT" "$BRANCH" \
      || die "git worktree add 실패 (feat 브랜치 체크아웃): $WT (브랜치: $BRANCH)"
    # 사후 검증: worktree HEAD에 SPEC.md 자연 노출 확인 (spec 스킬이 commit했어야)
    if [[ ! -f "$WT/$LOOPS_DIR_REL/SPEC.md" ]]; then
      die "feat 브랜치 ${BRANCH} 워크트리 HEAD에 SPEC.md 부재 (기대: $WT/$LOOPS_DIR_REL/SPEC.md)"
    fi

    # BASE SHA 메타 캡처 (SPEC 81 AC1) — 워크트리 생성 직후, baseline commit 전.
    # 게이트(scope·suppressor·secret)의 BASE..HEAD diff 기준점. BASE_SHA는 git add된 적
    # 없는 untracked 파일이므로 `git diff --name-only` 시야 밖 — 자기 참조 게이트 검사에
    # 잡히지 않는다. info/exclude는 별개 효과로 워크트리 git status에서 `.iterations/`
    # 노이즈를 억제할 뿐 untracked 상태와는 무관.
    # `.iterations/`는 iter raw 로그 디렉토리도 겸한다 (이전 별도 mkdir 블록 통합).
    mkdir -p "$WT/.iterations" \
      || die ".iterations 디렉토리 생성 실패: $WT/.iterations"
    local _base_sha_capture
    _base_sha_capture=$(git -C "$WT" rev-parse HEAD 2>/dev/null) \
      || die "BASE SHA 캡처 실패 (git rev-parse HEAD): $WT"
    printf '%s\n' "$_base_sha_capture" > "$WT/.iterations/BASE_SHA" \
      || die "BASE SHA 메타 기록 실패: $WT/.iterations/BASE_SHA"

    # 헌법을 워크트리 CLAUDE.md로 복사
    cp "$SCRIPT_DIR/constitution.md" "$WT/CLAUDE.md" \
      || die "constitution.md를 찾을 수 없음: $SCRIPT_DIR/constitution.md"
    # 헌법 cp는 워크트리-local 사실상의 untracked. main repo의 CLAUDE.md가 tracked일 때만
    # skip-worktree로 git 추적에서 분리해 suppressor·scope 등 게이트의 false-positive를 차단.
    # tracked 아니면 cp는 untracked가 되고 info/exclude로 이미 가려지므로 skip-worktree 불필요.
    # 워커가 의도적으로 헌법을 수정·commit하려면 `--no-skip-worktree` 풀어야 함 (scope 게이트 catch).
    if git -C "$WT" ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1; then
      git -C "$WT" update-index --skip-worktree CLAUDE.md \
        || die "skip-worktree 설정 실패: $WT/CLAUDE.md"
    fi

    # 이터간 메타(handoff/notes/done/blocked)는 task issue body·prefix comments로 발행됨 (헌법 §11).
    # 워크트리에는 메타 파일을 시드·commit하지 않는다 — feat 브랜치 HEAD가 그대로 BASE SHA가 된다.

    # 워크트리 로컬 비추적 등록 — .iterations/는 iter raw 로그, 어떤 git 브랜치에도
    # commit되지 않음. DONE은 종료 신호로 worktree-local.
    # 등록 위치 선택: --git-common-dir (공유 commondir의 info/exclude).
    # 배경: git은 워크트리별 $GIT_DIR/info/exclude(--git-dir)도 참조하지만 그 효과는
    #       해당 워크트리에만 한정된다. 본 패턴(CLAUDE.md·.iterations/·DONE)은 본 task의
    #       워크트리 동안만 필요하지만, autopilot worktree는 task별로 새로 생성되므로
    #       commondir에 idempotent하게 누적해도 충돌·중복은 없다. 단순성을 위해 commondir
    #       선택. 다른 워크트리·메인 트리에도 위 3 패턴이 untracked로 노출되지 않게
    #       정합되는 부수 효과는 의도된 것 (모두 ephemeral·메타 파일).
    local wt_common_dir
    wt_common_dir="$(git -C "$WT" rev-parse --git-common-dir)"
    [[ "$wt_common_dir" != /* ]] && wt_common_dir="$WT/$wt_common_dir"
    mkdir -p "$wt_common_dir/info"
    local exclude_file="$wt_common_dir/info/exclude"
    touch "$exclude_file"
    for pat in "CLAUDE.md" ".iterations/" "DONE"; do
      grep -qxF "$pat" "$exclude_file" 2>/dev/null || echo "$pat" >> "$exclude_file"
    done

    echo "[$(now_iso)] 워크트리 생성 완료: $WT"
    echo "브랜치: $BRANCH"
  else
    echo "[$(now_iso)] 기존 워크트리 사용: $WT"
  fi

  # 7. 이터레이션 루프
  START_TIME=$(date +%s)
  CLAUDE_FAIL_STREAK=0
  local n=0

  while true; do
    n=$((n + 1))

    set +e
    iterate
    local iter_status=$?
    set -e

    if [[ $iter_status -eq 100 ]]; then
      echo "[$(now_iso)] DONE 신호 감지. 정상 종료."

      # PR 생성·재사용 phase. SPEC 103 AC1: default로 실행 (opt-in 플래그 불필요).
      # SPEC 103 AC2: --no-pr 플래그가 지정되면 건너뜀.
      # 워크트리·로컬 브랜치는 후속 단계(리뷰 모니터·자동 fix)를 위해 보존한다.
      if (( no_pr == 1 )); then
        echo "[$(now_iso)] --no-pr 플래그 감지 — PR phase 건너뜀"
      else
        # ----- SPEC 123: request_review opt-in 감지 (PR phase 진입 *전*에 확정) -----
        # AC#1·#3: opt-in 활성 시 PR phase 진입 *직전*에 pre-PR rebase 실행.
        # AC#4·#12·#16·#17: opt-in 활성 시 PR phase 직후 review-fix-phase background dispatch.
        local spec_md="$WT/$LOOPS_DIR_REL/SPEC.md"
        local request_review_val=""
        if [[ -f "$spec_md" ]]; then
          if command -v yq >/dev/null 2>&1; then
            request_review_val=$(sed -n '1,/^---$/{
              1d
              /^---$/d
              p
            }' "$spec_md" | yq '.request_review // false' 2>/dev/null | tr -d '[:space:]')
          else
            echo "WARN: yq 미설치 — SPEC frontmatter request_review 파싱 불가, opt-in 비활성으로 처리" >&2
          fi
        fi

        # ----- AC#1·#3: pre-PR rebase (request_review opt-in 시) -----
        if [[ "$request_review_val" == "true" ]]; then
          echo "[$(now_iso)] request_review opt-in — pre-PR rebase (AC#1·#3)"
          if ! bash "$SCRIPT_DIR/rebase-phase.sh" "$WT" "$BRANCH" "$PROJECT_ROOT"; then
            echo "ERROR: pre-PR rebase 실패 — PR phase 건너뜀, 워크트리·브랜치 보존" >&2
            exit 1
          fi
        fi

        echo "[$(now_iso)] PR phase 진입 (default — 건너뛰려면 --no-pr 사용)"
        if ! bash "$SCRIPT_DIR/pr-phase.sh" "$WT" "$BRANCH" "$TASK_ID" "$PROJECT_ROOT"; then
          echo "ERROR: PR phase 실패 — worktree·branch는 보존됨. 진단 후 재시도하세요." >&2
          exit 1
        fi

        # ----- AC#4: PR 생성 성공 후 review-fix 루프 background dispatch -----
        # review-fix-phase 내부에서 rebase-phase·cleanup-phase를 호출하므로 loop.sh는
        # 진입점인 review-fix-phase만 dispatch한다.
        if [[ "$request_review_val" == "true" ]]; then
          # PR 번호 추출 (head 브랜치로 조회)
          local pr_num
          # pr-phase.sh가 방금 생성·재사용한 open PR만 매칭 — `--state all`은
          # 동일 head 브랜치의 과거 closed PR을 잘못 반환할 위험.
          pr_num=$( cd "$WT" && gh pr list --head "$BRANCH" --state open \
                      --json number --jq '.[0].number' 2>/dev/null || echo "")
          if [[ -z "$pr_num" ]]; then
            echo "WARN: request_review: true 인데 PR 번호 조회 실패 — review-fix 루프 dispatch skip" >&2
          else
            echo "[$(now_iso)] request_review: true — review-fix-phase.sh background dispatch (PR #$pr_num)"
            # review-fix-phase.sh는 PR이 MERGED/CLOSED/APPROVED 또는 owner cmd(/done·합격·통과)
            # 가 들어올 때까지 background로 폴링하며, 종료 시 자체적으로 cleanup-phase.sh를
            # 호출해 worktree·feat 로컬·feat origin을 정리한다. allowed-tools 환경 변수는
            # 이미 위에서 export됨.
            nohup bash "$SCRIPT_DIR/review-fix-phase.sh" \
                  "$WT" "$BRANCH" "$TASK_ID" "$PROJECT_ROOT" "$pr_num" \
                  > "$WT/.iterations/review-fix-phase.log" 2>&1 < /dev/null &
            disown $!
          fi
        fi
      fi

      # cleanup 시 archive로 이동하도록 안내만
      echo ""
      echo "task $task_id 완료."
      echo "메타 파일 정리 및 워크트리 제거:"
      echo "  $0 cleanup $task_id"
      exit 0
    fi
    if [[ $iter_status -eq 101 ]]; then
      echo "[$(now_iso)] 차단 신호 감지 (Status=Blocked / [blocked] comment). 사람 처리 대기."
      if [[ $WATCH_MODE -eq 1 ]]; then
        local watch_timeout_hours="${WATCH_TIMEOUT_HOURS:-24}"
        local poll_interval=60
        local poll_count=0
        local max_polls=$(( watch_timeout_hours * 3600 / poll_interval ))

        echo "[$(now_iso)] --watch 모드: 차단 신호 해제 polling 중 (60초 간격, 최대 ${watch_timeout_hours}시간, Ctrl+C로 종료)..."
        while task_status_is_blocked "$TASK_ID"; do
          sleep $poll_interval
          poll_count=$((poll_count + 1))
          # 매 5분(5 polls)마다 진행 표시
          if (( poll_count % 5 == 0 )); then
            echo "[$(now_iso)] --watch: Status=Blocked 대기 중 ($((poll_count * poll_interval / 60))분 경과)..."
          fi
          # timeout 검사
          if [[ $poll_count -ge $max_polls ]]; then
            echo "[$(now_iso)] --watch timeout (${watch_timeout_hours}시간 경과). 정지." >&2
            exit 1
          fi
        done
        echo "[$(now_iso)] 차단 신호 해제 감지. 루프 재개."
        continue
      fi
      exit 1
    fi
    if [[ $iter_status -ne 0 ]]; then
      exit "$iter_status"
    fi

    if [[ $n -ge $MAX_ITERATIONS ]]; then
      halt "이터 상한 도달 ($n / $MAX_ITERATIONS)"
    fi

    if [[ $(elapsed_minutes) -ge $WALL_CLOCK_MINUTES ]]; then
      halt "시계 캡 도달 ($(elapsed_minutes) / $WALL_CLOCK_MINUTES 분)"
    fi
  done
}

# ----- subcommand: status -----

cmd_status() {
  local filter_task_id="${1:-}"

  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."

  # filter 지정 시 task-id 검증 + 정규화 (단일 컴포넌트 → regular/) + SPEC 116
  # slug-bearing 디렉토리 매핑 (feat 브랜치 발견 시).
  if [[ -n "$filter_task_id" ]]; then
    validate_task_id "$filter_task_id"
    filter_task_id="$(normalize_task_id "$filter_task_id")"
    local _fchild="${filter_task_id#*/}"
    local _fmile="${filter_task_id%%/*}"
    local _ffeat=""
    local _frc=0
    set +e
    _ffeat=$(find_feat_branch "$_fchild")
    _frc=$?
    set -e
    case $_frc in
      0|1) ;;  # 단일 매칭 또는 매칭 없음 — 다음 단계로
      2) die "filter input-id '$_fchild' 가 모호 (위 stderr 참조)" ;;
      *) die "find_feat_branch 비정상 종료 (rc=$_frc)" ;;
    esac
    if [[ -n "$_ffeat" ]]; then
      local _fslug
      _fslug=$(slug_from_feat_branch "$_fchild" "$_ffeat")
      if [[ -n "$_fslug" ]]; then
        filter_task_id="${_fmile}/${_fchild}-${_fslug}"
      fi
    fi
  fi

  # task-id 목록 수집: milestones/<m>/loops/<c>/SPEC.md 단일 트리
  # (M1 cutover: legacy .loops/<id>/SPEC.md 스캔 제거)
  local milestones_base="$PROJECT_ROOT/milestones"
  local task_ids=()

  if [[ -n "$filter_task_id" ]]; then
    task_ids=("$filter_task_id")
  else
    # milestones/<m>/loops/<c>/SPEC.md 패턴으로 task 디렉토리 탐지
    while IFS= read -r spec_file; do
      [[ -z "$spec_file" ]] && continue
      local task_dir tid milestone_part child_part
      task_dir=$(dirname "$spec_file")
      # task_dir = $milestones_base/<m>/loops/<c>
      # 'milestones/<m>/loops/' prefix 제거 → '<c>'를 얻고, milestone 부분도 추출
      local relative="${task_dir#"$milestones_base"/}"
      [[ "$relative" == "$task_dir" ]] && continue
      # relative = '<m>/loops/<c>' → milestone=<m>, child=<c>
      milestone_part="${relative%%/loops/*}"
      child_part="${relative#"$milestone_part/loops/"}"
      # /loops/ 패턴 없으면 건너뛰기 (예: milestones/<m>/prd/PRD.md는 매칭 안 됨)
      [[ "$milestone_part" == "$relative" ]] && continue
      [[ "$child_part" == "$relative" ]] && continue
      tid="$milestone_part/$child_part"
      task_ids+=("$tid")
    done < <(find "$milestones_base" -path '*/loops/*' -name 'SPEC.md' -type f 2>/dev/null | sort)
  fi

  if [[ ${#task_ids[@]} -eq 0 ]]; then
    echo "실행 중인 task가 없습니다."
    echo "새 task를 시작하려면 spec 스킬로 SPEC.md 생성: Skill(skill: \"spec\", args: \"<task-id>\")"
    return 0
  fi

  printf "%-25s %-12s %-12s %s\n" "TASK-ID" "STATE" "ITERATIONS" "LAST-UPDATE"
  printf "%-25s %-12s %-12s %s\n" "-------------------------" "------------" "------------" "-----------"

  for tid in "${task_ids[@]}"; do
    # v0.2 cutover: 모든 산출물이 milestones/<m>/loops/<c>/ 단일 트리.
    local milestone_part="${tid%%/*}"
    local child_part="${tid#*/}"
    local loops_dir="$milestones_base/$milestone_part/loops/$child_part"
    local loops_dir_rel="milestones/$milestone_part/loops/$child_part"
    local wt="$loops_dir/.worktree"
    local lock_file="$loops_dir/.lock"
    local state="-"
    local iterations="-"
    local last_update="-"

    # 상태 판정
    if [[ -f "$lock_file" ]]; then
      state="running"
    elif [[ -d "$wt" ]]; then
      # 차단 신호는 task issue의 Project Status=Blocked 또는 최신 [blocked] prefix comment.
      # gh 부재·미설정 시 task_status_is_blocked가 1을 반환해 자연스럽게 idle로 떨어진다.
      if task_status_is_blocked "$tid"; then
        state="blocked"
      elif [[ -f "$wt/DONE" ]]; then
        state="done"
      else
        state="idle"
      fi
    elif [[ -d "$loops_dir" ]]; then
      # SPEC.md만 있으면 prepared
      if [[ -f "$loops_dir/SPEC.md" ]]; then
        state="prepared"
      fi
    fi

    # 이터 횟수 — 워크트리 안의 .iterations/ 디렉토리에서 카운트
    if [[ -d "$wt/.iterations" ]]; then
      local cnt
      cnt=$(find "$wt/.iterations" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ')
      iterations="$cnt"
    fi

    # 마지막 갱신 시각 — task issue의 최신 comment createdAt (헌법 §11).
    # gh 부재·issue 매핑 실패 시 워크트리 안의 .iterations/ 최신 로그 mtime으로 fallback.
    local issue_num last_at=""
    if issue_num=$(task_issue_number "$tid" 2>/dev/null) && command -v gh >/dev/null 2>&1; then
      last_at=$(gh issue view "$issue_num" --json comments \
        --jq '.comments | sort_by(.createdAt) | last | .createdAt // empty' 2>/dev/null || true)
    fi
    if [[ -n "$last_at" ]]; then
      last_update="$last_at"
    elif [[ -d "$wt/.iterations" ]]; then
      local ref_file
      ref_file=$(find "$wt/.iterations" -name "*.log" -type f 2>/dev/null \
        | sort | tail -n 1)
      if [[ -n "$ref_file" && -f "$ref_file" ]]; then
        local epoch=""
        # macOS BSD: stat -f %m, Linux GNU: stat -c %Y
        epoch=$(stat -f %m "$ref_file" 2>/dev/null || stat -c %Y "$ref_file" 2>/dev/null || echo "")
        if [[ -n "$epoch" ]]; then
          # macOS BSD: date -u -r <epoch>, Linux GNU: date -u -d "@<epoch>"
          last_update=$(date -u -r "$epoch" +%Y-%m-%dT%H:%MZ 2>/dev/null \
            || date -u -d "@$epoch" +%Y-%m-%dT%H:%MZ 2>/dev/null \
            || echo "-")
        fi
      fi
    fi

    printf "%-25s %-12s %-12s %s\n" "$tid" "$state" "$iterations" "$last_update"
  done
}

# ----- subcommand: stop -----

cmd_stop() {
  local task_id="$1"
  [[ -z "$task_id" ]] && die "사용: $0 stop <task-id>"

  compute_paths "$task_id"
  # 정규화된 task-id로 사용자 출력 통일
  task_id="$TASK_ID_NORMALIZED"

  if [[ ! -f "$LOCK_FILE" ]]; then
    die "task ${task_id}에 활성 락 없음"
  fi

  local pid
  pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  [[ -z "$pid" ]] && die "락 파일에서 PID 읽기 실패"

  # PID 유효성 검사
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[$(now_iso)] WARN: 락 PID ${pid}가 살아있지 않음 (stale lock). 락만 정리." >&2
    rm -f "$LOCK_FILE"
    return 0
  fi

  echo "[$(now_iso)] task $task_id (PID $pid) 정지 시그널 전송..."
  kill -TERM "$pid" 2>/dev/null

  # 5초 대기
  for _ in 1 2 3 4 5; do
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "[$(now_iso)] task $task_id 정상 정지."
      rm -f "$LOCK_FILE"
      return 0
    fi
  done

  echo "[$(now_iso)] WARN: PID $pid 5초 후에도 응답 없음. SIGKILL이 필요할 수 있음:" >&2
  echo "  kill -9 $pid && rm $LOCK_FILE" >&2
  exit 1
}

# ----- subcommand: list -----

cmd_list() {
  cmd_status ""
}

# ----- subcommand: cleanup -----

cmd_cleanup() {
  local task_id="$1"
  shift || true
  [[ -z "$task_id" ]] && die "사용: $0 cleanup <task-id> [--force]"

  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      *) die "알 수 없는 옵션: $1" ;;
    esac
  done

  compute_paths "$task_id"
  task_id="$TASK_ID_NORMALIZED"
  TASK_ID="$task_id"

  # 1. 실행 중 확인
  if [[ -f "$LOCK_FILE" ]]; then
    if [[ $force -eq 0 ]]; then
      die "task $task_id 가 실행 중입니다. 먼저 정지하세요: $0 stop $task_id\n강제 실행: $0 cleanup $task_id --force"
    fi

    # --force: 실행 중 프로세스를 SIGTERM으로 먼저 정지 (race 방지)
    # 단순히 lock만 지우면 bash·claude는 계속 실행되며, 그 사이 새 start가
    # 새 lock을 획득해 두 claude가 동시에 같은 워크트리를 수정할 수 있음.
    local lock_pid
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$lock_pid" ]] && [[ "$lock_pid" =~ ^[0-9]+$ ]] \
       && kill -0 "$lock_pid" 2>/dev/null; then
      echo "WARN: --force cleanup — 실행 중 task ${task_id} (PID $lock_pid) SIGTERM 후 종료 대기..."
      kill -TERM "$lock_pid" 2>/dev/null || true

      # 5초 grace
      for _ in 1 2 3 4 5; do
        sleep 1
        if ! kill -0 "$lock_pid" 2>/dev/null; then
          break
        fi
      done

      # 여전히 살아있으면 SIGKILL (--force 명시이므로 escalate)
      if kill -0 "$lock_pid" 2>/dev/null; then
        echo "WARN: PID $lock_pid SIGTERM 무응답 — SIGKILL 전송" >&2
        kill -KILL "$lock_pid" 2>/dev/null || true
        sleep 1
      fi
    else
      echo "WARN: lock 파일에 활성 PID 없음 (stale)."
    fi

    # bash가 EXIT trap으로 lock을 이미 제거했을 수 있으나 안전하게 다시 정리
    rm -f "$LOCK_FILE"
  fi

  # 2. 워크트리 존재 확인
  if [[ ! -d "$WT" ]]; then
    die "$task_id 에 대한 워크트리가 없습니다: $WT"
  fi

  # 2.5. Path guard — WT가 예상 nested 경로 (milestones/<m>/loops/<c>/.worktree) 안인지
  # 검증. 변수 누락·외부 경로·메인 레포 자체 손상을 차단.
  [[ -n "$WT" ]] || die "WT 변수가 비어 있음 (cleanup 거부)"
  [[ -n "$PROJECT_ROOT" ]] || die "PROJECT_ROOT 변수가 비어 있음 (cleanup 거부)"
  [[ "$WT" == "$PROJECT_ROOT"/* ]] \
    || die "워크트리가 PROJECT_ROOT 밖: $WT (cleanup 거부)"
  case "$WT" in
    */milestones/*/loops/*/.worktree) ;;
    *) die "워크트리 경로 형식 부적절 (기대: */milestones/<m>/loops/<c>/.worktree): $WT" ;;
  esac

  # 3. DONE 확인
  if [[ ! -f "$WT/DONE" ]] && [[ $force -eq 0 ]]; then
    die "task $task_id 에 DONE 신호가 없습니다.\n--force 없이 cleanup하려면 먼저 DONE 파일이 필요합니다: $0 cleanup $task_id --force"
  fi

  # 3.5. 단일 contract: worktree HEAD 브랜치가 feat/... 이어야 함 (사전 검증).
  # 외부에서 다른 브랜치로 체크아웃 변경된 경우 die — cleanup 동작 비정상화 차단.
  local current_branch=""
  current_branch=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$current_branch" != feat/* ]]; then
    die "워크트리 HEAD 브랜치가 feat/* 아님: '$current_branch' (cleanup 거부 — 외부에서 브랜치 변경된 듯)"
  fi
  BRANCH="$current_branch"

  # 4. 메타 파일은 feat 브랜치 commit history에 있으므로 메인 트리로 cp하지 않음.
  echo "단일 contract: 메모리 파일 archive 건너뜀 (feat 브랜치 ${BRANCH}이 PR base)"

  # 5. 워크트리 제거
  local wt_remove_flags=""
  [[ $force -eq 1 ]] && wt_remove_flags="--force"
  git -C "$PROJECT_ROOT" worktree remove $wt_remove_flags "$WT" \
    || die "git worktree remove 실패. 수동 제거: git worktree remove --force $WT"

  # 6. feat 브랜치는 PR base로 보존 (자동 삭제 없음).
  echo "feat 브랜치 보존: $BRANCH (PR base로 사용)"

  echo ""
  echo "정리 완료: $task_id"
}

# ----- subcommand: logs -----

cmd_logs() {
  local task_id="$1"
  shift || true
  [[ -z "$task_id" ]] && die "사용: $0 logs <task-id> [--tail] [--iter N]"

  local tail_mode=0 iter_n=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tail) tail_mode=1; shift ;;
      --iter) iter_n="$2"; shift 2 ;;
      *) die "알 수 없는 옵션: $1" ;;
    esac
  done

  compute_paths "$task_id"
  task_id="$TASK_ID_NORMALIZED"

  if [[ -n "$iter_n" ]]; then
    # 이터 raw 로그 — 워크트리 안의 .iterations/<N>.log (worktree-local untracked).
    local iter_log="$WT/.iterations/$iter_n.log"
    [[ -f "$iter_log" ]] || die "이터 로그가 없습니다: $iter_log"
    cat "$iter_log"
    return 0
  fi

  # 새 contract: 이터 흐름은 task issue의 comments에 저장 (헌법 §11). gh로 조회.
  # raw 이터 로그는 위 --iter N 분기로 .iterations/<N>.log를 그대로 출력.
  if ! command -v gh >/dev/null 2>&1; then
    die "gh CLI가 필요합니다 (이터 흐름은 task issue comments에 저장됨). raw 이터 로그는 --iter N으로 조회 가능."
  fi
  local issue_num
  if ! issue_num=$(task_issue_number "$task_id" 2>/dev/null); then
    die "task '$task_id' issue 매핑 실패 — issue number 직접 지정 또는 raw 이터 로그(--iter N) 사용"
  fi

  if [[ $tail_mode -eq 1 ]]; then
    # --tail: 60초 간격으로 새 comment polling (Ctrl+C로 종료). 매 polling마다
    # last_seen createdAt 이후의 신규 comment만 출력 — 기존 로그 파일 tail의
    # 증분 스트리밍과 동등한 UX. 첫 라운드(last_seen 빈 값)는 기존 전체를 한 번 출력.
    local last_seen=""
    while true; do
      # raw fetch 1회 → 같은 snapshot에서 new_block과 max_seen을 함께 계산해
      # 두 호출 사이의 race(첫 호출과 두 번째 호출 사이 새 comment 도착 시 누락)를
      # 제거. gh의 `--jq`는 `--arg`를 통과시키지 않으므로 comments 배열만 추출하고
      # since 바인딩은 별도 jq pipe에서 처리.
      local raw new_block max_seen
      raw=$(gh issue view "$issue_num" --json comments --jq '.comments' 2>/dev/null || true)
      if [[ -n "$raw" ]]; then
        new_block=$(jq -r --arg since "$last_seen" \
          '[.[] | select($since == "" or .createdAt > $since)]
            | sort_by(.createdAt)
            | map("=== @\(.author.login) (\(.createdAt)) ===\n\(.body)\n")
            | .[]' <<<"$raw" 2>/dev/null || true)
        if [[ -n "$new_block" ]]; then
          printf '%s\n' "$new_block"
          max_seen=$(jq -r 'sort_by(.createdAt) | last | .createdAt // empty' <<<"$raw" 2>/dev/null || true)
          [[ -n "$max_seen" ]] && last_seen="$max_seen"
        fi
      fi
      sleep 60
    done
  else
    gh issue view "$issue_num" --comments
  fi
}

# ----- 사용법 출력 -----

usage() {
  cat >&2 <<'EOF'
autopilot loop 드라이버

Subcommands:
  prepare <task-id>       (deprecated) spec 스킬로 안내  → Skill(skill: "spec", args: "<task-id>")
  start <task-id>         검증 후 워크트리·락 생성 + 루프 시작 [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>]
  status [<task-id>]      상태 조회
  stop <task-id>          실행 중 정지
  list                    전체 task 상태
  cleanup <task-id>       DONE 후 정리
  logs <task-id>          로그 조회

자세한 내용: references/operational-guide.md (autopilot/skills/loop/)
EOF
  exit 1
}

# ----- subcommand 디스패처 -----

if [[ $# -lt 1 ]]; then
  usage
fi

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  prepare)
    cmd_prepare "$@"
    ;;
  start)
    cmd_start "$@"
    ;;
  status)
    cmd_status "${1:-}"
    ;;
  stop)
    cmd_stop "${1:-}"
    ;;
  list)
    cmd_list
    ;;
  cleanup)
    cmd_cleanup "$@"
    ;;
  logs)
    cmd_logs "$@"
    ;;
  *)
    echo "알 수 없는 subcommand: $SUBCOMMAND" >&2
    usage
    ;;
esac
