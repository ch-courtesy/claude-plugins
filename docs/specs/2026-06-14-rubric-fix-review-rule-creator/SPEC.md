---
scope:
  include:
    - plugins/project-init/skills/review-rule-creator/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# rubric-fix-review-rule-creator

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`plugins/project-init/skills/review-rule-creator` 스킬의 루브릭 지적 2건(S-README, T-KEYWORDS)을 해소한다.

- S-README: 스킬 폴더에 사람 대상 `README.md`를 신규 생성한다. 내용은 스킬 정체·언제 활성화되는지·호출 방법을 계약·포인터 수준으로 담되, `SKILL.md` 본문 내용을 복제하지 않는다.
- T-KEYWORDS: `SKILL.md` frontmatter의 `description` 필드에 사용자가 실제로 쓸 자연어 동의어·키워드를 보강한다. 트리거 매칭 표면을 넓히는 것이며, WHAT/WHEN 구조와 스킬 동작 기술은 불변이다.

## 목적 (왜)
토스 스킬 품질 루브릭(30항목) 평가에서 이 스킬이 S-README·T-KEYWORDS 항목 FAIL 판정을 받았다. README 부재로 사람이 스킬 용도를 코드 없이 파악하기 어렵고, description 키워드 부족으로 LLM 트리거 매칭 정확도가 낮다. 두 지적을 해소해 루브릭 품질 게이트를 통과하고, 스킬 발견 가능성과 트리거 정확도를 높인다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. **S-README 완료 조건**: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/review-rule-creator/SKILL.md` 재실행 시 S-README 항목이 `passed=true`로 출력된다.

2. **T-KEYWORDS 완료 조건**: rubric 모델 재평가 시 T-KEYWORDS 항목이 PASS 판정을 받는다(근거: `description`에 "리뷰 지침 생성", "코드 리뷰 규칙", "change adoption", "변경 반영", "PR 리뷰 원칙" 등 사용자가 실제로 입력할 자연어 키워드가 추가되어 트리거 매칭 표면이 충분히 넓어진다).

3. **불변식 조건**: 항상 스킬의 트리거 의미·동작·공개 계약이 보존된다. 기존 호출 방식, sub-룰 생성 절차, `rules/review/principles.md`·`rules/review/change-adoption.md` 페어 산출 계약, 확인 게이트 동작이 수정 전과 동일하게 유지된다.

## 범위
포함:
- `plugins/project-init/skills/review-rule-creator/SKILL.md`
- `plugins/project-init/skills/review-rule-creator/README.md` (신규 생성)
- `plugins/project-init/skills/review-rule-creator/references/**` (필요 시 참조)

비-목표 / 제외:
- 다른 스킬(`context-rule-creator`, `engineering-rule-creator` 등) 및 `plugins/` 하위 다른 경로
- `rules/**` (카테고리 지침 파일)
- 루브릭 자체(`skill-rubric` 플러그인·평가 기준) — 루브릭 verbatim 정책은 바꾸지 않는다
- 플러그인 메타 파일(`plugin.yaml`, `AGENTS.md` 등)
- S-NO-XML 등 이번 지적 범위 외 루브릭 항목 대응

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim — 스킬을 고치되 루브릭 자체는 수정하지 않는다.
- `SKILL.md`의 동작·공개 계약 의미 불변 — description 키워드 보강은 트리거 표면 확장에 한정하며, WHEN 구조·동작 기술을 바꾸지 않는다.
- no-code-duplication — `README.md`는 계약·포인터 수준으로 짧게 쓰고, `SKILL.md` 본문 내용(생성 절차, 규칙, 페어 이유 등)을 복제하지 않는다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/review-rule-creator/SKILL.md` 로 규칙 항목 PASS 확인.

## 위험
- **T-KEYWORDS 과확장 위험**: description에 키워드를 과도하게 추가하면 T-SCOPE 악화(다른 스킬과 트리거 충돌·오발동)가 발생할 수 있다 — description 보강은 이 스킬 고유 문맥(리뷰 지침 생성)에 한정하고 범용 키워드는 추가하지 않는다.
- **README 중복 위험**: README가 `SKILL.md`의 절차·규칙·페어 이유를 그대로 옮기면 단일 출처 원칙이 깨진다 — README는 "무엇·언제·어떻게 호출" 포인터에만 집중하고 내용 복제를 금한다.
