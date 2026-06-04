---
scope:
  include:
    - plugins/autopilot/skills/fsd/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# fsd start bug spinoff to queued task

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
`fsd start` 진행 중 오케스트레이터가 작업과 별개의 버그를 관찰했을 때, 그 버그를
**현재 task를 중단하지 않고** 별도의 **큐잉 버그-수정 task**로 분리하는 능력을
fsd에 추가한다. 분리된 버그 task의 SPEC에서 **사용자 결정이 필요한 지점은 비워둔
채**(미해결 마커) 등록되며, 그 task를 나중에 `fsd start`로 진행할 때 빈 칸이 먼저
채워진 뒤에야 구현(dispatch)이 시작된다. 분리된 버그 task는 자신을 촉발한 **원본
task와의 연결(origin)** 을 기록한다.

구체적으로 다음 관찰 가능한 능력을 갖춘다:
- `fsd intake` 가 분리 task의 출처를 기록하는 선택적 origin 링크를 받는다.
- `fsd start` 가 입력 SPEC의 미해결 사용자-결정 마커를 감지해, 해결 전에는 구현
  위임을 막고 어느 SPEC을 해결해야 하는지 알린다.
- `fsd status` 가 origin 링크를 노출한다.
- fsd 스킬 정의 문서가 "진행 중 버그 분리" 절차와 위 계약을 단일 출처로 기술한다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->
fsd 구현 도중 발견한 부수 버그를 현재 task의 의도를 흐리지 않고 안전하게 별도
작업으로 떼어내, 누락 없이 같은 파이프라인으로 흘려보내기 위함이다. 동시에 그
버그에 대한 사용자 결정은 실제로 그 task를 진행하는 시점까지 미뤄, 발견 즉시
사람을 붙잡지 않으면서도 미결정 상태로 자동 구현이 시작되는 것을 막는다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면) -->
1. `fsd intake --origin <task-id> <spec...>` 로 task를 등록**할 때**, 등록된 task의
   origin이 그 `<task-id>` 로 기록되고 `fsd status` 출력에 그 값이 표시된다.
2. `--origin` 없이 `fsd intake <spec...>` 를 호출**할 때**, origin 기록 없이 기존과
   동일하게 task가 등록된다(하위 호환 — 기존 출력·상태 전이 불변).
3. `fsd start <spec...>` 의 입력 SPEC 중 하나라도 미해결 사용자-결정 마커
   (`[NEEDS CLARIFICATION` 로 시작하는 마커)를 포함**하면(오류성 가드)**, dispatch
   위임이 일어나지 않고 task state가 `needs-clarification` 으로 기록되며, 마커를 가진
   SPEC마다 `needs-resume: <SPEC-경로>` 가 출력되고 명령은 비-0으로 종료한다.
4. 입력 SPEC에 미해결 마커가 없을 **때**, `fsd start` 는 기존대로 dispatch에 구현을
   위임하고 run-id를 기록하며 task state가 `dispatched` 가 된다(회귀 없음).
5. **항상** `fsd.sh selftest` 는 (a) `--origin` 기록, (b) 마커 보유 SPEC의 start
   차단·미-dispatch·`needs-resume:` 출력, (c) 마커 없는 SPEC의 정상 dispatch 회귀를
   각각 검증하는 케이스를 포함하여 전부 통과한다.
6. **항상** spec·loop·dispatch 스킬의 정의 파일과 그 공개 인터페이스(서브커맨드·시그널
   계약)는 이 변경으로 수정되지 않는다 — SPEC 작성은 spec, task 등록·run 소유는 fsd
   라는 역할 분리가 유지된다.
7. fsd 스킬 정의 문서(SKILL.md)에 다음이 기술**될 때** 충족된다: "진행 중 버그 분리"
   절차(start 중 버그 관찰 → spec으로 버그 SPEC 작성하되 사용자-결정 지점은 마커로
   비워둠 → `intake --origin` 으로 큐잉 → 현재 task 계속 → 나중 `start` 시 마커 감지로
   `spec --resume` 후 dispatch), 그리고 intake의 `--origin` 인자·start의 마커 가드·상태
   레이아웃의 origin 필드.

## 범위
포함:
- `plugins/autopilot/skills/fsd/references/lib-state.sh` — origin 필드 set/get 래퍼.
- `plugins/autopilot/skills/fsd/references/fsd.sh` — intake `--origin`, start 마커 가드,
  status origin 출력, selftest 케이스, usage 표기.
- `plugins/autopilot/skills/fsd/SKILL.md` — 버그 분리 절차·계약·레이아웃 문서화.

비-목표 / 제외:
- spec·loop·dispatch 스킬 정의 파일 수정.
- loop 시그널 계약(`signals/DONE`·`BLOCKED`)에 새 시그널 추가(버그 자동 감지 경로 미채택).
- `fsd bug` 같은 신규 서브커맨드(분리는 start 절차 + 기존 intake 재사용).
- review·merge·poll 서브커맨드 동작 변경.
- spec 스킬이 마커를 만들고 `--resume` 로 해소하는 기존 메커니즘 자체의 변경.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된
것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이
단일 출처로 정의한다.

## 제약 (있을 때만)
- bash 3.2+ 호환(associative array 미사용) — 기존 `fsd.sh`·`lib-state.sh` 규약 유지.
- 미해결 마커 감지는 `[NEEDS CLARIFICATION` prefix 매칭으로 spec 스킬의 기존 관례와
  일치시킨다(닫는 괄호에 의존하지 않음).
- origin·마커-가드 구현은 기존 헬퍼(`set_field`/`get_field`, `validate_specs`,
  `derive_task_id`, `ensure_task_dir`)와 selftest의 mock 주입 패턴(`FSD_STATE_ROOT`·
  `DISPATCH_CMD` 치환·TRACE 파일)을 재사용한다.
- 빈 칸 표현·진행 시 채움은 새 메커니즘을 도입하지 않고 spec의 기존
  `[NEEDS CLARIFICATION]` 마커 + `spec --resume` 관례를 재사용한다.
- fsd는 `.fsd/` 밖 경로를 만들지 않으며 SPEC을 직접 저작하지 않는다(저작은 spec 스킬).

## 위험 (있을 때만)
- start의 마커 가드가 자연어 진입(spec→intake→start) 흐름을 깨면 안 된다 — 승인된
  SPEC은 마커가 없으므로 가드에 걸리지 않아야 한다(완료 조건 4가 이 회귀를 고정).
