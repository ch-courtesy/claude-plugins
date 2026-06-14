---
scope:
  include:
    - plugins/autopilot/skills/loop/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# rubric-fix-loop

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`plugins/autopilot/skills/loop/` 폴더에 두 가지 산출물을 추가·갱신한다.

1. **README.md 신규 생성**: 스킬의 무엇(what)·언제(when)·호출 방법(how to call)을 계약·포인터 수준으로 담은 사람 대상 문서 1개. SKILL.md 본문 내용을 복제하지 않고 포인터(참조)만 제공한다.
2. **description 키워드 보강**: `SKILL.md` front-matter의 `description` 필드에 사용자가 실제로 쓸 자연어 동의어·키워드를 추가해 트리거 매칭 표면을 넓힌다. SKILL.md의 WHAT·WHEN 구조와 스킬 동작은 보존한다.

## 목적 (왜)
루브릭 품질 게이트(S-README, T-KEYWORDS)를 통과해 스킬의 발견 가능성과 신뢰성을 높인다. README가 없으면 사람이 폴더를 탐색할 때 스킬의 목적과 진입점을 파악하기 어렵고, description 키워드가 빈약하면 LLM 트리거 매칭이 누락된다. 두 수정 모두 SKILL.md 단일 출처를 해치지 않고 계약 표면만 확장하므로 기존 동작을 변경하지 않는다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

- 항상 S-README: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/loop/SKILL.md` 재실행 시 `S-README` 항목 `passed=true`.
- 항상 T-KEYWORDS: rubric 모델 재평가 시 `T-KEYWORDS` 항목 PASS(근거: description에 "랄프 루프", "자율 구현", "워크트리 격리", "SPEC 실행", "백그라운드 에이전트" 등 사용자가 실제로 쓸 동의어 키워드가 추가되어 트리거 매칭 표면이 확장됨).
- 항상 불변식: 기존 호출 방식(`Skill(skill="loop", args="<subcommand> [<args>]")`), 서브커맨드(start/status/stop/list/cleanup/logs/env/gates/paths/deps), 신호 계약, 공개 절차 의미가 모두 보존된다.

## 범위
포함:
- `plugins/autopilot/skills/loop/SKILL.md`
- `plugins/autopilot/skills/loop/README.md` (신규 생성)
- `plugins/autopilot/skills/loop/references/**` (참조 확인용, 내용 변경 불가)

비-목표 / 제외:
- 다른 스킬 폴더(`plugins/autopilot/skills/` 하위 loop 외 모든 스킬)
- `rules/**` — 카테고리 지침 불변
- 플러그인 메타 파일(플러그인 레벨 manifest 등)
- 루브릭 자체(`skill-rubric` 플러그인 파일) — verbatim 정책은 바꾸지 않는다
- `references/` 내 파일 내용 수정 (constitution.md, loop.sh 등 SoT 파일은 읽기 전용)

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim: 스킬을 고치되 루브릭 파일은 수정하지 않는다.
- SKILL.md의 동작·공개 계약 의미 불변: description 키워드 추가는 트리거 표면 확장에만 국한하고 WHAT/WHEN 구조·서브커맨드·신호 계약을 변경하지 않는다.
- no-code-duplication: README는 계약·포인터 수준으로 짧게 작성하고 SKILL.md 본문(서브커맨드 상세·references 표·규칙 목록 등)을 복제하지 않는다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/autopilot/skills/loop/SKILL.md` 로 규칙 항목 PASS 확인.

## 위험
- T-KEYWORDS 키워드 보강이 트리거 과확장(T-SCOPE 악화)되지 않게: 추가 키워드는 loop 스킬에 실제로 해당하는 유의어에 한정하고, 다른 스킬(spec·dispatch·flow)의 트리거 영역을 침범하는 과도한 일반 용어(예: "자동화", "실행")는 사용하지 않는다.
- README가 SKILL.md 내용을 무심코 복제할 위험: README 작성 시 SKILL.md의 서브커맨드 상세·references 표·규칙 목록을 그대로 옮기면 단일 출처 원칙 위반 — 요약·포인터(링크)만 허용한다.
