#!/usr/bin/env bash
# test-spec-loop-contract.sh — SPEC 116 verify
#
# spec↔loop feat 브랜치·worktree 경로 단일 규약 contract verifier.
#
# 검사 항목 (SPEC 116 수용 기준 매핑):
#   T1. slug 도출 결정성 — canonical 알고리즘이 "Foo Bar" → "foo-bar".
#       + spec SKILL.md 가 canonical 알고리즘을 문서화하고 있는지 (drift guard).
#       + spec SKILL.md 가 slug-bearing SPEC.md 경로를 참조하는지.
#   T2. find_feat_branch — `feat/<input-id>-<slug>` 브랜치를 input-id 만으로 발견.
#   T3. worktree 경로 — `milestones/<m>/loops/<input-id>-<slug>/.worktree`.
#   T4. SPEC.md 경로 정합 — spec 작성 경로 = loop 읽기 경로 = pr-phase 읽기 경로.
#   T5. 모호성 die — 동일 input-id 매칭 브랜치 2+ 일 때 비-zero exit + 안내.
#
# 셋업: 임시 git fixture · mock claude (DONE 즉시 생성) · yq 필요.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOOP_SH="$REPO_ROOT/plugins/autopilot/skills/loop/references/loop.sh"
PR_PHASE_SH="$REPO_ROOT/plugins/autopilot/skills/loop/references/pr-phase.sh"
SPEC_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/spec/SKILL.md"

[[ -f "$LOOP_SH" ]]      || { echo "FAIL setup: loop.sh missing: $LOOP_SH" >&2; exit 1; }
[[ -f "$PR_PHASE_SH" ]]  || { echo "FAIL setup: pr-phase.sh missing: $PR_PHASE_SH" >&2; exit 1; }
[[ -f "$SPEC_SKILL_MD" ]]|| { echo "FAIL setup: SKILL.md missing: $SPEC_SKILL_MD" >&2; exit 1; }

# yq 의존 — 없으면 cmd_start가 scope.include 파싱 단계에서 die.
command -v yq >/dev/null 2>&1 \
  || { echo "SKIP: yq 미설치 — verify 실행 불가" >&2; exit 0; }

# Canonical slug 알고리즘 (SKILL.md §9.5.1 단일 출처). 이 함수가 변하면
# SKILL.md 문서·loop 코드 추출 로직과 함께 변경해야 한다.
canonical_slug() {
  local title="$1"
  printf '%s' "$title" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -c 'a-z0-9-' '-' \
    | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

WORK_DIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf $WORK_DIR" EXIT

PROJECT="$WORK_DIR/proj"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init -q
git config user.email t@t
git config user.name t
git commit --allow-empty -m init -q
MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD)
# baseline empty commit (suppressor 오탐 방지)
git commit --allow-empty -q -m "chore: baseline"

# mock claude — stdin 소비 + DONE 생성 + JSON 응답
MOCK_BIN="$WORK_DIR/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
touch DONE
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
MOCKEOF
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

INPUT_ID="test123"
TITLE="Foo Bar"
SLUG=$(canonical_slug "$TITLE")
DIR_REL="milestones/regular/loops/${INPUT_ID}-${SLUG}"

# ──────────────────────────────────────────────────────────────────────────────
# T1. slug 도출 결정성 + SKILL.md drift guard
# ──────────────────────────────────────────────────────────────────────────────
[[ "$SLUG" == "foo-bar" ]] \
  || { echo "FAIL T1a: canonical_slug 'Foo Bar' = '$SLUG', want 'foo-bar'" >&2; exit 1; }

# SKILL.md 단일 출처 검사 — canonical bash 알고리즘 라인이 그대로 박혀 있어야 한다.
grep -qF "LC_ALL=C tr '[:upper:]' '[:lower:]'" "$SPEC_SKILL_MD" \
  || { echo "FAIL T1b: SKILL.md missing canonical lowercase step" >&2; exit 1; }
grep -qF "LC_ALL=C tr -c 'a-z0-9-' '-'" "$SPEC_SKILL_MD" \
  || { echo "FAIL T1c: SKILL.md missing canonical char-replacement step" >&2; exit 1; }
grep -qF "sed -e 's/--*/-/g'" "$SPEC_SKILL_MD" \
  || { echo "FAIL T1d: SKILL.md missing canonical collapse step" >&2; exit 1; }

# SKILL.md 가 slug-bearing SPEC.md 경로 컨벤션을 참조해야 한다 (단일 컨벤션 선언).
grep -qF "milestones/<m>/loops/<c>-<slug>" "$SPEC_SKILL_MD" \
  || { echo "FAIL T1e: SKILL.md missing slug-bearing directory reference (milestones/<m>/loops/<c>-<slug>)" >&2; exit 1; }

echo "OK T1: slug 도출 결정성 + SKILL.md drift guard"

# ──────────────────────────────────────────────────────────────────────────────
# Fixture: slug-bearing 디렉토리·feat 브랜치 셋업 (spec 스킬의 신규 contract 결과를 모사)
# ──────────────────────────────────────────────────────────────────────────────
mkdir -p "$PROJECT/$DIR_REL"
cat > "$PROJECT/$DIR_REL/SPEC.md" <<SPECEOF
---
scope:
  include: ["src/**"]
verify: "true"
---

# $TITLE

## 무엇을 만들 것인가
Test fixture.
SPECEOF

git checkout -q -b "feat/${INPUT_ID}-${SLUG}"
git add -f "$DIR_REL/SPEC.md"
git commit -q -m "feat(spec): ${INPUT_ID} — ${TITLE}"
git checkout -q "$MAIN_BRANCH"

# ──────────────────────────────────────────────────────────────────────────────
# T2. find_feat_branch — input-id 단일 인자로 발견
# ──────────────────────────────────────────────────────────────────────────────
set +e
T2_OUT=$(bash "$LOOP_SH" start "$INPUT_ID" --no-pr --max-iterations 1 2>&1)
T2_RC=$?
set -e

if [[ $T2_RC -ne 0 ]]; then
  echo "FAIL T2: loop.sh start '$INPUT_ID' rc=$T2_RC" >&2
  echo "----- output:" >&2
  echo "$T2_OUT" >&2
  echo "----- branches:" >&2
  git branch -a >&2
  exit 1
fi
echo "$T2_OUT" | grep -q "feat 브랜치 부재" \
  && { echo "FAIL T2: find_feat_branch did not match feat/${INPUT_ID}-${SLUG} by input-id alone" >&2
       echo "$T2_OUT" >&2; exit 1; }

echo "OK T2: find_feat_branch — input-id roundtrip"

# ──────────────────────────────────────────────────────────────────────────────
# T3. worktree 경로 — slug-bearing
# ──────────────────────────────────────────────────────────────────────────────
EXPECTED_WT="$PROJECT/${DIR_REL}/.worktree"
if [[ ! -d "$EXPECTED_WT" ]]; then
  echo "FAIL T3: 기대 worktree 경로 부재: $EXPECTED_WT" >&2
  echo "  실제 worktree 디렉토리:" >&2
  find "$PROJECT/milestones" -name '.worktree' -type d 2>/dev/null >&2 || true
  exit 1
fi
echo "OK T3: worktree 경로 — $EXPECTED_WT"

# ──────────────────────────────────────────────────────────────────────────────
# T4. SPEC.md 경로 정합 (spec 작성 = loop 읽기 = pr-phase 읽기)
# ──────────────────────────────────────────────────────────────────────────────
# spec 작성 경로 = $DIR_REL/SPEC.md (위 fixture)
# loop 읽기 경로 = worktree 안의 $DIR_REL/SPEC.md
WT_SPEC="$EXPECTED_WT/${DIR_REL}/SPEC.md"
[[ -f "$WT_SPEC" ]] \
  || { echo "FAIL T4a: worktree 안 SPEC.md 부재: $WT_SPEC" >&2; exit 1; }

# pr-phase.sh 의 SPEC_FILE 도출 — feat 브랜치 이름의 slug를 사용해야 한다.
# 동일 도출 로직을 본 테스트에서 재현해 결과가 slug-bearing 경로와 일치하는지 확인.
PR_TASK_ID="regular/${INPUT_ID}"
PR_BRANCH="feat/${INPUT_ID}-${SLUG}"
PR_CHILD="${PR_TASK_ID#*/}"
PR_MILESTONE="${PR_TASK_ID%%/*}"
PR_SLUG_FROM_BRANCH=""
PR_PREFIX="feat/${PR_CHILD}"
if [[ "$PR_BRANCH" == "${PR_PREFIX}-"* ]]; then
  PR_SLUG_FROM_BRANCH="${PR_BRANCH#${PR_PREFIX}-}"
fi
if [[ -n "$PR_SLUG_FROM_BRANCH" ]]; then
  PR_DERIVED_SPEC="$EXPECTED_WT/milestones/${PR_MILESTONE}/loops/${PR_CHILD}-${PR_SLUG_FROM_BRANCH}/SPEC.md"
else
  PR_DERIVED_SPEC="$EXPECTED_WT/milestones/${PR_MILESTONE}/loops/${PR_CHILD}/SPEC.md"
fi
[[ "$PR_DERIVED_SPEC" == "$WT_SPEC" ]] \
  || { echo "FAIL T4b: pr-phase 도출 경로 ≠ 실제 경로:" >&2
       echo "  derived: $PR_DERIVED_SPEC" >&2
       echo "  actual:  $WT_SPEC" >&2; exit 1; }

# pr-phase.sh 의 실제 코드가 $BRANCH 로부터 slug 를 추출해 SPEC_FILE 을 만드는지 확인 (drift guard).
# 구 코드: SPEC_FILE="$WT/milestones/${TASK_ID%%/*}/loops/${TASK_ID#*/}/SPEC.md"  ← slug 미고려
# 신 코드: $BRANCH 기반 slug 추출 (`${BRANCH#feat/<child>-}` 패턴) 후 경로 조립.
if ! grep -qE '\$\{?BRANCH#' "$PR_PHASE_SH"; then
  echo "FAIL T4c: pr-phase.sh SPEC_FILE 도출이 \$BRANCH 의 slug 를 사용하지 않음 (\${BRANCH#...} 패턴 부재):" >&2
  grep -nE 'SPEC_FILE=' "$PR_PHASE_SH" >&2 || true
  exit 1
fi

echo "OK T4: SPEC.md 경로 정합 (slug-bearing 단일 컨벤션)"

# ──────────────────────────────────────────────────────────────────────────────
# T5. 모호성 die — 동일 input-id 매칭 브랜치가 2+ 일 때
# ──────────────────────────────────────────────────────────────────────────────
# 추가 feat 브랜치 생성: feat/${INPUT_ID}-another-slug
git checkout -q -b "feat/${INPUT_ID}-another-slug"
git checkout -q "$MAIN_BRANCH"

set +e
T5_OUT=$(bash "$LOOP_SH" status "$INPUT_ID" 2>&1)
T5_RC=$?
set -e

[[ $T5_RC -ne 0 ]] \
  || { echo "FAIL T5a: 모호 케이스에서 비-zero exit 미발생 (rc=$T5_RC)" >&2
       echo "$T5_OUT" >&2; exit 1; }
echo "$T5_OUT" | grep -qE '여러 feat 브랜치|모호|ambig' \
  || { echo "FAIL T5b: stderr 모호성 안내 부재" >&2
       echo "$T5_OUT" >&2; exit 1; }

echo "OK T5: 모호성 die"

echo ""
echo "ALL TESTS PASSED (T1–T5)"
