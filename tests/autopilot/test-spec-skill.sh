#!/usr/bin/env bash
# autopilot:spec 스킬 검증 실패 라우팅 검증 테스트
#
# SPEC.md (#65 작업) 수용 기준 1·2·4·5·6·7·8·9·10에 대응하는 assertion 집합.
# 본 테스트는 SKILL.md가 검증 실패 분기 라우팅을 명시적으로 기술하는지를 정적
# 검사로 확인한다. 실제 사용자 인터랙션·외부 도구 호출은 e2e 범위 밖.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/spec"
SKILL_MD="$SKILL_DIR/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$SKILL_MD" ]] || fail "SKILL.md 부재: $SKILL_MD"

# ---------------------------------------------------------------------------
echo "=== TEST 1: 검증 실패 라우팅 섹션 존재 ==="
# 수용 기준 1·9: 라우팅 옵션 (a)/(b)/(c)를 모두 명시
grep -qE '검증 실패.*(라우팅|분기|routing)' "$SKILL_MD" \
  || fail "SKILL.md에 '검증 실패 라우팅/분기' 섹션 명시 없음"
ok "검증 실패 라우팅/분기 섹션 헤더 존재"

# 라우팅 옵션 (a)/(b)/(c) 모두 명시 — 본문 흐름에서 (a) … (b) … (c) 패턴
for opt_label in '(a)' '(b)' '(c)'; do
  grep -qF "$opt_label" "$SKILL_MD" \
    || fail "SKILL.md에 라우팅 옵션 $opt_label 표기 없음"
done
ok "라우팅 옵션 (a)/(b)/(c) 모두 명시"

# 각 옵션 의미가 본문에 보이는지 키워드 검사 (수용 기준 1)
grep -qE '재입력|다시 입력|재시도' "$SKILL_MD" \
  || fail "옵션 (a) 의미(재입력·재시도) 명시 없음"
ok "옵션 (a) 의미(task-id 재입력·재시도) 명시"

grep -qE '사전 명확화 라운드' "$SKILL_MD" \
  || fail "옵션 (b) '사전 명확화 라운드' 키워드 없음"
ok "옵션 (b) '사전 명확화 라운드' 명시"

grep -qE '종료|abort|중단' "$SKILL_MD" \
  || fail "옵션 (c) 종료·abort 의미 명시 없음"
ok "옵션 (c) 종료 의미 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 2: 자연어 입력 감지 트리거 ==="
# 수용 기준 2: 자연어 문장으로 보이는 입력 = 검증 실패 트리거
grep -qE '자연어|natural language|문장으로 보이' "$SKILL_MD" \
  || fail "SKILL.md에 '자연어 입력' 검증 실패 트리거 명시 없음"
ok "자연어 입력 트리거 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 3: 사전 명확화 라운드 = step 4 메커니즘 앞당김 ==="
# 수용 기준 4·제약: 별도 phase 신설 없이 기존 step 4 메커니즘 재사용
grep -qE 'step 4|단계 4|명확화 라운드.*앞당김|앞당겨' "$SKILL_MD" \
  || fail "SKILL.md에 step 4 앞당김 명시 없음"
ok "step 4 메커니즘 앞당김 명시"

# 한 번에 한 AskUserQuestion 규칙 재사용 — 본문에 명시되어야 함
grep -qE '한 번에 한 (질문|AskUserQuestion)' "$SKILL_MD" \
  || fail "SKILL.md에 '한 번에 한 질문/AskUserQuestion' 규칙 명시 없음"
ok "'한 번에 한 질문' 규칙 명시"

# 수집할 정보: 문제·목표·범위·제약 (수용 기준 4)
for token in '문제' '목표' '범위' '제약'; do
  grep -q "$token" "$SKILL_MD" \
    || fail "사전 명확화 수집 항목 '$token' 명시 없음"
done
ok "수집 항목 (문제·목표·범위·제약) 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 4: 단일 task 경로 — 프로젝트 태스크 관련 지침 ==="
# 수용 기준 5: 단일 task 수렴 시 프로젝트의 태스크 관련 지침에 따라 task 생성
grep -qE '단일 task|단일 규모|단일로 수렴' "$SKILL_MD" \
  || fail "SKILL.md에 '단일 task 수렴' 분기 명시 없음"
ok "단일 task 수렴 분기 명시"

grep -qE '프로젝트의? 태스크 관련 지침|태스크 관련 지침' "$SKILL_MD" \
  || fail "SKILL.md에 '프로젝트 태스크 관련 지침' 참조 없음"
ok "프로젝트 태스크 관련 지침 참조 명시"

# 수용 기준 5: task 생성 후 step 2 (컨텍스트 탐색)부터 재개
grep -qE 'step 2|단계 2|컨텍스트 탐색.*재개|재개.*(step|단계) ?2' "$SKILL_MD" \
  || fail "SKILL.md에 'step 2부터 재개' 흐름 명시 없음"
ok "task-id 확보 후 step 2 재개 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 5: 마일스톤 경로 — PRD 스킬 라우팅 ==="
# 수용 기준 6: 마일스톤 규모 수렴 시 PRD invoke 여부를 AskUserQuestion으로
grep -qE '마일스톤 규모|마일스톤으로 수렴|마일스톤 분해' "$SKILL_MD" \
  || fail "SKILL.md에 '마일스톤 규모 수렴' 분기 명시 없음"
ok "마일스톤 규모 분기 명시"

grep -qE '(PRD|prd) ?(스킬|skill)' "$SKILL_MD" \
  || fail "SKILL.md에 PRD 스킬 라우팅 명시 없음"
ok "PRD 스킬 라우팅 명시"

# 수용 기준 6·8: PRD 호출은 AskUserQuestion 명시적 승인 후
grep -qE '명시적 승인|승인.*invoke|AskUserQuestion.*PRD|PRD.*AskUserQuestion' "$SKILL_MD" \
  || fail "SKILL.md에 PRD invoke 전 AskUserQuestion 승인 흐름 명시 없음"
ok "PRD invoke 전 AskUserQuestion 승인 명시"

# 위험: PRD 스킬은 milestone-id 인자 필요 — spec이 받아 넘김
grep -qE 'milestone-id|milestone ?id' "$SKILL_MD" \
  || fail "SKILL.md에 PRD 호출 시 milestone-id 인자 전달 명시 없음"
ok "milestone-id 인자 전달 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 6: 산출물 안전성 (취소·종료 시) ==="
# 수용 기준 7·10: 종료·취소 시 SPEC.md/task 어느 것도 남기지 않음
grep -qE '취소|cancel' "$SKILL_MD" \
  || fail "SKILL.md에 '취소' 시나리오 명시 없음"
ok "사전 명확화 라운드 취소 시나리오 명시"

grep -qE '산출물.*(없이|않고|남기지)|어떠한 산출물도|작성하지 않' "$SKILL_MD" \
  || fail "SKILL.md에 '산출물 미작성/미생성' 안전 종료 명시 없음"
ok "취소·종료 시 산출물 미생성 안전 종료 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 7: AskUserQuestion 기반 스킬 체인 규칙 ==="
# 수용 기준 8: "다음 단계: Skill(...)" 자유 텍스트 안내 대신 AskUserQuestion 확인
grep -qE 'AskUserQuestion' "$SKILL_MD" \
  || fail "SKILL.md에 AskUserQuestion 도구 참조 없음"
ok "AskUserQuestion 도구 참조 존재"

# 후속 스킬 호출은 항상 AskUserQuestion 확인 후 invoke 규칙
grep -qE '후속 스킬 호출.*AskUserQuestion|AskUserQuestion.*invoke|AskUserQuestion.*확인 후' "$SKILL_MD" \
  || fail "SKILL.md에 '후속 스킬 호출 = AskUserQuestion 확인 후' 규칙 명시 없음"
ok "AskUserQuestion 기반 스킬 체인 규칙 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 8: 기존 워크플로 보존 ==="
# 검증 실패 분기 외 기존 10단계 흐름은 그대로 유지되어야 함 (SPEC scope.exclude)
grep -qE '10[- ]?(단계|step) 워크플로' "$SKILL_MD" \
  || fail "SKILL.md에 10단계 워크플로 헤더 보존 없음"
ok "10단계 워크플로 헤더 보존"

for step_kw in '컨텍스트 탐색' '범위 분해 게이트' '명확화 라운드' '섹션별 SPEC' '자체 검토' '사용자 최종 검토'; do
  grep -q "$step_kw" "$SKILL_MD" \
    || fail "기존 step 키워드 '$step_kw' 보존 실패"
done
ok "기존 step 키워드 보존"

# WHAT/HOW 방어선 보존
grep -q 'WHAT/HOW' "$SKILL_MD" \
  || fail "WHAT/HOW 방어선 명시 보존 실패"
ok "WHAT/HOW 방어선 보존"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 9: agent-prompts.md 양식 파일 (subagent 역할 2종) ==="
# 이슈 #72 수용 기준 1·2: references/agent-prompts.md 존재 + 두 역할 헤더 + 각 양식 3섹션
AGENT_PROMPTS="$SKILL_DIR/references/agent-prompts.md"
[[ -f "$AGENT_PROMPTS" ]] \
  || fail "agent-prompts.md 부재: $AGENT_PROMPTS"
ok "references/agent-prompts.md 존재"

for role in 'spec-context-explorer' 'spec-self-reviewer'; do
  grep -qF "$role" "$AGENT_PROMPTS" \
    || fail "agent-prompts.md에 역할 헤더 '$role' 부재"
done
ok "두 역할 헤더(spec-context-explorer·spec-self-reviewer) 존재"

# 각 양식의 세 섹션 (언제·임무·응답) 키워드
for section_kw in '언제' '임무' '응답'; do
  cnt="$(grep -c "$section_kw" "$AGENT_PROMPTS" || true)"
  [[ "$cnt" -ge 2 ]] \
    || fail "양식 섹션 '$section_kw' 가 2회 이상(두 역할 각각) 등장하지 않음 (현재: $cnt)"
done
ok "각 양식의 세 섹션(언제·임무·응답) 양 역할 모두 존재"

# context-explorer 응답 5섹션: 관련 룰·관련 기존 SPEC·관련 코드 영역·컨벤션·권고
for resp_kw in '관련 룰' '관련 기존 SPEC' '관련 코드 영역' '컨벤션' '권고'; do
  grep -qF "$resp_kw" "$AGENT_PROMPTS" \
    || fail "context-explorer 응답 키워드 '$resp_kw' 부재"
done
ok "context-explorer 응답 5섹션 키워드 존재"

# self-reviewer 응답 3섹션: 5축 검토 결과·Critical·Important·Minor·판정
for resp_kw in '5축' 'Critical' 'Important' 'Minor' '판정'; do
  grep -qF "$resp_kw" "$AGENT_PROMPTS" \
    || fail "self-reviewer 응답 키워드 '$resp_kw' 부재"
done
ok "self-reviewer 응답 3섹션 키워드 존재"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 10: SKILL.md frontmatter allowed-tools에 Agent 포함 ==="
# 수용 기준 5: subagent dispatch 도구 허가.
# allowed-tools는 YAML inline (한 줄) 또는 block list (다음 줄 들여쓰기 `- Agent`) 두 형태 모두
# valid. frontmatter 안에서 두 형식 중 하나로 Agent 토큰이 나타나면 통과.
#   - block list 형식:  `^[[:space:]]+-[[:space:]]+Agent[[:space:]]*$`
#   - inline list 형식: `^allowed-tools:.*[[ ,]Agent([],[:space:]]|$)`
#     ('Agent' 앞은 공백·`[`·`,` 중 하나, 뒤는 `]`·`,`·공백·줄끝 중 하나.)
awk '/^---$/{c++; next} c==1' "$SKILL_MD" | \
  grep -qE '^[[:space:]]+-[[:space:]]+Agent[[:space:]]*$|^allowed-tools:.*[[ ,]Agent([],[:space:]]|$)' \
  || fail "SKILL.md frontmatter allowed-tools에 Agent 미포함"
ok "frontmatter allowed-tools에 Agent 포함"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 11: step 3·step 9 본문에 양식 참조·도입 휴리스틱 ==="
# 수용 기준 3·4: step 3(컨텍스트 탐색)·step 9(자체 검토) 본문이 양식 파일을 참조
ref_count=$(grep -cE 'references/agent-prompts\.md' "$SKILL_MD")
[[ "$ref_count" -ge 2 ]] \
  || fail "SKILL.md에 references/agent-prompts.md 참조가 2회 미만 (step 3·step 9 각각 필요)"
ok "agent-prompts.md 참조 2회 이상 (step 3·step 9 본문)"

# 역할명이 SKILL.md 본문에도 등장 (스킬 본문이 역할명을 적시)
for role in 'spec-context-explorer' 'spec-self-reviewer'; do
  grep -qF "$role" "$SKILL_MD" \
    || fail "SKILL.md 본문에 역할명 '$role' 부재"
done
ok "두 역할명 SKILL.md 본문 등장"

# 권장 도입 휴리스틱 — 본문에 '권장'·'휴리스틱' 또는 '트리거' 어구
grep -qE '권장 도입|도입 휴리스틱|권장 트리거|도입 트리거' "$SKILL_MD" \
  || fail "SKILL.md에 권장 도입 휴리스틱/트리거 어구 부재"
ok "권장 도입 휴리스틱 어구 존재"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 12: 모듈 구성 표·헌법 §11.6 인용·결정/합성 메인 책임 ==="
# 수용 기준 6: 모듈 구성 표에 agent-prompts.md 행 (테이블 라인 안에 파일명)
grep -qE '^\|.*agent-prompts\.md.*\|' "$SKILL_MD" \
  || fail "모듈 구성 표에 agent-prompts.md 행 부재"
ok "모듈 구성 표에 agent-prompts.md 행 존재"

# 수용 기준 7: 헌법 §11.6 또는 "이터 내 서브 도구 위임" 인용
grep -qE '§11\.6|이터 내 서브 도구 위임' "$SKILL_MD" \
  || fail "SKILL.md에 헌법 §11.6 또는 '이터 내 서브 도구 위임' 인용 부재"
ok "헌법 §11.6 / '이터 내 서브 도구 위임' 인용 존재"

# 수용 기준 7: 결정·합성 메인 책임 유지 문구
grep -qE '결정·합성.*메인|메인.*결정·합성|결정과 합성.*메인' "$SKILL_MD" \
  || fail "SKILL.md에 '결정·합성은 메인 책임' 문구 부재"
ok "'결정·합성 메인 책임' 문구 존재"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 13: SKILL.md step 5 — test 코드 변경 자동 판단 절차 명시 ==="
# AC1·AC2: 명확화 라운드 마지막에 task scope가 test 코드 변경(rename·cleanup·삭제·내용 수정 등)을
# 포함하는지 자동 판단하고, 포함 시 sweep 화이트리스트 후보 경로를 단발 yes/no로 확인.
TEMPLATE_MD="$SKILL_DIR/references/spec-template.md"
SELF_REVIEW_MD="$SKILL_DIR/references/self-review.md"

[[ -f "$TEMPLATE_MD" ]] || fail "spec-template.md 부재: $TEMPLATE_MD"
[[ -f "$SELF_REVIEW_MD" ]] || fail "self-review.md 부재: $SELF_REVIEW_MD"

# step 5 본문에 'test 코드 변경' (rename·cleanup·삭제·내용 수정 등) 자동 판단 어구
grep -qE 'test 코드 변경|테스트 코드 변경|test code change' "$SKILL_MD" \
  || fail "SKILL.md에 'test 코드 변경' 자동 판단 어구 없음"
ok "test 코드 변경 자동 판단 어구 존재"

# 단발 yes/no 확인 — AC2
grep -qE '단발 yes/no|단발 (예|aye)/no|단일 yes/no|단발 확인' "$SKILL_MD" \
  || fail "SKILL.md에 'test 변경 sweep 단발 yes/no 확인' 절차 없음"
ok "단발 yes/no 확인 절차 존재"

# 화이트리스트 후보 경로 추출 — AC2
grep -qE '화이트리스트 후보|sweep 화이트리스트|sweep 후보 경로|화이트리스트 경로 후보' "$SKILL_MD" \
  || fail "SKILL.md에 'sweep 화이트리스트 후보 경로 추출' 어구 없음"
ok "sweep 후보 경로 추출 어구 존재"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 14: SKILL.md step 8 — test_sweep_paths frontmatter 치환 룰 ==="
# AC3·AC4: yes 응답 시 frontmatter test_sweep_paths에 기록, no/판단 미발동 시 키 부재
grep -qE '\{\{test_sweep_paths\}\}|test_sweep_paths.*frontmatter|frontmatter.*test_sweep_paths' "$SKILL_MD" \
  || fail "SKILL.md step 8 치환 룰에 test_sweep_paths frontmatter 처리 명세 없음"
ok "step 8 치환 룰에 test_sweep_paths 명세 존재"

# AC4: test 변경 없을 때 키 부재 — SKILL.md에 명시
grep -qE 'test_sweep_paths.*(키|key).*(부재|생략|미추가|추가하지|없음)|키 부재|키 추가하지|키를 추가하지' "$SKILL_MD" \
  || fail "SKILL.md에 test 변경 없을 때 'test_sweep_paths 키 부재' 룰 명시 없음"
ok "test 변경 없을 때 frontmatter 키 부재 룰 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 15: spec-template.md — test_sweep_paths placeholder ==="
# AC3·AC4 지원: active frontmatter 영역에 placeholder 정의. 기존 commented 예시는 보존.
# active placeholder는 {{test_sweep_paths}} 형식 — step 8 치환 대상.
grep -qE '\{\{test_sweep_paths\}\}' "$TEMPLATE_MD" \
  || fail "spec-template.md active 영역에 {{test_sweep_paths}} placeholder 부재"
ok "spec-template.md에 {{test_sweep_paths}} active placeholder 존재"

# 기존 commented 예시 블록 보존 — # test_sweep_paths: 라인
grep -qE '^# test_sweep_paths:' "$TEMPLATE_MD" \
  || fail "spec-template.md commented '# test_sweep_paths:' 예시 블록 보존 실패"
ok "commented '# test_sweep_paths:' 예시 블록 보존"

# 기존 commented '# test_paths:' 예시 블록도 보존
grep -qE '^# test_paths:' "$TEMPLATE_MD" \
  || fail "spec-template.md commented '# test_paths:' 예시 블록 보존 실패"
ok "commented '# test_paths:' 예시 블록 보존"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 16: self-review.md — 5축 검사 항목에 test_sweep_paths 검사 추가 ==="
# AC5: scope에 test 코드 변경 포함 시 test_sweep_paths가 비어 있지 않다 검사
grep -qE 'test_sweep_paths' "$SELF_REVIEW_MD" \
  || fail "self-review.md에 'test_sweep_paths' 검사 항목 없음"
ok "self-review.md에 test_sweep_paths 검사 항목 존재"

# 검사 의미: scope에 test 코드 변경 포함 시 → 필드가 비어 있지 않다
grep -qE 'test 코드 변경|테스트 코드 변경' "$SELF_REVIEW_MD" \
  || fail "self-review.md에 'test 코드 변경' 트리거 어구 없음"
ok "self-review.md에 test 코드 변경 트리거 어구 존재"

grep -qE '비어 있지 않|채워|값이 있|empty' "$SELF_REVIEW_MD" \
  || fail "self-review.md에 'test_sweep_paths 필드가 비어 있지 않다' 의미 어구 없음"
ok "self-review.md에 필드 비어 있지 않음 의미 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== 모든 spec 검증 실패 라우팅 테스트 통과 ==="
