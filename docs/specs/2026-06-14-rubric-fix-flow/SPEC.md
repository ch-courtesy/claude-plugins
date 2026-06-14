---
scope:
  include:
    - plugins/autopilot/skills/flow/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# rubric-fix-flow

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`flow` 스킬 폴더에 아래 두 가지 산출물을 추가·보강한다.

1. **README.md 신설** — 사람 대상의 스킬 요약 문서. 스킬이 무엇인지·언제 쓰는지·어떻게 호출하는지를 계약·포인터 수준으로 기술한다. SKILL.md 본문 내용을 복제하지 않는다.
2. **references 읽기 시점 지시 보강** — SKILL.md 내 `references` 섹션이 각 파일을 "언제·무엇을 할 때 읽어야 하는지"를 명시하도록 갱신한다. 역할 나열을 넘어 읽기 시점 지시로 보강한다.

## 목적 (왜)
`flow` 스킬은 루브릭 평가에서 S-README(README 부재)·R-LINKWHEN(references 읽기 시점 미명시) 항목 FAIL을 받았다. 두 항목을 해소해 루브릭 품질 게이트를 통과하고, 기여자·호출자가 스킬 입구와 references 용도를 즉시 파악해 인지 비용을 낮춘다. 수정은 기존 스킬의 동작·공개 계약을 변경하지 않으므로 하위 호환성이 유지된다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. **S-README** — `plugins/autopilot/skills/flow/README.md` 파일이 존재하고, 스킬의 무엇(what)·언제(when)·호출(how) 세 항목을 계약·포인터 수준으로 담으며, SKILL.md 본문 내용(subcommand 설명·engine API·예시 코드 등)을 복제하지 않는다. rubric 모델 재평가 시 해당 항목 PASS(근거: `plugins/autopilot/skills/flow/README.md` 파일 존재 + 계약·포인터 수준 내용 확인).

2. **R-LINKWHEN** — SKILL.md의 `references` 섹션(또는 동등 위치)이 각 파일(`flow.sh`, `runner.py`, `workflow_replica/`, `tests/`)에 대해 "언제·무엇을 할 때 읽는지"를 명시한다. rubric 모델 재평가 시 해당 항목 PASS(근거: 역할 나열을 넘어 읽기 시점이 명시됨).

3. **불변식** — 항상, 스킬의 트리거 의미·동작·공개 계약이 보존된다. 기존 subcommand(`run`/`selftest`/`deps`)·호출 방식·JSON 출력 계약·engine API가 수정 전후 동일하다.

## 범위
포함:
- `plugins/autopilot/skills/flow/SKILL.md`
- `plugins/autopilot/skills/flow/README.md` (신규 파일)

비-목표 / 제외:
- 다른 스킬 폴더(`dispatch`, `loop`, `spec`, `review`, `using-autopilot` 등) 일체
- `rules/**` — 루브릭 verbatim 정책 및 프로젝트 지침은 바꾸지 않는다
- `plugins/autopilot/skills/flow/references/**` 실행 파일(`flow.sh`, `runner.py`, `workflow_replica/`, `tests/`) — 동작 코드는 변경하지 않는다
- 루브릭 자체(`skill-rubric` 플러그인 코드·평가 기준) 완화 또는 수정
- S-NO-XML 등 이번 지적 외의 다른 루브릭 항목 수정

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim — 스킬 파일을 고치되 루브릭 평가 기준은 변경하지 않는다.
- SKILL.md의 동작·공개 계약 의미 불변 — subcommand 인터페이스·JSON 출력 스키마·engine API 시그니처를 바꾸지 않는다.
- no-code-duplication — README와 SKILL.md가 분리되더라도 단일 출처를 유지한다. README는 계약·포인터 수준에 머물고 구체 설명은 SKILL.md가 단일 출처다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/flow/SKILL.md` 를 실행해 규칙 항목 PASS를 확인한다.

## 위험
- **R-LINKWHEN 보강이 역할 설명을 과잉 복제할 위험** — 읽기 시점 지시를 추가할 때 기존 역할 설명 문장을 그대로 두고 "언제 읽는가"만 덧붙여야 한다. 역할 설명 전체를 다시 쓰면 SKILL.md 길이가 불필요하게 늘어난다.
- **README가 SKILL.md를 암묵적으로 복제할 위험** — README 작성 시 subcommand 상세·engine API·예시 코드를 재서술하면 단일 출처 원칙 위반이다. 무엇·언제·호출 형식(한 줄)만 남기고 "자세한 내용은 SKILL.md 참조" 포인터로 끝낸다.
- **불변식 위반 위험** — SKILL.md references 섹션 수정 시 인접 코드 블록(예시·사용 계약)을 실수로 편집할 수 있다. 외과적 변경(해당 테이블 셀만 수정)만 허용한다.
