---
scope:
  include:
    - plugins/autopilot/skills/dispatch/**
    - plugins/autopilot/agents/**
    - plugins/autopilot/.claude-plugin/plugin.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko (default)
---

# dispatch worker as generic subagent

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만, 파일·도구명 등은 제약으로. -->
dispatch가 준비된 SPEC마다 띄우는 per-SPEC 워커를 **전용 서브에이전트 타입이 아니라 범용 서브에이전트**로
띄우고, 워커 절차 계약을 **spawn 프롬프트에 실어 전달**한다. 워커는 부모 세션의 권한을 상속해, 백그라운드로
띄워져도 격리 구현 스킬·결정적 통합/리뷰/머지 헬퍼를 **권한 프롬프트 없이 호출**할 수 있어야 한다.

## 목적 (왜)
전용 서브에이전트 타입은 독립 권한 컨텍스트라 백그라운드로 띄우면 모든 도구 호출이 자동 거부돼 워커가 구현을
진행할 수 없었다(검증됨). 권한 사전부여(프로젝트 설정·훅)는 배제됐고 타입의 도구 선언은 권한을 부여하지
못한다. 부모 권한을 상속하는 범용 서브에이전트로 되돌려 **백그라운드에서 실제로 동작**하게 하는 것이 목적이다.

## 완료 조건
- **항상**: dispatch는 준비된 SPEC마다 워커를 **범용 서브에이전트**로 띄워야 한다(전용 워커 타입으로 띄우지 않는다).
- **워커를 띄울 때**: **워커 절차 계약 전문이 spawn 프롬프트로 전달**돼야 한다(계약이 단일 출처 문서로 존재하고 임베드된다).
- **백그라운드로 띄워지면**: 워커가 격리 구현 스킬·결정적 통합/리뷰/머지 헬퍼를 **권한 거부 없이 호출**할 수 있어야 한다.
- **항상**: 워커 지침은 구현·리뷰 스킬을 **네임스페이스 포함 이름으로 호출**하도록 명시해야 한다 —
  구현은 `Skill(skill="autopilot:loop", ...)`, 리뷰(direct 경로)는 `autopilot:review`. bare `loop`/`review` 로 부르지 않는다.
- **항상**: 워커 계약의 안전 의도가 보존돼야 한다 — 구현은 격리 구현 스킬로만, 통합·리뷰·머지는 결정적 헬퍼로,
  raw 원격 명령(직접 PR 생성/머지·푸시)을 직접 수행하지 않음, 승인 이후에만 머지, 자기 SPEC을 식별 가능한
  구조화 결과(머지됨/비완료) 보고.
- **항상**: 더 이상 spawn에 쓰이지 않는 **전용 워커 타입 정의는 제거**돼야 한다.
- **항상**: 워커 계약은 단일 출처 문서로 존재하고, dispatch 문서·헬퍼 주석의 참조가 그 문서를 가리켜야 한다.
- **항상**: 기존 결정적 헬퍼 self-test가 계속 통과해야 한다.

## 범위
포함:
- 워커 spawn 방식 전환(전용 타입 → 범용 + 계약 프롬프트 임베드).
- 전용 워커 타입 정의 제거.
- 워커 계약을 단일 출처 문서(`references/subagent-prompt.md`)로 신설, dispatch 문서·주석 참조 갱신.
- 버전 범프.

비-목표 / 제외:
- **되돌리지 않고 유지**: 머지 승인 게이트(PR 승인 상태/마커), forge 경로의 PR-리뷰 구동(로컬 리뷰 스킬 미호출),
  계약에서 force·머지방식 지침 제거.
- `loop`·`review` 스킬 내부 구현.
- `rules/`·`milestones/`·`CLAUDE.md`.

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을
실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 변경 범위는 `plugins/autopilot/skills/dispatch/**`, `plugins/autopilot/agents/**`,
  `plugins/autopilot/.claude-plugin/plugin.json`에 한정.
- 전용 워커 타입 = `plugins/autopilot/agents/dispatch-worker.md`(제거 대상). 범용 서브에이전트 = Agent 도구
  기본 타입(general-purpose). 워커 계약(=범용 서브에이전트 spawn 프롬프트로 임베드되는) 단일 출처 문서 =
  `references/subagent-prompt.md`(신설; 현 `agents/dispatch-worker.md` 본문 기준, force·머지방식 지침 배제 유지). 격리 구현 스킬 =
  `autopilot:loop`. 결정적 헬퍼 = `integration.sh`·`review-loop.sh`·`merge.sh`.
- **강제 약화 인지**: 범용 서브에이전트는 계약을 시스템 프롬프트로 강제받지 않고 spawn 프롬프트로만 받으므로,
  계약 위반(예: loop 우회·워크트리 점유) 가능성이 전용 타입보다 높다 — 이는 백그라운드 권한과의 트레이드오프로 수용한다.
- #356/#357 개선(merge.sh 승인 게이트·review-loop.sh forge PR-리뷰·계약의 force/머지방식 지침 제거)은 보존한다.

## 위험
- **강제 약화로 인한 회귀**: 범용 워커가 계약을 안 따라 직접 편집·세션/메인 워크트리 점유·raw 머지로 회귀할 수
  있음 — spawn 프롬프트를 강하게 쓰고 dispatch가 결과·격리를 관찰해 완화하되, 근본 강제는 권한 제약과의
  트레이드오프로 남는다.
- **권한 상속 가정**: 범용 서브에이전트가 부모 권한을 상속한다는 가정이 환경/버전에 따라 다를 수 있음 — 통제 run으로 검증 필요.
