#!/usr/bin/env bash
# in_design 인터뷰 재개(resume) 경로 — 정적 계약 검증 (#443)
#
# 계약: 작성/등록 분리(#445)를 깨지 않고 in_design(미완성) 태스크를 대화형으로 완성한다.
#  - feature = 인터뷰 작성자에 재개 경로를 둔다: 기존 in_design 태스크의 본문과 남은
#    [NEEDS CLARIFICATION] 마커를 get_body(read-only)로 불러와 인터뷰로 부족분을 채우고,
#    완성 본문을 create-task 로 위임한다(작성만 — write 동사는 create-task 소유).
#  - create-task = 재개/갱신 분기를 둔다: 기존 task-id 를 받으면 신규 create_task 대신
#    set_body(#447)로 본문을 교체하고, 마커 재평가로 마커 0 이면 in_design→backlog 전이,
#    잔존이면 in_design 유지(#442 전이 소유).
# (SKILL.md 는 LLM 지침 산문이므로 핵심 계약 어구를 정적으로 검증한다.)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILLS="$REPO_ROOT/plugins/autopilot/skills"
FEATURE="$SKILLS/feature/SKILL.md"
CREATE="$SKILLS/create-task/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$FEATURE" ]] || fail "feature/SKILL.md 부재"
[[ -f "$CREATE"  ]] || fail "create-task/SKILL.md 부재"

# === R1: feature 재개 모드 기술 ===
echo "=== R1: feature 재개(resume) 모드 ==="
grep -q '재개' "$FEATURE" \
  || fail "R1: feature 가 재개(resume) 경로를 기술하지 않음"
grep -q 'resume' "$FEATURE" \
  || fail "R1: feature 에 resume 호출 규약(예: resume <task-id>)이 없음"
grep -q 'in_design' "$FEATURE" \
  || fail "R1: feature 재개 모드가 in_design 태스크 대상을 명시하지 않음"
ok "feature: 재개 모드 + resume 규약 + in_design 대상"

# === R2: feature 가 get_body(read)로 기존 본문/마커를 불러옴 ===
echo "=== R2: feature get_body 로 기존 본문 로드 ==="
grep -q 'get_body' "$FEATURE" \
  || fail "R2: feature 가 get_body 로 기존 본문을 불러오지 않음"
grep -qF '[NEEDS CLARIFICATION' "$FEATURE" \
  || fail "R2: feature 가 [NEEDS CLARIFICATION 마커(부족분)를 인터뷰 대상으로 삼지 않음"
ok "feature: get_body + [NEEDS CLARIFICATION 마커 채움"

# === R3: feature allowed-tools 에 get_body(read) 허용 ===
echo "=== R3: feature allowed-tools get_body ==="
grep -qE 'adapter\.sh:get_body' "$FEATURE" \
  || fail "R3: feature frontmatter allowed-tools 에 adapter.sh:get_body 허용 없음"
ok "feature: allowed-tools get_body 허용"

# === R4: feature 가 완성 본문을 create-task 재개로 위임 ===
echo "=== R4: feature → create-task 재개 위임 ==="
grep -qE 'create-task.*resume|resume.*create-task' "$FEATURE" \
  || fail "R4: feature 가 완성 본문을 create-task 재개 경로로 위임하지 않음"
ok "feature: create-task 재개 위임"

# === R5: create-task 재개/갱신 분기 — set_body 로 기존 본문 교체 ===
echo "=== R5: create-task 재개/갱신 분기 ==="
grep -q '재개' "$CREATE" \
  || fail "R5: create-task 가 재개/갱신 분기를 기술하지 않음"
grep -qE 'set_body.*task-id|기존 task-id|task-id.*set_body' "$CREATE" \
  || fail "R5: create-task 재개 분기가 set_body 로 기존 태스크 본문을 교체하지 않음"
ok "create-task: 재개 분기 set_body 본문 교체"

# === R6: create-task 재개 완료 시 in_design→backlog 전이 ===
echo "=== R6: create-task 재개 완료 시 backlog 전이 ==="
grep -qE 'in_design.*backlog|backlog.*전이' "$CREATE" \
  || fail "R6: create-task 재개 완료(마커 0) 시 in_design→backlog 전이가 없음"
ok "create-task: 재개 완료 in_design→backlog 전이"

# === R7: create-task 재개 분기가 task-id 를 get_task 로 해석해 제목 충돌 방지 (#461 버그1) ===
echo "=== R7: create-task 재개 신호 task-id 유효성 가드 ==="
grep -q 'get_task' "$CREATE" \
  || fail "R7: create-task 재개 분기가 get_task 로 task-id 유효성을 확인하지 않음"
grep -qE '신규 등록' "$CREATE" \
  || fail "R7: create-task 가 해석 실패한 task-id(=자연어 제목)를 신규 등록으로 처리하는 가드를 명시하지 않음"
ok "create-task: 재개 신호 task-id get_task 해석 + 미해석시 신규 등록"

# === R8: create-task 재개 진입 시 in_design 검증 — 비-in_design 거부 (#461 버그2) ===
echo "=== R8: create-task 재개 in_design 검증 가드 ==="
grep -qE 'in_design 이 아니면|in_design이 아니면|비-in_design|in_design 아니면' "$CREATE" \
  || fail "R8: create-task 재개 진입 시 status 가 in_design 이 아니면 거부하는 가드가 없음"
grep -qE '거부|중단' "$CREATE" \
  || fail "R8: create-task 재개가 비-in_design 태스크를 거부/중단하지 않음(종단·진행 태스크 훼손 위험)"
ok "create-task: 재개 진입 in_design 검증 + 비-in_design 거부"

# === R9: feature 참조 — test_sweep_paths 동시 선언 규칙(#509) ===
# 재개 경로도 동일 참조를 사용하므로 test_sweep_paths 규칙 존재를 확인한다.
echo "=== R9: feature 참조 — test_sweep_paths 동시 선언 규칙 ==="
SHARED_REFS="$REPO_ROOT/plugins/autopilot/references"
grep -q 'test_sweep_paths' "$SHARED_REFS/task-body-template.md" \
  || fail "R9: feature task-body-template에 test_sweep_paths 동시 선언 규칙 없음"
grep -q 'test_sweep_paths' "$SHARED_REFS/self-review.md" \
  || fail "R9: feature self-review에 test_sweep_paths 점검 항목 없음"
ok "feature 참조: test_sweep_paths 동시 선언 규칙 존재"

echo ""
echo "=== 모든 #443/#461 in_design 재개 경로 계약 테스트 통과 ==="
