---
scope:
  include:
    - "plugins/project-init/skills/engineering-rule-creator/**"
    - "plugins/project-init/skills/bootstrap/SKILL.md"
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; S=plugins/project-init/skills/engineering-rule-creator; test -f $S/SKILL.md && test -d $S/templates && ls $S/templates/*.md >/dev/null && grep -q engineering-rule-creator $S/SKILL.md && grep -q rules/engineering $S/SKILL.md && grep -E \"rules/<name>/|디렉터리 카테고리|directory category\" plugins/project-init/skills/bootstrap/SKILL.md >/dev/null'"
ears_language: ko
request_review: true
---

# engineering-rule-creator 스킬과 versioning sub-룰 도입

## 무엇을 만들 것인가

이 task는 project-init 플러그인에 새로운 형제 스킬 `engineering-rule-creator`를 추가하고, 그 첫 sub-룰 산출물로 임의의 타깃 프로젝트 루트의 engineering 카테고리 디렉터리 아래 versioning 지침 파일을 대화형으로 생성·갱신할 수 있게 한다.

추가로 bootstrap 오케스트레이터가 형제 스킬을 자동 발견할 때, 평면 파일(`rules/<name>.md`)뿐 아니라 디렉터리 카테고리(`rules/<name>/`)도 "이미 존재"로 인식하도록 카테고리 존재 판정 규칙을 확장한다.

산출되는 versioning 지침의 *내용 자체*는 본 task의 책임이 아니다 — 본 task는 인터페이스(스킬·템플릿·bootstrap 통합)만 만들고, 실제 versioning 내용은 사용자와의 대화형 질문으로 결정·기록된다.

## 수용 기준 (EARS)

1. 시스템은 `plugins/project-init/skills/engineering-rule-creator/` 아래 SKILL.md와 templates 디렉터리, 그리고 첫 sub-룰 versioning 템플릿 파일을 제공한다.
2. engineering-rule-creator 스킬이 호출될 때, 시스템은 templates 디렉터리의 sub-룰 후보가 1개면 묻지 않고 자동 선택하고, 2개 이상이면 `AskUserQuestion`으로 사용자가 sub-룰을 고르게 한다.
3. engineering-rule-creator 스킬이 사용자 입력과 함께 완주할 때, 시스템은 타깃 프로젝트 루트의 `rules/engineering/<sub>.md`에 frontmatter가 제거된 본문(placeholder 치환 결과)을 기록한다 — 상위 디렉터리 부재 시 함께 생성한다.
4. bootstrap 오케스트레이터가 카테고리 존재 검사를 할 때, 시스템은 `rules/<name>.md` 평면 파일과 `rules/<name>/` 디렉터리 두 형태 모두를 "이미 존재"로 판정한다.
5. 기존 `rules/engineering/<sub>.md`가 존재하는 경우, 시스템은 그대로 덮어쓰지 않고 diff와 함께 사용자에게 명시적 동의를 요구한다.
6. 시스템은 engineering-rule-creator 실행 시 `rules/engineering/<sub>.md` 외의 어떤 파일도 생성·수정하지 않는다.

## 범위

포함:
- `plugins/project-init/skills/engineering-rule-creator/SKILL.md` (신규)
- `plugins/project-init/skills/engineering-rule-creator/templates/*.md` (신규, 최소 1개 — versioning 단일 추천 템플릿)
- `plugins/project-init/skills/bootstrap/SKILL.md` (카테고리 존재 판정 갱신 — `rules/<name>/` 디렉터리도 인식)

비-목표 / 제외:
- 다른 engineering sub-룰 (testing, linting, dependency, security 등) — 별도 후속 task
- 산출되는 `rules/engineering/versioning.md`의 실제 *내용 결정* (본 task는 인터페이스만)
- project-init 외 다른 플러그인의 변경
- plugin.json 자체의 버전 필드 갱신

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash -c 'set -e; S=plugins/project-init/skills/engineering-rule-creator; test -f $S/SKILL.md && test -d $S/templates && ls $S/templates/*.md >/dev/null && grep -q engineering-rule-creator $S/SKILL.md && grep -q rules/engineering $S/SKILL.md && grep -E "rules/<name>/|디렉터리 카테고리|directory category" plugins/project-init/skills/bootstrap/SKILL.md >/dev/null'
```

## 제약

- 본 스킬은 타깃 프로젝트 루트의 `rules/engineering/<sub>.md`만 생성·갱신한다. 다른 파일은 만지지 않는다.
- 형제 스킬(`context-rule-creator`/`orchestration-rule-creator`)의 디스패처 컨셉(`templates/*.md` enumerate → 선택 → placeholder 치환 → 파일 기록) 패턴을 따른다. 본문 내용은 SKILL.md가 알지 않는다.
- bootstrap의 카테고리 존재 판정 갱신은 기존 형제 스킬(`context`·`orchestration`)의 평면 파일 매핑 동작을 깨지 않는다 — 두 형태(`rules/<name>.md` 또는 `rules/<name>/`)를 모두 "이미 존재"로 판정해 카테고리 셋업이 중복 실행되지 않도록만 확장한다.
- 작성 언어는 프로젝트 기본 한국어(`ears_language: ko`)를 유지한다.

## 위험

- bootstrap의 카테고리 enumerate·존재 판정 로직 변경이 기존 형제 스킬(`context`·`orchestration`)의 실행 경로에 회귀를 낼 수 있다. 평면 파일과 디렉터리 두 경우를 모두 시뮬레이션해 동작을 확인해야 한다.
- `rules/engineering/<sub>.md`가 기존 `rules/<name>.md` 평면 관례와 달라, 다른 플러그인·외부 도구(예: 다른 감사 스크립트·init 검사기)가 카테고리 자동 감지에 실패할 가능성. 본 repo 내부에서는 bootstrap 갱신으로 해결되지만 외부 도구는 본 task 범위 밖.
