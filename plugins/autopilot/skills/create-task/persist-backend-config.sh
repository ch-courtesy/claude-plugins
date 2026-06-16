#!/usr/bin/env bash
# persist-backend-config.sh — 백엔드 선택 SoT(.autopilot/task-backend.json)를 메인에 영속화.
#
# 책임 (create-task 자체 소유, 플러그인 자기완결):
#   - create-task 의 백엔드 init 직후 호출되어, config 파일을 **config만 담은 최소 커밋**으로
#     메인 브랜치에 올린다. origin 이 있으면 별도 브랜치+PR+auto-merge, 없으면 로컬 merge.
#   - 이미 메인(base)에 동일 내용이 추적되고 있으면 멱등적으로 건너뛴다(중복 PR/커밋 없음).
#
# 하지 않는 일:
#   - 태스크 본문·다른 변경 동반 커밋(항상 config 파일 단독). plugin.json 범프(워치=plugins 가
#     아닌 .autopilot/ 변경이므로 범프 게이트 비대상). rules/·타 스킬 doc-link.
#
# 워킹트리 비파괴: config 커밋은 plumbing(commit-tree)으로 만들어 사용자의 더티 워킹트리·
# 스테이징을 건드리지 않는다. config 외 파일은 절대 커밋에 포함되지 않는다.
#
# 출력: 한 줄 JSON  {status: persisted|skip|pending|pr_created, ...}
#   persisted  = 메인 머지(또는 auto-merge 예약) 확인됨.
#   skip       = base 에 동일 config 이미 추적(멱등).
#   pending    = gh 미가용 등으로 PR 미생성·메인 영속화 미완(브랜치만 push). exit 3.
#   pr_created = PR 은 생성됐으나 머지(예약) 실패로 메인 영속화 미완. exit 3.
# 메인 영속화가 확인되지 않으면 절대 persisted 로 보고하지 않는다(조용한 부분 실패 금지).
set -euo pipefail

PBC_REL=".autopilot/task-backend.json"
PBC_BRANCH="chore/persist-task-backend-config"
PBC_GH="${PBC_GH:-gh}"   # gh CLI(테스트 시 스텁 주입 가능)
pbc_die() { echo "persist-backend-config: $*" >&2; exit 1; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || pbc_die "git repo 아님"
CONFIG="$ROOT/$PBC_REL"
[[ -f "$CONFIG" ]] || pbc_die "config 없음: $CONFIG (먼저 adapter init 필요)"

# origin 유무로 통합 경로 결정 (github PR vs 로컬 direct)
ORIGIN_URL="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"

# 기본(메인) 브랜치 이름 판정
pbc_default_branch() {
  if [[ -n "$ORIGIN_URL" ]]; then
    local r; r="$(git -C "$ROOT" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
    [[ -n "$r" ]] && { printf '%s' "${r##*/}"; return; }
    printf 'main'; return
  fi
  local b
  for b in main master; do
    git -C "$ROOT" show-ref --verify --quiet "refs/heads/$b" && { printf '%s' "$b"; return; }
  done
  git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'main'
}
DEFAULT_BRANCH="$(pbc_default_branch)"

# base ref: origin 있으면 origin/<default>, 없으면 로컬 <default>
if [[ -n "$ORIGIN_URL" ]]; then
  git -C "$ROOT" fetch -q origin "$DEFAULT_BRANCH" 2>/dev/null || true
  BASE_REF="origin/$DEFAULT_BRANCH"
else
  BASE_REF="$DEFAULT_BRANCH"
fi
git -C "$ROOT" rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null \
  || pbc_die "base ref 확인 불가: $BASE_REF"

# ----- 멱등성: base 에 동일 config 가 이미 추적되면 skip -----
if git -C "$ROOT" cat-file -e "$BASE_REF:$PBC_REL" 2>/dev/null; then
  if diff -q <(git -C "$ROOT" show "$BASE_REF:$PBC_REL") "$CONFIG" >/dev/null 2>&1; then
    jq -nc --arg b "$BASE_REF" '{status:"skip", reason:"already-persisted", base:$b}'
    exit 0
  fi
fi

# ----- config-only 커밋 생성 (plumbing, 워킹트리 비파괴) -----
BASE_SHA="$(git -C "$ROOT" rev-parse "$BASE_REF^{commit}")"
BLOB="$(git -C "$ROOT" hash-object -w "$CONFIG")"
MSG="chore(autopilot): 태스크 백엔드 선택 SoT를 메인에 영속화

.autopilot/task-backend.json(백엔드 선택)을 추적 파일로 메인에 올린다."

TMP_IDX="$(mktemp)"; trap 'rm -f "$TMP_IDX"' EXIT
GIT_INDEX_FILE="$TMP_IDX" git -C "$ROOT" read-tree "$BASE_SHA"
GIT_INDEX_FILE="$TMP_IDX" git -C "$ROOT" update-index --add --cacheinfo "100644,$BLOB,$PBC_REL"
TREE="$(GIT_INDEX_FILE="$TMP_IDX" git -C "$ROOT" write-tree)"
COMMIT="$(git -C "$ROOT" commit-tree "$TREE" -p "$BASE_SHA" -m "$MSG")"

if [[ -n "$ORIGIN_URL" ]]; then
  # ----- github: config-only 브랜치 push → PR → repo auto-merge 경로 -----
  git -C "$ROOT" push -q origin "+$COMMIT:refs/heads/$PBC_BRANCH"

  # gh 미가용: 브랜치만 push 됨 — PR·머지 미수행. 조용한 성공(persisted) 금지.
  if ! command -v "$PBC_GH" >/dev/null 2>&1; then
    jq -nc --arg br "$PBC_BRANCH" --arg base "$DEFAULT_BRANCH" \
      '{status:"pending", path:"'"$PBC_REL"'", branch:$br, base:$base,
        note:"gh 미설치 — config 브랜치만 push됨. PR 생성·메인 머지를 수동 완료 필요."}'
    exit 3
  fi

  PR_URL="$("$PBC_GH" pr create --base "$DEFAULT_BRANCH" --head "$PBC_BRANCH" \
            --title "chore(autopilot): persist task backend config SoT to main" \
            --body "백엔드 선택 SoT(\`$PBC_REL\`)를 메인에 영속화. config 파일 단독 변경." \
            2>/dev/null || "$PBC_GH" pr view "$PBC_BRANCH" --json url -q .url 2>/dev/null || true)"

  # auto-merge 예약(또는 즉시 머지) 성공 여부를 추적 — 실패를 || true 로 삼키지 않는다.
  MERGE_OK=0
  if "$PBC_GH" pr merge "$PBC_BRANCH" --auto --merge 2>/dev/null; then MERGE_OK=1
  elif "$PBC_GH" pr merge "$PBC_BRANCH" --merge 2>/dev/null; then MERGE_OK=1
  fi

  if (( MERGE_OK )); then
    jq -nc --arg br "$PBC_BRANCH" --arg pr "$PR_URL" --arg base "$DEFAULT_BRANCH" \
      '{status:"persisted", path:"'"$PBC_REL"'", branch:$br, base:$base}
       + (if $pr != "" then {pr_url:$pr} else {} end)'
  else
    # PR 은 생성됐으나 머지(예약) 실패 — 권한·브랜치 보호·체크 등. 메인 영속화 미완.
    jq -nc --arg br "$PBC_BRANCH" --arg pr "$PR_URL" --arg base "$DEFAULT_BRANCH" \
      '{status:"pr_created", path:"'"$PBC_REL"'", branch:$br, base:$base,
        note:"PR 생성됨, auto-merge 예약 실패 — 메인 머지를 수동 완료 필요."}
       + (if $pr != "" then {pr_url:$pr} else {} end)'
    exit 3
  fi
else
  # ----- direct(로컬): config-only 커밋을 메인에 merge 커밋으로 통합 -----
  MERGE="$(git -C "$ROOT" commit-tree "$TREE" -p "$BASE_SHA" -p "$COMMIT" \
            -m "Merge: 태스크 백엔드 선택 SoT 영속화")"
  git -C "$ROOT" update-ref "refs/heads/$DEFAULT_BRANCH" "$MERGE"
  # 메인이 현재 체크아웃이면 인덱스만 새 HEAD로 동기화(워킹트리 파일은 유지).
  if [[ "$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "$DEFAULT_BRANCH" ]]; then
    git -C "$ROOT" read-tree "$MERGE"
  fi
  jq -nc --arg base "$DEFAULT_BRANCH" \
    '{status:"persisted", path:"'"$PBC_REL"'", base:$base, mode:"direct"}'
fi
