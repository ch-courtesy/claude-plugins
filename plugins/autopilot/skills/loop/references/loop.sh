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
  BRANCH="autonomous-loop/$task_id"
  # v0.2 cutover: 워크트리·lock·메타 파일이 모두 milestones/<m>/loops/<c>/ 단일
  # 트리 안에 있다. 외부 sibling·.loops/locks/는 사용하지 않음.
  local milestone="${task_id%%/*}"
  local child="${task_id#*/}"
  LOOPS_DIR="$PROJECT_ROOT/milestones/$milestone/loops/$child"
  # LOOPS_DIR_REL: worktree 안의 SPEC.md canonical 경로 prefix (신규 contract).
  # 신규 contract에선 SPEC.md가 feat 브랜치에 commit되어 worktree에서
  # <wt>/$LOOPS_DIR_REL/SPEC.md 경로로 자연 노출된다.
  LOOPS_DIR_REL="milestones/$milestone/loops/$child"
  WT="$LOOPS_DIR/.worktree"
  LOCK_FILE="$LOOPS_DIR/.lock"
  # 정규화된 task-id를 caller에게 노출 (cmd_start에서 TASK_ID로 사용)
  TASK_ID_NORMALIZED="$task_id"
}

# 신규 contract 감지: feat/<task-id> 또는 feat/<task-id>-<slug> 브랜치 검색.
# 0개 매칭이면 빈 출력 + return 1 (legacy 분기로 fallback).
# 정확히 1개 매칭이면 브랜치 이름 출력 + return 0.
# 2개 이상이면 die (모호성).
find_feat_branch() {
  local task_id="$1"
  local matches count
  matches=$(git -C "$PROJECT_ROOT" for-each-ref \
    --format='%(refname:short)' \
    "refs/heads/feat/$task_id" \
    "refs/heads/feat/$task_id-*" 2>/dev/null)
  if [[ -z "$matches" ]]; then
    return 1
  fi
  count=$(printf '%s\n' "$matches" | grep -c .)
  if [[ $count -ge 2 ]]; then
    die "여러 feat 브랜치가 task-id '$task_id'와 매칭됨 (모호):\n$matches\n수동으로 하나 남기고 다른 것 정리 후 재시도."
  fi
  printf '%s\n' "$matches"
  return 0
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
  # SPEC.md 위치 자동 감지:
  #   - 신규 contract: <WT>/<LOOPS_DIR_REL>/SPEC.md (feat 브랜치 commit으로 자연 포함)
  #   - legacy: <WT>/.loop/SPEC.md (셋업 시 cp)
  local spec_path
  if [[ -n "${LOOPS_DIR_REL:-}" ]] && [[ -f "$WT/$LOOPS_DIR_REL/SPEC.md" ]]; then
    spec_path="$WT/$LOOPS_DIR_REL/SPEC.md"
  else
    spec_path="$WT/.loop/SPEC.md"
  fi
  sed -n '1,/^---$/{
    1d
    /^---$/d
    p
  }' "$spec_path" 2>/dev/null
}

diff_vs_scope() {
  local scope_yaml include_patterns exclude_patterns committed working changed
  scope_yaml=$(read_scope_yaml)
  include_patterns=$(echo "$scope_yaml" | yq '.scope.include[]' 2>/dev/null || true)
  exclude_patterns=$(echo "$scope_yaml" | yq '.scope.exclude[]' 2>/dev/null || true)
  # 커밋된 diff + working tree 변경 양쪽 검사 (claude 비정상 종료로 미커밋 변경이 남는 경우 차단)
  committed=$(cd "$WT" && git diff --name-only HEAD~1 HEAD 2>/dev/null || true)
  working=$(cd "$WT" && git diff --name-only HEAD 2>/dev/null || true)
  changed=$(printf '%s\n%s\n' "$committed" "$working" | sort -u | grep -v '^$' || true)

  [[ -z "$changed" ]] && return 0

  local out_of_scope=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    # 프레임워크 파일은 항상 scope 검사에서 제외 (워커 프레임워크 메타파일)
    # CLAUDE.md는 SPEC scope.exclude로 통제 — skip-worktree로 보통은 diff에 안 잡히지만,
    # 워커가 unskip + commit하면 여기서 정상 catch되어야 함 (워크트리 셋업 직후 자동 skip 처리).
    case "$file" in
      .loop/*|.loop|DONE) continue ;;
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
  # 커밋된 diff + working tree 변경 양쪽 검사 (미커밋 suppressor도 catch)
  # .loop/는 워커 메모리(헌법 인용 등 false positive 발생)이므로 검사 제외
  cd "$WT" || return
  {
    git diff HEAD~1 HEAD -- ':(exclude).loop/**' 2>/dev/null
    git diff HEAD -- ':(exclude).loop/**' 2>/dev/null
  } \
    | grep -E '^\+' \
    | grep -E '#[[:space:]]*noqa|@ts-ignore|eslint-disable|#pragma[[:space:]]+warning[[:space:]]+disable' \
    || true
}

check_secrets() {
  command -v gitleaks >/dev/null 2>&1 || return 0
  # 이번 이터 커밋(HEAD~1..HEAD) + 미커밋 staged 양쪽 검사
  # 비고: gitleaks는 unstaged-tracked 변경의 직접 스캔 옵션이 없음 (--no-git은 워크트리
  #       전체 스캔이라 노이즈 큼) → unstaged-tracked는 본 게이트의 의도된 미커버.
  #       헌법이 매 이터 commit 강제하므로 일반 흐름에선 gap 없음.
  {
    cd "$WT" && gitleaks detect --log-opts="HEAD~1..HEAD" --no-banner 2>&1 || true
    cd "$WT" && gitleaks detect --staged --no-banner 2>&1 || true
  }
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

  # 자동 ESCALATION 작성
  mkdir -p "$WT/.loop"
  cat > "$WT/.loop/ESCALATION.md" <<EOF
# 에스컬레이션 보고 (드라이버 자동 작성)

**작업**: $TASK_ID
**이터레이션**: 자동 정지
**트리거**: 객관 게이트 위반 — $reason

## 현재 상태

드라이버가 매 이터 후 게이트를 검사한 결과 위반이 감지되어 자동 정지함.

## 문제

$reason

## 처리

다음 중 하나:
1. 가설 점검 후 작업 명세(scope·verify) 조정
2. 메모리 파일(NOTES.md) 보강
3. 본 ESCALATION.md 삭제 후 재시작

자세한 내용은 .loop/iterations/ 의 최근 로그 참조.
EOF

  exit 1
}

# ----- 이터레이션 호출 -----

iterate() {
  local n
  n=$(($(find "$WT/.loop/iterations" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ') + 1))

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
  # SPEC.md stdin 경로: 신규 contract는 worktree의 milestones/<m>/loops/<c>/SPEC.md,
  # legacy는 .loop/SPEC.md (셋업 시 cp). 둘 다 worktree 안의 단일 canonical 경로.
  local spec_stdin_path=".loop/SPEC.md"
  if [[ -n "${LOOPS_DIR_REL:-}" ]] && [[ -f "$WT/$LOOPS_DIR_REL/SPEC.md" ]]; then
    spec_stdin_path="$LOOPS_DIR_REL/SPEC.md"
  fi
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
      > ".loop/iterations/$n.log" 2>&1
  ) &
  local claude_pid=$!
  wait "$claude_pid" || exit_code=$?

  echo "[$(now_iso)] 이터 #$n 종료 (exit: $exit_code). 게이트 검사..."

  if [[ $exit_code -ne 0 ]]; then
    CLAUDE_FAIL_STREAK=$((CLAUDE_FAIL_STREAK + 1))
    echo "WARN: claude 호출이 0이 아닌 exit code 반환 (연속 실패: $CLAUDE_FAIL_STREAK). iterations/$n.log 확인 권장."
    if [[ $CLAUDE_FAIL_STREAK -ge ${CLAUDE_FAIL_STREAK_LIMIT:-3} ]]; then
      halt "claude 비정상 exit ${CLAUDE_FAIL_STREAK}회 연속 (rate limit·네트워크·인증 의심). iterations/$n.log 확인."
    fi
  else
    CLAUDE_FAIL_STREAK=0
  fi

  # 종료 신호 검사 (먼저)
  if [[ -f "$WT/DONE" ]]; then
    return 100   # 메인 루프에서 정상 종료 처리
  fi
  if [[ -f "$WT/.loop/ESCALATION.md" ]]; then
    return 101   # 메인 루프에서 ESCALATION 처리
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

  local out_of_scope new_supp streak osc
  out_of_scope=$(diff_vs_scope)
  [[ -n "$out_of_scope" ]] && halt "Scope 위반: $out_of_scope"

  new_supp=$(grep_new_suppressors)
  [[ -n "$new_supp" ]] && halt "Suppressor 신규 추가: $new_supp"

  if command -v gitleaks >/dev/null 2>&1; then
    local secrets
    secrets=$(check_secrets)
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
  [[ -z "$task_id" ]] && die "사용: $0 start <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>]"

  local max_iterations_override="" wall_clock_minutes_override="" watch_mode=0 spec_path=""
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

  # 1.5. 신규 contract 감지: feat/<task-id>[-<slug>] 브랜치가 main repo에 있으면
  # 그 브랜치를 worktree base로 사용하고 SPEC은 worktree에서 자연 노출되는 경로로 읽음.
  # 없으면 legacy 분기 (LOOPS_DIR/SPEC.md를 .loop/로 cp).
  NEW_CONTRACT=0
  local feat_branch=""
  if feat_branch=$(find_feat_branch "$task_id"); then
    if [[ -n "$feat_branch" ]]; then
      NEW_CONTRACT=1
      BRANCH="$feat_branch"
    fi
  fi

  # 2. SPEC.md 존재·내용 검증 — 신규 contract와 legacy 분기.
  local spec_content=""
  if [[ $NEW_CONTRACT -eq 1 ]]; then
    # 신규 contract: SPEC을 feat 브랜치 commit에서 읽음 (main 작업트리는 무시).
    # 브랜치는 있는데 SPEC commit이 없으면 fail-fast.
    spec_content=$(git -C "$PROJECT_ROOT" show "${BRANCH}:${LOOPS_DIR_REL}/SPEC.md" 2>/dev/null) \
      || die "feat 브랜치 '${BRANCH}'의 HEAD에 SPEC.md(${LOOPS_DIR_REL}/SPEC.md) 부재 — spec 스킬로 SPEC 작성·commit 필요."
  else
    # legacy: main 작업트리의 LOOPS_DIR/SPEC.md를 읽음.
    local spec_path_local="$LOOPS_DIR/SPEC.md"
    if [[ ! -f "$spec_path_local" ]]; then
      die "SPEC.md가 없습니다 (기대 경로: $spec_path_local 또는 feat/${task_id}[-<slug>] 브랜치).\n먼저 실행하세요: Skill(skill: \"spec\", args: \"$task_id\")"
    fi
    spec_content=$(cat "$spec_path_local")
  fi

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

  # 6. 워크트리 생성 (없는 경우)
  if [[ ! -d "$WT" ]]; then
    echo "[$(now_iso)] 워크트리 생성 시작: $WT"

    # 새 nested 정책: WT 부모(loops_dir)는 이미 SPEC.md 존재 시 만들어짐.
    # 일관성을 위해 mkdir -p로 보장.
    mkdir -p "$(dirname "$WT")"

    # 신규 contract: 기존 feat 브랜치를 base로 worktree 체크아웃 (-b 없음).
    # legacy: 새 autonomous-loop 브랜치를 만들며 worktree 생성.
    if [[ $NEW_CONTRACT -eq 1 ]]; then
      git -C "$PROJECT_ROOT" worktree add "$WT" "$BRANCH" \
        || die "git worktree add 실패 (feat 브랜치 체크아웃): $WT (브랜치: $BRANCH)"
      # 사후 검증: worktree HEAD에 SPEC.md 자연 노출 확인 (spec 스킬이 commit했어야)
      if [[ ! -f "$WT/$LOOPS_DIR_REL/SPEC.md" ]]; then
        die "feat 브랜치 ${BRANCH} 워크트리 HEAD에 SPEC.md 부재 (기대: $WT/$LOOPS_DIR_REL/SPEC.md)"
      fi
    else
      git -C "$PROJECT_ROOT" worktree add "$WT" -b "$BRANCH" \
        || die "git worktree add 실패: $WT"
    fi

    # 워크트리 baseline empty commit — iter 1의 HEAD~1..HEAD diff가 부모 브랜치의
    # ensure_loops_setup chore commit 등 setup history를 worker 변경으로 오인하지
    # 않도록 분리한다. 기존 외부 sibling 워크트리 시절에는 프로젝트 setup이 baseline을
    # 만들었으나, nested 정책에서 ensure_loops_setup이 main 브랜치에 .gitignore
    # chore commit을 추가하므로 worktree 브랜치 baseline이 필요.
    ( cd "$WT" && git commit -q --allow-empty -m "chore: autopilot worktree baseline" ) \
      || die "워크트리 baseline commit 실패: $WT"

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

    # 메타 파일 시드 — 신규 contract는 SPEC을 worktree에서 자연 포함하므로 cp 안 함.
    # legacy만 LOOPS_DIR/SPEC.md → .loop/SPEC.md로 cp.
    mkdir -p "$WT/.loop/iterations"
    if [[ $NEW_CONTRACT -eq 0 ]]; then
      cp "$LOOPS_DIR/SPEC.md" "$WT/.loop/SPEC.md"
    fi
    cp "$SCRIPT_DIR/plan-template.md" "$WT/.loop/PLAN.md"
    cp "$SCRIPT_DIR/notes-template.md" "$WT/.loop/NOTES.md"
    cp "$SCRIPT_DIR/handoff-template.md" "$WT/.loop/HANDOFF.md"
    cp "$SCRIPT_DIR/runlog-template.md" "$WT/.loop/RUN_LOG.md"

    # 워크트리 로컬 비추적 등록
    local wt_gitdir
    wt_gitdir="$(git -C "$WT" rev-parse --git-dir)"
    mkdir -p "$wt_gitdir/info"
    {
      echo "CLAUDE.md"
      echo ".loop/"
      echo "DONE"
    } >> "$wt_gitdir/info/exclude"

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
      # cleanup 시 archive로 이동하도록 안내만
      echo ""
      echo "task $task_id 완료."
      echo "메타 파일 정리 및 워크트리 제거:"
      echo "  $0 cleanup $task_id"
      exit 0
    fi
    if [[ $iter_status -eq 101 ]]; then
      echo "[$(now_iso)] ESCALATION.md 감지. 사람 처리 대기."
      if [[ $WATCH_MODE -eq 1 ]]; then
        local watch_timeout_hours="${WATCH_TIMEOUT_HOURS:-24}"
        local poll_interval=60
        local poll_count=0
        local max_polls=$(( watch_timeout_hours * 3600 / poll_interval ))

        echo "[$(now_iso)] --watch 모드: ESCALATION.md 사라짐 polling 중 (60초 간격, 최대 ${watch_timeout_hours}시간, Ctrl+C로 종료)..."
        while [[ -f "$WT/.loop/ESCALATION.md" ]]; do
          sleep $poll_interval
          poll_count=$((poll_count + 1))
          # 매 5분(5 polls)마다 진행 표시
          if (( poll_count % 5 == 0 )); then
            echo "[$(now_iso)] --watch: ESCALATION.md 대기 중 ($((poll_count * poll_interval / 60))분 경과)..."
          fi
          # timeout 검사
          if [[ $poll_count -ge $max_polls ]]; then
            echo "[$(now_iso)] --watch timeout (${watch_timeout_hours}시간 경과). 정지." >&2
            exit 1
          fi
        done
        echo "[$(now_iso)] ESCALATION.md 해제 감지. 루프 재개."
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

  # filter 지정 시 task-id 검증 + 정규화 (단일 컴포넌트 → regular/)
  if [[ -n "$filter_task_id" ]]; then
    validate_task_id "$filter_task_id"
    filter_task_id="$(normalize_task_id "$filter_task_id")"
  fi

  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."

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
    local wt="$loops_dir/.worktree"
    local lock_file="$loops_dir/.lock"
    local state="-"
    local iterations="-"
    local last_update="-"

    # 상태 판정
    if [[ -f "$lock_file" ]]; then
      state="running"
    elif [[ -d "$wt" ]]; then
      if [[ -f "$wt/.loop/ESCALATION.md" ]]; then
        state="escalated"
      elif [[ -f "$wt/DONE" ]]; then
        state="done"
      else
        state="idle"
      fi
    elif [[ -d "$loops_dir" ]]; then
      # SPEC.md만 있으면 prepared, 메모리 파일이 있으면 archived
      if [[ -f "$loops_dir/PLAN.md" ]] || [[ -f "$loops_dir/NOTES.md" ]]; then
        state="archived"
      elif [[ -f "$loops_dir/SPEC.md" ]]; then
        state="prepared"
      fi
    fi

    # 이터 횟수
    if [[ -d "$wt/.loop/iterations" ]]; then
      local cnt
      cnt=$(find "$wt/.loop/iterations" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ')
      iterations="$cnt"
    elif [[ -d "$loops_dir" ]]; then
      # archived 상태에서 RUN_LOG.md로 추정
      if [[ -f "$loops_dir/RUN_LOG.md" ]]; then
        local cnt
        cnt=$(grep -c '^\[' "$loops_dir/RUN_LOG.md" 2>/dev/null || echo "?")
        iterations="$cnt"
      fi
    fi

    # 마지막 갱신 시각
    local ref_file=""
    if [[ -d "$wt/.loop" ]]; then
      ref_file="$wt/.loop/RUN_LOG.md"
    elif [[ -f "$loops_dir/RUN_LOG.md" ]]; then
      ref_file="$loops_dir/RUN_LOG.md"
    fi
    if [[ -n "$ref_file" ]] && [[ -f "$ref_file" ]]; then
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

  # 3.5. 신규 contract 감지 — worktree HEAD 브랜치가 feat/... 이면 신규.
  # 신규 contract는 메모리 파일 archive를 폐기하고 feat 브랜치를 PR base로 남긴다.
  local current_branch=""
  current_branch=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  local cleanup_new_contract=0
  if [[ "$current_branch" == feat/* ]]; then
    cleanup_new_contract=1
    BRANCH="$current_branch"
  fi

  # 4. 메타 파일 archive — legacy contract만 수행.
  # 신규 contract: worker 메모리 파일을 main 작업트리로 복사하지 않음 (worktree 제거와 함께 폐기).
  if [[ $cleanup_new_contract -eq 0 ]]; then
    mkdir -p "$LOOPS_DIR"
    for f in PLAN.md NOTES.md HANDOFF.md RUN_LOG.md ESCALATION.md; do
      cp "$WT/.loop/$f" "$LOOPS_DIR/$f" 2>/dev/null || true
    done
    echo "메타 파일 보관: $LOOPS_DIR"
  else
    echo "신규 contract: 메모리 파일 archive 건너뜀 (feat 브랜치 ${BRANCH}이 PR base)"
  fi

  # 5. 워크트리 제거
  local wt_remove_flags=""
  [[ $force -eq 1 ]] && wt_remove_flags="--force"
  git -C "$PROJECT_ROOT" worktree remove $wt_remove_flags "$WT" \
    || die "git worktree remove 실패. 수동 제거: git worktree remove --force $WT"

  # 6. 브랜치 삭제 — legacy contract만 수행.
  # 신규 contract: feat 브랜치는 PR base로 남겨야 하므로 삭제하지 않음.
  if [[ $cleanup_new_contract -eq 0 ]]; then
    local branch_delete_flag="-d"
    [[ $force -eq 1 ]] && branch_delete_flag="-D"
    git -C "$PROJECT_ROOT" branch $branch_delete_flag "$BRANCH" 2>/dev/null \
      || echo "WARN: 브랜치 삭제 실패 (이미 머지됐거나 없을 수 있음): $BRANCH"
  else
    echo "feat 브랜치 보존: $BRANCH (PR base로 사용)"
  fi

  echo ""
  echo "정리 완료: $task_id"
  if [[ $cleanup_new_contract -eq 0 ]]; then
    echo "보관된 메타 파일: $LOOPS_DIR"
  fi
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
    # 이터 로그 출력 (워크트리 우선, fallback 없음)
    local iter_log="$WT/.loop/iterations/$iter_n.log"
    [[ -f "$iter_log" ]] || die "이터 로그가 없습니다: $iter_log"
    cat "$iter_log"
    return 0
  fi

  # RUN_LOG.md 위치 찾기 (워크트리 우선, archived fallback)
  local run_log=""
  if [[ -f "$WT/.loop/RUN_LOG.md" ]]; then
    run_log="$WT/.loop/RUN_LOG.md"
  elif [[ -f "$LOOPS_DIR/RUN_LOG.md" ]]; then
    run_log="$LOOPS_DIR/RUN_LOG.md"
  else
    die "RUN_LOG.md를 찾을 수 없습니다. task-id가 올바른지 확인하세요: $task_id"
  fi

  if [[ $tail_mode -eq 1 ]]; then
    tail -f "$run_log"
  else
    cat "$run_log"
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
