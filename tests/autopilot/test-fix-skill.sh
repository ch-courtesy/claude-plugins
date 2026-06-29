#!/usr/bin/env bash
# 신규 fix 스킬 정적 계약 검증 (#444).
#
# 계약: task-backend 계열 버그 작성자 fix 스킬.
#  - fix = 정적 분석 버그 작성자. 증상·실패 신호에서 본문(진단 섹션 포함)을 자율 생성해
#    등록 프리미티브 create-task 로 등록을 위임한다(파일 미생성, 본문=SoT).
#  - fix 는 플러그인 자기완결 — 외부 스킬 참조나 rules/ 를 doc-link 하지 않고
#    방법론을 자체 소유한다(feature 와 동일 패턴). (구 spec/repair 미의존 — 둘 다 제거됨.)
#  - workflow-task 드레인자가 버그·실패 신호를 감지해 중앙에서 fix 를 호출한다(틱 기반 흡수).
# (SKILL.md 는 LLM 지침 산문이므로 핵심 계약 어구를 정적으로 검증한다.)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILLS="$REPO_ROOT/plugins/autopilot/skills"
FIX="$SKILLS/fix"
CREATE="$SKILLS/create-task"
WT="$SKILLS/workflow-task"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

# === S1: fix 스킬 패키지 구조 (자체 소유 참조) ===
echo "=== S1: fix 스킬 구조 + 자체 소유 참조 ==="
for f in SKILL.md \
         README.md \
         references/diagnosis.md \
         references/task-body-template.md \
         references/self-review.md \
         references/agent-prompts.md; do
  [[ -f "$FIX/$f" ]] || fail "S1: fix/$f 부재"
done
ok "fix SKILL.md + README + 4 참조 존재"

# === S2: fix frontmatter name ===
echo "=== S2: fix frontmatter name: fix ==="
grep -qE '^name:[[:space:]]*fix[[:space:]]*$' "$FIX/SKILL.md" \
  || fail "S2: fix/SKILL.md frontmatter에 'name: fix' 없음"
ok "name: fix"

# === S3: fix = 정적 분석 진단 → create-task 등록 위임 ===
echo "=== S3: fix 정적 분석 → create-task 등록 위임 ==="
grep -q '정적 분석' "$FIX/SKILL.md" || fail "S3: fix가 정적 분석 진단을 기술하지 않음"
grep -q 'create-task' "$FIX/SKILL.md" \
  || fail "S3: fix가 등록을 create-task에 위임하지 않음"
ok "fix: 정적 분석 + create-task 등록 위임"

# === S4: fix 는 작성만 — write 동사·파일 미생성 ===
echo "=== S4: fix 작성만(파일 미생성, write 동사 직접 호출 안 함) ==="
grep -qE 'set_body|set_status|create_task' "$FIX/SKILL.md" \
  && grep -qE '직접 호출(하지|을 하지) ?(않|안)' "$FIX/SKILL.md" \
  || true
grep -q '작성만' "$FIX/SKILL.md" \
  || fail "S4: fix가 '작성만' 경계를 명시하지 않음"
ok "fix: 작성만 경계 명시"

# === S5: fix 플러그인 자기완결 — spec/repair doc-link 부재 ===
echo "=== S5: fix 자기완결(spec/repair 참조 doc-link 부재) ==="
if grep -rqE '\.\./(spec|repair)/' "$FIX/"; then
  fail "S5: fix가 spec/repair 참조를 doc-link함(자기완결 위반)"
fi
ok "fix: spec/repair doc-link 부재"

# === S6: fix 참조가 자체 소유 표기 (타 스킬 소유 표기 잔존 금지) ===
echo "=== S6: fix 참조 자체 소유 표기 ==="
if grep -rqE 'repair 고유|create-task 자체 소유|feature 자체 소유' "$FIX/references/"; then
  fail "S6: fix 참조에 타 스킬 소유 표기 잔존(소유 갱신 누락)"
fi
ok "fix 참조: 타 스킬 소유 표기 부재"

# === S7: fix task-body-template 에 진단 섹션 + 완료 조건 ===
echo "=== S7: fix 본문 템플릿 진단 섹션 + 완료 조건 ==="
grep -qE '^##[[:space:]]*진단' "$FIX/references/task-body-template.md" \
  || fail "S7: fix task-body-template에 '## 진단' 섹션 없음"
grep -qE '^##[[:space:]]*완료 조건' "$FIX/references/task-body-template.md" \
  || fail "S7: fix task-body-template에 '## 완료 조건' 섹션 없음"
ok "fix 본문 템플릿: 진단 섹션 + 완료 조건"

# === S8: fix 진단은 정적 한정 + 가설 프레이밍 + 마커 ===
echo "=== S8: fix diagnosis 정적 한정 + 마커 ==="
grep -q '정적 분석' "$FIX/references/diagnosis.md" \
  || fail "S8: fix diagnosis가 정적 분석 한정을 기술하지 않음"
grep -qF '[NEEDS CLARIFICATION' "$FIX/references/diagnosis.md" \
  || fail "S8: fix diagnosis에 [NEEDS CLARIFICATION 마커 규칙 없음"
ok "fix diagnosis: 정적 한정 + 마커"

# === S9: fix 상태 전이 — 완성→backlog / 미해결→in_design ===
echo "=== S9: fix 상태 전이 backlog/in_design ==="
grep -q 'backlog' "$FIX/SKILL.md" || fail "S9: fix에 backlog 전이 언급 없음"
grep -q 'in_design' "$FIX/SKILL.md" || fail "S9: fix에 in_design 전이 언급 없음"
ok "fix: backlog/in_design 전이 명시"

# === S10: task-body-template — DoD-요구 테스트 경로를 scope.include에 포함 규칙(#483) ===
# loop scope 게이트(diff_vs_scope)는 scope 밖 파일 작성을 halt 하므로, 완료 조건이
# 회귀 가드 테스트를 요구하면 그 테스트 경로가 scope.include 안에 있어야 RED 테스트를 쓸 수 있다.
echo "=== S10: fix 본문 템플릿 — DoD-요구 테스트 경로 scope.include 포함 규칙 ==="
grep -q '회귀 가드' "$FIX/references/task-body-template.md" \
  || fail "S10: fix task-body-template에 '회귀 가드' 테스트 경로 규칙 없음"
grep -qE '테스트.*scope\.include|scope\.include.*테스트' "$FIX/references/task-body-template.md" \
  || fail "S10: fix task-body-template에 테스트 경로의 scope.include 포함 규칙(한 줄) 없음"
ok "fix task-body-template: DoD-요구 테스트 경로 scope.include 포함 규칙"

# === S10b: self-review 축6 — DoD-요구 테스트 경로 점검 항목(#483) ===
echo "=== S10b: fix self-review 축6 — DoD-요구 테스트 경로 점검 ==="
grep -qE '테스트.*scope\.include|scope\.include.*테스트' "$FIX/references/self-review.md" \
  || fail "S10b: fix self-review 축6에 테스트 경로 scope.include 점검 항목(한 줄) 없음"
ok "fix self-review: DoD-요구 테스트 경로 점검 항목"

# === S10c: fix task-body-template — test_sweep_paths 동시 선언 규칙(#509) ===
# scope.include에 기존 테스트 파일이 있으면 test_sweep_paths에도 선언해야 loop의
# 테스트 약화 게이트(HALT)를 통과할 수 있다.
echo "=== S10c: fix 본문 템플릿 — test_sweep_paths 동시 선언 규칙 ==="
grep -q 'test_sweep_paths' "$FIX/references/task-body-template.md" \
  || fail "S10c: fix task-body-template에 test_sweep_paths 동시 선언 규칙 없음"
ok "fix task-body-template: test_sweep_paths 동시 선언 규칙"

# === S10d: fix self-review 축6 — test_sweep_paths 점검 항목(#509) ===
echo "=== S10d: fix self-review 축6 — test_sweep_paths 점검 항목 ==="
grep -q 'test_sweep_paths' "$FIX/references/self-review.md" \
  || fail "S10d: fix self-review 축6에 test_sweep_paths 점검 항목 없음"
ok "fix self-review: test_sweep_paths 점검 항목"

# === S11: create-task 가 fix 를 작성자로 인지(짝 정합) ===
echo "=== S11: create-task fix 짝 정합 ==="
grep -q 'fix' "$CREATE/SKILL.md" \
  || fail "S11: create-task가 fix를 작성자로 인지하지 않음"
ok "create-task: fix 작성자 인지"

# === S12: workflow-task 드레인자 중앙 fix 호출 + failed_ids ===
echo "=== S12: workflow-task 드레인자 중앙 fix 호출 ==="
grep -q 'fix' "$WT/SKILL.md" \
  || fail "S12: workflow-task SKILL.md가 드레인자 중앙 fix 호출을 기술하지 않음"
grep -q 'failed_ids' "$WT/references/workflow-task.sh" \
  || fail "S12: workflow-task.sh가 failed_ids를 노출하지 않음"
ok "workflow-task: 드레인자 중앙 fix + failed_ids"

echo ""
echo "=== 모든 #444 fix 스킬 계약 테스트 통과 ==="
