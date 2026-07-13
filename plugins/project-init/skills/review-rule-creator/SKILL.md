---
name: review-rule-creator
description: 현재 프로젝트에 맞는 리뷰 지침(review rule·코드 리뷰 규칙)을 리뷰 카테고리 디렉터리 아래 두 sub-룰 파일(`rules/review/principles.md`·`rules/review/change-adoption.md`)로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 리뷰 지침·코드 리뷰 원칙을 새로 만들고 싶어 할 때 — "리뷰 지침 생성", "코드 리뷰 규칙 만들어줘", "PR 리뷰 원칙 세팅", "change adoption·변경 반영 판단 지침 작성", "principles·change-adoption sub-룰 파일 작성" 같은 표현을 포함합니다.
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Glob
  - Bash(ls:*)
  - Bash(mkdir -p:*)
  - Bash(diff:*)
  - Bash(git diff:*)
  - Bash(rm:*)
---

# review-rule-creator

리뷰 카테고리 디렉터리 아래 **고정된 sub-룰 한 쌍**을 함께 기록합니다.

- `rules/review/principles.md` — 무엇을 리뷰하든 따르는 공통 리뷰 원칙(판정 전 사실 확정, 구속 기준, 위험도 비례 정밀도 등).
- `rules/review/change-adoption.md` — 리뷰·제안·자체 점검에서 *나온 지적을 반영할지* 판단하는 기준.

출력 파일명은 `principles`·`change-adoption`으로 **고정**입니다. 디렉터리 구조라 향후 다른 리뷰 sub-룰이 같은 카테고리 아래 공존할 수 있습니다.

## 페어로 함께 기록하는 이유

두 sub-룰은 **설계된 페어**입니다. `change-adoption.md`는 본문에서 `rules/review/principles.md`를 명시적으로 상호 참조하며, "리뷰를 *어떻게* 수행하는가"(principles)와 "거기서 나온 지적을 *반영할지*"(change-adoption)로 역할을 나눕니다. 한쪽만 기록하면 dangling 참조가 생기므로, 이 스킬은 한 번의 호출마다 둘을 **항상 함께** 산출합니다 — 한쪽만 기록·갱신하지 않으며, "1 호출 = 1 sub-룰"은 이 카테고리에 적용되지 않습니다(실제 상호 참조 의존성 때문에 co-production). 백엔드·변형 축이 없으므로 선택지나 대화형 입력도 없습니다.

## 템플릿 레이아웃

이 파일 옆 `templates/` 아래:

- `templates/principles.md` — 리뷰 원칙 본문(frontmatter 없음).
- `templates/change-adoption.md` — 변경 반영 판단 본문(frontmatter 없음).

두 템플릿 본문은 placeholder 치환 없이 그대로 복사합니다. 새 리뷰 sub-룰을 추가하려면 `templates/` 아래에 본문 파일을 두고 이 SKILL.md를 함께 갱신합니다.

## 생성 절차

1. **템플릿 열거.** 이 파일 옆 `templates/principles.md`·`templates/change-adoption.md`만 읽습니다. 다른 경로를 탐색하지 않습니다. 둘 중 하나라도 없으면 사용자에게 알리고 중단합니다.

2. **본문 조립.** 두 템플릿 본문을 그대로 사용합니다. placeholder 치환·대화형 입력·옵션 선택은 없습니다.

3. **기록 전 확인 게이트.** 조립된 두 본문(`principles`·`change-adoption`)을 사용자에게 보여 주고, 이 내용으로 기록해도 되는지 **확인을 받습니다**. 신규 파일·기존 파일 모두에 적용하며, 이는 4단계의 기존 파일 덮어쓰기 diff 확인과 별개입니다. 확인 없이는 기록하지 않습니다.

4. **파일 기록.**
   - 대상 디렉터리 `rules/review/`가 없으면 기록 전에 생성합니다. (평면 파일 `rules/review.md`와 디렉터리 `rules/review/`는 경로가 달라 공존 가능하므로 디렉터리 생성 자체는 실패하지 않습니다.)
   - **레거시 산출물 처리.** 평면 파일 `rules/review.md` 또는 `rules/change-adoption.md`가 있으면, 이 파일들이 새 분할 구조(`rules/review/principles.md`·`rules/review/change-adoption.md`)로 대체됨을 사용자에게 알리고 제거 여부를 확인합니다. 둘 다 남으면 리뷰 지침이 중복 적용되므로 정리를 권장하되, 사용자의 명시적 동의 없이는 삭제하지 않습니다.
   - `rules/review/principles.md`와 `rules/review/change-adoption.md`를 **함께** 기록합니다.
   - 각 대상 파일이 이미 있으면 덮어쓰지 않고 diff를 보여 사용자에게 확인합니다. 명시적 확인 없이는 덮어쓰지 않습니다. 자유 텍스트나 침묵은 동의가 아닙니다.

## 규칙

- 본 스킬은 `rules/review/` 아래 두 파일(`principles.md`·`change-adoption.md`)만 **항상 함께** 생성·갱신합니다. 같은 실행에서 카테고리 밖 파일을 만지지 않습니다.
- 템플릿 본문은 그대로 복사합니다. SKILL.md에 본문별 로직을 추가하지 않습니다.
- 기존 파일은 단순 재실행을 포함해 사용자 명시 동의 없이는 절대 덮어쓰지 않습니다.
