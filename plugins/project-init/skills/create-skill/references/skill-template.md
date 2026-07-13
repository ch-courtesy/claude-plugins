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

허용 frontmatter 키는 위 네 가지(`name`·`description`·`allowed-tools`·`argument-hint`)뿐이다.

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

각 항목을 어떻게 채우는가(description 완결성·본문/references 분리 기준·피해야 할 패턴)는
SKILL.md 절차 2·4·5단계가 다루는 기준을 따른다 — 이 틀은 구조만 정의하고 그 내용을
복제하지 않는다.
