---
scope:
  include:
    - plugins/project-init/skills/bootstrap/SKILL.md
    - plugins/project-init/skills/context-rule-creator/SKILL.md
    - plugins/project-init/skills/engineering-rule-creator/SKILL.md
    - plugins/project-init/skills/version-control-rule-creator/SKILL.md
    - plugins/project-init/skills/workspace-rule-creator/SKILL.md
    - plugins/project-init/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# project-init 5개 스킬에 allowed-tools 권한 선언 추가

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

project-init 플러그인의 5개 스킬(`bootstrap`, `context-rule-creator`, `engineering-rule-creator`, `version-control-rule-creator`, `workspace-rule-creator`) 각각의 `SKILL.md` frontmatter에, 그 스킬이 본문 절차에서 실제로 사용하는 도구 권한을 `allowed-tools` 리스트로 빠짐없이 선언한다. 현재 이 5개 스킬에는 `allowed-tools`가 전혀 없어, 사용 시 도구 호출마다 권한 프롬프트가 발생한다. 각 스킬의 절차 단계에서 호출되는 도구(사용자 질의, 파일 읽기/쓰기, 형제 스킬 위임, 디렉토리 열거, 디렉토리 생성, diff 표시, git origin 읽기, read-only 네트워크 probe 등)를 그 스킬 본문에 근거해 도출하고, 근거 없는 도구는 넣지 않는다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

- **항상**: 5개 스킬(`bootstrap`·`context-rule-creator`·`engineering-rule-creator`·`version-control-rule-creator`·`workspace-rule-creator`) 각각의 `SKILL.md` frontmatter에 비어 있지 않은 `allowed-tools` YAML 리스트가 존재해야 한다.
- **항상**: 각 스킬의 `allowed-tools` 항목 하나하나는 그 스킬 본문의 어떤 절차 단계가 그 도구를 사용하는지로 설명 가능해야 한다 — 본문에 근거 없는 도구 항목이 하나도 없어야 한다(과다 부여 금지).
- **항상**: 각 스킬이 본문 절차에서 실제로 호출하는 도구 중 `allowed-tools`에서 누락된 것이 하나도 없어야 한다(누락 금지).
- **항상**: 모든 Bash 권한은 포괄형(`Bash` 또는 `Bash(*)`)이 아니라, 하위 명령 단위 granular 패턴(예: `Bash(ls:*)`)으로만 선언되어야 한다 — 같은 레포의 `plugins/autopilot/skills/spec`·`loop`가 쓰는 표기 컨벤션과 일치해야 한다.
- **항상**: `bootstrap`의 `allowed-tools`에는 사용자 질의(`AskUserQuestion`), 파일 읽기(`Read`), `CLAUDE.md` 생성(`Write`), 형제 `*-rule-creator` 위임(`Skill`), `skills/` 하위 `*-rule-creator` 및 `rules/` 카테고리 열거·존재 확인 도구, 기존 `CLAUDE.md` diff 표시 도구가 포함되어야 한다.
- **…할 때**: `version-control-rule-creator`가 git origin remote로 호스팅 백엔드를 판별할 때, origin URL 읽기 도구와 self-hosted 호스트용 read-only(GET류) 네트워크 probe 도구가 그 스킬의 `allowed-tools`에 포함되어 권한 프롬프트 없이 수행될 수 있어야 한다.
- **…할 때**: `context-rule-creator`가 레거시 평면 파일(`rules/context.md`)을 사용자 동의 후 제거할 때, 파일 제거에 필요한 도구가 그 스킬의 `allowed-tools`에 포함되어 있어야 한다.
- **항상**: 4개 `*-rule-creator` 스킬 각각의 `allowed-tools`에는 그 스킬이 사용하지 않는 도구(형제 스킬을 호출하지 않으므로 `Skill`, 부분 편집을 하지 않으므로 `Edit`)가 포함되지 않아야 한다.
- **항상**: 변경 후 5개 `SKILL.md`는 모두 frontmatter가 유효한 YAML로 파싱되고, `name`·`description` 등 기존 필드가 보존되어야 한다.

## 범위
포함:
- 5개 project-init 스킬의 `SKILL.md` frontmatter에 `allowed-tools` 리스트 추가.
- `plugins/` 워치 디렉토리 변경에 따른 버전 단일 출처(`plugins/project-init/.claude-plugin/plugin.json`)와 그 미러(`.claude-plugin/marketplace.json`의 project-init 항목) 동반 상향 — 통합(머지) 책임자가 같은 머지 안에서 수행.

비-목표 / 제외:
- 스킬 **본문**(절차·규칙)의 로직 변경 — 본 SPEC은 frontmatter `allowed-tools`만 추가하며 동작을 바꾸지 않는다.
- `docs/project-init-guidance-optimization/...` 아래의 오래된 설계 스냅샷 카피 및 `.claude/worktrees/**` 의 워크트리 카피 — 정식 소스가 아니므로 건드리지 않는다.
- autopilot 등 다른 플러그인 스킬, project-init 외 스킬.
- `.claude/settings.json` 등 하네스 권한 설정 파일 변경(스킬 frontmatter 선언만 다룬다).

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)

- **표기 컨벤션**: `allowed-tools`는 같은 레포의 `plugins/autopilot/skills/spec/SKILL.md`·`plugins/autopilot/skills/loop/SKILL.md`와 동일한 YAML 리스트 표기(각 항목 `- <Tool>` 또는 `- Bash(<pattern>)`)를 따른다. Bash는 하위 명령별 granular 패턴으로만 적는다.

- **스킬별 도출 목표 도구 집합**(본문 절차 근거. 구현 시 본문을 재검토해 누락·과다를 보정한다):

  - **bootstrap** — `AskUserQuestion`(step 1·2·4 질의), `Read`(자산·베이스 템플릿·기존 `CLAUDE.md` 읽기), `Write`(`CLAUDE.md` 생성), `Skill`(step 5 형제 `*-rule-creator` 위임), `Glob`·`Bash(ls:*)`(step 4 `skills/` 하위 `*-rule-creator` 및 step 1 `rules/` 카테고리 열거·존재 확인), `Bash(diff:*)`·`Bash(git diff:*)`(기존 `CLAUDE.md` diff 표시).

  - **공통(4개 rule-creator 모두)** — `AskUserQuestion`(선택·입력 질의), `Read`(`templates/` 본문·frontmatter 읽기), `Write`(`rules/<category>/...` 기록), `Glob`·`Bash(ls:*)`(`templates/` 열거 및 동적 입력의 depth1 디렉토리 후보 산출), `Bash(mkdir -p:*)`(대상 카테고리 디렉토리 생성), `Bash(diff:*)`·`Bash(git diff:*)`(기존 파일 덮어쓰기 전 diff 표시).

  - **context-rule-creator** — 공통 + `Bash(rm:*)`(레거시 `rules/context.md` 동의 후 제거).

  - **engineering-rule-creator** — 공통(추가 도구 없음).

  - **version-control-rule-creator** — 공통 + `Bash(git remote get-url:*)`·`Bash(git config:*)`(origin URL 읽기) + `WebFetch`(self-hosted 호스트 read-only API probe).

  - **workspace-rule-creator** — 공통(추가 도구 없음).

- **버전 동반(필수 규칙)**: `plugins/`는 버전 워치 디렉토리이므로, 이 변경이 기본 브랜치에 머지될 때 같은 머지 안에서 project-init 버전 단일 출처(`plugins/project-init/.claude-plugin/plugin.json`)와 미러(`.claude-plugin/marketplace.json`의 project-init 항목)를 함께 상향해야 한다(`rules/engineering/versioning.md`). 단, 구현 워커는 버전을 올리지 않고 통합 책임자가 머지 직전에 SemVer를 직접 상향한다(본 레포의 dispatch 통합 관례). frontmatter 메타데이터만 추가하는 비파괴 변경이므로 자리수는 MINOR 또는 PATCH가 적절하다.

## 위험 (있을 때만)

- **열거 도구 선택 불확실성**: 디렉토리/템플릿 열거를 실행기가 `Glob`로 할지 `Bash(ls:*)`로 할지 사전에 단정할 수 없다. 누락 시 권한 프롬프트만 발생할 뿐 기능은 깨지지 않으므로, "누락 금지" 의도에 맞춰 두 도구를 함께 포함한다(과다 부여가 아니라 동등 대체 경로 허용).
- **probe 도구 형태**: version-control의 read-only probe를 `WebFetch`로 볼지 `Bash(curl:*)`류로 볼지 갈릴 수 있다. 본 SPEC은 네이티브 `WebFetch`를 기준으로 하되, 본문이 curl 호출을 명시하면 구현 시 해당 Bash granular 패턴으로 대체·보강한다.
- **frontmatter 파손**: 리스트 들여쓰기 오류로 YAML이 깨지면 스킬 메타가 로드되지 않는다 — 변경 후 5개 frontmatter의 YAML 유효성과 기존 필드 보존을 반드시 확인한다.
