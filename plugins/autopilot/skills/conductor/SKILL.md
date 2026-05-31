---
name: conductor
description: "자연어 의도 → SPEC → 구현 → 리뷰 → 머지 파이프라인을 task 단위로 끝까지 자동으로 닫고 싶을 때 사용 — SPEC 작성(spec)·구현 위임(dispatch)을 forge/task backend 위에서 엔드투엔드로 오케스트레이션. 호출 'Skill(skill=\"conductor\", args=\"<subcommand> [<args>]\")' (intake/start/review/merge/poll/status/list/stop)."
---

# conductor

`conductor` 는 `spec`·`loop`·`dispatch` 가 의도적으로 비워둔 **forge 호출 레이어**를 구현하는 오케스트레이터다. spec-first 자동화 파이프라인을 엔드투엔드로 닫는 컴포넌트로, "자연어 의도 → SPEC 작성(spec) → 구현(dispatch) → 리뷰 → 머지" 흐름을 task 단위로 운영한다.

conductor 는 `spec`·`loop`·`dispatch` 를 **공개 인터페이스로만** 조합한다. 그들의 내부 신호 파일·워크트리·run 디렉토리를 직접 들여다보지 않으며, 자기 상태 디렉토리(`.conductor/`) 밖의 경로를 만들지 않는다(자기 스킬 정의 파일 제외).

## 호출

`Skill(skill: "conductor", args: "<subcommand> [<args>]")`

또는 직접: `bash plugins/autopilot/skills/conductor/references/conductor.sh <subcommand> [<args>]`

## 모델

- **단위**: task. 하나의 task 는 한 작업 의도(보통 SPEC 한 묶음)에 대응하며, 진행 상태를 `<project_root>/.conductor/tasks/<task-id>/` 아래 격리 디렉토리에 보관한다.
- **task-id**: 첫 SPEC 의 slug + 입력 SPEC 집합 sha7. 같은 SPEC 집합으로 재진입하면 같은 task-id 를 얻어 idempotent 하다.
- **위임**: SPEC 작성은 `spec` 스킬의 공개 호출(`Skill(skill: "spec", ...)`)로, 구현은 `dispatch` 의 공개 서브커맨드(`dispatch start <spec...>`)로만 한다.
- **상태 저장소**: task 별 디렉토리에 상태 미러·SPEC 경로·브랜치·PR 번호·소유한 dispatch run-id·append-only 로그·리뷰 라운드 카운터·마지막 head 식별자를 담는다. 이 디렉토리는 git 추적에서 제외한다(`.gitignore` 의 `.conductor/`).
- **골격 범위(C0)**: 본 단위는 정의 문서·서브커맨드 라우터·상태 저장소 헬퍼까지만 만든다. `intake`·`start` 는 spec·dispatch 조합까지만 수행하고, forge·task backend 동작(이슈 생성·PR·머지·상태 전이)은 후속 단위의 자리(미구현 핸들러)로 남긴다.

## 상태 저장소 레이아웃

```
<project_root>/.conductor/
└── tasks/
    └── <task-id>/
        ├── state          # 상태 로컬 미러 (intake|dispatching|dispatched|stopped|...|done|failed)
        ├── SPECS.txt       # 이 task 의 SPEC 경로 목록 (append-only, 한 줄에 하나)
        ├── branch          # 작업 브랜치 이름            (forge 연동은 후속 단위)
        ├── pr              # PR 번호                      (forge 연동은 후속 단위)
        ├── run-id          # 이 task 가 소유한 dispatch run 식별자
        ├── review-round    # 리뷰 라운드 카운터          (review 루프는 후속 단위)
        ├── head            # 마지막으로 관측한 head 식별자
        └── LOG.md          # append-only 이벤트 로그
```

## Subcommands

본 골격(C0)이 6 서브커맨드(`intake`·`start`·`review`·`merge`·`poll`·`status`/`list`/`stop`)의 책임과 입출력 계약을 **완전판**으로 고정한다. 후속 단위(C1~C5)는 이 계약을 입력 컨텍스트로 차용하며 SKILL.md 는 C0 단독 소유로 둔다(병렬 wave 충돌 방지).

### conductor intake `<spec...>`

자연어 의도를 SPEC 으로 떠서(상위 spec 스킬 위임 결과) 얻은 SPEC 경로(들)로 새 task 를 등록한다.

- 입력: 1 개 이상의 SPEC 파일 경로. 각 경로는 파일로 존재하고 읽을 수 있어야 한다(아니면 abort).
- 동작: task-id 를 도출하고 `.conductor/tasks/<task-id>/` 를 생성, SPEC 경로를 `SPECS.txt` 에 기록, `state=intake` 로 설정, `LOG.md` 에 이벤트를 남긴다.
- 출력: `task-id: <task-id>`.
- **후속(C1)**: task backend(Issue/Project) 항목 생성·연결.

### conductor start `<spec...>`

task 의 SPEC(들)을 자율 실행기 오케스트레이터(`dispatch`)에 위임해 구현을 시작한다.

- 입력: 1 개 이상의 SPEC 파일 경로(검증·절대경로화).
- 동작: task-id 도출 후 디렉토리를 보장하고(미등록이면 `SPECS.txt` 기록), `state=dispatching` → `dispatch start <spec...>` 공개 서브커맨드로 위임 → 그 출력에서 run 식별자를 추출해 `run-id` 에 기록 → `state=dispatched`.
- 출력: `task-id: <task-id>` 와 `run-id: <run-id>`.
- 실패: dispatch 출력에서 run-id 를 얻지 못하면 `state=dispatch-failed` 로 기록하고 dispatch 출력과 함께 abort.
- **후속(C2)**: DONE→push→PR forge 통합.

### conductor review `<task-id>`

PR 리뷰 피드백을 받아 추가 loop 라운드로 반영하는 루프.

- 본 골격(C0): **미구현**. 호출 시 미구현 안내를 출력하고 비-0(2) 으로 종료.
- **후속(C3)**: 리뷰 코멘트 수집 → loop 재위임 → `review-round` 증가 → 재푸시.

### conductor merge `<task-id>`

리뷰 통과한 task 를 머지하고 Done 처리·cleanup 한다.

- 본 골격(C0): **미구현**. 호출 시 미구현 안내를 출력하고 비-0(2) 으로 종료.
- **후속(C4)**: 머지·task backend Done 전이·브랜치/워크트리 cleanup.

### conductor poll

진행 중인 모든 task 의 dispatch run 상태를 드레인하며 전이를 진행한다(상시 호스트 운영 진입점).

- 본 골격(C0): **미구현**. 호출 시 미구현 안내를 출력하고 비-0(2) 으로 종료.
- **후속(C5)**: poll 드레인 루프·상시 호스트 운영 가이드.

### conductor status `<task-id>`

task 단위로 상태 미러·소유 run-id·브랜치·PR·리뷰 라운드·head·SPEC 목록을 표 형태로 출력한다.

### conductor list

`.conductor/tasks/` 아래 모든 task 와 요약(state·run-id)을 표시한다. **빈 상태에서도 오류 없이(0 exit) 정상 출력**(빈 목록 안내)을 낸다.

### conductor stop `<task-id>`

task 가 소유한 dispatch run 을 `dispatch` 의 공개 `stop` 서브커맨드로 정지 위임하고 `state=stopped` 로 기록한다. 연결된 run 이 없으면 안내만 출력하고 0 exit.

## references

| 파일 | 역할 |
|---|---|
| `conductor.sh` | 서브커맨드 라우터 + 프로젝트 루트 탐지 + intake/start 의 spec·dispatch 블랙박스 조합(forge 없음) |
| `lib-state.sh` | `.conductor/tasks/<task-id>/` 상태 저장소 헬퍼(set/get 필드·log_event·run-id 기록·list 등) |

## 의존성

`git`, `bash` 3.2+, `sha256sum` 또는 `shasum`, `autopilot:spec`·`autopilot:dispatch` 스킬. forge(`gh` 등)·task backend 연동은 본 골격 의존성이 아니며 후속 단위 references 모듈의 책임이다.

## 불변식 / 규칙

- conductor 는 `.conductor/` 디렉토리 밖 경로를 만들지 않는다(자기 스킬 정의 파일 제외).
- `spec`·`loop`·`dispatch` 의 정의 파일을 수정하지 않고, 공개 인터페이스만 소비한다.
- 구현 위임은 `dispatch start <spec...>` 공개 서브커맨드로만 하고, dispatch·loop 의 내부 신호 파일·워크트리를 직접 들여다보지 않는다.
- 본 골격은 forge CLI 를 직접 호출하지 않는다(forge 연동은 후속 단위 references 모듈 책임).
- 상태 디렉토리(`.conductor/`)는 git 추적에서 제외한다.
- 라우터는 bash 3.2+ 호환으로 작성한다.
