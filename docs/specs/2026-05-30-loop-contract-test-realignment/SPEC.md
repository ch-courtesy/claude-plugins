---
scope:
  include:
    - tests/autopilot/test-loop-sh.sh
    - tests/autopilot/test-loop-events-only.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# loop contract test realignment

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

loop의 두 계약 테스트(`tests/autopilot/test-loop-sh.sh`,
`tests/autopilot/test-loop-events-only.sh`)를 **현재 spec-file-driven loop contract**에
맞춰 재정합한다. loop의 spec-file-driven 리팩토링이 스킬 본문(SKILL.md·loop.sh·
constitution.md)은 새 contract로 마이그레이션했으나 이 두 테스트는 누락해, 두 테스트가
이미 제거된 구 contract를 참조하며 기본 브랜치에서 RED 상태다(기존 테스트 부채).

이 변경은 **테스트만** 현 contract에 맞춘다 — loop 스킬 자체 동작은 바꾸지 않는다. 현
contract의 단일 출처는 실제 loop 스킬 파일이며, 테스트는 그것을 따라야지 정의해서는 안 된다.
제거된 기능을 검증하던 항목은 **혼합 방식**으로 처리한다: 현 contract에 대응 개념이 있으면
새 동작 검증으로 재작성하고, 기능 자체가 사라졌으면 삭제한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

**재정합 (GREEN)**

- When `tests/autopilot/test-loop-events-only.sh`를 실행하면, 종료 코드는 0이어야 한다(모든 check 통과).
- When `tests/autopilot/test-loop-sh.sh`를 실행하면, 종료 코드는 0이어야 한다(모든 TEST 통과).
- The `test-loop-events-only.sh`의 Monitor 섹션 검증은 현 loop SKILL.md의 실제 헤더(`#### Monitor`)를 대상으로 해야 하며, 더 이상 제거된 헤더(`#### 자동 Monitor 가설`)를 찾지 않아야 한다.
- The 두 테스트는 제거된 구 contract(`prepare` 서브커맨드, feat 브랜치 기반 셋업, task-issue/gh-comment halt 모델, `--no-pr` 플래그, PLAN.md 시드, milestones 중첩 디렉토리 경로, 스테일 status 값)를 더 이상 참조하지 않아야 한다.

**마이그레이션 방식 (혼합)**

- If 제거된 기능 검증 항목이 현 contract에 대응 개념을 가지면, 그 항목은 현 contract 동작 검증으로 재작성되어야 한다(예: `prepare`→서브커맨드 부재 확인, task-issue halt→`.loop/signals/BLOCKED` 종결, 작업공간→`WT=SPEC_DIR/.worktree`).
- If 제거된 기능 검증 항목이 현 contract에 대응 개념이 없으면, 그 항목은 삭제되어야 한다.
- The 두 테스트가 검증하는 현 contract 표면은 실제 loop 스킬 단일 출처(SKILL.md·loop.sh·constitution.md)와 일치해야 한다 — 서브커맨드 집합 `start/status/stop/list/cleanup/logs/env/gates/paths/deps`, terminal 신호 `.loop/signals/DONE|BLOCKED`(드라이버는 내용 미파싱), 메타파일 `.loop/notes.md`·`.loop/iterations/`·`.loop/BASE_SHA`.

**불변(범위·회귀 보장)**

- The 재정합은 loop 스킬 자체 동작(loop.sh·SKILL.md·constitution.md 로직)을 변경하지 않고 테스트만 현 contract에 맞춰야 한다.
- The 본 변경 이전에 GREEN이던 다른 autopilot 테스트는 본 변경 후에도 GREEN이어야 한다(회귀 없음).

## 범위
포함:
- `tests/autopilot/test-loop-sh.sh`를 현 spec-file-driven contract로 재정합(혼합: 대응물 재작성, 없으면 삭제)
- `tests/autopilot/test-loop-events-only.sh`를 현 spec-file-driven contract로 재정합(Monitor 헤더 교정 포함)

비-목표 / 제외:
- loop 스킬 자체 동작 변경(loop.sh·SKILL.md·constitution.md 로직)
- 가산 기능 추가(페르소나 적대적 검증·lateral 회복 등은 별도 SPEC 소관)
- 현 contract 정렬을 넘어서는 새 테스트 시나리오·커버리지 확장
- `plugins/` 워치 디렉토리 변경(버전 상향 불요)

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 테스트만 수정한다. 프로덕션 스킬 파일(loop.sh·SKILL.md·constitution.md 등)은 불변.
- 현 contract의 단일 출처는 실제 loop 스킬 파일이다 — 테스트는 그것을 따르며 contract를 정의하지 않는다.
- `plugins/` 워치 디렉토리를 건드리지 않으므로 버전 상향이 필요 없다(건드릴 경우에만 `rules/engineering/versioning.md`에 따라 MINOR 동반 상향).

## 위험 (있을 때만)
- 혼합 마이그레이션에서 재작성 대상을 과도하게 삭제하면 현존 기능 커버리지 공백이 생긴다 → "대응물 있으면 재작성" 원칙으로 완화.
- `test-loop-sh.sh`가 대규모(~3237줄, 72 TEST 블록)라 단일 이터에 끝나지 않을 수 있다 → loop의 다중 이터·콜드스타트 인계로 흡수.
- 테스트가 잘못된 contract를 박제하면 다시 표류한다 → 실제 loop 스킬 파일을 단일 출처로 대조해 완화.
