---
scope:
  include:
    - plugins/project-init/skills/workflow-rule-creator/templates/spec-layout.md
  exclude:
    - plugins/project-init/skills/workflow-rule-creator/SKILL.md
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# workflow-rule-creator spec-layout — SPEC 경로를 질문으로 받기

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

`workflow-rule-creator`(project-init의 workflow 카테고리 sub-룰 디스패처)가 `spec-layout` 산출물을 생성할 때, SPEC 설계 문서의 **per-spec 경로/레이아웃을 고정 텍스트로 박지 말고 사용자에게 질문해 확정**하도록 한다. 형제 생성기(`engineering-rule-creator`의 `versioning` 템플릿이 버전 규약을 묻는 것)와 동형으로, 사용자가 고른 경로 값이 생성되는 `rules/workflow/spec-layout.md` 본문에 반영된다.

질문 범위는 **경로/레이아웃 템플릿(per-spec 디렉터리 경로)뿐**이다. SPEC 이름 규칙의 단일 출처인 `rules/engineering/branch-and-slug.md`의 기본값(`docs/specs/<YYYY-MM-DD>-<slug>/`)을 추천 답으로 제시하고, slug 파생 규칙과 "per-spec 디렉터리 + 그 안 `SPEC.md`" 불변식은 본문에 고정 유지한다.

질문 메커니즘은 새로 발명하지 않는다 — 디스패처가 이미 가진 템플릿 frontmatter `inputs` → `AskUserQuestion` → 본문 `{{name}}` 치환 계약을 그대로 사용한다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

- 항상 `templates/spec-layout.md` frontmatter는 기존 `label`·`description`·`recommended: true`를 보존하면서, 형제 `engineering-rule-creator/templates/versioning.md`와 동형 스키마(`name`·`header`·`question`·`options[{label, description, value}]`)의 `inputs` 한 항목(`name: spec_path`)을 갖는다.
- 항상 `spec_path` 입력의 첫 선택지는 `branch-and-slug.md` 기본 레이아웃(`docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md`)을 가리키는 추천 답이며, 그 `value`는 per-spec **디렉터리** 템플릿(`docs/specs/<YYYY-MM-DD>-<slug>`, 끝의 `/SPEC.md` 제외)이다.
- 항상 `spec-layout.md` 본문의 "저장 위치" 레이아웃 블록은 고정 경로 대신 `{{spec_path}}/SPEC.md`로 표기되어, 디스패처 치환 후 선택된 경로가 본문에 반영된다.
- 항상 "베이스 경로 재정의" 섹션은 baked-in 값과 모순되지 않도록, 선언이 없을 때의 기본을 `{{spec_path}}/SPEC.md`(위 "저장 위치"의 레이아웃)로 참조한다.
- 항상 본문의 "slug 규칙" 섹션, "per-spec 디렉터리 + 그 안 `SPEC.md`" 불변식 문장, engineering 단일 출처(`branch-and-slug.md`) 참조 노트, "위반 발견 시" 섹션은 그대로 보존된다(경로 placeholder 외 의미 변경 없음).
- 첫 선택지(추천)로 생성기를 실행하면 산출 `rules/workflow/spec-layout.md`의 "저장 위치" 블록이 `docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md`로 렌더되어 현행 동작과 동일하다.
- 같은 질문에서 "Other"로 자유 경로(예: `spec/<slug>`)를 입력하면 본문이 `spec/<slug>/SPEC.md`로 렌더되고 slug 규칙·불변식·engineering 참조 노트는 그대로 남는다.
- `spec_path` 응답이 누락·비어 있으면 산출 본문에 `{{spec_path}}` placeholder가 보존된다(형제 정적 입력과 동일 동작).
- 항상 `workflow-rule-creator/SKILL.md`는 변경되지 않는다(디스패처가 이미 `inputs`를 파싱·치환하므로 불필요).

## 범위

포함:
- `plugins/project-init/skills/workflow-rule-creator/templates/spec-layout.md` (frontmatter `inputs` 추가 + 본문 경로 2곳 `{{spec_path}}/SPEC.md` 치환)

비-목표 / 제외:
- `workflow-rule-creator/SKILL.md` 수정 — 디스패처 `inputs` 계약이 이미 존재하므로 불필요(본문별 로직을 SKILL.md에 넣지 않는다는 형제 미러링 제약과도 정합).
- slug 파생 규칙·"per-spec 디렉터리 + `SPEC.md`" 불변식 변경 — branch-and-slug.md 단일 출처이므로 본문 고정.
- `rules/workflow/` 손수 작성, 다른 sub-룰(gates 등) 템플릿 추가.
- `plugin.json`·`marketplace.json` 버전 범프 — 통합 시 통합자가 versioning 규칙대로 처리(워커는 범프하지 않는다).

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)

- frontmatter `inputs`는 형제 `versioning.md`의 스키마·표현을 미러링한다 — 새 입력 키나 디스패처 계약을 발명하지 않는다. `options`는 추천 답을 첫 선택지로 두고 최소 2개를 제공하며, "Other" 자유입력은 디스패처가 자동 제공한다.
- `value`는 per-spec **디렉터리** 템플릿이며 본문이 `/SPEC.md`를 붙여 "그 안 `SPEC.md`" 불변식을 강제한다. 사용자가 디렉터리 경로만 입력하도록 `question`에 명시한다.
- 본문 치환은 경로가 실제로 나타나는 "저장 위치" 블록과 "베이스 경로 재정의"의 기본 참조 문장으로 한정한다. 그 외 의미 텍스트(slug 규칙·불변식·engineering 참조·위반 발견 시)는 건드리지 않는다.
- 경로/slug 규칙은 새로 발명하지 않고 `branch-and-slug.md` 단일 출처와 정합한다(타깃에 그 출처가 없을 수 있으므로 본문이 규칙을 자기완결로 담거나 engineering 카테고리를 참조).

## 위험 (있을 때만)

- **불변식 훼손 위험**: 경로를 placeholder로 바꾸며 "per-spec 디렉터리 + `SPEC.md`" 불변식 문장이나 slug 규칙을 함께 흐리면 산출 룰이 약화된다 → 치환은 경로 표기 2곳으로 한정하고 불변식·규칙 섹션은 그대로 보존한다.
- **계약 발명 위험**: 형제 디스패처에 없는 새 입력 처리 규칙을 SKILL.md에 추가하려는 유혹 → SKILL.md는 손대지 않고 기존 `inputs` 계약만 사용한다.
