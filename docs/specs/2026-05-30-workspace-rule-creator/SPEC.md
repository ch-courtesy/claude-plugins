---
scope:
  include:
    - plugins/project-init/skills/workspace-rule-creator/SKILL.md
    - plugins/project-init/skills/workspace-rule-creator/templates/temp-files.md
    - plugins/project-init/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# workspace-rule-creator 스킬

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

`project-init` 플러그인에 새 형제 rule-creator 스킬 `workspace-rule-creator`를 추가한다. 이 스킬은 형제 `engineering-rule-creator`와 동일한 **템플릿 디스패처** 모델로, 새 `workspace`(작업공간 위생) 카테고리 디렉터리 아래 sub-룰을 호출마다 하나씩 누적한다.

- 첫 sub-룰은 **임시 파일 관리(`temp-files`)** 다. 이 룰은 임시·스크래치 파일을 **프로젝트 트리 내부의 전용 디렉터리**에 두고 버전 관리에서 제외하는 정책을 규정한다.
- 임시 파일 저장 경로 정책은 **프로젝트 안(gitignore된 전용 디렉터리)** 단일 정책으로 고정한다 — 사용자에게 "프로젝트 밖 vs 안"을 묻지 않는다.
- 생성되는 지침의 범위는 **저장 경로 + .gitignore 등록 규율 + 사용 후 정리/수명 규율**까지 포괄한다.
- 이 카테고리는 첫 sub-룰(임시 파일) 외에 빌드 산출물·스크래치 데이터 등 다른 작업공간 sub-룰로 확장 가능해야 하며, 확장은 새 템플릿 추가만으로 가능해야 한다(스킬 본문 변경 없이).
- `plugins/` 하위에 산출물이 추가되므로, 같은 변경 안에서 플러그인 버전 단일 출처가 함께 올라가야 한다.

개념 경계(혼동 방지):
- 본 스킬이 만드는 것은 작업공간 위생 카테고리의 sub-룰뿐이다. 빌드 시스템·릴리스 산출물 위치(engineering)나 태스크 기록(context)의 기존 지침은 건드리지 않는다.
- `temp-files` 룰은 "임시·스크래치 파일"에 한정하며, 영구 산출물·소스·생성 코드의 위치를 규정하지 않는다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

- WHEN 스킬이 호출되면, THE 스킬 SHALL 자신의 templates 디렉터리를 열거해 각 템플릿의 sub-룰 ID를 식별하고, 후보가 하나뿐이면 사용자 메뉴 없이 자동 선택한다.
- WHEN 후보 템플릿이 둘 이상이면, THE 스킬 SHALL `AskUserQuestion` single-select로 하나를 선택받는다.
- WHEN sub-룰을 기록하면, THE 스킬 SHALL 템플릿 frontmatter를 제거한 본문을 `rules/workspace/<sub>.md`로 기록하고 상위 디렉터리를 필요 시 생성한다.
- IF 기록 대상 sub-룰 파일이 이미 존재하면, THEN THE 스킬 SHALL 차이를 제시하고 사용자의 명시적 교체 동의가 있을 때만 덮어쓴다.
- THE 스킬 SHALL 한 번의 호출에서 `workspace` 카테고리의 단일 sub-룰 파일만 생성·갱신하고, 다른 카테고리의 기존 지침을 변경하지 않는다.
- THE 생성된 `temp-files` 지침 SHALL 임시·스크래치 파일을 프로젝트 트리 내부의 전용 디렉터리에 두도록 규정하며, 프로젝트 밖·시스템 temp를 기본 저장 위치로 삼지 않는다.
- THE 생성된 `temp-files` 지침 SHALL 그 전용 임시 디렉터리를 버전 관리에서 제외하는 `.gitignore` 등록 규율을 포함한다.
- THE 생성된 `temp-files` 지침 SHALL 임시 파일을 언제·어떻게 정리하는지(사용 후 정리/수명) 규율을 포함한다.
- WHERE 새 workspace sub-룰을 추가하려면, THE 스킬 SHALL 새 템플릿 파일 추가만으로 확장 가능해야 하며 스킬 본문 수정을 요구하지 않는다.
- WHEN 부트스트랩 오케스트레이터가 카테고리를 열거하면, THE `workspace` 카테고리 SHALL rule-creator 슬러그로부터 자동으로 후보에 포함된다.
- WHEN `plugins/` 하위에 변경이 발생하면, THE 변경 SHALL 같은 변경 안에서 플러그인 버전 단일 출처(매니페스트)와 그 미러(마켓플레이스)를 함께 올린다.

## 범위
포함:
- `workspace-rule-creator` 스킬 본문(형제 `engineering-rule-creator`와 동형인 템플릿 디스패처).
- 임시 파일 관리 sub-룰 템플릿 하나(`temp-files`, 프로젝트 안 gitignore 정책 + 정리 규율).
- 플러그인 버전 단일 출처와 마켓플레이스 미러의 동반 버전 상향.

비-목표 / 제외:
- "프로젝트 밖 / 시스템 temp" 정책 변형 템플릿(기본은 프로젝트 안 단일 — 후속 확장 여지).
- 빌드 산출물·스크래치 데이터 등 다른 workspace sub-룰의 실제 내용(구조만 확장 가능하게 두고 내용은 후속).
- 기존 카테고리(engineering·context·version-control 등) 지침의 내용 변경.
- `.gitignore` 자동 편집·임시 파일 자동 정리 스크립트·강제 훅(룰은 규율 문서일 뿐, 강제 메커니즘이 아니다).
- 사용자에게 "프로젝트 밖 vs 안" 선택을 묻는 인터랙션.

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 형제 rule-creator 스킬(특히 `engineering-rule-creator`)과 구조·규약을 일관되게 따른다: 템플릿 frontmatter 파싱, 기존 파일 덮어쓰기 보호, 본문 그대로 복사, 한 호출 = 한 sub-룰.
- 임시 디렉터리 경로는 프로젝트 내부 전용 디렉터리 규약(예: `.tmp/`)으로 템플릿 본문에 명시한다. 출력 sub-룰 파일명에는 정책 변형 식별자를 남기지 않는다.
- 룰은 규율 문서이며, 파일시스템을 강제하는 훅·스크립트·자동 편집을 만들지 않는다.

## 위험
- `workspace` 카테고리는 engineering(빌드 산출물 위치)·context(기록)와 개념이 인접해 사용자가 경계를 혼동할 수 있다 — 룰 본문에서 적용 범위를 "임시·스크래치 파일"로 명시해 완화한다.
- 단일 정책(프로젝트 안)만 제공하므로, 시스템 temp가 반드시 필요한 프로젝트는 후속 템플릿 확장이 필요하다(의도된 동작이며, 제외 범위에 명시됨).
