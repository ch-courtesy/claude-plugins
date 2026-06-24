#!/usr/bin/env bash
# 작성/등록 분리(#445) 정적 계약 검증.
#
# 계약: 스킬 계층을 작성(feature)과 등록(create-task)으로 분리한다.
#  - feature = 인터뷰 작성자. create-task의 경량 참조 4종을 포팅(이동)해 소유하고,
#    인터뷰로 본문을 생성한 뒤 create-task로 등록을 위임한다.
#  - create-task = 등록 프리미티브. 외부 작성 본문을 받아 등록 + #442 상태 전이를
#    소유하고, 본문 갱신은 #447 set_body에 위임한다. 인터뷰/작성 로직을 보유하지 않는다.
#  - using-autopilot = 기능 의도를 feature로 라우팅(버그 경로는 create-task 현행 유지).
# (SKILL.md는 LLM 지침 산문이므로 핵심 계약 어구를 정적으로 검증한다.)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILLS="$REPO_ROOT/plugins/autopilot/skills"
FEATURE="$SKILLS/feature"
CREATE="$SKILLS/create-task"
USING="$SKILLS/using-autopilot/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

# === S1: feature 스킬 패키지 구조 (참조 4종 포팅) ===
echo "=== S1: feature 스킬 구조 + 경량 참조 포팅 ==="
for f in SKILL.md \
         references/clarification.md \
         references/decomposition-gate.md \
         references/self-review.md \
         references/task-body-template.md; do
  [[ -f "$FEATURE/$f" ]] || fail "S1: feature/$f 부재"
done
ok "feature SKILL.md + 4 참조 존재"

# === S2: feature frontmatter name + 작성자 역할 ===
echo "=== S2: feature frontmatter name: feature ==="
grep -qE '^name:[[:space:]]*feature[[:space:]]*$' "$FEATURE/SKILL.md" \
  || fail "S2: feature/SKILL.md frontmatter에 'name: feature' 없음"
ok "name: feature"

# === S3: feature는 인터뷰로 본문 생성 → create-task로 등록 위임 ===
echo "=== S3: feature 인터뷰 → create-task 등록 위임 ==="
grep -q '인터뷰' "$FEATURE/SKILL.md" || fail "S3: feature가 인터뷰를 기술하지 않음"
grep -q 'create-task' "$FEATURE/SKILL.md" \
  || fail "S3: feature가 등록을 create-task에 위임하지 않음"
ok "feature: 인터뷰 + create-task 등록 위임"

# === S4: create-task = 등록 프리미티브 — 작성 로직 미보유 ===
echo "=== S4: create-task 작성 참조 미보유(이동됨) ==="
for f in clarification.md decomposition-gate.md self-review.md task-body-template.md; do
  [[ -f "$CREATE/references/$f" ]] && fail "S4: create-task가 작성 참조 $f 를 아직 보유(미이동)"
done
ok "create-task references에 작성 참조 4종 부재(feature로 이동)"

echo "=== S5: create-task SKILL.md에 명확화 인터뷰 작성 단계 부재 ==="
grep -q '명확화 인터뷰' "$CREATE/SKILL.md" \
  && fail "S5: create-task가 아직 '명확화 인터뷰' 작성 로직을 기술(프리미티브 위반)"
ok "create-task: 명확화 인터뷰 작성 단계 부재"

# === S6: create-task가 set_body(#447)를 노출/위임 ===
echo "=== S6: create-task set_body 위임 ==="
grep -q 'set_body' "$CREATE/SKILL.md" \
  || fail "S6: create-task가 본문 갱신을 set_body로 위임하지 않음"
ok "create-task: set_body 위임 명시"

# === S7: create-task가 #442 전이를 소유(회귀 가드와 정합) ===
echo "=== S7: create-task #442 전이 소유 ==="
grep -qF '[NEEDS CLARIFICATION' "$CREATE/SKILL.md" \
  || fail "S7: create-task가 [NEEDS CLARIFICATION 마커 전이 기준을 보유하지 않음"
grep -qE '없으면.*backlog' "$CREATE/SKILL.md" \
  || fail "S7: create-task에 '마커 없으면 backlog' 분기 없음"
ok "create-task: #442 전이 소유"

# === S8: using-autopilot이 기능 의도를 feature로 라우팅 ===
echo "=== S8: using-autopilot 기능 의도 → feature 라우팅 ==="
[[ -f "$USING" ]] || fail "S8: using-autopilot SKILL.md 부재"
grep -q 'feature' "$USING" \
  || fail "S8: using-autopilot이 feature 라우팅을 기술하지 않음"
ok "using-autopilot: feature 라우팅 명시"

# === S9: feature 참조 헤더가 feature 소유로 갱신 ===
echo "=== S9: 포팅된 참조가 create-task 소유 표기를 남기지 않음 ==="
if grep -rq 'create-task 자체 소유' "$FEATURE/references/"; then
  fail "S9: feature 참조에 'create-task 자체 소유' 표기 잔존(소유 갱신 누락)"
fi
ok "feature 참조: 소유 표기 갱신"

# === S10: task-body-template — DoD-요구 테스트 경로를 scope.include에 포함 규칙(#483) ===
# loop scope 게이트(diff_vs_scope)는 scope 밖 파일 작성을 halt 하므로, 완료 조건이
# 회귀 테스트를 요구하면 그 테스트 경로가 scope.include 안에 있어야 RED 테스트를 쓸 수 있다.
echo "=== S10: feature 본문 템플릿 — DoD-요구 테스트 경로 scope.include 포함 규칙 ==="
grep -q '회귀 가드' "$FEATURE/references/task-body-template.md" \
  || fail "S10: feature task-body-template에 '회귀 가드' 테스트 경로 규칙 없음"
grep -qE '테스트.*scope\.include|scope\.include.*테스트' "$FEATURE/references/task-body-template.md" \
  || fail "S10: feature task-body-template에 테스트 경로의 scope.include 포함 규칙(한 줄) 없음"
ok "feature task-body-template: DoD-요구 테스트 경로 scope.include 포함 규칙"

# === S11: self-review 축6 — DoD-요구 테스트 경로 점검 항목(#483) ===
echo "=== S11: feature self-review 축6 — DoD-요구 테스트 경로 점검 ==="
grep -qE '테스트.*scope\.include|scope\.include.*테스트' "$FEATURE/references/self-review.md" \
  || fail "S11: feature self-review 축6에 테스트 경로 scope.include 점검 항목(한 줄) 없음"
ok "feature self-review: DoD-요구 테스트 경로 점검 항목"

echo ""
echo "=== 모든 #445 작성/등록 분리 계약 테스트 통과 ==="
