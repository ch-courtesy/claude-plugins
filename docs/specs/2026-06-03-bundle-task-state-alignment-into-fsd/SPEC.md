---
scope:
  include:
    - rules/orchestration/task-state-alignment.md
    - plugins/autopilot/skills/fsd/references/task-state-alignment.md
    - plugins/autopilot/skills/fsd/references/forge-integration.md
    - plugins/autopilot/skills/fsd/references/task-backend.sh
    - rules/context.md
    - plugins/autopilot/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - milestones/**
    - CLAUDE.md
    - docs/specs/**
ears_language: ko
---

# task-state-alignment 계약을 fsd 스킬로 번들

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
autopilot fsd 스킬의 번들 references가 repo-root 경로로 인용하던 task 상태 정합 계약을, 그 유일한 소비자인 fsd 스킬과 **함께 다니도록** 스킬 references 안으로 이전한다. 이 계약은 dispatch/loop 오케스트레이터를 위한 autopilot 전용 규칙이면서 저장소 루트의 규칙 디렉터리에 있어, 플러그인이 다른 프로젝트에 설치되면 그 인용 경로가 타깃 프로젝트를 가리켜 단일출처가 부재(dangling)가 된다. 계약을 fsd 스킬 안으로 모아 dangling을 해소하고, 그 이전으로 비게 되는 orchestration 규칙 디렉터리를 정리한다. 이전은 forge-integration 계약을 같은 자리로 모은 선례를 따른다. 범위는 task-state-alignment 한 계약에 한정한다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->
task 상태 정합 계약은 autopilot 오케스트레이터(fsd/dispatch/loop)만 소비하는 전용 규칙이라, 범용 규칙 디렉터리에 두면 플러그인 설치 환경에서 영구 dangling이 된다(project-init이 생성하지 않는 벤더 특화 규칙이므로 타깃에 결코 존재하지 않는다). 계약을 소비자(fsd 스킬)와 함께 배포해 단일출처를 자기완결로 만들고, 메모리에 후속으로 명시된 'fsd 인용 repo-root 룰 dangling' 정리의 첫 건을 닫는다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- 항상 task 상태 정합 계약 문서는 `plugins/autopilot/skills/fsd/references/task-state-alignment.md` 한 파일에 존재하며, 그 본문은 이전 규칙의 no-task-no-work 책임·4분기 상태 정합·새 task 생성·실패 처리를 그대로 담는다.
- 항상 저장소 루트의 `rules/orchestration/task-state-alignment.md`는 더 이상 존재하지 않는다.
- 항상 `rules/orchestration/` 디렉터리는 더 이상 존재하지 않는다(잔여 룰이 없어 빈 디렉터리를 제거하며, orchestration 카테고리가 이 저장소 규칙에서 사라진다).
- 활성 표면(`rules/`·`plugins/`·`CLAUDE.md`)에서 `rules/orchestration/task-state-alignment` 경로 문자열을 검색하면 매치가 없다.
- 항상 fsd 번들 sibling(`forge-integration.md`·`task-backend.sh`)의 task-state-alignment 인용은 같은 references 디렉터리 안의 번들 상대 파일명(`task-state-alignment.md`)을 가리킨다.
- 항상 `rules/context.md`의 task-state-alignment 인용은 새 번들 경로(`plugins/autopilot/skills/fsd/references/task-state-alignment.md`)를 가리킨다.
- 항상 autopilot 플러그인 버전은 `plugins/autopilot/.claude-plugin/plugin.json`(단일 출처)과 루트 `.claude-plugin/marketplace.json`의 autopilot 항목(미러) 둘 다에서 동일하게 `0.18.1`이다(origin/main의 `0.18.0`에서 PATCH 범프; 머지로 베이스가 올라가 재범프).
- `plugins/autopilot/skills/fsd/references/task-backend.sh`는 인용 주석 1줄만 갱신되고 스크립트 로직은 변경되지 않는다(무회귀).

## 범위
포함:
- `rules/orchestration/task-state-alignment.md` 본문을 `plugins/autopilot/skills/fsd/references/task-state-alignment.md`로 이전(번들본 작성 + repo-root 원본 삭제).
- 비게 된 `rules/orchestration/` 디렉터리 제거.
- 활성 인용 4곳을 번들 경로로 갱신 — `forge-integration.md`(line 5·15), `task-backend.sh`(line 7)는 같은 디렉터리 상대 파일명으로, `rules/context.md`(line 81)는 새 번들 절대경로로.
- autopilot 플러그인 버전 PATCH 범프(plugin.json SoT + marketplace.json 미러 함께).

비-목표 / 제외:
- task-state-alignment 본문 내용 변경 — 이동만 하며 본문은 그대로 보존(일반화·de-vendor 안 함).
- task-state-alignment 본문이 인용하는 `rules/context.md`(3곳) 변경 — forge-integration 선례와 동일하게 '플러그인 파일 → 벤더 중립 repo-root 규칙' 패턴이므로 그대로 둔다.
- 나머지 6종 fsd-인용 repo-root 룰(context·branch-and-slug·versioning·review·change-adoption·issue-sync) — 이번 범위 밖(벤더 중립은 타깃에 project-init 공존 시 해소).
- 역사 기록(`docs/specs/**`·`milestones/**`)의 task-state-alignment 언급 — 이번은 삭제가 아니라 이동이라 작성 시점 기준 기록은 그대로 정확하다. point-in-time 기록으로 보존한다.
- `rules/engineering/branch-and-slug.md`(머지 절차 단일출처) 수정.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 계약 본문은 **그대로 이전**한다 — autopilot 전용 계약이므로 일반화하지 않고, 내부 교차참조(`rules/context.md`)도 변경하지 않는다.
- 버전 범프는 SoT(`plugins/autopilot/.claude-plugin/plugin.json`)와 미러(루트 `.claude-plugin/marketplace.json`)를 같은 변경에서 함께 올린다(SemVer PATCH — 동작 변화 없는 출처 재배치). 단일 출처 규칙은 `rules/engineering/versioning.md`.
- git 반영(브랜치·commit·main 동기화)은 직접 main 편집 없이 프로젝트 규칙(`rules/engineering/branch-and-slug.md`)을 따르며 force push를 쓰지 않는다.

## 위험 (있을 때만)
- `rules/orchestration/` 제거로 orchestration 카테고리가 이 저장소 규칙에서 사라진다 — repo CLAUDE.md의 카테고리 로딩은 `rules/` 하위를 동적으로 읽고 orchestration을 하드코딩하지 않으므로(확인됨) 깨지지 않는다.
- 이전 후 `rules/context.md`가 플러그인 내부 경로를 인용하게 된다 — 단 context.md는 이미 issue-sync trigger 등 autopilot 특화 동작을 기술하는 autopilot-aware 규칙이므로 벤더 중립 계층이 플러그인을 가리키는 위반이 아니다.
