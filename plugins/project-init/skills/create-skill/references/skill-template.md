# SKILL.md 구조 틀

아래는 새 스킬을 작성할 때 따르는 기본 구조다. 각 항목의 의미는 괄호 주석으로 표시했다.
파일을 작성할 때는 괄호 주석을 제거하고 실제 내용으로 채운다.

---

## frontmatter

```
---
name: <skill-name>        # kebab-case, ≤64자, 폴더명과 동일
description: <설명>        # WHEN(트리거) 중심 + 간결한 WHAT + 키워드, 1–1024자
allowed-tools:             # 필요한 도구만 열거 (파괴적 도구 금지)
  - AskUserQuestion
  - Read
  - Write
---
```

허용 frontmatter 키: `name`, `description`, `allowed-tools`, `argument-hint`.
그 외 키는 MAJOR 결함(S-ALLOWED-KEYS).

---

## 본문

```markdown
# <skill-name>

한 줄 요약 — 스킬이 하는 일을 동사-목적어로 기술한다.

## 절차

### 1. <첫 번째 단계>

...

### 2. <두 번째 단계>

...

### N. <마지막 단계>

...

## 규칙

- <추가 규칙>

## references

| 파일 | 용도 | 읽는 시점 |
|------|------|-----------|
| `references/<file>` | <용도> | <단계> |
```

references 섹션은 파일이 있을 때만 작성한다. 없으면 생략한다.

---

## 작성 지침

### description 완결성

description은 에이전트가 호출 여부를 판단하는 단일 출처다. 무게중심은 **WHEN(언제 호출되는가·
트리거)**에 둔다 — 활성화 조건·증상·오류 신호·사용자 표현을 동의어와 함께 구체적으로 담는다.
WHAT(무엇을 하는가)은 동사-목적어 한 구절로 간결하게만 남긴다(생략은 T-WHATWHEN 위반).
예외 케이스도 description 안에 포함해 별도 예외처리 지침이 없어도 완결되게 한다.

### 본문 분리 기준

- 핵심 순서·판단 기준 → SKILL.md 본문
- 손으로 하면 틀리기 쉬운 결정적 작업 → `references/` 스크립트로 고정
- 상세 정보·레퍼런스 → `references/*.md`

### 피해야 할 패턴

- 대문자 XML 태그 본문 사용 (BLOCKER)
- `[TODO]`, `[PLACEHOLDER]`, `FIXME`, `{{ ... }}` 잔재 (MINOR)
- 참조 체인 A→B→C (MAJOR)
- 시점 정보가 본문에만 있고 description에 없음 (BLOCKER)
