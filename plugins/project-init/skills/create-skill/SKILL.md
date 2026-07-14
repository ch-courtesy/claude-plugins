---
name: create-skill
description: 새 스킬(SKILL.md)을 인터뷰 기반으로 설계·작성하는 가이드. 루브릭 30항목 품질 기준을 작성 단계에 내장해 BLOCKER·MAJOR 0 목표로 스킬을 완성한다. 사용자가 새 스킬 작성·설계·제작·초안 생성을 요청할 때 활성화된다.
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Bash(mkdir -p:*)
  - Bash(python3 *rule_checker.py*:*)
  - Bash(git rev-parse:*)
---

# create-skill

새 스킬(SKILL.md)을 인터뷰 기반으로 설계·작성한다. 루브릭 30항목 품질 기준을
작성 단계에 내장해 단일 진입점으로 BLOCKER·MAJOR 0 스킬을 완성한다.

## 절차

### 1. 스킬 목적 인터뷰

다음 세 질문을 구조화된 사용자 질문 기능 또는 간결한 직접 질문으로 묻는다.

- 이 스킬이 자동화하는 워크플로우는 무엇인가?
- 여러 상황에서 반복 재사용되는 절차인가, 일회성 작업인가?
- 에이전트 기본 능력만으로 일관되게 수행하기 어려운 고유 절차·지식이 있는가?

세 답변으로 V-REPEAT·V-GENERIC·V-IRREPLACEABLE 타당성을 1차 판단한다.
타당성이 낮으면 그 이유를 알리고 계속 진행 여부를 묻는다.

### 2. description 설계

description은 에이전트가 본문을 보기 전에 **호출 여부를 판단하는 단일 출처**다. 무게중심을
**언제 호출되는가(WHEN·트리거)**에 둔 초안을 작성한다.

- WHEN(중심): 활성화 조건·증상·오류 신호·사용자 표현을 "~할 때"·"~신호에서" 형태로 구체적으로,
  사용자가 실제로 쓸 법한 동의어·유사 표현과 함께 충분히 담는다(트리거 매칭의 핵심).
- WHAT(간결): 스킬이 하는 일을 동사-목적어 한 구절로만 남긴다(생략하면 T-WHATWHEN 위반) —
  상세 동작·방법은 본문의 몫이다.
- 예외 케이스("~이면 쓰지 않는다")도 description 안에 포함해 description 자체로 완결한다.

description 초안을 사용자에게 보여주고 수정 여부를 확인한다.

### 3. 도구 목록 결정

절차에 필요한 도구를 allowed-tools에 열거한다. 참고:

- 사용자 선택이 필요하면 구조화된 사용자 질문 기능
- 파일 읽기: `Read`, `Glob`
- 파일 쓰기: `Write`
- 디렉토리 생성: `Bash(mkdir -p:*)`
- 스크립트 실행: `Bash(python3:*)`, `Bash(bash:*)`
- `rm -rf`, `git push --force` 등 파괴적 도구는 allowed-tools에 넣지 않는다.

### 4. 절차·references 설계

절차 본문과 references 분리 기준을 결정한다.

- 핵심 순서·판단 기준은 SKILL.md 본문에 둔다.
- 손으로 하면 틀리기 쉬운 결정적 작업은 `references/` 스크립트로 고정한다.
- references 파일이 있으면 본문에서 "언제 읽는가"를 명시한다.
- 본문 → references 1단계로 참조 깊이를 제한한다.
- 본문 500줄 이하를 목표로 한다.

### 5. 품질 자가점검 (모델 13항목)

`../../shared/rubric/criteria.md`를 읽고 설계 내용을 "2. 모델 항목" 13개(의미 판정)
기준으로 점검한다. BLOCKER 항목은 반드시 해소하고, MAJOR 항목은 0을 목표로 한다.
규칙 17항목(결정적 판정)은 손으로 대조하지 않는다 — 7단계에서 검사기로 확인한다.

### 6. 파일 작성

대상 디렉토리를 사용자에게 물어본다 (예: `plugins/foo/skills/bar/`).
대상 디렉토리가 없으면 `mkdir -p`로 생성한다.
대상 디렉토리에 다음 파일을 생성한다.

- `SKILL.md` — 1–5단계에서 설계한 내용으로 `references/skill-template.md` 구조를 따라 작성
- `README.md` — 목적·호출 예시 요약 (SKILL.md 내용 복제 금지)
기존 파일은 diff를 보여준 뒤 명시적 승인이 있을 때만 덮어쓴다.

### 7. 규칙 검사 실행 (결정적 17항목)

6단계에서 생성·덮어쓴 SKILL.md가 없으면(승인 거절 등) 이 단계를 건너뛴다.
`../../shared/rubric/checker-invocation.md`의 호출 계약(절대경로 고정·실행
형식·결과 해석)대로 생성된 SKILL.md에 검사기를 실행하고, stdout JSON의
규칙 17항목 결과에서 BLOCKER·MAJOR 0을 확인한다. BLOCKER·MAJOR가 발견되면
해당 파일을 수정한 뒤 **1회만 재검**한다 — 재검에서도 남으면 반복하지 않고
잔존 지적으로 8단계에 넘긴다(무한 루프 방지).

### 8. 완료 요약

생성·보존·승인 거절로 생략된 파일을 구분해 요약한다.
BLOCKER·MAJOR 잔여가 있으면 수정을 권고한다.

## 규칙

- `../../shared/rubric/criteria.md`는 5단계에서 읽는다 — 사전에 읽지 않는다.
- `references/skill-template.md`는 6단계에서 읽는다.
- 기존 파일은 사용자 명시 동의 없이 덮어쓰지 않는다.
- 루브릭 30항목 기준의 단일 출처는 `../../shared/rubric/criteria.md`다 — 사본을 만들지 않는다.

## references

| 파일 | 용도 | 읽는 시점 |
|------|------|-----------|
| `../../shared/rubric/criteria.md` | 루브릭 30항목 자가점검 체크리스트 (단일 출처) | 5단계 — 품질 자가점검 |
| `references/skill-template.md` | SKILL.md 구조 틀 | 6단계 — 파일 작성 |
| `../../shared/rubric/checker-invocation.md` | 검사기 호출 계약 (단일 출처) | 7단계 — 규칙 검사 실행 |
| `../../shared/rubric/rule_checker.py` | 규칙 17항목 결정적 검사기 | 7단계 — 규칙 검사 실행 |
