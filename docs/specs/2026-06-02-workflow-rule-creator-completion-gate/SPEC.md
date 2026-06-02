---
scope:
  include:
    - plugins/project-init/skills/workflow-rule-creator/templates/completion-gate.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# workflow-rule-creator 완료 게이트 (completion-gate)

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

`workflow-rule-creator` 생성기(project-init 플러그인)에 **완료 단계 게이트 sub-룰 템플릿 하나**를 추가한다. 이 템플릿은 타깃 프로젝트에서 선택·기록되면 개발 워크플로 척추(설계 → 구현 → 리뷰 → 반복 → **완료**)의 **완료 단계 게이트**를 정의하는 워크플로 sub-룰이 된다.

이 sub-룰이 규정하는 것은 오직 **흐름·전이·위임 경계**다: "리뷰가 통과 게이트를 넘으면 → 완료 단계로 전이하고 → 변경 통합(머지)과 머지 후 정리가 수행된다"는 **순서와 전이 조건과 책임 위임선**만 고정한다. 머지·정리의 **기계적 절차**는 규정하지 않고 다른 카테고리에 위임한다 — 변경 통합·머지는 version-control, 작업 상태 전이는 context, 빌드·버전은 engineering. 이는 워크플로 척추의 "게이트는 정의만, 기계는 위임" 원칙을 완료 단계에 적용한 것으로, 기존 `spec-layout`(설계 단계 산출물 레이아웃)과 같은 카테고리 아래 나란히 누적되는 두 번째 sub-룰이다.

생성기는 기존 디스패처 그대로 `templates/*.md`를 자동 열거하므로, 이 템플릿 파일 추가만으로 후보에 나타난다. SKILL.md·bootstrap·기존 템플릿은 건드리지 않는다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

- 항상 `plugins/project-init/skills/workflow-rule-creator/templates/completion-gate.md`가 존재하며 필수 frontmatter `label`과 `description`을 가지고, `recommended` 키는 갖지 않는다(템플릿당 하나만 허용되며 이미 `spec-layout`이 보유).
- 항상 이 템플릿 본문은 **완료 단계 게이트만** 규정한다 — 리뷰 통과 게이트 조건, 완료 단계로의 전이, 그리고 머지·머지 후 정리·작업 상태 전이의 위임 경계. base sync·push·PR 생성·승인·머지·cleanup 같은 **구체 통합/정리 명령이나 절차를 본문에 담지 않는다.**
- 항상 본문은 형제 템플릿(`spec-layout`)과 동형 형식으로 "규정하는 것(또는 적용 범위) / 규정하지 않는 것(위임) / 위반 발견 시" 절을 포함하고, 변경 통합·머지는 version-control, 작업 상태 전이는 context, 빌드·버전은 engineering 카테고리가 단일 출처임을 명시 위임한다.
- `workflow-rule-creator` 생성기를 실행해 `completion-gate`를 선택하면 타깃에 `rules/workflow/completion-gate.md`가 생성되고, 그 내용이 템플릿 본문(frontmatter 제거)과 일치한다.
- 템플릿이 둘(`spec-layout` + `completion-gate`)인 상태에서 생성기를 실행하면 디스패처가 single-select 질문을 띄우고, `recommended`인 `spec-layout`이 맨 앞에 오며 `completion-gate`가 선택지로 나타난다 — **한 호출 = 한 sub-룰** 계약이 SKILL.md 변경 없이 유지된다.

## 범위

포함:
- `plugins/project-init/skills/workflow-rule-creator/templates/completion-gate.md` (게이트 sub-룰 템플릿, 형제 `spec-layout` 미러링)

비-목표 / 제외:
- `SKILL.md` 수정 — 디스패처가 `templates/*.md`를 자동 열거하므로 불필요(기존 spec-layout 단위의 완료 조건과 정합).
- 기존 `spec-layout.md` 수정 — 산출물 레이아웃 전용 책임을 유지하고 머지/정리 절을 덧붙이지 않는다.
- bootstrap SKILL.md 수정 — 자동 탐색이라 불필요.
- `plugin.json`·`marketplace.json` 버전 범프 — 통합 시 통합자가 `rules/engineering/versioning` 규칙대로 처리(워커는 범프하지 않음).
- 이 레포 자체 `rules/workflow/` 손수 작성 — 본 산출물은 *생성기 템플릿*이지 이 레포의 dogfood 룰이 아니다.
- `gates` 외 다른 sub-룰 템플릿 — 후속 단위.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)

- 템플릿은 형제 생성기 템플릿(`spec-layout`)의 frontmatter 키 구성·본문 절 구성을 미러링하고, 게이트 내용만 다르게 한다. 형제에 없는 새 frontmatter 계약(새 입력 종류 등)을 발명하지 않는다 — `inputs`/`dynamic_inputs`는 두지 않고 자기완결 게이트 텍스트로 한다(`spec-layout`도 입력 없음).
- "게이트는 정의만, 기계는 위임" 경계를 지킨다 — 구체 머지/정리 명령·절차는 이미 `rules/orchestration/forge-integration.md`(호출 레이어 통합 흐름)와 version-control 카테고리가 단일 출처이므로, 본문은 그것을 **중복 정의하지 않고 카테고리 이름으로 위임만** 한다.
- 자기완결성: 타깃 프로젝트에 version-control·context 카테고리 룰이 아직 없을 수 있으므로, 위임 대상을 카테고리 이름으로 참조하되 게이트의 *의도*(무엇이 게이트이고 어디로 전이하는지)는 본문 안에서 자기완결로 읽히게 한다.

## 위험 (있을 때만)

- **책임 중복 위험**: 게이트 sub-룰이 머지/정리의 기계적 절차를 떠안으면 version-control·`forge-integration.md`와 충돌해 모호성이 늘어난다 → 본문은 흐름·전이·위임 경계만, 기계는 축에 위임으로 한정한다.
- **디스패처 회귀 위험**: 두 번째 템플릿 추가가 디스패처의 single-select 동작이나 `recommended` 정렬을 깨면 안 된다 → SKILL.md를 변경하지 않고 기존 계약(자동 열거·recommended 우선)에 의존하며, 완료 조건의 마지막 항목으로 이를 검증한다.
- **선행 산출물 의존**: 이 게이트 sub-룰은 `workflow-rule-creator` 생성기(SKILL.md + 기존 `spec-layout` 템플릿) 위에 얹힌다. 그 생성기는 이미 origin/main에 머지되어 있으므로(spec-layout 단위 완료) 별도 선행 단위 대기는 필요 없고, 본 단위는 origin/main을 베이스로 단독 진행한다. 다만 디스패처가 두 템플릿을 동형으로 다루도록 SKILL.md를 변경하지 않는다는 제약은 그대로 적용된다.
