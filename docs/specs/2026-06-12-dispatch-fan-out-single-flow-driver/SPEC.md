---
scope:
  include:
    - plugins/autopilot/skills/dispatch/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko (default)
---

# dispatch fan-out single flow driver

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
dispatch의 **fan-out 단계**(준비된 SPEC마다 워커 1개를 진행시키는 부분)를 구동하는 **드라이버 모델을 단일 `flow` 드라이버로 통합**한다.

기존에는 fan-out이 실행 환경 역량에 따라 **세 드라이버**(`strong-parallel`=내장 dynamic Workflow 도구, `background`, `foreground-batch`) 중 하나로 구동되고, 모델이 환경을 판정해 자동 선택하거나 `strong-parallel → background → foreground-batch`로 안전 강등했다. 이 변경은 그 **세 드라이버 구분과 자동 감지·override·안전 강등 사슬을 모두 제거**하고, 준비된 SPEC의 스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달을 **`flow` 스킬 하나를 통해** 수행한다.

또한 워커 spawn에 대한 dispatch의 서술을, 워커가 "부모 세션 권한을 상속하는 인세션 Agent 서브에이전트"여야 한다는 기존 전제 대신 **`flow`의 서브프로세스 에이전트 모델에 맞게 조정**한다.

이 변경은 **dispatch 스킬에 한정**된다 — 서술 계약(`SKILL.md`)과 드라이버 라우팅을 소유한 결정적 헬퍼(`dispatch.sh`) 양쪽을 함께 단일 flow 드라이버로 정리한다. dispatch의 준비도 스케줄링·DAG 구성·머지=done 전이·실패 이행 격리 같은 **결정적 코어의 의미는 보존**하고, fan-out을 무엇으로 구동하느냐만 바꾼다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->
dispatch의 fan-out을 Claude Code 전용 내장 dynamic Workflow 도구 대신 **Python 표준 라이브러리만으로 어디서나 동작하는 `flow` 스킬**로 구동해, Claude Code뿐 아니라 다양한 벤더 환경에서도 dispatch를 쓸 수 있게 한다. 동시에 환경마다 달라지는 **3단계 드라이버 감지·안전 강등 사슬의 환경 의존 복잡도를 제거**한다.

## 완료 조건
<!-- 5문장 패턴. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- **항상**: dispatch의 fan-out 단계는 단일 `flow` 드라이버로 구동되어야 한다 — `SKILL.md`와 `dispatch.sh` 어디에도 `strong-parallel`·`background`·`foreground-batch` 세 드라이버 구분이나 그 사이의 안전 강등 사슬에 대한 서술·코드가 남아 있지 않아야 한다(관찰: 두 파일에서 세 드라이버 이름과 강등 사슬 서술/분기가 검색되지 않음).
- **준비된 SPEC이 fan-out될 때**, dispatch는 `flow` 스킬의 공개 계약(워크플로 정의 입력 → 단일 JSON 결과)을 통해 의존성 그래프를 스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume으로 실행하고, 준비된 SPEC마다 워커 1개를 띄워야 한다(관찰: dispatch 서술·헬퍼가 flow의 입력→JSON 출력 계약으로 fan-out을 구동함).
- **워커를 띄울 때**, dispatch는 `flow`의 에이전트 노드(서브프로세스 에이전트 caller) 메커니즘으로 워커를 spawn하고, 워커 계약 전문(`references/subagent-prompt.md`)을 그 프롬프트에 embed하며 `spec`·`target-branch`·`run-dir`·`key`를 입력으로 넘겨야 한다(관찰: dispatch 서술이 인세션 Agent 도구 권한상속 전제 대신 flow 서브프로세스 워커 모델로 기술됨).
- **`python3` 3.9+가 사용 불가이면**, dispatch는 명확한 오류로 즉시 중단하고 사유를 안내해야 한다 — 다른 드라이버로 강등하지 않아야 한다(관찰: python3 미가용 환경에서 비-0 종료 + 강등 없음).
- **항상**: 드라이버 자동 감지·운영자 override(`DISPATCH_DRIVER` 3진값)·강등 신호(`DISPATCH_NO_STRONG_PARALLEL`/`DISPATCH_NO_BACKGROUND`)·드라이버 sticky 마커(`DRIVER`) 로직이 제거되고, 드라이버를 보고하던 관찰 진입점(`dispatch driver`·`dispatch status`의 `driver:` 라인)은 단일 `flow`만 일관되게 보고해야 한다(관찰: 위 환경 변수·마커가 더 이상 동작을 가르지 않고, 보고 진입점이 `flow`를 반환).
- **항상**: 워커 내부 단계(구현→리뷰→재구현→머지)의 데이터 의존 동기 순서, 승인 후 ff-only 머지, 머지=done 전이, 실패 이행 격리 같은 안전 불변식은 드라이버 통합과 무관하게 그대로 보존되어야 한다(관찰: 워커 계약·머지 게이트 서술이 의미상 변하지 않음).

## 범위
포함:
- dispatch `SKILL.md`의 "fan-out 드라이버" 섹션과 서브에이전트 위임·spawn 서술을 단일 `flow` 드라이버 모델로 재작성(세 드라이버 표·강등 사슬·`strong-parallel` 실행 경로 서술 제거, flow 호출 경로로 대체).
- `dispatch.sh`의 드라이버 감지·override·안전 강등 사슬·`DRIVER` sticky 마커·`driver` 보고 로직을 단일 `flow`로 정리.
- 워커 spawn 서술을 `flow`의 서브프로세스 에이전트 caller 모델에 맞게 조정.
- `python3` 미가용 시 hard-abort(폴백 없음) 경로.
- 위 변경에 직접 연관된 `SKILL.md` references 표·의존성·규칙 문구 정합.

비-목표 / 제외:
- `flow` 스킬·엔진(`workflow_replica`) 자체의 구현·동작 변경(별도 작업이며 PR #376에서 진행 중) — dispatch는 flow를 블랙박스 공개 계약으로만 호출한다.
- 워커 절차 계약(`references/subagent-prompt.md`)의 구현→리뷰→머지 로직 변경.
- dispatch의 준비도 스케줄링·DAG 구성·머지=done 전이·실패 이행 격리 같은 결정적 코어의 **의미** 변경(드라이버 구동 방식만 바꾸고 코어 의미는 보존).
- `dispatch start` 등 호출자에게 노출된 시작 인터페이스 변경.
- `loop`·`review` 등 다른 스킬 변경.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- **단일 `flow` 드라이버만** 둔다 — 드라이버 선택·override·안전 강등 사슬을 두지 않는다.
- `python3` 3.9+ 부재 시 **폴백 없이 hard-abort**한다(강등 사슬 자체를 제거하는 것이 이 변경의 핵심).
- flow 호출은 `flow` 스킬의 **공개 계약**(`flow run <정의 파일>` → 단일 JSON, 또는 `references/flow.sh`)을 통한다 — flow 엔진 내부 모듈을 직접 들여다보지 않는다(블랙박스 경계 보존).
- 호출자에게 노출된 **시작 인터페이스(`dispatch start ...`)는 변하지 않는다** — flow 통합은 dispatch 내부에서 일어난다.
- **멀티벤더**: 워커를 띄우는 서브프로세스 에이전트 caller는 벤더 중립이어야 한다(caller argv 주입 가능, 기본은 Claude). 특정 벤더 CLI에 하드 종속하지 않는다.

## 위험
- **flow 미머지 의존성**: `flow` 스킬은 현재 main에 없고 PR #376(`feat/workflow-replica-skill-flow`)에서 구현 중이다 — dispatch가 flow를 호출하려면 flow가 main에 머지·가용해야 한다(이 변경의 선행 의존성).
- **서브프로세스 워커의 권한·스킬 가용성**: flow의 서브프로세스 에이전트(예: `claude --print` 또는 벤더 CLI)가 autopilot 스킬·필요 권한을 갖고 unattended로 구현→리뷰→머지를 완수할 수 있어야 한다 — 인세션 Agent의 부모 권한 상속과 달리 이 가용성은 flow agent caller 설정·벤더 CLI 실행 환경에 의존한다. 환경이 이를 보장하지 못하면 워커가 권한·스킬 부재로 막힐 수 있다.
- **강등 제거의 트레이드오프**: 안전 강등 사슬을 없애므로 `python3` 없는 환경에서는 dispatch가 동작 불가가 된다 — hard-abort가 명시 동작이므로 의도된 트레이드오프이나, 기존에 동적/백그라운드 불가 환경에서 foreground-batch로 굴러가던 경로는 사라진다.
