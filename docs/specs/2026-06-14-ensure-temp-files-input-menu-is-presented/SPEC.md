---
scope:
  include:
    - plugins/project-init/skills/workspace-rule-creator/SKILL.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# Ensure temp-files input menu is presented

## 무엇을 만들 것인가
`workspace-rule-creator` 스킬이 temp-files sub-룰을 생성할 때, `temp_path` 입력 메뉴(추천 `.tmp/` + `.scratch/` + 자유입력 "Other")를 사용자에게 **반드시 제시**하도록 SKILL.md의 정적 입력 단계를 바로잡는다. 기본값 `.tmp/`는 사용자가 질문에 응답을 비우거나 거절했을 때에만 적용되며, 질문을 건너뛰고 곧바로 기본값을 쓰는 것은 허용되지 않는다.

## 목적 (왜)
현재 SKILL.md 4단계 문구가 "질문한다"와 "응답 누락·빈 값이면 기본값 `.tmp/`로 치환"을 한 문장에 묶어, 에이전트가 질문 자체를 건너뛰고 기본값을 쓰는 합리화 여지를 준다. 그 결과 사용자가 임시 경로를 고를 메뉴가 표시되지 않는다. 메뉴 제시와 기본값 적용 조건을 분리해 입력 기회를 보장한다.

## 완료 조건
- 항상, workspace-rule-creator가 temp-files 템플릿을 처리할 때 `temp_path` 입력을 `AskUserQuestion` 메뉴로 제시한다(추천 `.tmp/`를 첫 선택지로, `.scratch/`, 자유입력 "Other" 포함).
- 사용자가 그 질문에 응답을 비우거나 거절한 동안에만 기본값 `.tmp/`로 치환한다 — 질문을 제시하지 않고 기본값을 적용하지 않는다.
- 질문을 제시할 수 없는 비대화(자율 오케스트레이션) 맥락이면, 그 사실을 알리고 무응답과 동일하게 기본값 `.tmp/`로 진행한다.
- 항상, SKILL.md의 정적 입력 단계 문구는 "입력 메뉴를 먼저 제시한다"와 "기본값은 무응답·거절에만 적용한다"를 분리해 명시한다.

## 범위
포함:
- `plugins/project-init/skills/workspace-rule-creator/SKILL.md`의 정적 입력 단계(및 그 단계가 참조하는 인접 문구)뿐.

비-목표 / 제외:
- temp-files 템플릿의 `inputs` 정의(이미 추천+선택지+자유입력을 올바르게 선언).
- 다른 rule-creator 스킬(engineering 등)이나 동적 입력 단계.
- 이미 생성된 `rules/workspace/temp-files.md`의 재생성.

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 외과적 변경: SKILL.md의 정적 입력 단계 문구만 수정한다. 템플릿과 다른 단계는 불변으로 둔다.

## 위험
- 자율 오케스트레이션(bootstrap 위임) 맥락에서 대화형 질문이 원천적으로 불가한 경우와, 대화형 맥락에서 "그냥 건너뜀"을 구분해야 한다. 후자만 결함이며, 전자는 무응답=기본값 규칙으로 흡수한다.
