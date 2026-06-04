---
name: fsd
description: "자연어 의도 → SPEC → 구현 → 리뷰 → 머지 파이프라인을 task 단위로 끝까지 자동으로 닫고 싶을 때 사용 — SPEC 작성(spec)·구현 위임(dispatch)을 forge/task backend 위에서 엔드투엔드로 오케스트레이션. 호출 'Skill(skill=\"fsd\", args=\"<subcommand> [<args>]\")' (intake/start/review/merge/poll/status/list/stop)."
---

# fsd

`fsd` 는 `spec`·`loop`·`dispatch` 가 의도적으로 비워둔 **forge 호출 레이어**를 구현하는 오케스트레이터다. spec-first 자동화 파이프라인을 엔드투엔드로 닫는 컴포넌트로, "자연어 의도 → SPEC 작성(spec) → 구현(dispatch) → 리뷰 → 머지" 흐름을 task 단위로 운영한다.

fsd 는 `spec`·`loop`·`dispatch` 를 **공개 인터페이스로만** 조합한다. 그들의 내부 신호 파일·워크트리·run 디렉토리를 직접 들여다보지 않으며, 자기 상태 디렉토리(`.fsd/`) 밖의 경로를 만들지 않는다(자기 스킬 정의 파일 제외).

## 호출

`Skill(skill: "fsd", args: "<subcommand> [<args>]")`

또는 직접: `bash plugins/autopilot/skills/fsd/references/fsd.sh <subcommand> [<args>]`

### 진입 모드 — 자연어 의도 vs SPEC 경로

`fsd` 는 두 가지 입력으로 진입한다:

- **자연어 의도로 호출되면** (예: `Skill(skill: "fsd", args: "<자연어 task 설명>")`) — 먼저 `Skill(skill: "spec", args: "<자연어 task 설명>")` 로 SPEC 을 산출하고, 그 결과 SPEC 경로(들)로 `intake` → `start` 를 이어 구현까지 자동으로 닫는다. spec 의 명확화 인터뷰·최종 단일 승인은 그대로 수행되어 자기완결 SPEC 을 보장하며, 승인된 SPEC 으로 task 등록·dispatch 위임이 자동으로 흐른다. SPEC 에 `[NEEDS CLARIFICATION` 미해결 마커가 남으면 자동 진행을 멈추고 `--resume` 해결을 안내한다.
- **이미 SPEC 경로(들)가 주어지면** — spec 호출을 건너뛰고 바로 `intake <spec...>` → `start <spec...>` 를 수행한다.

어느 모드든 SPEC 산출은 `spec` 스킬의 책임(외부 상태 안 만듦)이고, task 등록·run 소유·forge 연동은 `fsd` 의 책임이다 — 이 역할 분리는 불변이다. 현재 실효 자동 범위는 `intake → start`(dispatch 위임)에 더해 `review`(리뷰 생산자 호출→판정 분기)·`poll`(드레인 전이)까지이며, `merge`(C4) 만 미구현 핸들러다(아래 Subcommands 참조).

## 모델

- **단위**: task. 하나의 task 는 한 작업 의도(보통 SPEC 한 묶음)에 대응하며, 진행 상태를 `<project_root>/.fsd/tasks/<task-id>/` 아래 격리 디렉토리에 보관한다.
- **task-id**: 첫 SPEC 의 slug + 입력 SPEC 집합 sha7. 같은 SPEC 집합으로 재진입하면 같은 task-id 를 얻어 idempotent 하다.
- **위임**: SPEC 작성은 `spec` 스킬의 공개 호출(`Skill(skill: "spec", ...)`)로, 구현은 `dispatch` 의 공개 서브커맨드(`dispatch start <spec...>`)로만 한다.
- **상태 저장소**: task 별 디렉토리에 상태 미러·SPEC 경로·브랜치·PR 번호·소유한 dispatch run-id·append-only 로그·리뷰 라운드 카운터·마지막 head 식별자를 담는다. 이 디렉토리는 git 추적에서 제외한다(`.gitignore` 의 `.fsd/`).
- **골격 범위(C0)**: 본 단위는 정의 문서·서브커맨드 라우터·상태 저장소 헬퍼까지만 만든다. `intake`·`start` 는 spec·dispatch 조합까지만 수행하고, forge·task backend 동작(이슈 생성·PR·머지·상태 전이)은 후속 단위의 자리(미구현 핸들러)로 남긴다.

## 상태 저장소 레이아웃

```
<project_root>/.fsd/
└── tasks/
    └── <task-id>/
        ├── state          # 상태 로컬 미러 (intake|dispatching|dispatched|stopped|...|done|failed)
        ├── SPECS.txt       # 이 task 의 SPEC 경로 목록 (append-only, 한 줄에 하나)
        ├── branch          # 작업 브랜치 이름            (forge 연동은 후속 단위)
        ├── pr              # PR 번호                      (forge 연동은 후속 단위)
        ├── run-id          # 이 task 가 소유한 dispatch run 식별자
        ├── review-round    # 리뷰 라운드 카운터          (review 오케스트레이션이 누적)
        ├── head            # 마지막으로 관측한 head 식별자
        ├── origin          # 이 task 를 촉발한 원본 task 식별자 (버그 분리 연결, 선택)
        └── LOG.md          # append-only 이벤트 로그
```

## Subcommands

본 골격(C0)이 6 서브커맨드(`intake`·`start`·`review`·`merge`·`poll`·`status`/`list`/`stop`)의 책임과 입출력 계약을 **완전판**으로 고정한다. 후속 단위(C1~C5)는 이 계약을 입력 컨텍스트로 차용하며 SKILL.md 는 C0 단독 소유로 둔다(병렬 wave 충돌 방지).

### fsd intake `[--origin <task-id>]` `<spec...>`

자연어 의도를 SPEC 으로 떠서(상위 spec 스킬 위임 결과) 얻은 SPEC 경로(들)로 새 task 를 등록한다.

- 입력: 1 개 이상의 SPEC 파일 경로. 각 경로는 파일로 존재하고 읽을 수 있어야 한다(아니면 abort).
- 옵션 `--origin <task-id>`: 이 task 를 촉발한 **원본 task** 와의 연결을 `origin` 필드에 기록한다(진행 중 버그 분리에서 사용). 생략하면 origin 기록 없이 기존과 동일하게 등록한다(하위 호환).
- 동작: task-id 를 도출하고 `.fsd/tasks/<task-id>/` 를 생성, SPEC 경로를 `SPECS.txt` 에 기록, `state=intake` 로 설정, `--origin` 이 주어지면 `origin` 에 기록, `LOG.md` 에 이벤트를 남긴다.
- 출력: `task-id: <task-id>`.
- **후속(C1)**: task backend(Issue/Project) 항목 생성·연결.

### fsd start `<spec...>`

task 의 SPEC(들)을 자율 실행기 오케스트레이터(`dispatch`)에 위임해 구현을 시작한다.

- 입력: 1 개 이상의 SPEC 파일 경로(검증·절대경로화).
- **미해결 마커 가드**: 입력 SPEC 중 하나라도 미해결 사용자-결정 마커(`[NEEDS CLARIFICATION` 로 시작)를 포함하면 dispatch 위임을 하지 않는다 — `state=needs-clarification` 으로 기록하고, 마커를 가진 SPEC 마다 `needs-resume: <SPEC-경로>` 를 출력한 뒤 비-0 으로 종료한다. 빈 칸은 `spec --resume <SPEC-경로>` 로 채운 뒤 다시 `start` 한다.
- 동작(마커 없을 때): task-id 도출 후 디렉토리를 보장하고(미등록이면 `SPECS.txt` 기록), `state=dispatching` → `dispatch start <spec...>` 공개 서브커맨드로 위임 → 그 출력에서 run 식별자를 추출해 `run-id` 에 기록 → `state=dispatched`.
- 출력: `task-id: <task-id>` 와 `run-id: <run-id>`.
- 실패: dispatch 출력에서 run-id 를 얻지 못하면 `state=dispatch-failed` 로 기록하고 dispatch 출력과 함께 abort.
- **후속(C2)**: DONE→push→PR forge 통합.

### fsd review `<task-id>`

리뷰 생산자(`autopilot:review`)를 한 작업에 대해 1회 호출해 단일 판정을 얻고 그에 따라 전이한다.

- 입력: task-id. task 의 SPEC 경로·PR·브랜치를 상태 저장소에서 조회한다(PR 미생성이면 abort — 먼저 통합 필요).
- 동작: `review-loop.sh run` 으로 단일 라운드를 위임한다(주입 가능 `FSD_REVIEW_CMD`). review-loop 가 생산자 판정을 받아:
  - `request_changes` → 분류된 재작업 브리프(`rework_brief.must_adopt`)를 SPEC 델타로 만들어 구현(loop)을 재위임하고 같은 head 브랜치로 재푸시(새 PR 미생성·force 금지), `review-round` 증가. `defer` 지적은 별도 백로그 task 로 분리.
  - `approve` → 머지 진행가능 상태로 전이(`state=review-approved`), 추가 라운드 미시작.
  - `unavailable`·사람 리뷰어의 변경 요청 → 자동수정 멈추고 사람에게 에스컬레이션(승인 요청 Review 유지).
- 가드: 라운드 수 상한(기본 3) 초과·무진전(must_adopt 0)·핑퐁(차단성 집합 직전 동일)이면 멈추고 에스컬레이션. 수렴(iterate-until-approved) 반복은 `poll` 드레인이 소유한다(한 호출=한 라운드).
- 채택 분류는 `rules/change-adoption.md`, 리뷰 원칙은 `rules/review.md` 를 단일 출처로 따른다(생산자가 적용).

### fsd merge `<task-id>`

리뷰 통과한 task 를 머지하고 Done 처리·cleanup 한다.

- 본 골격(C0): **미구현**. 호출 시 미구현 안내를 출력하고 비-0(2) 으로 종료.
- **후속(C4)**: 머지·task backend Done 전이·브랜치/워크트리 cleanup.

### fsd poll

진행 중인 모든 task 를 한 바퀴 드레인하며 각 task 를 가능한 다음 한 스텝으로 전진시킨다(멱등, 상시 호스트 운영 진입점).

- 동작: `poll.sh poll` 로 위임한다(주입 가능 `FSD_POLL_CMD`). 리뷰 상태 task 는 위 `review` 전이를 한 라운드 적용하고, 그 외는 start·integrate·merge 경로를 전이적으로 적용한다. 호출 단위 무상태·멱등이라 재실행이 안전하다.
- 수렴: `review` 가 한 호출=한 라운드이므로, 리뷰→재구현→재리뷰→승인 수렴은 poll 의 반복 드레인이 소유한다(라운드 카운터·가드는 상태 저장소에 누적).

### fsd status `<task-id>`

task 단위로 상태 미러·origin(원본 task 연결)·소유 run-id·브랜치·PR·리뷰 라운드·head·SPEC 목록을 표 형태로 출력한다. origin 이 없으면 빈 값으로 표시한다.

### fsd list

`.fsd/tasks/` 아래 모든 task 와 요약(state·run-id)을 표시한다. **빈 상태에서도 오류 없이(0 exit) 정상 출력**(빈 목록 안내)을 낸다.

### fsd stop `<task-id>`

task 가 소유한 dispatch run 을 `dispatch` 의 공개 `stop` 서브커맨드로 정지 위임하고 `state=stopped` 로 기록한다. 연결된 run 이 없으면 안내만 출력하고 0 exit.

## 진행 중 버그 분리 (start 중 관찰한 버그를 큐잉 task 로)

`fsd start` 로 한 task 를 진행하는 도중 오케스트레이터가 **작업과 별개의 버그**를 관찰하면, 현재 task 를 중단하지 않고 그 버그를 별도의 **큐잉 버그-수정 task** 로 분리한다. 사용자 결정은 그 버그 task 를 실제로 진행하는 시점까지 미룬다.

절차:

1. **버그 관찰** — 현재 task 진행 중 부수 버그를 발견한다(현재 task 는 계속 진행).
2. **버그 SPEC 작성** — `spec` 스킬로 버그 SPEC 을 작성하되, **사용자 결정이 필요한 지점은 비워둔다** — spec 의 기존 `[NEEDS CLARIFICATION]` 마커로 표시한다(새 메커니즘 도입 없음). SPEC 저작은 spec 스킬의 책임이다.
3. **큐잉** — `fsd intake --origin <현재-task-id> <버그-SPEC>` 로 버그 task 를 등록한다. `origin` 에 원본 task 연결이 기록된다.
4. **현재 task 계속** — 버그 task 는 큐에 남고, 현재 task 의 의도를 흐리지 않는다. 발견 즉시 사람을 붙잡지 않는다.
5. **나중 진행** — 버그 task 를 `fsd start <버그-SPEC>` 로 진행하면 미해결 마커 가드가 마커를 감지해 dispatch 를 막고 `needs-resume: <SPEC-경로>` 를 알린다. `spec --resume <SPEC-경로>` 로 빈 칸(사용자 결정)을 채운 뒤 다시 `start` 하면 마커가 사라져 dispatch 가 시작된다.

계약 요약:
- intake 의 `--origin <task-id>` — 분리 task 의 출처를 origin 필드로 기록(선택).
- start 의 마커 가드 — `[NEEDS CLARIFICATION` 보유 SPEC 은 dispatch 전 차단, `state=needs-clarification`, SPEC 마다 `needs-resume:` 출력, 비-0 종료.
- 상태 레이아웃의 `origin` 필드 — `fsd status` 에 노출.

이 분리는 `fsd bug` 같은 신규 서브커맨드 없이 **start 절차 + 기존 intake 재사용**으로 이뤄지며, loop 시그널 계약(`signals/DONE`·`BLOCKED`)에 새 시그널을 추가하지 않는다. 빈 칸 표현·진행 시 채움은 spec 의 기존 `[NEEDS CLARIFICATION]` 마커 + `spec --resume` 관례를 그대로 쓴다.

## references

| 파일 | 역할 |
|---|---|
| `fsd.sh` | 서브커맨드 라우터 + 프로젝트 루트 탐지 + intake/start 의 spec·dispatch 블랙박스 조합(forge 없음) |
| `lib-state.sh` | `.fsd/tasks/<task-id>/` 상태 저장소 헬퍼(set/get 필드·log_event·run-id 기록·list 등) |

## 의존성

`git`, `bash` 3.2+, `sha256sum` 또는 `shasum`, `autopilot:spec`·`autopilot:dispatch` 스킬. forge(`gh` 등)·task backend 연동은 본 골격 의존성이 아니며 후속 단위 references 모듈의 책임이다.

## 불변식 / 규칙

- fsd 는 `.fsd/` 디렉토리 밖 경로를 만들지 않는다(자기 스킬 정의 파일 제외).
- `spec`·`loop`·`dispatch` 의 정의 파일을 수정하지 않고, 공개 인터페이스만 소비한다.
- 구현 위임은 `dispatch start <spec...>` 공개 서브커맨드로만 하고, dispatch·loop 의 내부 신호 파일·워크트리를 직접 들여다보지 않는다.
- 본 골격은 forge CLI 를 직접 호출하지 않는다(forge 연동은 후속 단위 references 모듈 책임).
- 상태 디렉토리(`.fsd/`)는 git 추적에서 제외한다.
- 라우터는 bash 3.2+ 호환으로 작성한다.
