---
scope:
  include:
    - plugins/roundtable/skills/brainstorm/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# rubric-fix-brainstorm

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`plugins/roundtable/skills/brainstorm/` 폴더에 사람 대상 README.md 파일 1개를 추가한다. README.md는 스킬의 정체(무엇인가), 활성화 조건(언제 사용하는가), 호출 방법(어떻게 부르는가)을 계약·포인터 수준으로 기술하며 SKILL.md 본문 내용을 복제하지 않는다.

## 목적 (왜)
토스 스킬 품질 루브릭 S-README 항목이 스킬 폴더의 사람 대상 README.md 부재를 지적했다. README.md를 추가하면 루브릭 품질 게이트를 통과하고, 스킬 발견 가능성(사람이 폴더를 탐색할 때 스킬을 빠르게 이해)이 높아진다. SKILL.md가 단일 진실 출처로 유지되므로 중복 없이 신뢰성을 높일 수 있다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
1. **S-README**: `plugins/roundtable/skills/brainstorm/README.md` 파일이 존재하고, 스킬 정체·활성화 조건·호출 방법을 포함하며, SKILL.md 본문 내용을 복제하지 않을 때 — `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/roundtable/skills/brainstorm/SKILL.md` 재실행 시 S-README 항목 `passed=true`.
2. **불변식**: 스킬의 트리거 의미·동작·공개 계약이 보존된다. 기존 호출(`brainstorm start`·`brainstorm resume`·`brainstorm status`)·서브커맨드·절차 의미가 변경되지 않을 때 항상 충족된다.

## 범위
포함:
- `plugins/roundtable/skills/brainstorm/README.md` (신규 생성)
- `plugins/roundtable/skills/brainstorm/SKILL.md` (읽기 전용 참조 — 내용 변경 없음)
- `plugins/roundtable/skills/brainstorm/references/**` (읽기 전용 참조 — 내용 변경 없음)

비-목표 / 제외:
- 다른 스킬 폴더(roundtable, 기타 플러그인 스킬 포함)
- `rules/**`
- 플러그인 메타 파일(plugin.yaml 등)
- 루브릭 자체(루브릭 verbatim 정책은 바꾸지 않는다)
- SKILL.md 본문 수정

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim — 스킬을 고치되 루브릭 자체는 수정하지 않는다.
- SKILL.md 동작·공개 계약 의미 불변 — README.md 추가가 SKILL.md 내용·트리거·호출 계약에 영향을 주지 않는다.
- no-code-duplication — README.md와 SKILL.md가 동일 내용을 중복 기술하지 않는다. README.md는 포인터·요약만 담고 상세는 SKILL.md로 위임한다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/roundtable/skills/brainstorm/SKILL.md` 로 규칙 항목 PASS를 확인한다.

## 위험
- **README-SKILL 내용 중복**: README.md 작성 시 SKILL.md의 워크플로 세부 절차(상태 전이표·참조 파일표·디스패치 규칙 등)를 그대로 옮기면 단일 출처 원칙이 깨진다 — README.md는 계약·포인터 수준으로 제한하고 상세는 SKILL.md 링크로 처리해야 한다.
- **S-README 판정 기준 과소 충족**: README.md가 너무 짧거나 활성화 조건·호출 방법 중 하나를 빠뜨리면 rule_checker가 여전히 FAIL을 낼 수 있다 — 세 가지 항목(정체·활성화 조건·호출)을 명시적으로 포함해야 한다.
