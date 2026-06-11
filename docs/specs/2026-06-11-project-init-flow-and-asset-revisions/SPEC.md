---
scope:
  include:
    - plugins/project-init/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# project-init 대화형 흐름·산출 기본값 수정 (11개 항목)

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

project-init 플러그인의 **bootstrap** 및 다섯 개 rule-creator 스킬(**context-rule-creator**, **review-rule-creator**, **version-control-rule-creator**, **workflow-rule-creator**, **workspace-rule-creator**)의 대화형 질문 흐름과 일부 생성 산출물을, 아래 "완료 조건"에 나열한 11개 항목에 따라 수정한다. 구체적 파일 경로·구현 방식은 제약 절에 위임한다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->

project-init 스킬군의 대화형 질문 흐름과 생성 기본값을 사용자 의도에 맞게 단순화·자동화하고, `AskUserQuestion` 도구의 옵션 개수 제약(1-옵션 multiSelect 불가)을 견고하게 처리하며, 생성물에서 불필요한 출처 주석을 제거하기 위함이다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. **(bootstrap · 카파시 출처 줄)** 항상: bootstrap이 조립하는 AGENTS.md의 카파시 룰 블록은 출처 attribution 인용 줄(`> 안드레이 카파시 ... (2026-05-30 시점 스냅샷)`)을 포함하지 않는다 — 단일 출처 자산에서 그 줄이 제거되어, 카파시 블록은 H1 다음 곧바로 첫 H2(`## 코딩 전에 생각하기`)로 이어진다.

2. **(bootstrap · 벤더 선택)** 벤더 선택을 물을 때, 현재 실행 벤더를 제외한 나머지 벤더가 2개 이상이면 multiSelect 질문으로, 정확히 1개이면 그 벤더의 포함/제외 single-select 질문으로 제시한다. 어느 경우에도 1-옵션 multiSelect를 도구에 보내지 않는다.

3. **(context · 상태 집합 질문 제거)** context-rule-creator를 실행할 때, 상태 집합을 고르는 첫 질문(①)을 제시하지 않으며, `{{state_set}}` 값은 이벤트별 목표 상태(②) 답들의 합집합으로 도출되어 task-model 본문에 채워진다.

4. **(context · 이벤트 추천 기본)** context-rule-creator가 이벤트별 목표 상태를 물을 때, '태스크 최초 등록' 이벤트의 추천(첫) 선택지는 `in_design`이고, '계획/스펙 문서 생성' 이벤트의 추천(첫) 선택지는 `backlog`이다.

5. **(context · 승인 게이트 제거)** 항상: context-rule-creator는 신규 `task-model.md`·`task-ops.md`를 기록하기 전에 "이 내용으로 기록할까요" 류의 별도 승인 질문을 하지 않고 곧바로 기록한다. 기존 파일이 있을 때의 덮어쓰기 diff 확인 절차는 그대로 유지한다.

6. **(context · Project URL 직접 조회)** github-project 백엔드가 선택될 때, 스킬이 `gh`로 GitHub Project URL/번호를 직접 조회해 `{{project_url}}`을 실제 값으로 채운다 — 사용자에게 URL을 묻거나 TODO 마커만 남기지 않는다. 조회가 실패하거나 인증되지 않으면(오류), TODO 마커로 폴백하고 그 사실을 사용자에게 알린다.

7. **(review · 진입점 분리)** 항상: bootstrap의 카테고리 자동 열거(`*-rule-creator` 형제 스캔)는 review-rule-creator를 후보에서 제외한다 — review 지침 생성은 bootstrap 흐름이 자동 호출하지 않고, review-rule-creator의 독립 진입점(자체 스킬 호출)으로만 수행된다.

8. **(version-control · 전 서브룰 순서 생성)** version-control-rule-creator를 실행할 때, 어느 서브 지침을 쓸지 묻는 선택 질문 없이 적용 가능한 모든 서브 지침을 고정 순서(`review-approval` → `branch-naming` → `git`, git은 git 계열일 때만)로 생성한다. 각 서브 지침의 자체 inputs(머지 방식·정책 등)는 그대로 묻는다.

9. **(version-control · force push 폴백)** force push 정책 입력의 제시 가능한 옵션이 1개뿐이면, multiSelect 대신 허용/금지 single-select로 제시한다 — 1-옵션 multiSelect를 도구에 보내지 않는다.

10. **(workflow · 전 서브룰 순서 생성)** workflow-rule-creator를 실행할 때, 어느 서브 지침을 쓸지 묻는 선택 질문 없이 적용 가능한 모든 서브 지침을 고정 순서(`spec-layout` → `stage-gates`)로 생성한다. 각 서브 지침의 자체 inputs는 그대로 묻는다.

11. **(workspace · 임시 경로 입력)** workspace-rule-creator를 실행할 때, 임시 파일 경로를 입력으로 받아 temp-files 본문의 임시 디렉터리 경로를 그 값으로 채운다. 입력이 없거나 비면(오류) 기본값 `.tmp/`를 쓴다.

12. **(공통 · 버전 동반)** 항상: 위 변경은 `plugins/` 워치 디렉터리를 수정하므로, 같은 변경 안에서 project-init 플러그인 버전 단일 출처(`plugins/project-init/.claude-plugin/plugin.json`)와 그 미러(`.codex-plugin/plugin.json`, `.claude-plugin/marketplace.json`의 project-init 항목)를 동일한 값으로 SemVer 증가시킨다.

## 범위
포함:
- `plugins/project-init/**` — bootstrap 및 5개 rule-creator 스킬의 SKILL.md, 관련 자산(`shared/bootstrap/assets/`), 영향 템플릿(`*/templates/`), 플러그인 버전 매니페스트.

비-목표 / 제외:
- 이미 생성된 이 레포의 산출물(`/workspace/claude-plugins/AGENTS.md`, `rules/**`)은 수정하지 않는다 — 스킬 소스만 고친다.
- 플러그인 cache 카피, `.claude/worktrees/**`, `docs/specs/**/.worktree/**` 의 비-정식 카피는 건드리지 않는다.
- review-rule-creator를 별도 플러그인/패키지로 외부 분리하는 작업은 범위 밖 — 항목 7은 "bootstrap 자동 열거에서 제외 + 독립 진입점 유지"까지다.
- 각 rule-creator의 "템플릿 본문은 그대로 복사" 계약을 바꾸는 것은 범위 밖 — 항목 11의 경로 placeholder 추가만 예외로 허용한다.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- **정식 소스만 수정**: `plugins/project-init/**`의 정식 파일만 고친다. cache·워크트리·`.worktree` 카피는 손대지 않는다.
- **도구 제약 준수**: `AskUserQuestion`은 옵션 2–4개를 요구한다. 항목 2·9의 single-select 폴백은 1-옵션 multiSelect 금지라는 이 제약을 충족하기 위한 것이며, 모든 질문은 옵션 2–4개를 유지해야 한다.
- **템플릿 계약 보존**: 항목 11을 제외하고, rule-creator 템플릿 본문은 placeholder 치환 외 변형 없이 그대로 복사하는 기존 계약을 유지한다. 항목 11은 temp-files 템플릿에 경로 placeholder(예: `{{temp_path}}`)를 도입한다.
- **기존 테스트 정합**: 각 스킬의 `tests/*.test.sh`가 계속 통과해야 한다. 출처 줄·승인 게이트·서브룰 선택 질문의 존재를 단언하는 테스트가 있으면 본 변경에 맞춰 함께 갱신한다.
- **버전 범프 출처**: 항목 12의 버전 증가·미러 일치는 `rules/engineering/versioning.md`·`rules/version-control/review-approval.md` 단일 출처를 따른다.

## 위험 (있을 때만)
- **항목 4의 흐름 부작용**: '최초 등록→in_design, 계획문서→backlog' 추천은 자동 구성되는 기본 흐름(transition_order)을 `in_design → backlog → in_progress → review → done`처럼 비직관적 순서로 만들 수 있다. 추천 기본값일 뿐 사용자가 override 가능하나, task-ops의 "기본 흐름" 표기가 어색해지는지 구현 시 검토가 필요하다.
- **항목 6의 외부 의존**: `gh` 직접 조회는 인증·권한·복수 Project 모호성에 의존한다. 비인증·조회 실패·다수 후보 시의 폴백(TODO 마커 + 사용자 안내)이 견고해야 한다.
- **항목 7의 계약 충돌**: bootstrap step 6의 "`*-rule-creator` 전부 열거" 계약·테스트와 충돌할 수 있다 — 제외 로직이 기존 테스트를 깨면 테스트도 갱신해야 한다.
- **광범위 단일 SPEC**: 6개 스킬에 걸친 단일 SPEC이라 구현·리뷰 단위가 크다. dispatch 시 N=1 단일 작업으로 처리되며, 항목 간 독립성에도 불구하고 한 번에 통합된다.
