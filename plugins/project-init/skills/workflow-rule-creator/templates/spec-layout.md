---
label: SPEC 레이아웃 (spec-layout)
description: 개발 워크플로의 설계 단계 산출물인 SPEC 문서가 어디에 어떤 디렉터리 레이아웃으로 사는지를 정의합니다. 산출물 경로/레이아웃만 규정하고 상태 추적·머지·빌드는 다른 카테고리에 위임합니다.
recommended: true
inputs:
  - name: spec_path
    header: "SPEC 경로"
    question: "각 SPEC의 per-spec 디렉터리 경로 템플릿은? 디렉터리 경로만 입력하고 끝의 `/SPEC.md`는 붙이지 마세요(`<YYYY-MM-DD>`·`<slug>` placeholder 사용 가능). 자유 입력은 'Other'로 직접 입력하세요."
    options:
      - label: "docs/specs/<YYYY-MM-DD>-<slug>"
        description: "engineering 단일 출처(branch-and-slug.md)의 기본 레이아웃. 날짜+slug per-spec 디렉터리"
        value: "docs/specs/<YYYY-MM-DD>-<slug>"
      - label: "spec/<slug>"
        description: "날짜 없이 slug만으로 per-spec 디렉터리를 명명하는 단순 레이아웃"
        value: "spec/<slug>"
---

# SPEC 레이아웃 지침

개발 워크플로(설계 → 구현 → 리뷰 → 반복 → 완료)의 **설계 단계 산출물인 SPEC 문서가 어디에, 어떤 디렉터리 레이아웃으로 사는지**를 정하는 규칙입니다. 이 지침은 워크플로 "척추(spine)"의 영속 설계 산출물에 대한 **경로/레이아웃의 단일 출처**입니다.

## 적용 범위

이 지침은 **SPEC 설계 문서의 위치와 디렉터리 레이아웃**에만 적용됩니다.

- **규정하는 것**: SPEC 문서가 사는 per-spec 디렉터리의 베이스·네이밍, 그 안의 본문 파일명.
- **규정하지 않는 것(위임)**: 작업 상태 추적은 **context** 카테고리, 변경 통합·머지는 **version-control** 카테고리, 빌드·버전은 **engineering** 카테고리가 단일 출처로 정의합니다. 이 지침은 그 책임들을 중복 정의하지 않습니다.
- SPEC의 *내용* 규약(수용 기준 표현·EARS 패턴 등)도 이 지침의 범위가 아닙니다 — 여기서는 오직 **어디에 두는가**만 정합니다.

## 저장 위치 (필수 규칙)

**각 SPEC은 자신의 전용 per-spec 디렉터리를 가지며, 본문은 그 디렉터리 안의 `SPEC.md`에 둔다.**

기본 레이아웃은 다음과 같습니다:

```
{{spec_path}}/SPEC.md
```

- `<YYYY-MM-DD>`는 SPEC 작성일(로컬 날짜)입니다.
- `<slug>`는 SPEC 제목(첫 H1)에서 아래 **slug 규칙**으로 파생합니다.
- 본문은 베이스 바로 아래의 맨몸 파일이 아니라 **per-spec 디렉터리 안의 `SPEC.md`**입니다. 이 불변식(per-spec 디렉터리 + 그 안 `SPEC.md`)은 베이스나 네이밍을 바꾸더라도 보존됩니다.
- per-spec 디렉터리 레이아웃은 그 SPEC의 실행이 만드는 부수 산출물(워크트리·락·실행 메타·신호 등)을 같은 디렉터리 하위로 격리하기 위한 것입니다 — 서로 다른 SPEC의 실행이 공통 부모를 공유하지 않습니다.
- 디렉터리가 없으면 `mkdir -p`로 만듭니다.

## slug 규칙

SPEC 첫 H1(`# `)에서 slug를 만듭니다.

1. ASCII lowercase
2. `[a-z0-9-]` 외 문자를 `-`로
3. 연속 `-` 압축
4. 앞뒤 `-` 제거

빈 slug면 fallback 디렉터리 없이 abort하고 제목 수정을 요청합니다.

> 이 slug·경로 규칙은 자기완결이 되도록 위에 담았습니다. 타깃 프로젝트에 **engineering 카테고리의 branch·slug 단일 출처**(예: `rules/engineering/branch-and-slug.md`)가 있으면 그 출처가 우선이며, 이 지침은 그것과 정합해야 합니다 — 두 곳이 어긋나면 engineering 출처에 맞춰 이 값을 수정합니다.

## 베이스 경로 재정의 (선택)

기본 베이스 `docs/specs/`가 프로젝트에 맞지 않으면, 사람이 읽고 grep 가능한 **약속된 키 한 줄** `spec-path:` 선언으로 per-spec 디렉터리 경로 템플릿을 재정의할 수 있습니다.

- `spec-path:` 값은 베이스뿐 아니라 per-spec 디렉터리 네이밍까지 표현하는 경로 템플릿이며 `<YYYY-MM-DD>`·`<slug>` placeholder를 포함할 수 있습니다.
- placeholder가 없어 디렉터리가 유일해지지 않으면, 서로 다른 SPEC이 같은 디렉터리를 공유하지 않도록 유일성을 보장하는 것은 선언자의 책임입니다.
- 선언이 없으면 위 기본 레이아웃(`{{spec_path}}/SPEC.md`)을 사용합니다.
- 재정의 유무·값과 무관하게 **per-spec 디렉터리 + 그 안 `SPEC.md`** 불변식은 보존됩니다.

## 위반 발견 시

SPEC 본문이 per-spec 디렉터리 밖(베이스 바로 아래 맨몸 파일 등)에 있거나, 여러 SPEC이 한 디렉터리를 공유하거나, slug가 규칙과 어긋난 것을 발견하면 즉시 멈추고 정상화합니다 — 본문을 전용 per-spec 디렉터리 안의 `SPEC.md`로 옮기고 slug를 규칙대로 맞춥니다. 다음 작업으로 미루지 않습니다.
