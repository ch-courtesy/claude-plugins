---
scope:
  include:
    - plugins/autopilot/skills/loop/SKILL.md
  exclude:
    - plugins/autopilot/skills/loop/references/**
    - plugins/autopilot/skills/dispatch/**
# ears_language: ko
---

# loop 포그라운드 실행 모델 (run_in_background 강제 제거)

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
autopilot:loop 스킬의 실행 지침(SKILL.md)을, 모델이 Skill 도구로 loop을 직접 호출하는 경로에서 **포그라운드(동기) 실행을 기본·유일 모델**로 바꾼다. 현재 SKILL.md는 `loop.sh start`를 백그라운드로 띄우도록 강제하고(동기 실행 금지) 그 위에 자동 Monitor 부착을 얹는데, 이 강제를 제거한다.

비차단(non-blocking) 실행이 필요한 경우의 안내를 단일 경로로 정한다 — loop 스킬을 **백그라운드 서브에이전트로 dispatch**하고, 그 서브에이전트가 loop을 포그라운드로 실행하게 한다. 자동 백그라운드 실행에 의존하던 지침(기본 ON Monitor 부착, 그와 짝인 SKILL 차원 옵션, 백그라운드 강제 문구)은 포그라운드 모델에 맞게 제거·갱신하고, 실시간 진행 관찰이 필요하면 loop이 디스크에 남기는 실행 아티팩트를 별도로 관찰하는 방법을 안내로 남긴다.

## 목적
<!-- 변경의 목표·동기. 완료 조건의 종속 앵커일 뿐 검증 기준이 아님. -->
서브에이전트 안에서 loop을 백그라운드로 띄우면 서브에이전트 턴 종료와 함께 백그라운드 프로세스가 kill되어 워커가 산출물 없이 실패한다(통제 실험으로 확인). 포그라운드 실행은 같은 서브에이전트 안에서도 정상 완료된다. 백그라운드 강제 지침을 제거해 이 함정을 구조적으로 없애고, 비차단이 필요한 경우의 경로를 "백그라운드 서브에이전트 경유"로 일원화하는 것이 목적이다.

## 완료 조건
<!-- 관찰 가능·독립 검증 가능. 5문장 패턴은 references/ears-patterns.md. -->
- loop SKILL.md의 start 지침은 `loop.sh start`를 백그라운드로 띄우도록 강제하지 않고, 포그라운드(동기) 실행을 기술해야 한다.
- loop SKILL.md는 "동기 실행 금지" 취지의 문구를 포함하지 않아야 한다.
- loop SKILL.md는 비차단 실행이 필요하면 loop 스킬을 백그라운드 서브에이전트로 dispatch하며, 그 서브에이전트가 loop을 포그라운드로 실행한다는 안내를 포함해야 한다.
- loop SKILL.md는 서브에이전트 안에서 loop을 백그라운드로 실행하면 서브에이전트 턴 종료 시 워커가 kill되어 실패한다는 근거(왜 포그라운드인지)를 포함해야 한다.
- loop SKILL.md는 자동 백그라운드 실행에 의존하던 자동 Monitor 부착 지침과 그와 짝을 이루던 SKILL 차원 모니터링 옵션(전달 시 loop.sh가 거부하는 옵션) 서술을, 포그라운드 모델에 더 이상 유효하지 않은 형태로 남기지 않아야 한다(제거 또는 포그라운드 모델에 맞게 갱신).
- loop SKILL.md는 실시간 진행 관찰이 필요할 때 loop이 디스크에 남기는 실행 아티팩트(이터레이션 로그·신호 디렉토리)를 별도로 관찰하는 방법을 안내해야 한다.
- WHEN allowed-tools에서 Monitor 도구 항목의 유지/제거를 정할 때, SKILL.md 본문이 Monitor를 어떻게 다루는지(디스크 아티팩트 관찰 용도로 남기는지 여부)와 일관되어야 한다.
- loop SKILL.md 변경은 loop.sh 드라이버의 동작 서술과 start가 받는 인자(`--max-iterations`·`--wall-clock-minutes`) 서술을 바꾸지 않아야 한다.

## 범위
포함:
- `plugins/autopilot/skills/loop/SKILL.md`의 start 실행 지침·Monitor 절·관련 옵션 서술·호출 안내·allowed-tools를 포그라운드 모델로 정리.

비-목표 / 제외:
- `loop.sh` 드라이버 코드 변경(드라이버는 포그라운드/백그라운드 호출 방식과 무관하게 동일 동작 — 변경 불필요).
- dispatch 스킬 변경. dispatch는 SKILL.md 지침이 아니라 셸(`LOOP_CMD="bash .../loop.sh"`)로 loop.sh를 직접 호출하고 자체 오케스트레이션으로 동시성을 관리하므로 본 변경의 영향을 받지 않는다.
- 워커 헌법(`constitution.md`)·기타 references 변경.
- 메인 세션의 라이브 Monitor 스트리밍 기능 자체를 다른 메커니즘으로 재구현하는 일(상실을 수용하고 디스크 아티팩트 관찰로 대체 안내).
- 플러그인 버전 범프(통합 단계에서 `rules/engineering/versioning.md`와 dispatch 버전 범프 게이트가 담당).

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않으며 프로젝트 규칙(rules/)에서 온다. -->
검증 기준의 단일 출처는 위 "완료 조건"이며, 검증 진입 명령은 프로젝트 규칙(`rules/`)을 따른다.
