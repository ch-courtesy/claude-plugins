---
scope:
  include:
    - plugins/project-init/skills/workflow-rule-creator/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# rubric-fix-workflow-rule-creator

## 무엇을 만들 것인가

`plugins/project-init/skills/workflow-rule-creator/` 스킬 폴더의 세 가지 루브릭 지적(S-README, R-PLACEHOLDER, T-KEYWORDS)을 해소한 결과물을 만든다.

- `SKILL.md` description 키워드를 보강한다 — WHAT/HOW 의미와 트리거 동작은 그대로 두고, 사용자가 실제로 입력할 자연어 동의어만 넓힌다.
- `SKILL.md` 본문에서 `{{...}}` 리터럴 placeholder 잔재를 제거한다 — 치환 메커니즘은 코드펜스 예시나 평문 서술("name 필드")로만 표현한다.
- 스킬 폴더에 사람 대상 `README.md`를 신규 추가한다 — 계약·포인터 수준으로 짧게, `SKILL.md` 본문 내용을 복제하지 않는다.

## 목적 (왜)

토스 스킬 품질 루브릭 30항목 게이트를 통과하려면 규칙 검사(S-README, R-PLACEHOLDER)와 모델 평가(T-KEYWORDS) 모두 PASS여야 한다. README 부재는 사람이 스킬 폴더를 탐색할 때 진입점이 없음을 의미하고, placeholder 리터럴은 템플릿 미완성 신호로 오독될 수 있다. 키워드 부족은 트리거 매칭 표면이 좁아 사용자가 스킬을 호출하지 못하는 실질적 손실로 이어진다.

## 완료 조건

- S-README: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/workflow-rule-creator/SKILL.md` 재실행 시 S-README 항목 `passed=true`.
- R-PLACEHOLDER: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/workflow-rule-creator/SKILL.md` 재실행 시 R-PLACEHOLDER 항목 `passed=true`.
- T-KEYWORDS: 루브릭 모델 재평가 시 T-KEYWORDS 항목 PASS(근거: description에 사용자가 실제로 쓸 동의어·키워드가 충분히 포함되어 트리거 매칭 표면이 넓어진 것이 확인됨).
- 불변식: 스킬의 트리거 의미·동작·공개 계약이 보존된다 — 기존 호출 방식, 서브커맨드, 생성 절차(1–5단계), `rules/workflow/<sub>.md` 생성·갱신 의미가 수정 전과 동일하게 유지된다.

## 범위

포함:
- `plugins/project-init/skills/workflow-rule-creator/SKILL.md`
- `plugins/project-init/skills/workflow-rule-creator/README.md` (신규 생성)

비-목표 / 제외:
- `plugins/project-init/skills/workflow-rule-creator/templates/**` — 템플릿 파일 내용은 건드리지 않는다.
- 다른 스킬 폴더 일체.
- `rules/**` — 프로젝트 규칙 파일은 수정하지 않는다.
- 루브릭 자체(`skill-rubric` 플러그인) — 루브릭 verbatim 정책은 바꾸지 않는다.
- 플러그인 메타(`plugin.json` 등).
- S-NO-XML 등 이번 지적 목록에 없는 루브릭 항목은 이 SPEC의 범위가 아니다.

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약

- 루브릭은 verbatim — 스킬을 고치되 루브릭 자체는 수정하지 않는다.
- `SKILL.md` 동작·공개 계약 의미 불변 — description 키워드 보강과 placeholder 제거는 행동 변경 없이 표현만 다듬는다.
- no-code-duplication — `README.md`는 계약·포인터 수준으로 짧게 유지하고, `SKILL.md` 본문 내용(절차, 규칙 목록 등)을 복제하지 않는다. 단일 출처는 `SKILL.md`.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/workflow-rule-creator/SKILL.md` 로 규칙 항목(S-README, R-PLACEHOLDER) PASS를 확인한다.

## 위험

- T-KEYWORDS 과확장: 키워드 보강이 트리거 범위를 지나치게 넓혀 T-SCOPE(과다 트리거) 항목이 악화될 수 있음 — 워크플로 sub-룰 생성에 직접 관련된 동의어만 추가하고, 형제 스킬(engineering-rule-creator 등)과 겹치는 표현은 피한다.
- R-PLACEHOLDER 오해: `{{...}}` 제거 시 치환 메커니즘 자체를 설명하는 서술까지 삭제하지 않도록 주의 — 리터럴 placeholder 토큰만 제거하고, 메커니즘 설명은 코드펜스 예시나 평문으로 보존한다.
- README 과잉: README.md가 절차·규칙을 재서술하면 단일 출처 원칙 위반 및 유지보수 이중화 발생 — 스킬명·목적 한 줄, 호출 방법, SKILL.md 포인터만 담는다.
