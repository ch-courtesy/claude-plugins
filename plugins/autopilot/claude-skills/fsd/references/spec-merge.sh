#!/usr/bin/env bash
# spec-merge.sh — fsd: dispatch 위임 직전 SPEC 을 타겟(기본) 통합 브랜치에 ff-merge 안착.
#
# 책임:
#   - 레포의 기본 통합 브랜치를 감지(리터럴 main 하드코딩 금지).
#   - 입력 SPEC 문서(들)를 그 타겟 브랜치 git 이력에 fast-forward 로 안착시키고
#     원격(origin)에 반영한다 — dispatch 가 구현을 시작하기 전 의도(SPEC)가 통합
#     브랜치 이력에 별도 commit 으로 남도록 보장한다.
#   - 멱등: 같은 내용이 이미 타겟에 올라가 있으면 새 commit 없이 통과(no-op).
#
# 절차의 단일 출처:
#   rules/engineering/branch-and-slug.md 의 "feat 브랜치 + commit" · "원격 동기화"
#   절차의 **형태**(feat 브랜치 경유 · ff-only · force push 금지)를 소비한다.
#   그 절차의 리터럴 `main` 은 감지된 기본 브랜치의 예시로 해석한다. 절차를 여기서
#   중복 재정의하지 않는다.
#
# 불변식:
#   - git 만 사용(forge CLI 호출 없음).
#   - force push 금지. 비-ff·push 거부는 **오류**로 보고하고 비-0 으로 종료한다
#     (호출자 fsd 는 이 비-0 을 dispatch 미시작 신호로 쓴다).
#   - 워킹 트리를 건드리지 않는다(plumbing 으로 commit 생성; 체크아웃 juggling 없음).
#
# 사용:
#   bash spec-merge.sh merge <task-id> <abs-spec...>
#   bash spec-merge.sh detect-target
#   bash spec-merge.sh selftest
#
# 환경 변수:
#   DEFAULT_BRANCH   타겟 브랜치 강제 지정(감지보다 우선). dispatch 와 동일 어휘.
#
# bash 3.2+ 호환 (associative array 미사용).

set -euo pipefail

# ----- 타겟(기본 통합) 브랜치 감지 -----
# 우선순위: DEFAULT_BRANCH env > origin/HEAD symbolic-ref > `remote show origin`
#           HEAD branch > 로컬 main/master > 현재 브랜치. 리터럴 main 하드코딩 아님.
sm_detect_target_branch() {
  if [[ -n "${DEFAULT_BRANCH:-}" ]]; then
    echo "$DEFAULT_BRANCH"; return 0
  fi
  local ref
  ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$ref" ]]; then
    echo "${ref#refs/remotes/origin/}"; return 0
  fi
  ref="$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1 || true)"
  if [[ -n "$ref" && "$ref" != "(unknown)" ]]; then
    echo "$ref"; return 0
  fi
  local b
  for b in main master; do
    if git show-ref --verify --quiet "refs/heads/$b"; then echo "$b"; return 0; fi
  done
  git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# ----- 후보 tree 구성 -----
# base tree 를 임시 인덱스에 읽어 SPEC 경로들을 갱신한 새 tree 해시를 출력.
# 워킹 트리·현재 인덱스를 건드리지 않는다.
sm_build_tree() {
  local base="$1"; shift   # 나머지는 rel:abs 쌍을 "rel" + 별도 배열 대신, rel\tabs 인코딩
  local idx; idx="$(mktemp)"
  local rc=0
  GIT_INDEX_FILE="$idx" git read-tree "$base" || rc=1
  local pair rel abs blob
  for pair in "$@"; do
    rel="${pair%%	*}"   # tab 구분
    abs="${pair#*	}"
    blob="$(git hash-object -w "$abs")" || { rc=1; break; }
    # 분리-인자 형식(쉼표 파싱 회피 — 경로에 쉼표가 있어도 안전).
    GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo 100644 "$blob" "$rel" || { rc=1; break; }
  done
  if [[ $rc -eq 0 ]]; then
    GIT_INDEX_FILE="$idx" git write-tree || rc=1
  fi
  rm -f "$idx"
  return $rc
}

# ----- 핵심: SPEC 을 타겟 브랜치에 ff-merge -----
merge_specs_to_target() {
  local task_id="${1:-}"; shift || true
  [[ -n "$task_id" ]] || { echo "spec-merge: task-id 필요" >&2; return 2; }
  [[ $# -ge 1 ]] || { echo "spec-merge: SPEC 경로 필요" >&2; return 2; }

  local root target
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "spec-merge: git 저장소 아님" >&2; return 2; }
  target="$(sm_detect_target_branch)"
  [[ -n "$target" ]] || { echo "spec-merge: 타겟 브랜치 감지 실패 — SPEC 미안착, dispatch 미시작" >&2; return 1; }

  local has_origin=0
  git remote get-url origin >/dev/null 2>&1 && has_origin=1

  local base
  if [[ $has_origin -eq 1 ]]; then
    if ! git fetch --quiet origin "$target" 2>/dev/null; then
      echo "spec-merge: origin/$target fetch 실패 — SPEC 미안착, dispatch 미시작 (재시도 안내)" >&2
      return 1
    fi
    base="origin/$target"
  else
    base="$target"
  fi
  if ! git rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
    echo "spec-merge: 타겟 브랜치 '$base' 가 없음 — SPEC 미안착, dispatch 미시작" >&2
    return 1
  fi
  local base_sha base_tree
  base_sha="$(git rev-parse "$base")"
  base_tree="$(git rev-parse "$base^{tree}")"

  # rel\tabs 쌍 구성(레포 루트 상대 경로만 허용).
  # rel 과 abs 를 탭 한 개로 인코딩하므로, 경로 자체에 탭·개행이 들어가면 분리가
  # 깨져 엉뚱한 경로를 tree 에 쓸 수 있다(git 은 경로에 탭을 허용함). SPEC 문서 경로에
  # 탭·개행은 정당하게 쓰이지 않으므로 명시 거부한다(미안착·dispatch 미시작).
  local pairs=() s rel
  for s in "$@"; do
    case "$s" in
      "$root"/*) rel="${s#"$root"/}" ;;
      *) echo "spec-merge: SPEC 이 레포 루트 밖: $s — SPEC 미안착, dispatch 미시작" >&2; return 1 ;;
    esac
    if [[ "$rel" == *$'\t'* || "$rel" == *$'\n'* ]]; then
      echo "spec-merge: SPEC 경로에 탭·개행 문자 — 미지원(엉뚱한 경로 기록 위험). SPEC 미안착, dispatch 미시작: $rel" >&2
      return 1
    fi
    [[ -f "$s" ]] || { echo "spec-merge: SPEC 파일 없음: $s" >&2; return 1; }
    pairs+=("$rel	$s")
  done

  # 후보 tree → base tree 와 같으면 멱등 no-op.
  local newtree
  newtree="$(sm_build_tree "$base" "${pairs[@]}")" || { echo "spec-merge: tree 구성 실패" >&2; return 1; }
  if [[ "$newtree" == "$base_tree" ]]; then
    echo "spec-merge: SPEC 이미 타겟 브랜치($target)에 안착 — no-op (멱등)"
    return 0
  fi

  # feat 브랜치 경유 commit (parent=base; ff-only 보장).
  local feat_commit feat_branch
  feat_commit="$(git commit-tree "$newtree" -p "$base_sha" \
      -m "feat(spec): $task_id — SPEC 을 $target 에 선반영")" \
    || { echo "spec-merge: commit-tree 실패 — SPEC 미안착" >&2; return 1; }
  feat_branch="feat/$task_id"
  git branch -f "$feat_branch" "$feat_commit" >/dev/null 2>&1 || true

  local cleanup_feat='git branch -D "$feat_branch" >/dev/null 2>&1 || true'

  # 로컬 타겟이 이미 있으면 분기(비-ff) 여부를 먼저 검사한다(어떤 ref 변경보다 먼저).
  local orig_branch local_sha local_exists=0
  orig_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if git rev-parse --verify --quiet "refs/heads/$target" >/dev/null 2>&1; then
    local_exists=1
    local_sha="$(git rev-parse "refs/heads/$target")"
    if ! git merge-base --is-ancestor "$local_sha" "$feat_commit"; then
      eval "$cleanup_feat"
      echo "spec-merge: 로컬 $target 가 origin/$target 와 분기 — ff 불가. force 금지; 'git reset --hard origin/$target' 또는 PR 흐름으로 재시도. SPEC 미안착, dispatch 미시작." >&2
      return 1
    fi
  fi

  # 원격 반영을 먼저 한다(force 금지). 로컬 타겟은 원격 push 가 성공한 뒤에만 전진시켜,
  # push 거부 시 로컬 기본 브랜치에 SPEC commit 이 남지 않게 한다(미안착 의미·멱등 보존).
  # feat_commit 을 origin/<target> 으로 직접 ff push — 로컬 ref 상태와 분리한다.
  if [[ $has_origin -eq 1 ]]; then
    if ! git push --quiet origin "$feat_commit:refs/heads/$target" 2>/dev/null; then
      eval "$cleanup_feat"
      echo "spec-merge: origin/$target push 거부 — 로컬 $target 미전진(원격·로컬 모두 미반영). force 금지; 'git fetch origin $target' 후 재시도하거나 PR 흐름으로 전환. SPEC 미안착, dispatch 미시작." >&2
      return 1
    fi
  fi

  # 여기 도달 = 원격 push 성공(또는 origin 없음). 이제 로컬 타겟을 ff 로 전진시킨다.
  # origin 이 있으면 SPEC 은 이미 origin/<target> 에 안착했으므로 로컬 sync 실패는
  # 치명적이지 않다(best-effort). origin 이 없으면 로컬이 곧 통합 타겟이라 실패는 오류.
  if [[ $local_exists -eq 1 ]]; then
    if [[ "$orig_branch" == "$target" ]]; then
      if ! git merge --ff-only "$feat_branch" >/dev/null 2>&1 && [[ $has_origin -eq 0 ]]; then
        eval "$cleanup_feat"
        echo "spec-merge: 로컬 $target ff 머지 실패 — SPEC 미안착, dispatch 미시작." >&2
        return 1
      fi
    else
      if ! git update-ref "refs/heads/$target" "$feat_commit" "$local_sha" 2>/dev/null && [[ $has_origin -eq 0 ]]; then
        eval "$cleanup_feat"
        echo "spec-merge: 로컬 $target 갱신 실패 — SPEC 미안착, dispatch 미시작." >&2
        return 1
      fi
    fi
  else
    # 로컬 타겟 브랜치 없음(base=origin/target) → 새로 생성.
    git update-ref "refs/heads/$target" "$feat_commit"
  fi

  eval "$cleanup_feat"
  echo "spec-merge: SPEC ${#pairs[@]}건 타겟 브랜치($target) 안착 완료$([[ $has_origin -eq 1 ]] && echo ' + origin push')"
  return 0
}

# ----- 자체 검증 (실제 git 저장소) -----
sm_selftest() {
  set +e
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local fail=0 rc
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }

  # ---- S1: 타겟 브랜치 감지 (기본=trunk, main 하드코딩 아님) ----
  local O1="$TMP/o1.git" R1="$TMP/r1"
  git init -q --bare "$O1"
  git init -q "$R1"
  ( cd "$R1"
    git config user.email t@t; git config user.name t
    git checkout -q -b trunk
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    git remote add origin "$O1"
    git push -q origin trunk
    git remote set-head origin trunk )
  local det
  det="$( cd "$R1" && unset DEFAULT_BRANCH && sm_detect_target_branch )"
  [[ "$det" == "trunk" ]] && ok "S1 타겟 감지=trunk(비-main, 하드코딩 아님)" || bad "S1 타겟 감지 got=$det"

  # ---- S2: ff-merge 성공 — SPEC 이 로컬 trunk·origin/trunk 에 안착 ----
  ( cd "$R1"
    mkdir -p docs/specs/x
    printf '# X\n## 수용 기준\n1. A.\n' > docs/specs/x/SPEC.md
    git checkout -q -b work )   # orig_branch != target (loop 워크트리 모사)
  local spec2="$R1/docs/specs/x/SPEC.md"
  ( cd "$R1" && unset DEFAULT_BRANCH && merge_specs_to_target "x-task" "$spec2" ) > "$TMP/s2.out" 2>&1
  rc=$?
  [[ $rc -eq 0 ]] && ok "S2 머지 0 exit" || { bad "S2 머지 rc=$rc"; cat "$TMP/s2.out"; }
  ( cd "$R1" && git show "trunk:docs/specs/x/SPEC.md" 2>/dev/null | grep -q '# X' ) \
    && ok "S2 SPEC 로컬 trunk 이력 안착(AC1)" || bad "S2 SPEC 로컬 trunk 안착"
  ( cd "$R1" && git show "origin/trunk:docs/specs/x/SPEC.md" 2>/dev/null | grep -q '# X' ) \
    && ok "S2 SPEC origin/trunk 안착(원격 반영)" || bad "S2 SPEC origin/trunk 안착"
  # 워킹 트리 미교란: 여전히 work 브랜치
  [[ "$( cd "$R1" && git rev-parse --abbrev-ref HEAD )" == "work" ]] \
    && ok "S2 워킹 트리 미교란(현재 브랜치 유지)" || bad "S2 워킹 트리 교란됨"
  # feat 브랜치 정리됨
  ( cd "$R1" && ! git show-ref --verify --quiet refs/heads/feat/x-task ) \
    && ok "S2 ephemeral feat 브랜치 정리" || bad "S2 feat 브랜치 잔존"

  # ---- S3: 멱등 — 재실행 no-op, origin/trunk sha 불변 (AC3) ----
  local before after
  before="$( cd "$R1" && git rev-parse origin/trunk )"
  ( cd "$R1" && unset DEFAULT_BRANCH && merge_specs_to_target "x-task" "$spec2" ) > "$TMP/s3.out" 2>&1
  rc=$?
  ( cd "$R1" && git fetch -q origin trunk )
  after="$( cd "$R1" && git rev-parse origin/trunk )"
  [[ $rc -eq 0 ]] && ok "S3 재실행 0 exit" || bad "S3 재실행 rc=$rc"
  [[ "$before" == "$after" ]] && ok "S3 멱등 no-op(새 commit 없음)" || bad "S3 멱등 깨짐 $before→$after"
  grep -q "no-op" "$TMP/s3.out" && ok "S3 no-op 메시지" || bad "S3 no-op 메시지"

  # ---- S4: 비-ff(로컬 분기) → 실패·비-0·force 금지·원격 미반영 (AC5) ----
  local O2="$TMP/o2.git" R2="$TMP/r2" R2b="$TMP/r2b"
  git init -q --bare "$O2"
  git init -q "$R2"
  ( cd "$R2"
    git config user.email t@t; git config user.name t
    git checkout -q -b trunk
    echo a > a.txt; git add a.txt; git commit -q -m A
    git remote add origin "$O2"; git push -q origin trunk )
  git -C "$O2" symbolic-ref HEAD refs/heads/trunk
  git clone -q "$O2" "$R2b"
  ( cd "$R2b"
    git config user.email t@t; git config user.name t
    echo c > c.txt; git add c.txt; git commit -q -m C; git push -q origin trunk )
  ( cd "$R2"
    git checkout -q trunk
    echo b > b.txt; git add b.txt; git commit -q -m B   # 로컬 전용 분기
    git checkout -q -b work
    mkdir -p docs/specs/y; printf '# Y\n## 수용 기준\n1. B.\n' > docs/specs/y/SPEC.md )
  ( cd "$R2" && DEFAULT_BRANCH=trunk merge_specs_to_target "y-task" "$R2/docs/specs/y/SPEC.md" ) > "$TMP/s4.out" 2>&1
  rc=$?
  [[ $rc -ne 0 ]] && ok "S4 비-ff 실패 비-0 종료(dispatch 미시작 신호)" || { bad "S4 비-ff 비-0 (rc=$rc)"; cat "$TMP/s4.out"; }
  grep -qi "dispatch 미시작\|ff 불가\|분기" "$TMP/s4.out" \
    && ok "S4 SPEC 미안착 메시지(원인 구분)" || bad "S4 메시지"
  ( cd "$R2" && git fetch -q origin trunk )
  ( cd "$R2" && ! git show "origin/trunk:docs/specs/y/SPEC.md" >/dev/null 2>&1 ) \
    && ok "S4 SPEC origin 미반영(force 금지)" || bad "S4 SPEC origin 반영됨(force 의심)"
  ( cd "$R2" && [[ "$(git rev-parse origin/trunk)" == "$( cd "$R2b" && git rev-parse origin/trunk 2>/dev/null || echo x )" ]] ) >/dev/null 2>&1

  # ---- S5: 원격 push 실패 시 로컬 타겟 미전진 (롤백/미반영) [blocking/90] ----
  # 로컬은 비-분기인데 origin push 만 거부되는 상황: push 후 로컬 기본 브랜치에
  # SPEC commit 이 남으면 "SPEC 미안착"·멱등 의미가 깨진다(codex blocking/90).
  local O3="$TMP/o3.git" R3="$TMP/r3"
  git init -q --bare "$O3"
  git init -q "$R3"
  ( cd "$R3"
    git config user.email t@t; git config user.name t
    git checkout -q -b trunk
    echo a > a.txt; git add a.txt; git commit -q -m A
    git remote add origin "$O3"; git push -q origin trunk )
  git -C "$O3" symbolic-ref HEAD refs/heads/trunk
  cat > "$O3/hooks/update" <<'HK'
#!/bin/sh
[ "$1" = refs/heads/trunk ] && { echo "test-hook: trunk push rejected" >&2; exit 1; }
exit 0
HK
  chmod +x "$O3/hooks/update"
  ( cd "$R3"
    git checkout -q -b work
    mkdir -p docs/specs/z; printf '# Z\n## 수용 기준\n1. C.\n' > docs/specs/z/SPEC.md )
  local s5_before
  s5_before="$( cd "$R3" && git rev-parse refs/heads/trunk )"
  ( cd "$R3" && DEFAULT_BRANCH=trunk merge_specs_to_target "z-task" "$R3/docs/specs/z/SPEC.md" ) > "$TMP/s5.out" 2>&1
  rc=$?
  [[ $rc -ne 0 ]] && ok "S5 push 실패 시 비-0 종료" || { bad "S5 push 실패 rc=$rc"; cat "$TMP/s5.out"; }
  [[ "$( cd "$R3" && git rev-parse refs/heads/trunk )" == "$s5_before" ]] \
    && ok "S5 push 실패 후 로컬 trunk 미전진(롤백) [blocking/90]" || bad "S5 로컬 trunk 가 전진함(롤백 안 됨)"
  ( cd "$R3" && ! git show "refs/heads/trunk:docs/specs/z/SPEC.md" >/dev/null 2>&1 ) \
    && ok "S5 SPEC 로컬 trunk 미반영" || bad "S5 SPEC 로컬 trunk 반영됨"

  # ---- S6: 탭/개행 포함 SPEC 경로 거부 [blocking/85] ----
  # git 경로엔 탭이 허용되므로 탭 포함 경로를 받으면 rel\tabs 인코딩이 깨져 엉뚱한
  # 경로를 기본 브랜치 이력에 쓸 수 있다 — 명시 거부해야 한다(codex blocking/85).
  local s6dir
  s6dir="docs/specs/$(printf 'tab\there')"
  ( cd "$R1" && mkdir -p "$s6dir" && printf '# T\n## 수용 기준\n1. A.\n' > "$s6dir/SPEC.md" )
  local s6_before
  s6_before="$( cd "$R1" && git rev-parse origin/trunk )"
  ( cd "$R1" && unset DEFAULT_BRANCH && merge_specs_to_target "tab-task" "$R1/$s6dir/SPEC.md" ) > "$TMP/s6.out" 2>&1
  rc=$?
  [[ $rc -ne 0 ]] && ok "S6 탭 경로 비-0 종료 [blocking/85]" || { bad "S6 탭 경로 rc=$rc(거부 안 됨)"; cat "$TMP/s6.out"; }
  grep -qi "탭\|개행\|미지원" "$TMP/s6.out" && ok "S6 탭 경로 거부 메시지" || bad "S6 탭 경로 메시지 없음"
  ( cd "$R1" && git fetch -q origin trunk 2>/dev/null; [[ "$(git rev-parse origin/trunk)" == "$s6_before" ]] ) \
    && ok "S6 origin/trunk 불변(미기록)" || bad "S6 origin/trunk 변경됨"

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- 디스패처 -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sub="${1:-}"; shift || true
  case "$sub" in
    merge)         merge_specs_to_target "$@" ;;
    detect-target) sm_detect_target_branch ;;
    selftest)      sm_selftest ;;
    *) echo "usage: spec-merge.sh {merge <task-id> <spec...>|detect-target|selftest}" >&2; exit 1 ;;
  esac
fi
