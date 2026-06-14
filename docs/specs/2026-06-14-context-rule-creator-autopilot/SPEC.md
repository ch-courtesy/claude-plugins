---
scope:
  include:
    - plugins/autopilot/**
    - plugins/project-init/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# context-rule-creator를 autopilot 플러그인으로 이관

## 무엇을 만들 것인가
프로젝트의 컨텍스트 관리 지침(task-model·task-ops)을 생성하는 `context-rule-creator` 스킬을 `project-init` 플러그인에서 `autopilot` 플러그인으로 옮긴다. 스킬의 동작(백엔드 템플릿 열거 → 백엔드 선택 → 입력·이벤트별 목표 상태 수집 → `rules/context/task-model.md`·`task-ops.md` 생성·갱신)은 그대로 보존하고, **소유 플러그인만** 바꾼다. 이전 뒤 `project-init`은 task 관련 컨텍스트 지침 생성을 더 이상 소유하지 않으며, `project-init:bootstrap`의 자동 카테고리 생성 흐름에서도 컨텍스트 규칙 생성이 사라진다. autopilot은 이 컨텍스트 규칙 생성을 독립 진입점(직접 호출)으로 소유한다. 두 플러그인과 다른 스킬에 남은 `context-rule-creator`/`project-init:context` 교차 참조를 새 소유 위치에 맞게 정정한다.

## 목적 (왜)
task 라이프사이클 흐름(spec→dispatch→loop)이 이미 autopilot에 있는데 task 모델·운영 규율을 **생성하는** 책임만 project-init에 떨어져 있어 task 관련 지침이 두 플러그인에 흩어져 있다. 생성기를 autopilot으로 모아 "task 컨텍스트 지침은 task 워크플로 플러그인(autopilot)이 소유한다"는 단일 응집점을 만들고, project-init은 task와 무관한 나머지 카테고리 지침 생성만 맡도록 책임 경계를 깔끔히 한다.

## 완료 조건
- autopilot 플러그인에 `context-rule-creator` 스킬(SKILL.md·README.md·`templates/` 전체)이 존재하고, 호출하면 백엔드를 선택해 `rules/context/task-model.md`와 `rules/context/task-ops.md`를 이전과 동일한 내용·레이아웃으로 생성·갱신한다.
- `templates/` 아래 백엔드별 task-model 템플릿과 공유 task-ops 템플릿이 함께 이전되어, 백엔드-무관 생성기 성격(여러 백엔드 템플릿 중 하나 선택)이 보존된다.
- 이관이 끝나면 `project-init` 플러그인에는 `context-rule-creator` 스킬이 더 이상 존재하지 않는다.
- `project-init:bootstrap`의 카테고리 자동 생성 흐름을 실행할 때 컨텍스트 규칙 생성이 후보·호출 대상에 나타나지 않으며, 나머지 카테고리 rule-creator의 열거·호출은 이전과 동일하게 동작한다.
- repo의 라이브 스킬·문서에서 `context-rule-creator`를 가리키는 교차 참조가 새 소유 위치(autopilot)를 가리키도록 정정되어 있고, `project-init` 소유로 잘못 가리키는 참조가 남아 있지 않다.
- autopilot 플러그인 버전이 프로젝트 버전 관리 규칙에 따라 올바르게 범프되어 있다.

## 범위
포함:
- `context-rule-creator` 스킬 자산(SKILL.md·README.md·`templates/`)을 project-init에서 autopilot으로 이전.
- `project-init:bootstrap`이 컨텍스트 규칙 생성을 자동 흐름에서 제외하도록 정합(스킬이 디렉터리에서 사라지는 데 따른 자연 제외 포함, 부수 문구·요약 정정).
- project-init의 형제 rule-creator(engineering·review 등) 및 기타 라이브 문서에 남은 `context-rule-creator` 교차 참조 정정.
- 두 플러그인의 매니페스트·버전 등 소유 플러그인 변경에 수반되는 메타데이터 갱신.

비-목표 / 제외:
- 생성되는 `rules/context/task-model.md`·`task-ops.md`의 **내용·형식 변경**(이번엔 소유 위치 이전만 한다 — 산출물은 동일).
- task-model·task-ops 지침 자체를 autopilot 스킬 본문에 인라인으로 박는 것(생성기를 옮길 뿐, 생성기가 만드는 per-project 산출물 구조는 유지).
- project-init의 나머지 5개 rule-creator(engineering·review·version-control·workflow·workspace)의 위치·동작 변경.
- autopilot에 새로운 init/setup 오케스트레이션 흐름을 신설하는 것(스킬은 직접 호출 진입점으로 독립 동작한다 — bootstrap 같은 자동 오케스트레이터를 새로 만들지 않는다).
- 과거 `docs/specs/**` 이력 문서의 `context-rule-creator` 언급 정정(이력은 보존).

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 스킬 디렉터리명은 이전 후에도 `context-rule-creator`로 유지한다(설명·교차 참조의 안정성). autopilot 내 경로는 `plugins/autopilot/skills/context-rule-creator/`.
- 스킬 SKILL.md frontmatter의 `description`은 새 소유 플러그인 맥락(autopilot)에 맞게 갱신하되, 활성화 트리거 표현은 보존한다.
- `project-init:bootstrap`은 `project-init/skills/*-rule-creator/`를 자동 열거하므로 디렉터리가 옮겨가면 자동으로 후보에서 빠진다 — bootstrap 본문에 컨텍스트 규칙을 가리키는 잔여 문구가 있으면 그것만 정정하고, 동작 로직을 새로 추가하지 않는다.
- 버전 범프와 변경 통합 절차는 프로젝트 규칙(`rules/engineering`·`rules/version-control`)을 단일 출처로 따른다.

## 위험
- bootstrap이 형제 디렉터리 자동 열거에 의존하므로, 이전이 불완전하면(예: 일부 자산만 옮김) 컨텍스트 규칙 생성이 어느 플러그인에서도 동작하지 않을 수 있다 — SKILL.md·README.md·`templates/`를 한 단위로 함께 옮겨야 한다.
- project-init의 형제 rule-creator가 `context-rule-creator`를 패밀리의 일부로 교차 참조하므로, 정정 누락 시 사라진 스킬을 가리키는 깨진 참조가 남는다.
