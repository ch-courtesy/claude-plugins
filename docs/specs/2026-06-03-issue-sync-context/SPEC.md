---
scope:
  include:
    - plugins/project-init/skills/context-rule-creator/templates/task-ops.md
    - plugins/project-init/skills/context-rule-creator/templates/github-project/task-model.md
    - plugins/project-init/skills/context-rule-creator/templates/filesystem/task-model.md
    - plugins/project-init/skills/context-rule-creator/templates/beads/task-model.md
    - rules/context.md
    - rules/orchestration/issue-sync.md
    - rules/orchestration/forge-integration.md
    - rules/orchestration/task-state-alignment.md
  exclude:
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# issue-sync 지침을 context 카테고리로 재귀속

## 무엇을 만들 것인가

`rules/orchestration/issue-sync.md`가 담고 있던 "설계 문서(SPEC) 본문을 외부 task의 내용으로 동기화한다"는 지침을, **"한 태스크의 실질 내용은 그것이 구현하는 설계 문서다"** 라는 추상으로 재서술해 두 곳에 재귀속한다.

1. **project-init 플러그인의 context 카테고리 템플릿**(타 프로젝트용 산출물): 추상 원칙은 `task-ops` 템플릿에, 백엔드별 표현은 기존 세 `task-model` 변형(github-project·filesystem·beads)에 흡수한다. 이 흡수 콘텐츠는 **벤더 중립**이어야 한다.

2. **이 레포 자신의 룰**(autopilot dogfooding): `rules/orchestration/issue-sync.md`를 제거하고, 그 SPEC→Issue body 동기화 내용을 레포의 단일 출처 `rules/context.md`로 흡수한 뒤, 이를 참조하던 `forge-integration.md`·`task-state-alignment.md`의 참조를 `rules/context.md`로 재지정한다.

project-init 템플릿과 레포 자신의 룰은 별개 산출물이며 구조도 다르다(레포는 모놀리식 `rules/context.md`, 플러그인은 `task-model`+`task-ops` 분리). 두 측을 모두 정합시킨다.

## 완료 조건

- 항상 `plugins/project-init/skills/context-rule-creator/templates/task-ops.md`는 다음 추상 원칙을 담는다: 한 태스크의 실질 내용(목표·범위·수용 기준)은 그것이 구현하는 **설계 문서가 단일 출처**이고, 태스크 레코드에는 설계 문서 **본문을 그대로 복사**해 담으며 링크·경로 참조로 대체하지 않는다. 또한 절차로서 — 최초 작성 시 본문 복사 삽입, 재동기화 시 약속된 마커로 식별되는 영역만 교체하고 영역 밖 사용자 내용은 보존, 비표준 영역·백엔드 한도 초과 시 abort — 를 담고, 구체 마커 문자열은 `task-model`에 위임한다고 명시한다.

- 항상 세 `task-model` 백엔드 변형(`github-project/task-model.md`·`filesystem/task-model.md`·`beads/task-model.md`) 각각은 자기 백엔드 표현으로 설계 문서 **본문을 그대로 복사 임베드**하는 방법을 담고, 동기화 영역을 공통의 벤더 무관 마커 `<!-- spec-sync:begin -->` / `<!-- spec-sync:end -->`로 식별한다(어느 변형도 경로 참조로 대체하지 않는다).

- 항상 project-init이 흡수한 모든 콘텐츠에는 `autopilot` 문자열, 특정 스킬·도구 이름, `autopilot:` 마커 접두사가 하나도 없다(`grep -rin autopilot plugins/project-init/skills/context-rule-creator/templates/` 결과 0건).

- 항상 `rules/orchestration/issue-sync.md` 파일은 존재하지 않는다.

- 항상 `rules/context.md`는 issue-sync.md가 담던 SPEC→Issue body 동기화 지침을 단일 출처로 담는다: 설계 문서(SPEC) 전문을 fence 영역으로 Issue body에 sync하고, 최초 sync는 append·재sync는 fence 사이만 교체·fence 밖 보존, 비표준 body·한도 초과 시 abort 한다는 절차.

- 항상 `rules/orchestration/forge-integration.md`와 `rules/orchestration/task-state-alignment.md`는 `rules/orchestration/issue-sync.md`를 더 이상 참조하지 않고, 이슈 동기화 단일 출처를 `rules/context.md`로 가리킨다.

- …할 때 `rules/` 트리에서 `issue-sync` 문자열을 grep하면(`grep -rn issue-sync rules/`), 매치가 0건이다.

## 범위

포함:
- project-init context 템플릿 4종(task-ops + github-project/filesystem/beads task-model) 흡수.
- 레포 `rules/context.md`로 issue-sync 내용 흡수.
- `rules/orchestration/issue-sync.md` 제거.
- `rules/orchestration/forge-integration.md`·`task-state-alignment.md` 참조 재지정.

비-목표 / 제외:
- `task-state-alignment.md` 자체를 context로 파일 이전하거나 벤더중립화하는 것(이번엔 issue-sync 참조 재지정만 한다).
- `plugins/project-init/plugin.json`·루트 `marketplace.json`의 SemVer 버전 범프(통합 단계에서 통합자가 수행 — 아래 제약 참조).
- `milestones/**`의 frozen 명세(conductor PRD/DAG/C1, 220-spec-externalize-deps)의 issue-sync 참조 수정 — 역사 기록으로 보존한다.

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약

- **벤더 중립(project-init 한정)**: `plugins/project-init/**` 흡수 콘텐츠는 autopilot·특정 도구·`autopilot:` 마커 접두사를 참조하지 않는다. 동기화 마커는 `<!-- spec-sync:begin -->` / `<!-- spec-sync:end -->`. — 단, **레포 자신의 `rules/context.md`는 예외**: 이 레포가 autopilot 프로젝트이고 conductor 마일스톤이 `autopilot:spec-sync` 펜스를 실행 계약으로 검증하므로, `rules/context.md`로 흡수하는 fence는 기존 `<!-- autopilot:spec-sync:begin -->` / `<!-- autopilot:spec-sync:end -->` 마커를 유지한다.
- **consolidate-resplit**: project-init에 새 조각 파일을 추가하지 않는다. 추상 원칙은 task-ops, 백엔드 표현은 기존 task-model 변형에만 흡수한다.
- **본문 복사**: 모든 백엔드에서 설계 문서를 링크·경로 참조로 대체하지 않고 본문을 그대로 복사한다(filesystem 변형도 경로 참조가 아니라 본문 복사 임베드).
- **버전 범프는 통합 단계 책임**: `plugins/project-init/**`를 건드리므로 통합(머지) 단계에서 통합자가 `plugins/project-init/plugin.json`(SoT)과 루트 `marketplace.json`(미러)의 SemVer를 동반 상향한다. 구현 단계(loop)는 버전을 올리지 않는다.

## 위험

- `rules/context.md` fence 흡수 시 마커 접두사 혼동 — 레포 자신은 `autopilot:spec-sync` **유지**, project-init 템플릿은 `spec-sync`(접두사 없음). 두 측 마커를 뒤섞지 않는다.
- `forge-integration.md`는 머리말 괄호 문장(line 5)과 책임 경계 표(line 15) 두 곳에서 issue-sync를 가리킨다 — 둘 다 재지정해야 누락이 없다.
- `filesystem/task-model.md`는 본래 외부 의존 없는 평문 파일 백엔드라 "본문 복사 임베드"가 어색해 보일 수 있으나, 제약상 경로 참조가 아닌 본문 복사를 유지한다.
