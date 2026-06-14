---
scope:
  include:
    - plugins/project-init/skills/version-control-rule-creator/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# rubric-fix-version-control-rule-creator

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`version-control-rule-creator` 스킬의 루브릭 지적 4건(S-README, R-PLACEHOLDER, R-SPLIT, R-SCRIPTIFY)을 해소한다.

- S-README: 스킬 폴더에 사람 대상 `README.md`를 신규 생성한다 — 스킬의 무엇·언제·호출 방법을 계약·포인터 수준으로 담고, SKILL.md 본문 내용을 복제하지 않는다.
- R-PLACEHOLDER: SKILL.md 본문에 남은 `{{...}}` 리터럴 placeholder 잔재를 제거한다. 템플릿 치환 메커니즘은 placeholder 리터럴 없이 서술하거나 코드펜스 안 예시로만 표현한다.
- R-SPLIT: SKILL.md의 비대한 상세 절차(백엔드 판별 로직, 입력 치환 규칙 등)를 `references/` 아래 별도 파일로 분리하고, SKILL.md 본문은 핵심 계약·절차 요약만 남긴다. 단일 출처 유지, 중복 금지.
- R-SCRIPTIFY: 실수하기 쉬운 결정적 작업(파일명 파싱 로직, placeholder 치환 집계 로직, 백엔드 판별 분기 등)을 `references/` 아래 스크립트로 고정하고, SKILL.md 본문은 그 스크립트를 호출·참조하도록 바꾼다.

## 목적 (왜)
이 스킬은 루브릭 품질 게이트의 구조 규칙(S-README)·텍스트 규칙(R-PLACEHOLDER)·단일 출처 규칙(R-SPLIT)·스크립트화 규칙(R-SCRIPTIFY)을 통과하지 못하고 있다. README 신설로 사람 독자와 에이전트 트리거 정확도를 높이고, placeholder 제거로 SKILL.md 텍스트 완결성을 확보하며, references 분리와 스크립트화로 에이전트의 즉흥 재현 가능성을 제거해 스킬 신뢰성을 높인다. 수정 후 동일 루브릭 재실행에서 4개 항목 모두 PASS를 달성한다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. **S-README**: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/version-control-rule-creator/SKILL.md` 재실행 시 `S-README` 항목 `passed=true`.

2. **R-PLACEHOLDER**: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/version-control-rule-creator/SKILL.md` 재실행 시 `R-PLACEHOLDER` 항목 `passed=true`.

3. **R-SPLIT**: rubric 모델 재평가 시 `R-SPLIT` 항목 PASS(근거: SKILL.md 본문이 핵심 계약·절차 요약만 담고, 상세 절차는 `references/` 파일을 단일 출처로 가리키며, SKILL.md와 references 간 내용 중복이 없음).

4. **R-SCRIPTIFY**: rubric 모델 재평가 시 `R-SCRIPTIFY` 항목 PASS(근거: 파일명 파싱·placeholder 집계 치환·백엔드 판별 분기 등 결정적 작업이 `references/` 아래 스크립트에 고정되고, SKILL.md 본문은 해당 스크립트를 참조·호출하도록 기술되어 에이전트 즉흥 재현이 제거됨).

5. **불변식**: 스킬의 트리거 의미·동작·공개 계약이 보존된다 — 기존 호출 방법, 서브커맨드, 절차 의미(백엔드 자동 판별 → sub-룰 생성 흐름)가 수정 전후 동일하다. 항상 외부 호출자가 관찰 가능한 스킬 행동(입·출력, 트리거 조건)이 변경 전과 일치해야 한다.

## 범위
포함:
- `plugins/project-init/skills/version-control-rule-creator/SKILL.md`
- `plugins/project-init/skills/version-control-rule-creator/references/**` (신규 생성 포함)
- `plugins/project-init/skills/version-control-rule-creator/README.md` (신규 생성)

비-목표 / 제외:
- 다른 스킬 파일 (`plugins/project-init/skills/` 아래 다른 스킬 폴더)
- `rules/**` (카테고리 지침 불변)
- 플러그인 메타파일 (`plugins/project-init/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`) — 단, 스킬 내용 변경이 버전 범프를 요구하면 버전 파일은 포함 대상이 될 수 있음
- 루브릭 자체 (`skill-rubric` 플러그인, rule_checker.py 등) — 루브릭 verbatim 정책은 바꾸지 않는다
- `templates/` 하위 템플릿 파일의 내용(R-SPLIT·R-SCRIPTIFY는 SKILL.md 본문과 references에 한정)
- S-NO-XML 등 이번 지적 목록에 없는 루브릭 항목의 수정

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim으로 다룬다: 스킬을 고치되 루브릭(rule_checker.py 포함)은 수정하지 않는다.
- SKILL.md 동작·공개 계약의 의미는 불변이다: 트리거 조건, 입력·출력 형태, 절차 흐름을 바꾸지 않는다.
- no-code-duplication: README·references 분리 시 SKILL.md와 중복 내용을 만들지 않는다. SKILL.md가 references를 참조하면 references가 단일 출처이고, SKILL.md에 동일 내용을 재서술하지 않는다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/version-control-rule-creator/SKILL.md` 로 규칙 항목(S-README, R-PLACEHOLDER) PASS를 확인한다.
- R-SCRIPTIFY로 생성하는 스크립트는 최소 범위만 고정한다: 과설계(불필요한 추상화·CLI 옵션 등)를 피하고, 실수하기 쉬운 결정적 작업(파싱·집계·분기)만 스크립트화한다.

## 위험
- **R-SCRIPTIFY 과설계 위험**: 스크립트화 범위를 넓히면 SKILL.md보다 스크립트가 복잡해져 유지보수 부담이 커질 수 있음 — 결정적 작업(파일명 파싱, placeholder 집계 치환, 백엔드 판별 분기)에만 한정하고 최소 스크립트만 작성한다.
- **R-SPLIT 중복 잔존 위험**: 분리 후 SKILL.md에 상세 내용 요약을 "친절하게" 재서술하면 단일 출처 위반이 됨 — 분리된 절차는 참조 포인터만 남기고 내용을 SKILL.md에 남기지 않는다.
- **R-PLACEHOLDER 누락 위험**: `{{...}}` 형태가 여러 절에 걸쳐 분산되어 있어 일부를 빠트릴 수 있음 — 전체 SKILL.md를 grep하여 잔재를 빠짐없이 제거한다.
- **T-KEYWORDS 트리거 과확장 위험**: README나 SKILL.md 수정 과정에서 트리거 키워드를 과보강하면 T-SCOPE 악화로 이어질 수 있음 — 트리거 조건 키워드는 기존 의미를 벗어나지 않게 유지한다.
