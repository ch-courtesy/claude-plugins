---
name: dispatch
description: "milestone 단위 PRD를 child SPEC들로 자동 분해해 DAG(wave) 단위로 loop을 병렬 실행하는 오케스트레이션 인터페이스. PRD가 준비된 milestone을 여러 task로 자율 병렬 수행하려 할 때 사용. start/status/stop/list/cleanup/logs/resume 서브커맨드로 milestone lifecycle을 관리."
---

# dispatch

`autopilot:prd`가 만든 `milestones/<m>/prd/PRD.md`를 child SPEC으로 분해하고 DAG wave 단위로 `autopilot:loop`을 실행한다. milestone-level ops도 본 스킬이 맡는다.

## 호출

`Skill(skill: "dispatch", args: "<subcommand> [<args>]")`

## start 흐름

1. `dispatch start <m>` 입력 검증: PRD 존재, `[NEEDS CLARIFICATION` 마커 0개. 미충족 시 abort + `prd <m> --resume` 안내. `regular`는 PRD 없는 catch-all이므로 거부.
2. `references/decomposition-algorithm.md`로 단위 후보를 뽑고 3조건(단일 컨텍스트 윈도우 fit, 테스트 폐쇄성, 격리성)과 hard cap(1차 <= 8, 깊이 <= 2, 최종 <= 20)을 검사한다. 초과·cycle은 abort.
3. 게이트 1: wave별 분해 plan을 보여주고 `(a) 승인`, `(b) 분해 수정`, `(c) 취소`를 묻는다. 승인 시 `references/dag-template.md`로 `milestones/<m>/dispatch/DAG.md` 작성.
4. 게이트 2: DAG 레벨 wave·child·예상 verify·의존성 표를 재제시하고 `(a) 실행 시작`, `(b) 취소`를 묻는다.
5. 게이트 3: wave 단위로 순차 진행한다. 각 wave의 child마다 `Skill(skill: "spec", args: "--milestone <m> <자연어 task 설명>")`을 호출한다. child task-id는 spec이 생성하므로 dispatch는 보유하지 않는다.
6. spec 위임 전후 `milestones/<m>/loops/` 스냅샷 차이로 새 `milestones/<m>/loops/<c>-<slug>/SPEC.md`만 식별한다. spec의 dispatch 위임 모드가 auto-loop-start를 수행하므로 dispatch가 별도 `loop start`를 중복 호출하지 않는다.
7. `Bash(dispatch.sh watch_wave <m> child...)`로 wave 완료를 감시한다. 성공한 wave 뒤에만 다음 wave의 spec 위임을 시작한다.

## watch_wave

watch는 child issue의 완료 라벨(`LOOP_DONE_LABEL`)과 worktree `.loop/ESCALATION.md`만 본다. loop의 worktree·lock·iteration·헌법 준수는 `loop.sh` 책임이다.

| exit | 의미 | 후속 |
|---|---|---|
| `100` | wave 내 모든 child 완료 라벨 | DISPATCH_LOG 기록 후 다음 wave |
| `101` | 누군가 ESCALATION | watch_wave가 나머지 stop, 로그·보고, 다음 wave 차단 |
| `102` | timeout(`WATCH_TIMEOUT_SECONDS`, 기본 7200s) | 진행 중 child stop, partial 결과 보고, 다음 wave 차단 |

그 외 exit은 dispatch 결함으로 보고 stderr·exit code를 그대로 알린다.

## Subcommands

- `start <m>` 또는 `dispatch <m>`: 분해+실행.
- `status <m>`: `dispatch.sh status <m>`. PRD/DAG/wave와 child loop state 출력. `regular`는 child 상태만.
- `stop <m>`: 진행 중 모든 child loop stop + DISPATCH_LOG 기록.
- `list`: 모든 milestone(regular 포함) 상태.
- `cleanup [<m>]`: 완료된 worktree·child loop 상태 제거. PRD/DAG 보존.
- `logs <m>`: `DISPATCH_LOG.md` 출력.
- `resume <m>`: 분해 미완이면 게이트 1, wave 중단이면 다음 wave부터 재개.
- 인자 없음: 사용법과 subcommand 목록 출력.

## references

| 파일 | 역할 |
|---|---|
| `dispatch.sh` | status/stop/list/cleanup/logs/watch_wave/log_event driver |
| `dag-template.md` | DAG.md 템플릿 |
| `decomposition-algorithm.md` | 3조건, hard cap, 토포 정렬, cycle 감지 |

## 의존성

`git`, `bash` 3.2+(macOS), `claude` CLI, `spec` 스킬, `loop` 스킬.

## 규칙

- 직접 작성 범위는 `milestones/<m>/dispatch/`의 `DAG.md`와 `DISPATCH_LOG.md`.
- spec 위임은 항상 `--milestone <m> <자연어 task 설명>` 형식. task-id는 spec이 결정한다.
- loop 실행 식별은 스냅샷 차이로 찾은 SPEC 경로를 기준으로 한다.
- 모든 결정·승인은 `AskUserQuestion`.
