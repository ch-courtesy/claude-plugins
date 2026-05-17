---
name: dispatch
description: "milestone 단위 PRD를 child SPEC들로 자동 분해해 DAG(wave) 단위로 loop을 병렬 실행하는 오케스트레이션 인터페이스. start/status/stop/list/cleanup/logs/resume 서브커맨드로 milestone lifecycle ops도 책임. PRD 입력 검증·게이트 3종(분해 plan·spec 위임·최종 확인)·sentinel watch + fail-fast 포함."
---

# dispatch

`autopilot:prd` 스킬이 작성한 `milestones/<m>/prd/PRD.md`를 child SPEC들로 자동 분해하고, DAG(wave) 단위로 `autopilot:loop`을 병렬 실행하는 오케스트레이션 인터페이스.

본 스킬은 milestone-level ops도 책임 — 별도 `milestone` 스킬을 두지 않는다.

## 호출 방법

`Skill(skill: "dispatch", args: "<subcommand> [<args>]")`

또는 사용자가 자연어로 의도 전달 시 모델이 자동 호출.

서브커맨드 7종 — 자세한 동작은 §Subcommand 참조.

## 단일 흐름

```
1. dispatch start <m>
   → PRD 검증 (milestones/<m>/prd/PRD.md 존재 + [NEEDS CLARIFICATION 마커 0개]
   → 분해 (단위 후보 추출 + 3 조건 검사 + 하드 캡 검사)
   → 게이트 ① 분해 plan 승인 (사용자 AskUserQuestion)
   → DAG.md 작성 (milestones/<m>/dispatch/DAG.md)
   → 게이트 ② spec 위임 (각 child에 대해 Skill(skill: "spec", args: "<m>/<c>"))
   → 게이트 ③ 최종 확인 (SPEC 경로·verify 명령·의존성 표 + 사용자 승인)
   → wave 단위 병렬 실행 (각 child에 Bash(loop start <m>/<c>, run_in_background: true) 호출, sentinel은 Bash(dispatch.sh watch_wave ...))
   → sentinel watch (DONE/ESCALATION.md)
   → fail-fast (ESCALATION 시 같은 wave 다른 child들 loop stop)
   → wave 모두 통과 후 최종 보고
```

## 분해 알고리즘

자세한 내용: `references/decomposition-algorithm.md`. 핵심:

**입력 검증** — `milestones/<m>/prd/PRD.md` 존재 + `[NEEDS CLARIFICATION` 마커 0개. 미충족 시 abort + `prd <m> --resume` 안내.

**3 조건 동시 충족** (단위 후보별 검사)
1. **단일 컨텍스트 윈도우 fit**: spec 9-step + loop 30 iter 안에 끝낼 수 있는가
2. **테스트 폐쇄성**: 자체 verify 명령으로 닫히는가
3. **격리성**: 다른 단위와 같은 파일을 동시 수정하지 않는가

**하드 캡** — 1차 분해 ≤ 8 단위, 재귀 분해 깊이 ≤ 2, 최종 산출 ≤ 20 단위. 초과 시 abort + 사용자에게 PRD 자체 분해 권고.

**의존성·wave** — 단위 간 dependency(파일·산출물) 추출 → 토포 정렬 → wave 그룹화. cycle 감지 시 abort.

## 게이트 3종

### 게이트 ① 분해 plan 승인

분해 결과를 wave별 표로 제시:
```
wave 1 (parallel-safe): [child-a, child-b]
  - child-a: <한 줄> | 파일 [src/a/**] | verify [pytest tests/a]
  - child-b: <한 줄> | 파일 [src/b/**] | verify [pytest tests/b]
wave 2 (depends on wave 1): [child-c]
  - child-c: ...
```

`AskUserQuestion` 옵션: `(a) 승인`, `(b) 분해 수정` (자연어 피드백으로 재실행), `(c) 취소`.

승인 시 `references/dag-template.md` 치환해 `milestones/<m>/dispatch/DAG.md` 기록 (`mkdir -p milestones/<m>/dispatch/` 후).

### 게이트 ② spec 위임

승인된 DAG의 각 child에 대해 `Skill(skill: "spec", args: "<m>/<c>")` 호출. 입력 컨텍스트로 PRD 본문 + 분해 plan 항목 전달 (자연어 안내).

spec 스킬은 자체적으로 9-step 대화 진행. 사용자가 SPEC 작성에 직접 참여.

### 게이트 ③ 최종 확인

모든 SPEC 작성 후 표 재제시:
```
| child   | SPEC 경로                                | verify 명령           | 의존성    |
|---------|------------------------------------------|-----------------------|-----------|
| child-a | milestones/<m>/loops/child-a/SPEC.md     | pytest tests/a        | 없음      |
| child-b | milestones/<m>/loops/child-b/SPEC.md     | pytest tests/b        | 없음      |
| child-c | milestones/<m>/loops/child-c/SPEC.md     | pytest tests/c        | child-a   |
```

`AskUserQuestion` 옵션: `(a) 실행 시작`, `(b) 취소`. 승인 시 wave 1부터 실행.

## 실행 (wave 단위 병렬)

```
for wave in waves:
  for child in wave:
    Bash(loop start <m>/<c>, run_in_background: true)  # 비동기 시작 — watch_wave가 sentinel 폴링. run_in_background 없이는 동기 블로킹이라 wave 병렬 안 됨

  while wave 진행 중:
    # references/dispatch.sh watch_wave <m> child1 child2 ...
    각 child의 sentinel 파일 watch (sleep 2s + test -e 단순 폴링):
      milestones/<m>/loops/<c>/.worktree/DONE                  → 성공
      milestones/<m>/loops/<c>/.worktree/.loop/ESCALATION.md   → 실패

    누군가 ESCALATION (watch_wave exit 101):
      watch_wave가 나머지 진행 중 child들에 kill -TERM (fail-fast, 자동)
      milestones/<m>/dispatch/DISPATCH_LOG.md 기록
      ESCALATION 카테고리·보고서 사용자 제시
      다음 wave 차단 + 종료 (재계획은 사용자)

    모두 DONE (watch_wave exit 100):
      DISPATCH_LOG.md 기록 → 다음 wave

    타임아웃 (watch_wave exit 102):
      watch_wave가 진행 중 child들에 kill -TERM (orphan 방지, 자동)
      DISPATCH_LOG.md에 타임아웃 + 진행 단계 기록
      사용자에게 진행 상황·재개 옵션 보고
      다음 wave 차단 + 종료

모든 wave 통과: 최종 보고서 + 종료
```

### watch_wave exit code 매핑

| exit | 의미 | child stop 처리 | 모델 후속 행동 |
|---|---|---|---|
| `100` | wave 내 모든 child DONE | 불필요 | DISPATCH_LOG에 wave 성공 기록 → 다음 wave 진입 |
| `101` | wave 내 누군가 ESCALATION (fail-fast) | watch_wave가 자동 stop | DISPATCH_LOG에 escalation 기록, ESCALATION.md 본문·카테고리 사용자 제시, **다음 wave 차단**, 재계획은 사용자 책임 |
| `102` | `WATCH_TIMEOUT_SECONDS` 초과 (기본 7200s) | watch_wave가 자동 stop | DISPATCH_LOG에 timeout 기록, 진행 단계·partial 결과 사용자 제시, **다음 wave 차단**, `dispatch resume <m>`으로 이어갈지 사용자 결정 |

이 외 exit code는 dispatch 자체 결함을 의미하므로 즉시 abort + 사용자에게 stderr·exit code 그대로 보고.

**기존 loop과의 분업** — 워크트리·lock·iteration 상한·헌법 준수는 모두 `loop.sh`가 처리. dispatch는 sentinel 파일(`DONE`·`.loop/ESCALATION.md`) **존재만** 감시. 외부 셸 루프 표준 유지(in-process Stop 훅 미사용).

## Subcommand

### start <m> (또는 dispatch <m>)

분해+실행. PRD 부재 시 거부. PRD 마커 잔존 시 거부 + `prd --resume` 안내.

`regular` milestone은 PRD 부재로 자동 거부 (catch-all로 PRD 없음).

### status <m>

`Bash(bash $SKILL_DIR/references/dispatch.sh status <m>)`. 출력:
- PRD 존재 / DAG 존재 / wave 진행 상태
- 각 child loop의 state (running/done/escalated/idle/missing/archived)
- `regular` milestone의 경우 child loop 상태만 (PRD/DAG 없음)

### stop <m>

`Bash(bash $SKILL_DIR/references/dispatch.sh stop <m>)`. 진행 중 모든 child loop에 `loop stop` 호출 + DISPATCH_LOG.md 기록.

### list

`Bash(bash $SKILL_DIR/references/dispatch.sh list)`. 모든 milestone (regular 포함) 목록 + 상태.

### cleanup [<m>]

`Bash(bash $SKILL_DIR/references/dispatch.sh cleanup [<m>])`. 완료된 워크트리·child loop 상태 제거. PRD/DAG는 보존. `<m>` 미지정 시 모든 완료 milestone.

### logs <m>

`Bash(bash $SKILL_DIR/references/dispatch.sh logs <m>)`. `milestones/<m>/dispatch/DISPATCH_LOG.md` 출력.

### resume <m>

현재 상태(분해 미완 vs 실행 중단) 감지 후 올바른 단계에서 이어가기. 분해 미완이면 게이트 ①부터, wave 중단이면 다음 wave부터.

### 인자 없는 호출

사용법 안내 + 사용 가능한 subcommand 목록 출력.

## 자기완결성 가드

본 스킬은 PRD 마커 거부자 역할. `[NEEDS CLARIFICATION` 마커가 PRD 본문에 1개라도 잔존하면 `start` 거부 + `prd --resume` 안내. 이 가드 + spec 스킬의 자체 마커 차단으로 wave 실행 시점에는 마커가 없음이 보장된다.

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `dispatch.sh` | 외부 셸 드라이버. 셸 위임 서브커맨드(status/stop/list/cleanup/logs/watch_wave/log_event) + sentinel watch + DAG 파싱. `resume`은 모델 직접 처리(셸 위임 없음) |
| `dag-template.md` | DAG.md placeholder 템플릿 (wave 표·의존성 목록) |
| `decomposition-algorithm.md` | 3 조건 + 하드 캡 + 토포 정렬 + cycle 감지 휴리스틱 |

## 의존성 (target 프로젝트)

- `git` (worktree 지원)
- `bash` 3.2+ (macOS 호환)
- `claude` CLI
- loop 스킬 (`Skill(skill: "loop", args: "...")` 또는 `Bash(loop.sh ...)`)
- spec 스킬 (`Skill(skill: "spec", args: "...")`)

## 규칙

- 본 스킬은 target 프로젝트의 `milestones/<m>/dispatch/` 디렉터리만 직접 작성한다 (DAG.md·DISPATCH_LOG.md).
- spec 위임은 항상 `Skill(skill: "spec", args: "<m>/<c>")` 형식 — 2-컴포넌트 task-id.
- loop 실행은 항상 `<m>/<c>` 2-컴포넌트 task-id로.
- `regular` milestone-id는 ad-hoc 단일 task catch-all이므로 PRD가 없고 `dispatch start regular`는 거부.
- 모든 결정·승인은 `AskUserQuestion`으로 (CLAUDE.md 규칙).
