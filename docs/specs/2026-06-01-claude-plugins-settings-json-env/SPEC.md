---
scope:
  include:
    - .claude/settings.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# claude-plugins settings.json 토큰 절감 env 튜닝

## 무엇을 만들 것인가
이 레포의 공유 설정(`.claude/settings.json`)에 토큰·비용을 구조적으로 줄이는 설정을 추가한다: Task 서브에이전트를 메인보다 저렴한 모델로 라우팅하고, 프롬프트 캐시 유지 시간을 길게(1시간) 늘리고, Bash 도구 출력이 컨텍스트에 들어가는 길이를 상한으로 제한한다. 공유 설정에 두므로 이 레포에서 작업하는 모든 세션에 동일하게 적용된다.

## 목적 (왜)
autopilot의 dispatch/loop와 일반 작업이 서브에이전트와 도구 출력을 대량으로 만들어 토큰·비용·세션 압박이 크다. 작업 방식이 아니라 설정 차원에서 낭비를 낮춰 세션 수명을 늘리는 것이 목적이다.

## 완료 조건
- 항상, 이 레포에서 Task 서브에이전트를 스폰할 때 시스템은 메인 모델보다 저렴한 모델로 서브에이전트를 실행해야 한다.
- 항상, 시스템은 프롬프트 캐시 유지 시간을 기본값보다 길게(1시간) 적용해야 한다.
- Bash 도구가 큰 출력을 낼 때, 시스템은 컨텍스트에 반영되는 출력 길이를 정해진 상한으로 잘라야 한다.
- 이 설정들이 `.claude/settings.json`에 기록된 동안, 개인 오버라이드 없이도 레포를 사용하는 모든 세션에 동일하게 적용되어야 한다.
- 설정을 추가하는 동안, 기존 `enabledPlugins`·`extraKnownMarketplaces` 값은 변경 없이 보존되고 파일은 유효한 JSON이어야 한다.

## 범위
포함:
- `.claude/settings.json` — 토큰 절감 관련 설정 키 추가

비-목표 / 제외:
- `.claude/settings.local.json`(개인 설정) 변경
- 자동 컴팩션 임계값(PCT override) 변경 — 세션 핸드오프가 갖춰진 뒤로 보류
- 서드파티 토큰 절감 도구(RTK·Headroom·Caveman 등) 설치
- 활성 플러그인 목록(enabledPlugins) 변경

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 추가 의도는 다음 세 가지다: ① 서브에이전트 모델을 Sonnet 등 더 저렴한 모델로(`CLAUDE_CODE_SUBAGENT_MODEL`), ② 프롬프트 캐시 1시간(`ENABLE_PROMPT_CACHING_1H`), ③ Bash 출력 상한(`BASH_MAX_OUTPUT_LENGTH`, 예: 10000). 정확한 키 이름·배치(예: `env` 블록)는 현재 Claude Code 설정 규약을 따른다.
- 기존 키를 보존하고 JSON 유효성을 유지한다.

## 위험
- 서브에이전트를 더 저렴한 모델로 내리면 복잡한 작업에서 품질이 떨어질 수 있다 — 비용/품질 트레이드오프를 인지해야 한다.
- 기사 출처의 env 키가 현재 Claude Code 버전에서 유효한지 구현 단계에서 검증해야 한다 — 무효 키는 조용히 무시될 수 있다.
