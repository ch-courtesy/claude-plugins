---
scope:
  include:
    - plugins/project-init/skills/workflow-rule-creator/templates/spec-layout.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
depends_on: ["workflow-rule-creator-spec-layout"]
# ears_language: ko
---

# workflow-rule-creator spec-layout: SPEC 승인 후 main 머지 게이트

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

workflow-rule-creator의 `spec-layout` 템플릿 본문을 확장해, 타깃 프로젝트에 설치되는 `rules/workflow/spec-layout.md`가 SPEC 설계 문서의 **경로/레이아웃**에 더해 **머지 타이밍 게이트** — "SPEC 최종 승인 → 구현 착수 전 그 SPEC 문서를 `main`에 반영 → 그 뒤에야 구현 제안" 순서 — 를 함께 정의하도록 한다. 새 sub-룰 템플릿을 신설하지 않고 기존 spec-layout **한 템플릿의 본문만** 키운다.

이 게이트는 **타이밍/순서만** 소유한다. 머지의 git 기계(브랜치 생성·SPEC 문서만 commit·`main` ff-merge·origin 동기화·force push 금지·실패 시 PR 전환)는 정의하지 않고 `version-control`·`engineering` 카테고리에 위임한다. 이는 이 레포가 이미 dogfood로 따르는 분리 — 타이밍은 `rules/orchestration/approved-spec-merge.md`, 기계는 `rules/engineering/branch-and-slug.md` — 를 타깃 프로젝트용 sub-룰로 미러링한 것이다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

- 항상 `templates/spec-layout.md` 본문에 "SPEC 최종 승인 → 구현 착수 전 그 SPEC 문서를 `main`에 반영 → 그 뒤 구현 제안" 순서를 규정하는 머지 게이트 절이 존재한다.
- 항상 그 절은 머지의 git 기계(브랜치 생성·commit 범위·ff-merge·push·force push 금지·실패 처리)를 직접 규정하지 않고 `version-control`·`engineering` 카테고리에 위임하며, 타깃에 그 출처가 없을 수 있으므로 해당 카테고리를 먼저 생성하라는 자기완결 안내 문구를 포함한다.
- 항상 그 절은 머지 권한 출처를 **SPEC 최종 승인 하나**로 명시하고, 머지 직전 별도의 머지 확인 질문을 추가하지 않는다.
- spec-layout sub-룰을 골라 workflow-rule-creator를 실행하면, 타깃 `rules/workflow/spec-layout.md`에 기존 경로/레이아웃 절과 새 머지 게이트 절이 **함께** 기록되고, 그 내용이 템플릿의 frontmatter 제거 본문과 일치한다.
- 항상 이 변경 후에도 디스패처 계약이 유지된다 — 한 호출 = 한 sub-룰, 같은 실행에서 `rules/workflow/` 밖 파일 미접촉, SKILL.md·다른 템플릿 미수정.

## 범위
포함:
- `plugins/project-init/skills/workflow-rule-creator/templates/spec-layout.md` 본문에 머지 타이밍 게이트 절 추가(타이밍만 정의, 머지 기계는 위임).

비-목표 / 제외:
- 새 sub-룰 템플릿 신설(`spec-merge` 등) — 사용자 결정으로 기존 spec-layout 본문 확장만 수행.
- SKILL.md·sibling 생성기·다른 템플릿 수정 — 디스패처 계약 불변.
- 머지 git 기계 정의 — `version-control`/`engineering`에 위임(중복 정의 금지).
- 이 레포 자체 `rules/workflow/` 손수 작성 — 본 산출물은 *생성기 템플릿*이지 이 레포의 dogfood 룰이 아니다.
- `plugin.json` 버전 범프 — 통합 시 통합자가 `rules/engineering/versioning` 규칙대로 처리(워커는 범프하지 않음).

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)

- 이 단위는 선행 spec-layout 단위(`workflow-rule-creator-spec-layout`)가 만든 `templates/spec-layout.md`가 존재함을 전제로 그 본문을 확장한다(`depends_on`). 선행 단위가 정의한 경로/레이아웃 절은 보존하고 머지 게이트 절을 덧붙인다.
- **선행 spec-layout SPEC 제약의 명시적 개정.** 선행 SPEC은 "spec-layout은 산출물 경로/레이아웃에만 한정하고 머지는 version-control에 위임"(제약 + "책임 중복 위험")이라 못박았다. 본 단위는 이를 **이 지점에서 의도적으로 개정**한다 — spec-layout이 머지 *타이밍 게이트*는 소유하되 머지 *기계*는 여전히 위임한다. 이는 스파인 모델("게이트는 정의만, 기계는 축에 위임")과 정합하며 조용한 위반이 아니다.
- 머지 절차를 새로 발명하지 않는다. 게이트 문구는 `rules/orchestration/approved-spec-merge.md`의 타이밍 vs 기계 분리를 미러링하고, 기계는 `rules/engineering/branch-and-slug.md`·`version-control` 카테고리를 참조한다.
- 템플릿 frontmatter(`label`·`description`)와 디스패처가 본문을 그대로 복사하는 계약은 sibling 생성기 규약을 따른다 — SKILL.md에 본문별 로직을 넣지 않는다. `allowed-tools`는 변경하지 않는다.

## 위험 (있을 때만)

- **책임 중복 위험(재발).** 머지 게이트가 `version-control`의 머지 정책과 겹쳐 보일 수 있다 → 본 절은 *타이밍/순서*만 규정하고 git 기계는 명시적으로 위임해 중복 정의를 피한다. 위임 대상이 타깃에 없을 때를 위한 자기완결 안내로 깨진 참조를 막는다.
- **선행 의존 위험.** spec-layout 템플릿이 아직 없으면 확장 대상이 없다 → `depends_on`으로 순서를 강제하고, dispatch가 spec-layout 단위 완료 후 본 단위를 실행한다.
