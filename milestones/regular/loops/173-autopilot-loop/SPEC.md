---
scope:
  include: ["plugins/autopilot/skills/loop/**", "plugins/autopilot/skills/spec/**", "tests/autopilot/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-loop-events-only.sh"
---

# autopilot:loop 스킬 실행 로그를 호출 세션으로 실시간 출력

## 무엇을 만들 것인가

`autopilot:loop` 스킬을 통해 자율 task를 시작했을 때, 셸 드라이버가 출력하는 모든 비-noise 라인이 호출 세션의 알림 스트림에 실시간으로 전달된다.

기존 동작은 정규식 필터로 핵심 이벤트(이터 시작·종료, halt, escalation, done 등)만 통과시켰지만, 본 변경 후 default 동작은 **빈 줄과 단독 dot 라인만 제외**하고 그 외 모든 출력이 통과하도록 바뀐다 — 이터 내부의 상세 진행, 보조 명령 결과, 디버그·정보 라인 포함. 사용자는 자율 루프의 진행 상태를 더 풍부한 입자도로 실시간 추적할 수 있게 된다.

사용자가 기존 방식(핵심 이벤트만 알림)으로 회귀하고 싶을 때를 위해 opt-out 옵션이 제공된다. `autopilot:spec` 스킬의 최종 결정 단계의 "지금 loop start 호출" 자동 연계 분기에서도 동일 opt-out 선택이 사용자에게 명시적으로 제공되어, 자동 연계 호출의 args에 반영된다.

## 수용 기준 (EARS)

- **AC1 (Event-driven)**: `--events-only` 플래그 없이 사용자가 `autopilot:loop` 스킬을 통해 task를 시작할 때, 시스템은 셸 드라이버 stdout 라인 중 빈 줄과 단독 dot 라인을 제외한 모든 라인을 호출 세션의 알림 스트림으로 전달해야 한다.
- **AC2 (Event-driven)**: `--events-only` 플래그와 함께 사용자가 `autopilot:loop` 스킬을 통해 task를 시작할 때, 시스템은 기존 핵심 이벤트 정규식 필터(이터 #·HALT·WARN·FAIL·ERROR·rate limit·claude 비정상·에스컬레이션·DONE)만 적용해 핵심 이벤트만 호출 세션의 알림 스트림으로 전달해야 한다.
- **AC3 (State-driven)**: `autopilot:spec` 스킬이 최종 결정 단계의 "지금 loop start 호출" 분기에 진입한 동안, 시스템은 사용자에게 `--events-only` opt-out 선택을 명시적으로 묻고 그 선택 결과를 자동 연계 호출의 args 구성에 반영해야 한다.
- **AC4 (Unwanted)**: 사용자가 `autopilot:loop` 스킬을 경유하지 않고 셸 드라이버를 직접 호출하면, 시스템은 `--events-only` 플래그의 효력이 없음을 보장해야 한다 (기존 `--no-monitor` 정책과 일관).
- **AC5 (Ubiquitous)**: 시스템은 셸 드라이버의 stdout 출력 형식을 변경하지 않아야 한다 — 변경 대상은 스킬의 Monitor 가설 시 사용되는 필터 정의·안내로 한정된다.

## 범위

포함:
- `plugins/autopilot/skills/loop/SKILL.md` 의 Monitor 자동 가설 default 필터 정의 갱신 (noise-only 제외 의미를 표현하는 패턴으로 교체)
- `plugins/autopilot/skills/loop/SKILL.md` 에 `--events-only` 플래그 정의 명시 (`--no-monitor` 와 동일 contract — 스킬 차원 옵션, `loop.sh` 로 미전달)
- `plugins/autopilot/skills/spec/SKILL.md` step 10 결정 다이얼로그에 `--events-only` opt-out 선택 추가 + 자동 연계 args 구성에 반영하는 절차 명시
- `tests/autopilot/test-loop-events-only.sh` 정적 검증 스크립트 추가 (두 SKILL.md 파일에 대한 grep 기반 검사)

비-목표 / 제외:
- `plugins/autopilot/skills/loop/references/loop.sh` 셸 드라이버 stdout 자체 형식 변경
- `Monitor` 도구 자체 구현 변경 (도구의 패턴 입력 표현법은 수용)
- `logs` 서브커맨드 동작 변경 (`--tail`·`--iter N`)
- 기타 스킬(`autopilot:dispatch` 등) 수정
- 셸 드라이버를 직접 호출하는 경로에 대한 하위 호환성 (AC4)

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```
bash tests/autopilot/test-loop-events-only.sh
```

스크립트가 검사하는 항목:

[loop SKILL.md]
1. 기존 핵심 이벤트 정규식 패턴이 default 위치에서 제거됨 (`--events-only` 분기 설명에만 잔존하면 OK)
2. 새 default 필터가 "noise-only 제외" 의미를 표현하는 패턴으로 정의됨 (빈 줄·단독 dot 제외)
3. `--events-only` 플래그 정의 섹션이 존재 (명세·contract·`--no-monitor`와 일관 명시)
4. 셸 드라이버 직접 호출 시 미적용이 명시됨

[spec SKILL.md]
5. step 10의 "지금 loop start 호출" 분기 설명에 `--events-only` 선택이 언급됨
6. 자동 연계 args 구성에 그 선택이 반영됨 (예: args 입력 시 `--events-only` 토큰 추가 절차)

## 제약 (있을 때만)

- `Monitor` 도구의 패턴 입력 표현법(정규식 문법·invert match 가능 여부 등)은 도구 구현 세부에 의존하므로, SKILL.md는 패턴의 "의미"만 명시한다.
- `spec→loop` 자동 연계 계약은 spec 스킬 step 10 다이얼로그 구조에 결합되어 있다. step 10 명세가 먼저 바뀌면 본 옵션 전달 절차도 다시 정렬이 필요하다.

## 위험 (있을 때만)

- raw stdout 전달로 세션 컨텍스트·토큰 소비가 증가할 수 있다. 필요 시 `--events-only` 로 기존 핵심 이벤트 필터로 회귀해 완화한다.
