#!/usr/bin/env bash
# test-review-skill.sh
#
# autopilot:review 스킬 패키지의 정적 계약 검사 (SKILL.md·references 구조·스키마).
# 행위 계약은 test-review-harness.sh.
#
# 검증 대상 (수용 기준 매핑):
#  S1  필수 파일 존재 (SKILL.md·review.sh·agent-prompts.md·output-schema.json)
#  S2  SKILL.md frontmatter name: review + description 에 호출 양식
#  S3  공개 서브커맨드 3종 (run/status/list) 명시                              (공개표면)
#  S4  4 관점(lens) 독립 리뷰 + 중재 게이트 기술                                (AC2)
#  S5  적대 렌즈 정의 복제 금지 — personas.md 참조만                            (SPEC 제약)
#  S6  references 테이블에 review.sh·agent-prompts.md·output-schema.json
#  S7  의존성에 jq·bash 3.2+ 명시, 라우터 bash 3.2 호환(assoc array 미사용)
#  S8  output-schema.json 유효 JSON + 가산 필드(pipeline_verdict·acceptance_coverage·rework_brief)
#  S9  공유 스키마 재사용 핵심 필드 보존(findings·confidence_score·review_perspective·fingerprint 개념)
#  S10 verdict 어휘 approve|request_changes|unavailable 명시                     (AC1)
#  S11 신뢰도 80 게이트 + 4증거 요건 기술                                       (AC3)
#  S12 change-adoption 3분류 + 안전경계 must_adopt 고정 기술                    (AC6)
#  S13 agent-prompts: 4 lens 독립(서로 결론 못 봄) + 발견만 보고 brief
#  S14 불변식: 자기 상태·정의 파일 밖 경로 생성 금지

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$SCRIPT_DIR/.."
SKILL_MD="$SKILL_DIR/SKILL.md"
REVIEW_SH="$SKILL_DIR/references/review.sh"
AGENT_PROMPTS="$SKILL_DIR/references/agent-prompts.md"
SCHEMA="$SKILL_DIR/../../shared/review/references/output-schema.json"
PERSONAS="$SKILL_DIR/../../shared/spec/references/personas.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

# === S1: 필수 파일 ===
echo "=== S1: 필수 파일 존재 ==="
for f in "$SKILL_MD" "$REVIEW_SH" "$AGENT_PROMPTS" "$SCHEMA"; do
  [[ -f "$f" ]] || fail "S1: 부재 $f"
done
ok "S1"

# === S2: frontmatter ===
echo "=== S2: frontmatter ==="
grep -qE '^name: review$' "$SKILL_MD" || fail "S2: name: review 없음"
grep -qiE 'skill=\\?"review\\?"' "$SKILL_MD" || fail "S2: 호출 양식(Skill review) 없음"
ok "S2"

# === S3: 공개 서브커맨드 3종 ===
echo "=== S3: run/status/list ==="
for sub in run status list; do
  grep -qE "review $sub" "$SKILL_MD" || fail "S3: 서브커맨드 '$sub' 미기술"
done
ok "S3"

# === S4: 4 관점 + 중재 게이트 ===
echo "=== S4: 4 관점 + 중재 ==="
grep -qiE 'SPEC 수용기준|수용기준 준수' "$SKILL_MD" || fail "S4: lens① SPEC 준수 없음"
grep -qiE '정확성|보안' "$SKILL_MD" || fail "S4: lens② 정확성/보안 없음"
grep -qiE '회귀|역사' "$SKILL_MD" || fail "S4: lens③ 회귀/역사 없음"
grep -qiE '가이드라인|guideline' "$SKILL_MD" || fail "S4: lens④ 가이드라인 없음"
grep -qiE '중재|mediat|독립' "$SKILL_MD" || fail "S4: 중재 게이트/독립성 미기술"
ok "S4"

# === S5: personas 참조만 ===
echo "=== S5: personas 참조 (복제 금지) ==="
[[ -f "$PERSONAS" ]] || fail "S5: personas 단일 출처 부재(선행 SPEC 미적용): $PERSONAS"
grep -qE 'personas\.md' "$SKILL_MD" "$AGENT_PROMPTS" || fail "S5: personas.md 참조 없음"
# 렌즈 정의(세 페르소나 이름 동시 정의)를 복제하지 않았는지 — 카탈로그 헤더 문구 미복제
if grep -qE 'persona 카탈로그|적대 렌즈의 단일 출처' "$AGENT_PROMPTS" "$SKILL_MD"; then
  fail "S5: personas 카탈로그 정의를 복제함(참조만 해야 함)"
fi
ok "S5"

# === S6: references 테이블 ===
echo "=== S6: references 테이블 ==="
for r in review.sh agent-prompts.md output-schema.json; do
  grep -qE "$r" "$SKILL_MD" || fail "S6: references 에 $r 없음"
done
ok "S6"

# === S7: 의존성 + bash 3.2 ===
echo "=== S7: 의존성/bash 3.2 ==="
grep -qiE '\bjq\b' "$SKILL_MD" || fail "S7: jq 의존성 미기술"
grep -qE 'bash 3\.2' "$SKILL_MD" || fail "S7: bash 3.2+ 미기술"
# assoc array 미사용 (declare -A 금지)
if grep -qE 'declare -A|local -A' "$REVIEW_SH"; then
  fail "S7: review.sh 연관 배열 사용(bash 3.2 비호환)"
fi
ok "S7"

# === S8: 스키마 가산 필드 ===
echo "=== S8: output-schema 가산 필드 ==="
command -v jq >/dev/null 2>&1 || fail "S8: jq 필요"
jq -e . "$SCHEMA" >/dev/null 2>&1 || fail "S8: output-schema.json 유효 JSON 아님"
for fld in pipeline_verdict acceptance_coverage rework_brief; do
  jq -e ".properties.$fld" "$SCHEMA" >/dev/null 2>&1 || fail "S8: 스키마에 가산 필드 $fld 없음"
done
# pipeline_verdict enum
jq -e '.properties.pipeline_verdict.enum | index("approve") and index("request_changes") and index("unavailable")' \
  "$SCHEMA" >/dev/null 2>&1 || fail "S8: pipeline_verdict enum 3값 누락"
ok "S8"

# === S9: 공유 스키마 핵심 필드 보존 ===
echo "=== S9: 공유 스키마 재사용 ==="
for fld in findings reviewed_context skipped_duplicates resolved_threads context_requests; do
  jq -e ".properties.$fld" "$SCHEMA" >/dev/null 2>&1 || fail "S9: 공유 필드 $fld 미보존"
done
jq -e '.properties.findings.items.properties.confidence_score' "$SCHEMA" >/dev/null 2>&1 \
  || fail "S9: confidence_score 미보존"
# spec_compliance perspective 가산
jq -e '.properties.findings.items.properties.review_perspective.enum | index("spec_compliance")' \
  "$SCHEMA" >/dev/null 2>&1 || fail "S9: review_perspective 에 spec_compliance 가산 없음"
ok "S9"

# === S10: verdict 어휘 ===
echo "=== S10: verdict 어휘 ==="
for v in approve request_changes unavailable; do
  grep -qE "$v" "$SKILL_MD" || fail "S10: verdict '$v' 미기술"
done
ok "S10"

# === S11: 신뢰도 게이트 + 4증거 ===
echo "=== S11: 신뢰도/증거 ==="
grep -qE '80' "$SKILL_MD" || fail "S11: 신뢰도 80 미기술"
grep -qiE '증거|evidence' "$SKILL_MD" || fail "S11: 4증거 요건 미기술"
ok "S11"

# === S12: change-adoption 3분류 + 안전핀 ===
echo "=== S12: 채택 분류 ==="
grep -qE 'change-adoption' "$SKILL_MD" || fail "S12: change-adoption 참조 없음"
grep -qiE '안전 경계|안전경계|보안.*데이터' "$SKILL_MD" || fail "S12: 안전경계 고정 미기술"
ok "S12"

# === S13: agent-prompts 4 lens 독립 + 발견만 ===
echo "=== S13: agent-prompts ==="
grep -qiE '독립|서로.*결론|합의 투표 아님|보지 못' "$AGENT_PROMPTS" || fail "S13: lens 독립성 미기술"
grep -qiE '발견만|finding.*만|결정.*하지 않' "$AGENT_PROMPTS" || fail "S13: 발견만 보고 brief 없음"
ok "S13"

# === S14: 불변식 ===
echo "=== S14: 불변식 ==="
grep -qiE '자기 상태|자기 정의|밖.*경로|밖 경로' "$SKILL_MD" || fail "S14: 경로 생성 제한 불변식 없음"
ok "S14"

echo ""
echo "ALL SKILL TESTS PASSED"
