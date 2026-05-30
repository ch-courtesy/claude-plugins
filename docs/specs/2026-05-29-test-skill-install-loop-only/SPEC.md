---
scope:
  include: ["tests/autopilot/test-skill-install.sh"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# test-skill-install.sh loop 전용화 및 기대 구조 정합

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
`test-skill-install.sh`를 loop 스킬 패키지 구조 검증 전용으로 정리한다. 그동안 이 테스트에 누적된 다른 스킬(spec·dispatch·using-autopilot) 및 구 디렉터리 검증 블록을 제거하고(각 스킬은 전용 테스트가 커버한다), loop references 기대 목록을 현재 실제 구조(phase-스크립트 기반)와 일치시켜 테스트가 통과하도록 한다.

배경: loop 스킬 references가 템플릿 파일군(plan/notes/handoff/runlog/escalation)에서 phase-스크립트군(cleanup/pr/rebase/review-fix·task-storage)으로 리팩토링됐으나 본 테스트의 기대 목록이 미갱신되어 기존 실패 상태다.

## 수용 기준 (EARS)
<!-- 각 기준은 verify에서 fail 가능해야 함. 구현 방법·파일·클래스명은 피한다. -->
- **AC1 (Ubiquitous):** 시스템은 `test-skill-install.sh`가 loop 스킬 패키지 구조만 검증하고, 다른 스킬(spec·dispatch·using-autopilot) 및 구 디렉터리 검증 블록을 포함하지 않아야 한다.
- **AC2 (Ubiquitous):** 시스템은 `test-skill-install.sh`의 loop references 기대 목록이 현재 loop 스킬 references의 실제 파일 집합과 일치하도록(존재하지 않는 파일을 기대하지 않고 실제 존재 파일을 누락하지 않도록) 해야 한다.
- **AC3 (Event-driven):** `test-skill-install.sh`를 실행하면, 시스템은 0 exit(전체 통과)으로 종료해야 한다.
- **AC4 (Unwanted behavior):** 만약 loop 기대 references 중 하나라도 실제로 부재하면, 시스템은 그 불일치를 fail로 드러내야 한다.

## 범위
포함:
- `tests/autopilot/test-skill-install.sh`의 다른 스킬·구 디렉터리 검증 블록 제거.
- loop references 기대 목록을 현재 실제 구조와 정합.
- plugin-level 버전 bump 검증은 스킬별 테스트가 아니므로 유지.

비-목표 / 제외:
- 다른 스킬 전용 테스트 파일(`test-spec-skill*.sh`·`test-dispatch-skill.sh`·`test-using-autopilot-hook.sh`) 수정.
- loop 스킬 자체 또는 references 파일 변경.
- 테스트 파일명 변경.

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 제거되는 각 블록의 커버리지는 전용 테스트(spec→`test-spec-skill*.sh`, dispatch→`test-dispatch-skill.sh`, using-autopilot→`test-using-autopilot-hook.sh`)가 보장한다는 전제 하에서만 제거한다. 전제가 깨지면(전용 테스트 부재) 제거 대신 별도 처리한다.

## 위험 (있을 때만)
- PR #235가 `test-skill-install.sh`에 using-autopilot 검증 블록을 추가했다. 본 변경은 #235가 머지된 트리를 기준으로 적용하거나, 미머지 상태에서 진행 시 해당 블록 제거와의 충돌을 해소해야 한다.
