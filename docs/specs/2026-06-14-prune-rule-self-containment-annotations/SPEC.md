---
scope:
  include:
    - plugins/project-init/skills/workflow-rule-creator/templates/stage-gates.md
    - plugins/project-init/skills/workflow-rule-creator/templates/spec-layout.md
    - plugins/project-init/skills/version-control-rule-creator/templates/review-approval.github.md
    - plugins/project-init/skills/version-control-rule-creator/templates/review-approval.gitlab.md
    - rules/workflow/stage-gates.md
    - rules/workflow/spec-layout.md
    - rules/version-control/review-approval.md
  exclude:
    - milestones/**
    - CLAUDE.md
    - .claude/worktrees/**
    - docs/project-init-guidance-optimization/**
---

# Prune rule self-containment annotations

## 무엇을 만들 것인가
rule-creator 템플릿과 이 레포에 생성된 룰에서, "이 지침은 자기완결이며 타깃 프로젝트의 단일 출처와 정합하라"는 취지의 **메타주석**을 제거한다. 대상은 두 종류다.

1. **블록쿼트(`>`) 주석 7곳** — "단일 출처가 정의한다 / 두 곳이 어긋나면 단일 출처에 맞춘다 / 본 지침은 ~를 대체하지 않는다" 류:
   - 템플릿: `workflow-rule-creator/templates/stage-gates.md`, `workflow-rule-creator/templates/spec-layout.md`, `version-control-rule-creator/templates/review-approval.github.md`, `version-control-rule-creator/templates/review-approval.gitlab.md`
   - 생성룰: `rules/workflow/stage-gates.md`, `rules/workflow/spec-layout.md`, `rules/version-control/review-approval.md`
2. **유사 설명 문단** — stage-gates의 "게이트의 *의도*는 자기완결로 읽힙니다: …" 로 시작하는 문단(템플릿 + `rules/workflow/stage-gates.md` 2곳).

각 룰의 규범 본문은 그대로 둔다.

## 목적 (왜)
이 메타주석들은 룰 본문에 "어떻게 단일 출처와 정합하는지"를 중복 서술해, 계약만 남기고 메커니즘 중복을 피한다는 단일 출처 원칙에 어긋난다. 주석을 걷어내 룰을 계약 수준으로 슬림하게 유지한다.

## 완료 조건
- 항상, 위에 열거한 7개 파일에는 "단일 출처 정합 / 대체하지 않음" 취지로 시작하는 블록쿼트(`>`) 문단이 존재하지 않는다.
- 항상, stage-gates 템플릿과 `rules/workflow/stage-gates.md`에는 "게이트의 *의도*는 자기완결로 읽힙니다"로 시작하는 문단이 존재하지 않는다.
- 항상, 각 파일의 규범 본문은 보존된다 — 구체적으로 stage-gates의 "두 게이트가 통과 뒤 수행하는 일… 경계만 고정합니다" 위임 경계 문단과 "## 공통 — 단계 책임의 위임과 자기완결" 섹션 헤더, spec-layout의 slug·경로 규칙 본문, review-approval의 심사 단위·승인 상태 본문은 그대로 남는다.
- 항상, 주석 제거로 생긴 연속 빈 줄은 단일 빈 줄로 정리되어 인접 섹션의 마크다운 구조가 깨지지 않는다.
- 항상, 한 템플릿과 그 템플릿에서 파생된 생성룰의 동일 주석은 함께 제거되어, 템플릿에만 또는 룰에만 남는 불일치가 발생하지 않는다.

## 범위
포함:
- 위 "무엇을 만들 것인가"에 열거한 7개 파일(템플릿 4 + 생성룰 3)뿐.

비-목표 / 제외:
- 다른 rule-creator 템플릿·룰(context, engineering, review/principles 등).
- 워크트리·문서 사본(`.claude/worktrees/**`, `docs/project-init-guidance-optimization/**`, `.dispatch/**`)의 동일 파일.
- 규범 본문 재작성, 섹션 헤더 변경, 인접 문단 재포매팅.

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 외과적 변경: 지정된 주석 문단과 그로 인해 남는 빈 줄만 손댄다. 인접 문단을 재포매팅하거나 개선하지 않는다.

## 위험
- "유사 설명 문단"의 경계 — stage-gates의 위임 경계 문단(line 41/36)은 규범 내용이므로 **보존 대상**이며 제거 대상이 아니다. 과잉 제거에 주의한다.
