# 태스크 본문(=SPEC) 구조 (feature 자체 소유)

태스크 본문이 설계의 단일 출처다. 별도 SPEC 파일을 만들지 않는다. 본문은 **frontmatter-first 스펙 문서**다 —
맨 앞 frontmatter(`scope`/선택 `ears_language`) + 본문 섹션. 백엔드 공통이며 정규 정의는 플러그인
`task-backend/contract.md`와 일치한다.

**`# 제목` H1·`depends_on`은 본문에 넣지 않는다** — 제목·depends_on·status는 백엔드가 단일 저장하며(중복 회피),
materialize 가 frontmatter 뒤에 제목을 주입한다. 본문 frontmatter 에는 `scope`·`ears_language`만 둔다.

```markdown
---
scope:
  include:
    - <변경 대상 glob>      # step 1 컨텍스트 탐색·인터뷰에서 식별한 변경 대상. 불명확하면 해당 모듈
                            #   디렉터리로 보수적으로 넓게(과좁은 include 는 정당한 변경을 halt 시킨다).
  exclude:
    - rules/**
    - milestones/**
    - AGENTS.md
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만. 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

## 목적 (왜)
<!-- 이 변경을 왜 하는가 1–3문장. 완료 조건의 종속 앵커일 뿐 검증 기준이 아니다. 모호하면 [NEEDS CLARIFICATION: 왜 ...]. -->

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)·언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능·독립 검증 가능. -->

## 범위
포함:

비-목표 / 제외:

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건". 진입 명령(테스트·lint·빌드)은 SPEC 이 선언하지 않는다. -->
이 SPEC 의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다.

## 제약 (있을 때만)

## 위험 (있을 때만)
```

## 작성 규칙

- **frontmatter-first** — 본문 첫 줄은 `---`(여는 frontmatter). `scope.include` 는 step 1 인터뷰에서 식별한
  변경 대상 glob 으로 채운다. 불명확하면 보수적으로 넓게 잡고 **위험**에 명시한다.
- **WHAT/HOW 방어선** — 무엇을 만들 것인가·완료 조건에는 "무엇"만. 기술 선택·경로·라이브러리는 제약에.
- **완료 조건**은 `references/ears-patterns.md`의 5문장 패턴으로, 각 항목이 관찰 가능하고 독립적으로 테스트
  가능해야 한다(실행 스킬이 이걸로 검증).
- **`# 제목` H1·`depends_on` 금지** — 본문에 두지 않는다(백엔드 단일 저장).
- 미해결 항목은 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 남긴다 — 마커가 있으면 무인 실행이 차단된다.
- 본문은 자기완결이어야 한다 — 실행 스킬이 본문만 읽고 중간 질문 없이 구현할 수 있을 만큼.
