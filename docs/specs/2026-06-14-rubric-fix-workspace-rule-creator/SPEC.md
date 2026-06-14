---
scope:
  include:
    - plugins/project-init/skills/workspace-rule-creator/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# rubric-fix-workspace-rule-creator

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`plugins/project-init/skills/workspace-rule-creator/` 스킬 폴더를 루브릭 지적(S-README, R-PLACEHOLDER, T-KEYWORDS, R-SCRIPTIFY) 4항목이 모두 해소된 상태로 갱신한다. 구체적으로:
- 스킬 폴더에 `README.md` 파일이 존재(계약·포인터 수준, SKILL.md 본문 복제 금지)
- SKILL.md 본문 내 `{{...}}` 리터럴 placeholder 잔재 제거(템플릿 치환 메커니즘은 서술 또는 코드펜스 예시로만 표현)
- description에 사용자 자연어 동의어·키워드 보강(WHAT/WHEN 의미·동작은 불변)
- 반복 가능한 결정적 작업(파싱·치환·정규화 로직)을 `references/` 아래 스크립트로 고정하고, SKILL.md 본문은 그 스크립트를 호출·참조하도록 변경

## 목적 (왜)
루브릭 30항목 품질 게이트를 통과하기 위해 현재 지적된 4개 항목을 해소한다. README 추가로 사람 독자가 스킬의 목적·호출 조건을 신속히 파악할 수 있고, placeholder 잔재 제거와 스크립트화로 에이전트가 즉흥 재현 없이 스크립트를 그대로 실행하여 치환 오류를 줄인다. 키워드 보강은 트리거 매칭 정확도를 높여 의도한 상황에서 스킬이 올바르게 활성화되게 한다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

항상 아래 조건이 모두 충족될 때 완료로 본다.

1. **S-README**: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/workspace-rule-creator/SKILL.md` 재실행 시 `S-README` 항목 `passed=true`.

2. **R-PLACEHOLDER**: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/workspace-rule-creator/SKILL.md` 재실행 시 `R-PLACEHOLDER` 항목 `passed=true`.

3. **T-KEYWORDS**: rubric 모델 재평가 시 `T-KEYWORDS` 항목 PASS (근거: description에 "작업공간 위생", "임시 파일", "빌드 산출물", "스크래치", "temp", "clean", "workspace hygiene" 등 사용자 자연어 동의어가 추가되고, 기존 트리거 의미·WHAT/WHEN 구조는 보존됨).

4. **R-SCRIPTIFY**: rubric 모델 재평가 시 `R-SCRIPTIFY` 항목 PASS (근거: 파싱·치환·경로 정규화 등 결정적 작업이 `plugins/project-init/skills/workspace-rule-creator/references/` 아래 스크립트 파일로 분리되고, SKILL.md 본문은 해당 스크립트를 호출·참조하는 방식으로 작성되어 에이전트 즉흥 재현 로직이 없음).

5. **불변식**: 스킬의 트리거 의미·동작·공개 계약이 보존된다 — 기존 호출 방식, 서브커맨드, 생성 절차(5단계: 열거→파싱→선택→입력→기록) 의미가 수정 전후 동일하다.

## 범위
포함:
- `plugins/project-init/skills/workspace-rule-creator/SKILL.md`
- `plugins/project-init/skills/workspace-rule-creator/references/**` (R-SCRIPTIFY 신규 스크립트 포함)
- `plugins/project-init/skills/workspace-rule-creator/README.md` (S-README 신규 파일)

비-목표 / 제외:
- 다른 스킬 파일 (`engineering-rule-creator`, `context-rule-creator` 등)
- `rules/**` 카테고리 지침
- 플러그인 메타 파일 (plugin.yml, AGENTS.md 등)
- `plugins/project-init/skills/workspace-rule-creator/templates/**` (템플릿 본문은 이번 수정 범위 아님)
- 루브릭 자체 (`skill-rubric` 스킬 및 rule_checker.py 등) — 루브릭 verbatim 정책은 바꾸지 않는다.

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim — 스킬을 고치되 루브릭(rule_checker.py 포함) 자체는 수정하지 않는다.
- SKILL.md의 동작·공개 계약 의미(5단계 생성 절차, 규칙 섹션의 제약)는 수정 전후 불변이다.
- no-code-duplication: README와 references 스크립트에 SKILL.md 본문 로직을 복제하지 않는다. README는 계약·포인터 수준, references 스크립트는 SKILL.md가 위임하는 단일 출처.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/workspace-rule-creator/SKILL.md` 로 규칙 항목(S-README, R-PLACEHOLDER) PASS를 반드시 확인한다.

## 위험
- **R-SCRIPTIFY 과설계**: 파싱·치환·정규화를 스크립트화할 때 필요 이상의 범용 프레임워크를 만들 위험 — 최소 스크립트(결정적 작업 하나당 파일 하나)만 추가한다.
- **T-KEYWORDS 트리거 과확장**: 키워드 보강이 관련 없는 트리거까지 넓혀 T-SCOPE 항목이 악화될 수 있음 — 실제 사용자 발화 패턴("임시 파일 정리", "temp 규칙", "workspace 위생")에만 한정한다.
- **R-PLACEHOLDER 오탐 회피**: SKILL.md 본문에서 `{{...}}` 리터럴을 제거할 때, 템플릿 파일(`templates/*.md`) 내부의 placeholder는 수정 범위 밖이므로 건드리지 않는다 — SKILL.md 본문과 템플릿 파일을 혼동하지 않는다.
- **README 과잉 서술**: README가 SKILL.md 본문을 그대로 반복하면 no-code-duplication 위반 — 무엇(what)·언제(when)·호출(how to invoke) 세 가지 계약 포인터만 담는다.
