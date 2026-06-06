#!/usr/bin/env bash
# merge.sh — autopilot:dispatch per-SPEC 승인+머지 (M4)
#
# 책임 (파이프라인 종착: "승인되면 머지되고 SPEC 은 done(=머지됨)이 된다"):
#   - 승인 제출(분리 신원): 리뷰가 approve 로 수렴하면 **분리된 자율 approver 신원**으로
#     PR 을 승인한다(APPROVE_CMD). 자동 리뷰 봇(REVIEW_BOT)으로는 승인하지 않는다.
#   - 승인 확인: PR 에 approver 신원의 APPROVED 정식 리뷰가 있는지 확인한다. 자동 리뷰 봇의
#     self-approve 는 무효(분리된 approver 신원의 승인만 인정).
#   - 버전 범프 게이트: 머지될 변경이 워치 디렉토리(plugins/)를 건드리면 같은 변경 안에서
#     plugin.json 버전이 올랐는지 단언한다. 안 올랐으면 머지 차단(비완료 종착).
#   - 머지: default 브랜치에 fast-forward 전용(--ff-only)으로 머지(+base push). 머지 커밋·
#     force 금지. main 체크아웃+머지 구간은 run-dir 락으로 **직렬화**한다(동시 머지 레이스 차단).
#   - 완료: 머지 확인되면 int-phase=merged(스케줄러가 SPEC 을 done 으로 전이) + 작업 공간
#     정리를 loop 의 공개 cleanup 인터페이스로 위임.
#
# 불변식:
#   - force(강제) 머지·push 금지. 머지는 git merge --ff-only 만.
#   - 작업 공간은 직접 지우지 않고 loop 공개 cleanup 으로만 위임.
#   - per-SPEC 상태는 lib-integration.sh(run-dir + 키)로만. 키는 호출자 주입.
#   - 버전 게이트는 rules/engineering/versioning.md 실행자.
#
# 모든 외부 인터페이스(git·forge·loop·approve CLI)는 주입 가능. mock 으로 독립 검증
# (self-referential: 실제 머지·PR 미수행). bash 3.2+ 호환.
#
# 환경 변수 (mock 치환 가능):
#   GIT_CMD/FORGE_CMD/LOOP_CMD/DEFAULT_BRANCH   integration.sh 와 공유.
#   APPROVER        승인 권한 신원 login(설정 시 그 신원의 승인만 인정).
#   REVIEW_BOT      자동 리뷰 봇 login(이 신원의 self-approve 는 무효).
#   APPROVE_CMD <pr>  PR 승인 제출(기본: gh pr review <pr> --approve). approver 신원 자격으로.
#   WATCH_DIRS      버전 워치 디렉토리 prefix(기본: plugins/).

set -uo pipefail

MG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 통합 모듈(M2) → lib-integration(M1) 확보.
if ! declare -f int_set >/dev/null 2>&1; then
  # shellcheck source=lib-integration.sh
  . "$MG_SCRIPT_DIR/lib-integration.sh"
fi
set +e
set -uo pipefail

GIT_CMD="${GIT_CMD:-git}"
FORGE_CMD="${FORGE_CMD:-gh}"
LOOP_CMD_DEFAULT="bash $MG_SCRIPT_DIR/../../loop/references/loop.sh"
LOOP_CMD="${LOOP_CMD:-$LOOP_CMD_DEFAULT}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
APPROVER="${APPROVER:-}"
REVIEW_BOT="${REVIEW_BOT:-}"
WATCH_DIRS="${WATCH_DIRS:-plugins/}"
APPROVE_CMD="${APPROVE_CMD:-mg_approve_gh}"

mg_die() { echo "merge: $*" >&2; return 1; }

# ===== 1) 승인 제출 — 분리된 approver 신원으로 PR 승인 =====
mg_approve_gh() {
  local pr="$1"
  command -v gh >/dev/null 2>&1 || { mg_die "gh CLI 필요"; return 1; }
  gh pr review "$pr" --approve >/dev/null 2>&1
}

# mg_submit_approval <pr> — approver 신원으로 승인 제출(REVIEW_BOT 로는 승인 안 함).
mg_submit_approval() {
  local pr="$1"
  [[ -n "$pr" ]] || return 1
  # shellcheck disable=SC2086
  $APPROVE_CMD "$pr"
}

# ===== 2) 승인 확인 — approver 신원의 APPROVED. 리뷰 봇 self-approve 무효 =====
mg_pr_reviews() {
  # shellcheck disable=SC2086
  $FORGE_CMD pr view "$1" --json reviews \
    --jq '.reviews[] | "\(.state)\t\(.author.login)"' 2>/dev/null
}

# mg_approval_ok <pr> — approver 신원의 APPROVED 가 있으면 0.
mg_approval_ok() {
  local pr="$1" state author
  [[ -n "$pr" ]] || return 1
  while IFS=$'\t' read -r state author; do
    [[ "$state" == "APPROVED" ]] || continue
    [[ -n "$REVIEW_BOT" && "$author" == "$REVIEW_BOT" ]] && continue   # self-approve 무효
    [[ -n "$APPROVER" && "$author" != "$APPROVER" ]] && continue       # approver 신원만 인정
    return 0
  done < <(mg_pr_reviews "$pr")
  return 1
}

# ===== 3) 버전 범프 게이트 — versioning.md 실행자 =====
mg_merge_changed_files() {
  # shellcheck disable=SC2086
  $GIT_CMD diff --name-only "origin/$DEFAULT_BRANCH...$1" 2>/dev/null
}
mg_touches_watch_dir() {
  mg_merge_changed_files "$1" | grep -qE "^$WATCH_DIRS" 2>/dev/null
}
mg_changed_manifests() {
  mg_merge_changed_files "$1" | grep -E '(^|/)plugin\.json$' || true
}
# mg_json_version <ref> <path> — 해당 ref 의 plugin.json 에서 version 값(예 0.19.0) 추출.
#   없으면 빈 문자열. diff 라인 존재가 아니라 실제 값을 본다.
mg_json_version() {
  # shellcheck disable=SC2086
  $GIT_CMD show "$1:$2" 2>/dev/null \
    | grep -m1 -E '"version"[[:space:]]*:' \
    | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"?([0-9][0-9.]*)"?.*/\1/'
}

# mg_semver_gt <new> <old> — new 가 old 보다 큰 SemVer 면 0, 아니면 1.
#   old 가 비었으면(신규 매니페스트) new 만 있으면 0(증가로 간주). major.minor.patch 를
#   필드별 숫자 비교(bash 3.2, 외부 도구 없이).
mg_semver_gt() {
  local new="$1" old="$2"
  [[ -n "$new" ]] || return 1
  [[ -n "$old" ]] || return 0
  local oldIFS="$IFS"; IFS=.
  # shellcheck disable=SC2206
  local -a na=($new) oa=($old); IFS="$oldIFS"
  local i n o
  for ((i=0; i<3; i++)); do
    n="${na[i]:-0}"; o="${oa[i]:-0}"
    n="${n//[!0-9]/}"; o="${o//[!0-9]/}"
    [[ -n "$n" ]] || n=0; [[ -n "$o" ]] || o=0
    if (( 10#$n > 10#$o )); then return 0; fi
    if (( 10#$n < 10#$o )); then return 1; fi
  done
  return 1   # 모든 필드 동일 → 증가 아님(같은 값 재기입·재정렬 차단).
}

# mg_manifest_version_bumped <branch> — 변경된 plugin.json 중 하나라도 base 대비
#   실제 SemVer 가 증가했으면 0. 추가된 "version" 라인 존재가 아니라 old/new 값 비교.
mg_manifest_version_bumped() {
  local branch="$1" m oldv newv
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    oldv="$(mg_json_version "origin/$DEFAULT_BRANCH" "$m")"
    newv="$(mg_json_version "$branch" "$m")"
    if mg_semver_gt "$newv" "$oldv"; then return 0; fi
  done < <(mg_changed_manifests "$branch")
  return 1
}
# mg_version_gate <branch> — 워치 디렉토리 건드리는데 범프 없으면 1(차단). 없으면 0.
mg_version_gate() {
  local branch="$1"
  if mg_touches_watch_dir "$branch"; then
    mg_manifest_version_bumped "$branch" && return 0
    return 1
  fi
  return 0
}

# ===== 4) 머지 직렬화 락 — run-dir 단위(mkdir 원자성) =====
# mg_try_lock <run_dir> — 비차단 획득(성공 0, 점유중 1).
mg_try_lock() { mkdir "$1/.merge.lock" 2>/dev/null; }
# mg_release_lock <run_dir>
mg_release_lock() { rmdir "$1/.merge.lock" 2>/dev/null || true; }
# mg_acquire_lock <run_dir> [tries] — 바운드 대기 차단 획득(성공 0, 시간초과 1).
mg_acquire_lock() {
  local rd="$1" tries="${2:-600}" i=0
  while ! mg_try_lock "$rd"; do
    i=$((i+1)); [[ "$i" -ge "$tries" ]] && return 1
    sleep "${MERGE_LOCK_SLEEP:-1}"
  done
  return 0
}

# ===== 5) ff-only 머지 — 락 보호 구간. 머지 커밋·force 없음 =====
# mg_merge_ff_only <run_dir> <branch>
mg_merge_ff_only() {
  local rd="$1" branch="$2"
  mg_acquire_lock "$rd" || { mg_die "머지 락 획득 실패(직렬화 대기 초과): $rd"; return 1; }
  # 임계구간: main 체크아웃 + ff-only 머지 + base push.
  local rc=0
  {
    # shellcheck disable=SC2086
    $GIT_CMD fetch origin "$DEFAULT_BRANCH" \
      && $GIT_CMD checkout "$DEFAULT_BRANCH" \
      && $GIT_CMD merge --ff-only "$branch" \
      && $GIT_CMD push origin "$DEFAULT_BRANCH"
  } || rc=$?
  mg_release_lock "$rd"
  [[ "$rc" -eq 0 ]] || { mg_die "fast-forward 머지/푸시 실패(머지 커밋·force 금지): $branch → $DEFAULT_BRANCH"; return 1; }
}

# ===== 6) 정리 — loop 공개 cleanup 위임 =====
mg_cleanup_workspace() {
  # shellcheck disable=SC2086
  $LOOP_CMD cleanup "$1" >/dev/null 2>&1 || echo "WARN: cleanup 위임 실패(수동 정리 필요): $1" >&2
}

# ===== 7) 메인 진입 — 승인·버전 게이트 통과 시 머지하고 phase=merged =====
# mg_merge_finish <spec> <run_dir> <key> [pr] [skip_approval]
#   skip_approval=1 이면 승인 게이트만 우회한다(forge 미구성 직접 머지 서브모드: 승인 요청·
#   리뷰·승인 없이 머지). version 범프 게이트·ff-only·작업공간 정리는 그대로 유지한다.
#   반환: 0=머지 완료(phase=merged) / 1=버전게이트 차단(phase=blocked, 비완료 종착) /
#         2=미승인(대기, phase 불변).
mg_merge_finish() {
  local spec="$1" rd="$2" key="$3" pr="${4:-}" skip_approval="${5:-}"
  [[ -n "$spec" && -n "$rd" && -n "$key" ]] || { mg_die "사용: merge.sh finish <spec> <run_dir> <key> [pr] [skip_approval]"; return 1; }
  mkdir -p "$rd"

  local branch; branch="$(int_get_branch "$rd" "$key")"
  [[ -n "$branch" ]] || { mg_die "작업 브랜치 미설정(통합 선행 필요): key=$key"; return 1; }
  # direct 서브모드(skip_approval=1)는 PR 없이 동작하는 계약 — PR 보강을 건너뛴다
  # (같은 key 가 이전 forge 경로·재개에서 가졌을 수 있는 stale PR 을 끌어오지 않음).
  [[ "$skip_approval" == "1" ]] || { [[ -n "$pr" ]] || pr="$(int_get_pr "$rd" "$key")"; }
  int_log "$rd" "$key" "merge_finish spec=$spec branch=$branch pr=$pr skip_approval=${skip_approval:-0}"

  # 1) 승인 게이트(직접 머지 서브모드면 우회).
  if [[ "$skip_approval" == "1" ]]; then
    int_log "$rd" "$key" "직접 머지 서브모드: 승인 게이트 우회(version·ff-only 게이트는 유지)"
  elif ! mg_approval_ok "$pr"; then
    int_log "$rd" "$key" "승인 게이트 차단: approver 신원 APPROVED 없음(pr=$pr) — 머지 안 함(대기)"
    echo "key:     $key"
    echo "blocked: approval — approver 신원의 '승인됨' 리뷰가 없습니다(pr=$pr)."
    return 2
  fi

  # 2) 버전 범프 게이트(비완료 종착).
  if ! mg_version_gate "$branch"; then
    int_set_phase "$rd" "$key" blocked
    int_log "$rd" "$key" "버전 게이트 차단: plugins/ 변경에 plugin.json 범프 없음 — 머지 안 함(비완료 종착)"
    echo "key:     $key"
    echo "blocked: version-bump — plugins/ 를 건드리지만 plugin.json 버전이 오르지 않았습니다."
    return 1
  fi

  # 3) ff-only 머지(직렬화 락 보호).
  int_set_phase "$rd" "$key" merging
  int_log "$rd" "$key" "게이트 통과 → ff-only 머지(직렬화): $branch → $DEFAULT_BRANCH"
  mg_merge_ff_only "$rd" "$branch" || { int_set_phase "$rd" "$key" blocked; return 1; }

  # 4) 완료.
  int_set_phase "$rd" "$key" merged
  mg_cleanup_workspace "$spec"
  int_log "$rd" "$key" "완료: 머지 확인, phase=merged, 작업 공간 정리 위임."
  echo "key:     $key"
  echo "phase:   merged"
  echo "branch:  $branch → $DEFAULT_BRANCH (ff-only)"
  # direct 서브모드는 PR 없이 동작 — PR 필드 생략(stale PR 출력 방지).
  [[ "$skip_approval" == "1" ]] || echo "pr:      $pr"
  return 0
}

# ----- 사용법 -----
mg_usage() {
  cat >&2 <<'EOF'
usage: merge.sh <command> [args]

Commands:
  approve  <pr>                    분리 approver 신원으로 PR 승인 제출.
  approval <pr>                    approver 신원 APPROVED 유무(0/1).
  version-gate <branch>            버전 범프 게이트 판정(0=통과,1=차단).
  finish <spec> <run_dir> <key> [pr]
                                   승인·버전 게이트 통과 시 직렬화 ff-only 머지 후
                                   phase=merged + 작업 공간 정리 위임.

환경 변수: GIT_CMD FORGE_CMD LOOP_CMD DEFAULT_BRANCH APPROVER REVIEW_BOT APPROVE_CMD WATCH_DIRS
EOF
  return 1
}

# =====================================================================
# selftest — mock 인터페이스로 승인·버전 게이트·ff-only·직렬화 락·force 미사용 검증.
# =====================================================================
mg_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local rd="$TMP/.dispatch/runs/run1"; mkdir -p "$rd"
  local trace="$TMP/trace"; : > "$trace"

  mock_git() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    echo "git $*" >> "$trace"
    case "$1" in
      diff)
        if [[ "$*" == *"--name-only"* ]]; then printf '%s\n' ${MOCK_FILES:-}; return 0; fi
        ;;
      show)
        # git show <ref>:<path> — plugin.json version 값 시뮬(실제 값 비교 경로).
        #   base(origin/*)=1.0.0. branch: MOCK_BUMP=1 → 1.1.0(증가), MOCK_BUMP=same →
        #   1.0.0(동일, 차단되어야 함), 그 외 → 1.0.0.
        case "$2" in
          origin/*) echo '  "version": "1.0.0"' ;;
          *) if [[ "${MOCK_BUMP:-}" == "1" ]]; then echo '  "version": "1.1.0"'; else echo '  "version": "1.0.0"'; fi ;;
        esac
        ;;
    esac
    return 0
  }
  mock_forge() {
    echo "forge $*" >> "$trace"
    if [[ "$1" == "pr" && "$2" == "view" ]]; then printf '%s\n' "${MOCK_REVIEWS:-}"; fi
    return 0
  }
  mock_loop() { echo "loop $*" >> "$trace"; return 0; }
  mock_approve() { echo "approve $*" >> "$trace"; return 0; }
  GIT_CMD=mock_git; FORGE_CMD=mock_forge; LOOP_CMD=mock_loop; APPROVE_CMD=mock_approve
  DEFAULT_BRANCH=main; REVIEW_BOT="auto-review-bot"; APPROVER="approver-bot"

  local spec="$TMP/SPEC.md"; printf '# T\n' > "$spec"
  local fail=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
  has()   { grep -q "$1" "$trace"; }
  setup() { local k="$1"; int_set_branch "$rd" "$k" "feat/run1-$k"; int_set_pr "$rd" "$k" 77; }
  reset() { : > "$trace"; }

  # ---- AC6/AC7: 승인 O + 워치 변경 없음 → ff-only 머지 + phase=merged + cleanup ----
  reset; setup k1
  MOCK_REVIEWS=$'APPROVED\tapprover-bot' MOCK_FILES="README.md" MOCK_BUMP="" \
    mg_merge_finish "$spec" "$rd" k1 >/dev/null 2>&1; local rc=$?
  chk "AC7 머지 rc=0" "$rc" "0"
  has 'git merge --ff-only' && ok "AC7 ff-only 머지 호출" || bad "AC7 ff-only 머지 호출"
  has 'git push origin main' && ok "AC7 base push" || bad "AC7 base push"
  chk "AC7 phase=merged" "$(int_get_phase "$rd" k1)" "merged"
  has 'loop cleanup' && ok "AC7 cleanup 위임" || bad "AC7 cleanup 위임"

  # ---- AC6: 미승인 → 머지 안 함(대기 rc=2) ----
  reset; setup k2
  MOCK_REVIEWS=$'COMMENTED\tsomeone' MOCK_FILES="README.md" \
    mg_merge_finish "$spec" "$rd" k2 >/dev/null 2>&1; rc=$?
  chk "AC6 미승인 rc=2(대기)" "$rc" "2"
  if has 'git merge --ff-only'; then bad "AC6 미승인 머지 안 함"; else ok "AC6 미승인 머지 안 함"; fi
  chk "AC6 미승인 phase 불변" "$(int_get_phase "$rd" k2)" ""

  # ---- AC6: 리뷰 봇 self-approve → 무효 → 머지 안 함 ----
  reset; setup k3
  MOCK_REVIEWS=$'APPROVED\tauto-review-bot' MOCK_FILES="README.md" \
    mg_merge_finish "$spec" "$rd" k3 >/dev/null 2>&1; rc=$?
  chk "AC6 self-approve 무효 rc=2" "$rc" "2"
  if has 'git merge --ff-only'; then bad "AC6 self-approve 머지 안 함"; else ok "AC6 self-approve 머지 안 함"; fi

  # ---- AC7: plugins/ 변경 + 범프 없음 → 차단(비완료 종착 rc=1) ----
  reset; setup k4
  MOCK_REVIEWS=$'APPROVED\tapprover-bot' MOCK_FILES="plugins/autopilot/.claude-plugin/plugin.json" MOCK_BUMP="" \
    mg_merge_finish "$spec" "$rd" k4 >/dev/null 2>&1; rc=$?
  chk "AC7 워치+범프없음 rc=1(차단)" "$rc" "1"
  if has 'git merge --ff-only'; then bad "AC7 범프없음 머지 안 함"; else ok "AC7 범프없음 머지 안 함"; fi
  chk "AC7 차단 phase=blocked" "$(int_get_phase "$rd" k4)" "blocked"

  # ---- AC7 반례: plugins/ 변경 + 범프 있음 → 머지 ----
  reset; setup k5
  MOCK_REVIEWS=$'APPROVED\tapprover-bot' MOCK_FILES="plugins/autopilot/.claude-plugin/plugin.json" MOCK_BUMP="1" \
    mg_merge_finish "$spec" "$rd" k5 >/dev/null 2>&1; rc=$?
  chk "AC7 워치+범프있음 rc=0" "$rc" "0"
  has 'git merge --ff-only' && ok "AC7 범프시 머지" || bad "AC7 범프시 머지"

  # ---- 같은 version 값 재기입(라인은 추가되나 값 동일) → 차단 (Codex blocking 회귀 가드) ----
  reset; setup k6
  MOCK_REVIEWS=$'APPROVED\tapprover-bot' MOCK_FILES="plugins/autopilot/.claude-plugin/plugin.json" MOCK_BUMP="same" \
    mg_merge_finish "$spec" "$rd" k6 >/dev/null 2>&1; rc=$?
  chk "동일 버전 재기입 rc=1(차단)" "$rc" "1"
  if has 'git merge --ff-only'; then bad "동일 버전인데 머지함"; else ok "동일 버전 → 머지 안 함"; fi

  # ---- AC3/AC6: skip_approval=1 → 승인 게이트만 우회(직접 머지 서브모드) ----
  #   forge 미구성 직접 머지는 승인 요청·리뷰·승인 없이 머지하되 version gate·ff-only 는 유지.
  reset; setup kd1   # setup 은 int_set_pr 77 을 심는다 — direct 경로가 이 stale PR 을 끌어오면 안 된다.
  out="$(MOCK_REVIEWS=$'COMMENTED\tsomeone' MOCK_FILES="README.md" \
    mg_merge_finish "$spec" "$rd" kd1 "" 1 2>/dev/null)"; rc=$?
  chk "AC3 직접머지 skip-approval rc=0" "$rc" "0"
  has 'git merge --ff-only' && ok "AC3 직접머지 ff-only 머지" || bad "AC3 직접머지 ff-only 머지"
  chk "AC3 직접머지 phase=merged" "$(int_get_phase "$rd" kd1)" "merged"
  case "$out" in *77*) bad "AC3 직접머지 stale PR(77) 미출력 — skip_approval 시 보강 안 함";; *) ok "AC3 직접머지 stale PR(77) 미출력 — skip_approval 시 보강 안 함";; esac

  # ---- AC5: skip_approval=1 이어도 version gate 는 유지(차단) ----
  reset; setup kd2
  MOCK_REVIEWS="" MOCK_FILES="plugins/autopilot/.claude-plugin/plugin.json" MOCK_BUMP="" \
    mg_merge_finish "$spec" "$rd" kd2 "" 1 >/dev/null 2>&1; rc=$?
  chk "AC5 직접머지 version gate 차단 rc=1" "$rc" "1"
  if has 'git merge --ff-only'; then bad "AC5 직접머지 범프없음 머지 안 함"; else ok "AC5 직접머지 범프없음 머지 안 함"; fi

  # ---- AC6: approver 신원으로 승인 제출(approve action) ----
  reset
  mg_submit_approval 88 >/dev/null
  has 'approve 88' && ok "AC6 approver 신원 승인 제출" || bad "AC6 approver 신원 승인 제출"

  # ---- AC10: 머지 락 직렬화 — 점유 중엔 두 번째 획득 실패, 해제 후 성공 ----
  mg_try_lock "$rd" && ok "AC10 락 1차 획득" || bad "AC10 락 1차 획득"
  if mg_try_lock "$rd"; then bad "AC10 점유 중 2차 획득 차단"; else ok "AC10 점유 중 2차 획득 차단"; fi
  mg_release_lock "$rd"
  mg_try_lock "$rd" && ok "AC10 해제 후 재획득" || bad "AC10 해제 후 재획득"
  mg_release_lock "$rd"

  # ---- force 미사용 (mock_git force 보면 exit99; 위 머지 케이스 통과 = 미사용) ----
  reset; setup k6
  MOCK_REVIEWS=$'APPROVED\tapprover-bot' MOCK_FILES="README.md" \
    mg_merge_finish "$spec" "$rd" k6 >/dev/null 2>&1
  if grep -qiE 'force|(^| )-f( |$)' "$trace"; then bad "force 미사용"; else ok "force 미사용(git 인자에 force 없음)"; fi

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- CLI 진입 (sourcing 시 미실행) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SUB="${1:-}"; shift || true
  case "$SUB" in
    approve)      [[ $# -ge 1 ]] || mg_usage; mg_submit_approval "$1" ;;
    approval)     [[ $# -ge 1 ]] || mg_usage; mg_approval_ok "$1" && echo approved || { echo unapproved; exit 1; } ;;
    version-gate) [[ $# -ge 1 ]] || mg_usage; mg_version_gate "$1" && echo pass || { echo block; exit 1; } ;;
    finish)       mg_merge_finish "$@" ;;
    selftest)     mg_selftest ;;
    -h|--help|help) mg_usage ;;
    *) echo "알 수 없는 command: $SUB" >&2; mg_usage ;;
  esac
fi
