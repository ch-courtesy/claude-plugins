---
scope:
  include:
    - plugins/project-init/skills/engineering-rule-creator/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# rubric-fix-engineering-rule-creator

## 무엇을 만들 것인가

`plugins/project-init/skills/engineering-rule-creator/` 폴더 안에서 다음 네 가지 산출물을 수정·추가한다.

- `SKILL.md`: description 키워드 보강 및 본문의 `{{...}}` 리터럴 placeholder 잔재 제거.
- `README.md`: 스킬 폴더에 신규 추가. 무엇인지·언제 쓰는지·어떻게 호출하는지를 계약·포인터 수준으로 기술하고 SKILL.md 내용을 복제하지 않는다.
- `references/` 하위 스크립트: 파싱·치환·명령열 등 실수하기 쉬운 결정적 작업을 스크립트로 고정하고, SKILL.md 본문은 그 스크립트를 참조하도록 변경.

구현 방법·라이브러리·파일 내부 코드는 제약 섹션에 위임하고 여기서는 기술하지 않는다.

## 목적 (왜)

루브릭 품질 게이트(S-README, R-PLACEHOLDER, T-KEYWORDS, R-SCRIPTIFY) 통과를 위해 스킬 폴더의 사람 대상 가독성과 에이전트 신뢰성을 높인다. description 키워드 보강으로 트리거 매칭 정확도를 개선하고, placeholder 잔재 제거로 템플릿 처리 오류를 차단한다. 결정적 작업을 references/ 스크립트로 고정함으로써 에이전트 즉흥 재현을 제거하고 단일 출처를 유지한다.

## 완료 조건

**S-README**
항상, `plugins/project-init/skills/engineering-rule-creator/README.md` 파일이 존재하고, 계약·포인터 수준(SKILL.md 내용 비복제)으로 스킬의 무엇·언제·호출 방법을 기술할 때, `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/engineering-rule-creator/SKILL.md` 재실행 시 S-README 항목 passed=true.

**R-PLACEHOLDER**
항상, SKILL.md 본문에 `{{...}}` 형태의 리터럴 placeholder 잔재가 없을 때, `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/engineering-rule-creator/SKILL.md` 재실행 시 R-PLACEHOLDER 항목 passed=true.

**T-KEYWORDS**
rubric 모델 재평가 시 T-KEYWORDS 항목 PASS(근거: description에 사용자가 실제로 쓸 자연어 동의어·키워드가 보강되어 트리거 매칭 표면이 넓어졌으되, 스킬 WHAT/WHEN 구조와 동작은 불변).

**R-SCRIPTIFY**
rubric 모델 재평가 시 R-SCRIPTIFY 항목 PASS(근거: 파싱·치환·정해진 명령열 등 실수하기 쉬운 결정적 작업이 `references/` 아래 스크립트로 고정되고 SKILL.md 본문은 해당 스크립트를 호출·참조하도록 변경되어 에이전트 즉흥 재현이 제거됨).

**불변식**
항상, 수정 후 스킬의 트리거 의미·동작·공개 계약이 보존될 때, 기존 호출·서브커맨드·절차 의미가 변경 전후로 동일하다.

## 범위

포함:
- `plugins/project-init/skills/engineering-rule-creator/SKILL.md`
- `plugins/project-init/skills/engineering-rule-creator/README.md` (신규)
- `plugins/project-init/skills/engineering-rule-creator/references/**` (신규 스크립트)

비-목표 / 제외:
- 다른 스킬 폴더(`context-rule-creator`, `workflow-rule-creator` 등)는 건드리지 않는다.
- `rules/**` 하위 파일은 이 SPEC의 대상이 아니다.
- 플러그인 메타(plugin.yaml 등)는 수정하지 않는다.
- 루브릭 자체(`skill-rubric` 스킬·평가 기준)는 완화하거나 변경하지 않는다.
- S-NO-XML 등 다른 루브릭 verbatim 정책은 바꾸지 않는다.
- `templates/` 하위 파일은 이 SPEC의 직접 수정 대상이 아니다(SKILL.md 참조 방식 변경에 한해 간접 영향 허용).

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약

- 루브릭은 verbatim — 스킬을 고치되 루브릭 평가 기준·스크립트는 수정하지 않는다.
- SKILL.md의 동작·공개 계약 의미 불변 — description 키워드 보강·placeholder 제거·스크립트 참조 추가는 허용하나, 절차 의미·호출 방식·생성 출력물 계약을 바꾸지 않는다.
- no-code-duplication — README와 references/ 분리 시 단일 출처 유지; SKILL.md에 있는 내용을 README에 그대로 복사하지 않는다.
- R-SCRIPTIFY 스크립트는 최소 범위로 — 결정적 작업만 스크립트화하고, 이미 서술로 충분한 단순 흐름은 스크립트화하지 않는다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/engineering-rule-creator/SKILL.md` 로 규칙 항목(S-README, R-PLACEHOLDER) PASS를 확인한다.

## 위험

- **T-KEYWORDS 과확장**: 키워드 보강이 트리거 범위를 지나치게 넓혀 T-SCOPE(과좁음/과넓음) 항목을 악화시킬 수 있다. 실제 사용자 표현에 근거한 동의어만 추가하고, 의미가 다른 스킬과 혼동되는 표현은 배제한다.
- **R-SCRIPTIFY 과설계**: 스크립트화가 스킬을 과도하게 설계할 위험이 있다. 최소 스크립트(파싱·치환 등 결정적 작업만)로 한정하고, 단순 흐름 제어는 서술로 유지한다.
- **R-PLACEHOLDER 치환 후 의미 손실**: `{{...}}` 제거 시 해당 placeholder가 설명하던 치환 메커니즘이 누락될 수 있다. 제거 후 동등한 서술("name 필드" 형태) 또는 코드펜스 예시로 의미를 보존한다.
- **README 중복**: README 추가 시 SKILL.md 내용을 그대로 옮기면 단일 출처 원칙을 위반한다. README는 계약·포인터 수준(무엇·언제·호출 방법)으로 제한하고 본문 상세는 SKILL.md를 참조하도록 포인터만 둔다.
