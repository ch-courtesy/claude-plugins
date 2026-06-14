---
scope:
  include:
    - plugins/project-init/skills/bootstrap/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# rubric-fix-bootstrap

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리는 제약으로. -->
`bootstrap` 스킬의 루브릭 지적 두 항목을 해소한다.

- **S-README**: 스킬 폴더에 사람 대상 `README.md`를 새로 추가한다 — 스킬의 무엇·언제·호출 방법을 계약·포인터 수준으로 담고, `SKILL.md` 본문 내용을 복제하지 않는다.
- **T-KEYWORDS**: `SKILL.md` front-matter의 `description`에 사용자가 자연어로 쓸 동의어·키워드를 보강한다 — WHAT/WHEN 구조와 스킬 동작은 불변이며, 트리거 매칭 표면만 넓힌다.

## 목적 (왜)
루브릭 품질 게이트를 통과시켜 스킬 검색·트리거 정확도를 높인다. `README.md` 추가는 새 기여자가 폴더를 열었을 때 곧바로 스킬의 목적과 진입점을 파악할 수 있게 하며, `description` 키워드 보강은 사용자의 다양한 자연어 표현이 이 스킬을 올바르게 선택하도록 매칭 표면을 넓힌다. 두 수정 모두 단일 출처(`SKILL.md`)를 깨지 않고 외부 계약·포인터만 추가한다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. **S-README**: `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/bootstrap/SKILL.md` 재실행 시 `S-README` 항목이 `passed=true`이다.

2. **T-KEYWORDS**: rubric 모델 재평가 시 `T-KEYWORDS` 항목이 PASS이다(근거: `description`에 "프로젝트 초기화", "설정", "세팅", "초기 설정", "환경 구성", "셋업" 등 사용자가 자연어로 쓸 동의어가 추가되어 트리거 매칭 표면이 넓어졌다).

3. **불변식**: 스킬의 트리거 의미·동작·공개 계약이 보존된다 — 기존 호출 방식, 서브커맨드, 진행 순서(단계 1~7), 벤더 골격 생성·AGENTS.md 조립·카테고리 선택 절차의 의미가 변경 전후 동일하다.

## 범위
포함:
- `plugins/project-init/skills/bootstrap/SKILL.md`
- `plugins/project-init/skills/bootstrap/README.md` (신규 생성)

비-목표 / 제외:
- 다른 스킬(`*-rule-creator` 등)은 수정하지 않는다.
- `rules/**` 파일은 수정하지 않는다.
- 플러그인 메타(`package.json`, `manifest` 등)는 수정하지 않는다.
- 루브릭 자체(`skill-rubric` 플러그인·rule_checker.py)는 수정하지 않는다 — 루브릭 verbatim 정책은 바꾸지 않는다.
- `shared/bootstrap/**` 공통 자산은 수정하지 않는다.

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 루브릭은 verbatim: 스킬을 고치되 루브릭(`rule_checker.py` 포함)은 수정하지 않는다.
- `SKILL.md`의 동작·공개 계약 의미는 불변: `description`의 WHAT/WHEN 핵심 구조·진행 순서·규칙 본문을 변경하지 않는다.
- no-code-duplication: `README.md`와 `references/`를 분리할 경우 단일 출처를 유지한다 — `SKILL.md`에 있는 내용을 `README.md`에 그대로 옮기거나 복제하지 않는다.
- 수정 후 `python3 /home/coder/.claude/plugins/cache/courtesy-claude-plugins/skill-rubric/0.1.0/skills/rubric/references/rule_checker.py plugins/project-init/skills/bootstrap/SKILL.md`로 규칙 항목 PASS를 확인한다.

## 위험
- **T-KEYWORDS 과확장 위험**: `description`에 키워드를 지나치게 넓게 추가하면 이 스킬이 관련 없는 요청에서도 트리거될 수 있다(T-SCOPE 악화). 추가 키워드는 "새 프로젝트 초기화" 의미 범위 안에서만 보강한다.
- **README 중복 위험**: `README.md`가 `SKILL.md`의 진행 순서·규칙 본문을 반복하면 단일 출처 원칙(no-code-duplication 메모리)을 위반한다. `README.md`는 계약·포인터 수준(한 눈에 파악 가능한 분량)으로만 작성한다.
