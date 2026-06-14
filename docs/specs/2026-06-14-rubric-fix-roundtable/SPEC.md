---
scope:
  include:
    - plugins/roundtable/skills/roundtable/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# rubric-fix-roundtable

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`plugins/roundtable/skills/roundtable/` 폴더에 README.md 파일이 없다. 사람 독자를 위한 README.md를 스킬 폴더에 추가한다 — 스킬이 무엇인지, 언제 활성화되는지, 어떻게 호출하는지를 계약·포인터 수준으로 기술한 단일 파일이다. SKILL.md의 구현 본문을 복제하지 않는다.

## 목적 (왜)
루브릭 S-README 항목은 스킬 폴더에 사람 대상 README.md가 있어야 함을 요구한다. README.md가 없으면 스킬 품질 게이트를 통과하지 못하고, 새 기여자가 스킬의 역할·진입 조건·호출 방법을 SKILL.md 전체를 읽지 않고는 파악할 수 없다. README.md를 계약·포인터 수준으로 추가하면 루브릭 게이트를 통과하면서 단일 출처 원칙(SKILL.md가 동작 명세의 출처, README.md는 탐색·진입 포인터)도 보존된다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- **[S-README]** `plugins/roundtable/skills/roundtable/README.md` 파일이 존재하고, `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/roundtable/skills/roundtable/SKILL.md` 재실행 시 S-README 항목이 `passed=true`로 보고된다.
- **[불변식]** 언제나 스킬의 트리거 의미·동작·공개 계약이 보존된다: `roundtable start`, `roundtable resume`, `roundtable status` 서브커맨드의 동작·절차 의미가 수정 전후로 불변이다(SKILL.md 본문 변경 없음).

## 범위
포함:
- `plugins/roundtable/skills/roundtable/README.md` (신규 생성)

비-목표 / 제외:
- `plugins/roundtable/skills/roundtable/SKILL.md` — 동작·공개 계약을 담은 본문 파일이며 이번 수정 범위가 아니다.
- `plugins/roundtable/skills/roundtable/references/**` — references 파일은 변경하지 않는다.
- 다른 스킬 폴더 및 플러그인 메타 파일.
- `rules/**` — 루브릭 verbatim 정책과 프로젝트 규칙은 바꾸지 않는다.
- 루브릭 자체(평가 기준·rule_checker.py)는 완화하거나 수정하지 않는다.

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim: 스킬 파일을 고치되 루브릭·rule_checker.py는 수정하지 않는다.
- SKILL.md 동작·공개 계약 의미 불변: README.md 추가가 SKILL.md 내용이나 트리거 계약을 변경하지 않는다.
- no-code-duplication: README.md는 계약·포인터 수준으로만 기술하고, SKILL.md의 절차·프롬프트·참조 파일 목록·상태 전환 표 등 구현 본문을 복제하지 않는다(단일 출처 보존).
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/roundtable/skills/roundtable/SKILL.md` 로 S-README 항목 PASS를 확인한다.

## 위험
- README.md에 SKILL.md 본문을 과하게 복사하면 두 파일이 어긋날 때 단일 출처 원칙이 깨진다 — README.md는 "무엇·언제·어떻게 호출" 수준의 포인터에 머물러야 한다.
- README.md가 너무 얕아 S-README 조건을 충족하지 못할 위험 — 스킬 설명, 트리거 조건, 호출 형식 세 가지 최소 요소를 포함해야 한다.
