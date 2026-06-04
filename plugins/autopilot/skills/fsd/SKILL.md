---
name: fsd
description: "자연어 의도 → SPEC → 구현 → 머지 파이프라인을 task 단위로 끝까지 **완전자율**로 닫고 싶을 때 사용 — SPEC 작성(spec)·구현 위임(dispatch)을 엔드투엔드로 오케스트레이션. 리뷰·머지는 dispatch 통합 모드(기본 ON)에 완전위임하며 fsd 내부엔 리뷰·머지·승인 게이트가 없다(외부 승인 보류·사람 개입 없음). 호출 'Skill(skill=\"fsd\", args=\"<subcommand> [<args>]\")' (intake/start/poll/status/list/stop)."
allowed-tools:
  - Read
  - Skill
  - Bash(bash * fsd.sh intake:*)
  - Bash(bash * fsd.sh start:*)
  - Bash(bash * fsd.sh poll)
  - Bash(bash * fsd.sh status:*)
  - Bash(bash * fsd.sh list)
  - Bash(bash * fsd.sh stop:*)
  - Bash(bash * fsd.sh selftest:*)
---

# fsd

`fsd` 는 spec-first 자동화 파이프라인을 **완전자율**로 닫는 task 오케스트레이터다. "자연어 의도 → SPEC 작성(spec) → 구현 위임(dispatch) → (dispatch가 소유하는) 리뷰·머지" 흐름을 task 단위로 운영한다. **리뷰·머지·통합(PR)은 fsd 가 직접 하지 않고 `dispatch` 의 통합 모드(기본 ON)에 완전위임**한다 — fsd 내부에는 리뷰·머지·승인 게이트가 없고, 외부 승인 보류나 사람 개입 지점도 없다. `dispatch start` 가 implement→통합→(forge 미구성이면 direct 서브모드의 ff-only)머지까지 자기 파이프라인에서 수행하고, fsd 는 `intake`(task 등록)·`start`(dispatch 위임)·`poll`(dispatch run 관측)만 책임진다.

fsd 는 `spec`·`loop`·`dispatch` 를 **공개 인터페이스로만** 조합한다. 그들의 내부 신호 파일·워크트리·run 디렉토리를 직접 들여다보지 않으며, 자기 상태 디렉토리(`.fsd/`) 밖의 경로를 만들지 않는다(자기 스킬 정의 파일 제외).

## 호출

`Skill(skill: "fsd", args: "<subcommand> [<args>]")`

또는 직접: `bash plugins/autopilot/skills/fsd/references/fsd.sh <subcommand> [<args>]`

### 진입 모드 — 자연어 의도 vs SPEC 경로

`fsd` 는 두 가지 입력으로 진입한다:

- **자연어 의도로 호출되면** (예: `Skill(skill: "fsd", args: "<자연어 task 설명>")`) — 먼저 `Skill(skill: "spec", args: "<자연어 task 설명>")` 로 SPEC 을 산출하고, 그 결과 SPEC 경로(들)로 `intake` → `start` 를 이어 구현까지 자동으로 닫는다. spec 의 명확화 인터뷰·미해결 마커 가드·최종 SPEC 산출은 그대로 수행되지만, **fsd 가 spec 을 호출하는 맥락에서는 spec 의 step-7 옵트인 핸드오프 프롬프트("구현까지 자동 진행할까요?")를 띄우지 않고 곧바로 진행**한다 — fsd 는 항상 자율이므로 진행 결정을 fsd 가 소유하며 그 확인은 중복이다. 별도의 신호 인자는 필요 없다(같은 오케스트레이터가 fsd→spec 를 연달아 실행하므로 호출 맥락만으로 생략이 성립한다). 산출된 SPEC 으로 task 등록·dispatch 위임이 사람 개입 없이 자동으로 흐른다. SPEC 에 `[NEEDS CLARIFICATION` 미해결 마커가 남으면 자동 진행을 멈추고 `--resume` 해결을 안내한다.
- **이미 SPEC 경로(들)가 주어지면** — spec 호출을 건너뛰고 바로 `intake <spec...>` → `start <spec...>` 를 수행한다.

어느 모드든 SPEC 산출은 `spec` 스킬의 책임(외부 상태 안 만듦)이고, task 등록·run 소유·dispatch 위임은 `fsd` 의 책임이며, 리뷰·머지·통합은 `dispatch` 통합 모드의 책임이다 — 이 역할 분리는 불변이다. 실효 자동 범위는 `intake → start`(dispatch 위임) → `poll`(dispatch run 관측 전이)까지 **완전자율**로 닫힌다. dispatch 가 통합·머지를 소유하므로 fsd 에는 별도의 `merge` 서브커맨드나 외부 승인 보류 게이트가 없다 — `poll` 은 dispatch run 의 모든 SPEC 이 머지 종착에 도달하면 task 를 `done` 으로 전이할 뿐이다.

## 모델

- **단위**: task. 하나의 task 는 한 작업 의도(보통 SPEC 한 묶음)에 대응하며, 진행 상태를 `<project_root>/.fsd/tasks/<task-id>/` 아래 격리 디렉토리에 보관한다.
- **task-id**: 첫 SPEC 의 slug + 입력 SPEC 집합 sha7. 같은 SPEC 집합으로 재진입하면 같은 task-id 를 얻어 idempotent 하다.
- **위임**: SPEC 작성은 `spec` 스킬의 공개 호출(`Skill(skill: "spec", ...)`)로, 구현·리뷰·머지는 `dispatch` 의 공개 서브커맨드(`dispatch start <spec...>` — 통합 모드 기본 ON)로만 한다. fsd 는 dispatch run 상태를 `dispatch status` 공개 인터페이스로 관측한다.
- **상태 저장소**: task 별 디렉토리에 상태 미러·SPEC 경로·소유한 dispatch run-id·origin·append-only 로그를 담는다. 리뷰·머지·통합은 dispatch 가 소유하므로 forge 부수효과(브랜치·PR·head)는 fsd 상태에 보관하지 않는다. 이 디렉토리는 git 추적에서 제외한다(`.gitignore` 의 `.fsd/`).
- **완전자율**: fsd 는 외부 승인 보류·사람 개입 지점 없이 `intake → start → poll` 로 task 를 done 까지 전진시킨다. 리뷰·머지의 자율성은 dispatch 통합 모드(direct 서브모드: 분리 승인 신원 없이 ff-only 머지)가 제공한다.

## 상태 저장소 레이아웃

```
<project_root>/.fsd/
└── tasks/
    └── <task-id>/
        ├── state          # 상태 로컬 미러 (intake|dispatching|dispatched|stopped|done|dispatch-failed)
        ├── SPECS.txt       # 이 task 의 SPEC 경로 목록 (append-only, 한 줄에 하나)
        ├── run-id          # 이 task 가 소유한 dispatch run 식별자
        ├── origin          # 이 task 를 촉발한 원본 task 식별자 (버그 분리 연결, 선택)
        └── LOG.md          # append-only 이벤트 로그
```

## Subcommands

fsd 는 4 서브커맨드(`intake`·`start`·`poll`·`status`/`list`/`stop`)를 갖는다. 리뷰·머지·통합은 `dispatch` 통합 모드가 소유하므로 fsd 서브커맨드에 포함되지 않는다(별도 `merge` 서브커맨드 없음).

### fsd intake `[--origin <task-id>]` `<spec...>`

자연어 의도를 SPEC 으로 떠서(상위 spec 스킬 위임 결과) 얻은 SPEC 경로(들)로 새 task 를 등록한다.

- 입력: 1 개 이상의 SPEC 파일 경로. 각 경로는 파일로 존재하고 읽을 수 있어야 한다(아니면 abort).
- 옵션 `--origin <task-id>`: 이 task 를 촉발한 **원본 task** 와의 연결을 `origin` 필드에 기록한다(진행 중 버그 분리에서 사용). 생략하면 origin 기록 없이 기존과 동일하게 등록한다(하위 호환).
- 동작: task-id 를 도출하고 `.fsd/tasks/<task-id>/` 를 생성, SPEC 경로를 `SPECS.txt` 에 기록, `state=intake` 로 설정, `--origin` 이 주어지면 `origin` 에 기록, `LOG.md` 에 이벤트를 남긴다.
- 출력: `task-id: <task-id>`.

### fsd start `<spec...>`

task 의 SPEC(들)을 자율 실행기 오케스트레이터(`dispatch`)에 위임해 구현을 시작한다.

- 입력: 1 개 이상의 SPEC 파일 경로(검증·절대경로화).
- **미해결 마커 가드**: 입력 SPEC 중 하나라도 미해결 사용자-결정 마커(`[NEEDS CLARIFICATION` 로 시작)를 포함하면 dispatch 위임을 하지 않는다 — `state=needs-clarification` 으로 기록하고, 마커를 가진 SPEC 마다 `needs-resume: <SPEC-경로>` 를 출력한 뒤 비-0 으로 종료한다. 빈 칸은 `spec --resume <SPEC-경로>` 로 채운 뒤 다시 `start` 한다.
- 동작(마커 없을 때): task-id 도출 후 디렉토리를 보장하고(미등록이면 `SPECS.txt` 기록), `state=dispatching` → `dispatch start <spec...>` 공개 서브커맨드로 위임 → 그 출력에서 run 식별자를 추출해 `run-id` 에 기록 → `state=dispatched`.
- 출력: `task-id: <task-id>` 와 `run-id: <run-id>`.
- 실패: dispatch 출력에서 run-id 를 얻지 못하면 `state=dispatch-failed` 로 기록하고 dispatch 출력과 함께 abort.
- **리뷰·머지**: `dispatch start` 는 통합 모드(기본 ON)로 위임되므로(`--no-integrate` 미전달), dispatch 가 loop 구현 후 통합(PR)→리뷰→(direct 서브모드)ff-only 머지까지 자기 run 안에서 수행한다. fsd 는 이를 다시 하지 않는다.

### fsd poll

진행 중인 모든 task 의 dispatch run 을 관측해 done 까지 전진시킨다(멱등, 상시 호스트 운영 진입점, 완전자율).

- 동작: `poll.sh poll` 로 위임한다(주입 가능 `FSD_POLL_CMD`). run-id 를 가진 task 마다 `dispatch status <run-id>` 공개 인터페이스로 per-SPEC state 를 관측해, **모든 SPEC 이 머지 종착(`done`)이면 task 를 `done` 으로 전이**하고, 아직 진행 중이면 상태를 바꾸지 않는다. 호출 단위 무상태·멱등이라 재실행이 안전하다.
- **사람 개입·외부 승인 보류 없음**: poll 은 PR 생성·리뷰·승인 조회·머지를 호출하지 않는다 — 그 책임은 dispatch 통합 모드에 있다. dispatch 가 머지하지 못하는 환경에서는 task 가 done 에 이르지 못한 채 멈추지 않고 멱등 재드레인하며 상태를 바꾸지 않는다.

### fsd status `<task-id>`

task 단위로 상태 미러·origin(원본 task 연결)·소유 run-id·SPEC 목록을 표 형태로 출력한다. origin 이 없으면 빈 값으로 표시한다.

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
| `fsd.sh` | 서브커맨드 라우터 + 프로젝트 루트 탐지 + intake/start 의 spec·dispatch 블랙박스 조합 |
| `poll.sh` | dispatch run 관측 드레인(`dispatch status` 공개 인터페이스로 done 전이, 멱등) |
| `lib-state.sh` | `.fsd/tasks/<task-id>/` 상태 저장소 헬퍼(set/get 필드·log_event·run-id 기록·list 등) |
| `operational-guide.md` | 상시 호스트 무인 운영 가이드(토큰 스코프·실행기 권한 격리·폴링 주기) |
| `forge-integration.md` | loop 코어 신호 계약과 forge 통합(리뷰·머지) 책임이 dispatch 에 있음을 명시 |

## 의존성

`git`, `bash` 3.2+, `sha256sum` 또는 `shasum`, `autopilot:spec`·`autopilot:dispatch` 스킬. 리뷰·머지·forge(`gh` 등) 연동은 fsd 의 직접 의존성이 아니라 `dispatch` 통합 모드의 책임이다.

## 불변식 / 규칙

- fsd 는 `.fsd/` 디렉토리 밖 경로를 만들지 않는다(자기 스킬 정의 파일 제외).
- `spec`·`loop`·`dispatch` 의 정의 파일을 수정하지 않고, 공개 인터페이스만 소비한다.
- 구현·리뷰·머지 위임은 `dispatch start <spec...>`(통합 모드 ON) 공개 서브커맨드로만 하고, dispatch run 관측은 `dispatch status` 로만 한다 — dispatch·loop 의 내부 신호 파일·run 디렉토리·워크트리를 직접 들여다보지 않는다.
- fsd 는 리뷰·머지·통합(PR)을 직접 하지 않고 forge CLI 를 호출하지 않는다 — 그 책임은 dispatch 통합 모드에 있다.
- 완전자율: fsd 파이프라인에는 외부 승인 보류·사람 개입 게이트가 없다.
- 상태 디렉토리(`.fsd/`)는 git 추적에서 제외한다.
- 라우터는 bash 3.2+ 호환으로 작성한다.
