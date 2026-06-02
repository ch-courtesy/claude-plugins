---
scope:
  include:
    - plugins/project-init/skills/workflow-rule-creator/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# workflow-rule-creator (spec-layout)

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

project-init 플러그인에 **`workflow` 카테고리 생성기**(`workflow-rule-creator`)를 신설한다. 이 카테고리는 하나의 변경이 **설계 → 구현 → 리뷰 → 반복 → 완료**로 진행하는 개발 워크플로의 "얇은 척추(spine)"다 — 흐름·게이트와 단계별 영속 설계 산출물(SPEC 등)의 **경로/레이아웃**만 소유하고, 기계적 관심사는 기존 직교 축에 **위임**한다: 작업 상태 추적은 `context`, 변경 통합·머지는 `version-control`, 빌드·버전은 `engineering`.

이 생성기는 형제 생성기(`workspace`/`engineering`/`context`/`version-control`-rule-creator)와 **동형인 템플릿 디스패처**다 — `templates/*.md` 중 하나를 골라 타깃 프로젝트의 `rules/workflow/<sub>.md`로 기록한다. 초기 릴리스는 템플릿 **하나**, `spec-layout`만 싣는다: 타깃 프로젝트에서 SPEC 설계 문서가 어디에 어떤 레이아웃으로 사는지를 정의하는 산출물 sub-룰이다. 게이트(흐름·반복 종료·위임 경계) 등 다른 sub-룰은 SKILL.md 수정 없이 후속 템플릿으로 추가한다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

- 항상 `plugins/project-init/skills/workflow-rule-creator/SKILL.md`가 존재하며, 호출되면 자기 옆 `templates/*.md` 중 선택된 sub-룰 하나의 본문(frontmatter 제거)을 타깃의 `rules/workflow/<sub>.md`로 기록한다.
- 항상 이 SKILL.md는 형제 rule-creator와 동형 계약을 따른다 — 템플릿 열거 → frontmatter 파싱 → 선택 → 입력 → 기록의 디스패처 절차, **한 호출 = 한 sub-룰**, 기존 파일은 diff 제시 후 사용자 명시 동의가 있을 때만 덮어씀, 같은 실행에서 `rules/workflow/` 밖 파일은 만지지 않음.
- 항상 `templates/spec-layout.md`가 존재하고 필수 frontmatter(`label`, 그리고 `description`)를 가지며, 본문은 타깃 프로젝트의 SPEC 설계 문서 위치/레이아웃(`docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md`)을 정의한다.
- bootstrap이 카테고리를 열거할 때, `*-rule-creator/` 접미사 자동 탐색만으로 `workflow`가 후보에 나타난다(bootstrap SKILL.md 수정 없이).
- `spec-layout` sub-룰을 선택해 생성기를 실행하면 타깃에 `rules/workflow/spec-layout.md`가 생성되고, 그 내용이 템플릿 본문(frontmatter 제거)과 일치한다.

## 범위

포함:
- `plugins/project-init/skills/workflow-rule-creator/SKILL.md` (형제 디스패처 미러링, 카테고리 경로만 `rules/workflow/`)
- `plugins/project-init/skills/workflow-rule-creator/templates/spec-layout.md`

비-목표 / 제외:
- `gates` 및 기타 sub-룰 템플릿 — 후속 작업(디스패처가 SKILL.md 수정 없이 템플릿 추가를 지원하므로 별도 단위로 분리).
- 이 레포 자체 `rules/workflow/` 손수 작성 — 본 산출물은 *생성기*이지 이 레포의 dogfood 룰이 아니다.
- `plugin.json` 버전 범프 — 통합 시 통합자가 `rules/engineering/versioning` 규칙대로 처리(워커는 범프하지 않음).
- bootstrap SKILL.md 수정 — 자동 탐색이라 불필요.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)

- SKILL.md는 형제 생성기(workspace/engineering 등)의 디스패처 구조·문구를 미러링하고 카테고리 경로(`rules/workflow/`)·카테고리 설명만 바꾼다. 본문별 로직을 SKILL.md에 넣지 않는다(템플릿 본문은 그대로 복사). `allowed-tools`는 형제 생성기와 동일 집합.
- spec-layout 템플릿의 slug·경로 규칙은 **새로 발명하지 않는다** — `docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md` 레이아웃과 slug 파생은 기존 단일 출처(`rules/engineering/branch-and-slug.md`)와 정합해야 하며, 타깃 프로젝트에 그 출처가 없을 수 있으므로 템플릿이 규칙을 자기완결로 담거나 `engineering` 카테고리를 명시적으로 참조한다.
- 스파인의 "게이트는 정의만, 기계는 위임" 경계를 산출물 레이어에도 적용한다 — spec-layout은 상태 추적(context)·머지(version-control)·빌드(engineering)의 책임을 중복 정의하지 않고 산출물 *경로/레이아웃*에 한정한다.

## 위험 (있을 때만)

- **책임 중복 위험**: workflow가 리뷰·완료를 직접 규정하면 version-control·context와 충돌해 모호성이 늘어난다 → 스파인은 게이트 정의만, 기계는 축에 위임으로 한정한다(본 단위의 spec-layout은 산출물 경로에만 관여).
- **계약 발명 위험**: 형제 생성기에 없는 새 디스패처 규칙을 임의로 강요하면 안 된다 → 미러링이 기본, 차이는 카테고리 경로/설명뿐.
