---
scope:
  include: ["plugins/autopilot/skills/loop/references/constitution.md", "plugins/autopilot/skills/loop/references/loop.sh"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; C=plugins/autopilot/skills/loop/references/constitution.md; L=plugins/autopilot/skills/loop/references/loop.sh; test -f \"$C\" && test -f \"$L\" && bash -n \"$L\" && grep -qE \"LOOP_DONE_LABEL|loop:done\" \"$C\" && grep -qE \"Status[^a-zA-Z0-9_]+Blocked|상태.*Blocked|Blocked.*전이\" \"$C\" && ! grep -qE \"WT/DONE\" \"$L\"'"
ears_language: ko
request_review: true
---

# constitution.md 워커 신호 매체 부착 동작 명시 (done·blocked)

## 무엇을 만들 것인가

`autopilot:loop` 드라이버는 워커가 발행한 신호의 *검출*을 task 저장소에 부속된 매체(완료 = 부속 label 존재, 정지 = 상태 field 값)로 한정한다. 그러나 워커 헌법(`constitution.md`)은 추상 어휘만 사용해 "`done` 신호 발행"·"task 상태를 `blocked`로 전이"라고만 적혀 있고, 드라이버가 보는 구체 매체(label 부착·Status 전이)의 동작은 본문에 나타나지 않는다. 워커가 추상 어휘만 읽고 구체 매체 동작을 모르는 채로 종료하면 드라이버의 검출 키가 hit되지 않아 완료·정지 판정이 누락된다.

본 task는 두 가지를 함께 변경한다:

1. **헌법(`constitution.md`) 본문에 매체 부착 동작 명시** — 워커가 `done`·`blocked` 신호 발행 시 부속 매체 동작을 함께 수행해야 한다는 지침을 추가:
   - `done` 신호 발행 시, task 저장소에 `LOOP_DONE_LABEL` 값과 일치하는 label을 추가한다.
   - `blocked` 신호 발행 시, task 상태 field 값을 `Blocked`로 전이한다.

   추가 위치는 헌법의 "이터레이션 종료 절차" 섹션(현행 line 361 부근). 기존 추상 어휘 명시 옆에 매체 부착 동작이 첨가된다.

2. **드라이버(`loop.sh`)에서 `$WT/DONE` 호환 OR 결합 제거** — SPEC 134 §제약 "호환 OR 결합 유지"가 명시한 0.2.0 잔존 fallback. milestone 종료 후 사용자 결정으로 제거 예정이었으며 본 task가 그 결정을 수행한다. 검출 경로는 `task_status_is_done`(=label 존재) 단일 키로, cleanup 가드도 동일 함수로 통일한다. 통일 후 `loop.sh`에는 `WT/DONE` 토큰이 하나도 남지 않는다.

두 변경은 같은 의미론을 일관화하는 단일 의도다 — 헌법이 워커 부착 동작을 명시하고, 드라이버가 그 부착물을 단일 검출 키로 사용한다.

## 수용 기준 (EARS)

1. `plugins/autopilot/skills/loop/references/constitution.md`가 존재할 때, 시스템은 워커가 `done` 신호를 발행할 때 task 저장소에 `LOOP_DONE_LABEL` 값과 일치하는 label을 추가하는 동작을 본문에 명시한다.
2. `plugins/autopilot/skills/loop/references/constitution.md`가 존재할 때, 시스템은 워커가 `blocked` 신호를 발행할 때 task 상태 field 값을 `Blocked`로 전이하는 동작을 본문에 명시한다.
3. `plugins/autopilot/skills/loop/references/loop.sh`가 존재할 때, 시스템은 본 파일 안에서 `WT/DONE` 토큰의 참조(검출 OR fallback·주석·cleanup 가드 포함)를 모두 제거하고, bash 문법 검사(`bash -n`)에서 0 exit으로 통과한다.

## 범위

포함:

- `plugins/autopilot/skills/loop/references/constitution.md` 본문에 워커의 done·blocked 신호 매체 부착 동작 명시 추가
- `plugins/autopilot/skills/loop/references/loop.sh`에서 `$WT/DONE` 참조 전부 제거 — 검출 OR fallback(현행 line 865-867), 관련 주석(line 1029-1030 등), cleanup 가드(line 1495)까지 포함. cleanup의 done 판정은 `task_status_is_done`으로 통일

비-목표 / 제외:

- SPEC 134의 검출 로직(`task_status_is_done`·`task_label_present`·`ensure_label_exists`) 자체 변경
- `rules/context.md` 매핑표 변경 (별도 범위)
- `SKILL.md` 변경
- 기존 발행된 `[done]`·`[blocked]` prefix comment 히스토리 마이그레이션
- `LOOP_DONE_LABEL` 기본값(`loop:done`) 변경
- 드라이버의 escalation 자동 `[blocked]` comment 발행 동작(`gh_post_blocked_comment`) 변경
- 다른 phase script(`pr-phase.sh`·`rebase-phase.sh`·`review-fix-phase.sh`·`cleanup-phase.sh`)의 `$WT/DONE` 참조 정리 — 본 SPEC scope는 `loop.sh` 단일 파일만 다룬다. 다른 phase script에 `WT/DONE` 참조가 있으면 별도 SPEC로 분리

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash -c 'set -e; C=plugins/autopilot/skills/loop/references/constitution.md; L=plugins/autopilot/skills/loop/references/loop.sh; test -f "$C" && test -f "$L" && bash -n "$L" && grep -qE "LOOP_DONE_LABEL|loop:done" "$C" && grep -qE "Status[^a-zA-Z0-9_]+Blocked|상태.*Blocked|Blocked.*전이" "$C" && ! grep -qE "WT/DONE" "$L"'
```

## 제약

- AC1·AC2의 두 동작 명시는 헌법의 "이터레이션 종료 절차" 섹션 내부에 위치시킨다 (verify 명령으로 위치는 검증되지 않으므로 본 제약으로 보강).
- 본 task가 변경하는 파일은 `constitution.md`와 `loop.sh` 두 개만이다 — `scope.include`가 두 파일 단일 명시이므로 다른 파일 변경은 워크플로 게이트에서 차단된다.
- `feedback_no_self_apply_during_spec` 룰: 본 SPEC을 작성하는 *현재* spec 호출은 어느 파일도 변경하지 않는다 — 변경은 loop 실행 시점.
- `feedback_self_referential_verification` 룰: 워커는 verify·worktree source(직접 변경한 `constitution.md`·`loop.sh`)만 검사하고, 자기 task의 issue label·다른 task의 검출 동작은 검사하지 않는다.
- `LOOP_DONE_LABEL` 기본값은 `loop.sh`의 단일 위치(`: "${LOOP_DONE_LABEL:=loop:done}"`)에서 결정되며 본 SPEC은 그 이름을 변경하지 않는다.
- `loop.sh`의 `WT/DONE` 참조 제거는 검출 OR fallback·관련 주석·cleanup 가드를 모두 포함하며, cleanup의 done 판정은 `task_status_is_done` 호출로 통일한다. 환경 변수·플래그로 fallback 재활성화 옵션을 새로 추가하지 않는다.

## 위험

- **SPEC 133 AC3 ('매체 표현 본문에서 제거') 원칙과의 마찰**: SPEC 133은 헌법 본문에서 매체 표현(comment·label·status field)에 대한 직접 언급을 제거하라고 명시. 본 SPEC은 워커 행동을 헌법에 명시할 필요 때문에 매체 표현(`LOOP_DONE_LABEL`·`Status=Blocked`)을 의도적으로 본문에 다시 노출한다. 사용자 결정으로 수용 — 추상 어휘 원칙보다 워커 행동 명확성을 우선.
- **blocked 신호의 드라이버 안전망 부재**: `loop.sh:803`이 escalation 시점에 호출하는 `gh_post_blocked_comment`는 실제로는 `[blocked]` prefix comment 발행만 수행하며, Project Status=Blocked 자동 전이는 미구현(loop.sh:244-250 NOTE 명시 — GraphQL `updateProjectV2ItemFieldValue`에 필요한 세 식별자가 env 한 개로 합성 불가). 한편 검출 함수 `task_status_is_blocked`는 단일 의존(Status field만)이므로, 워커가 Status 전이를 누락하면 드라이버 escalation 후에도 `task_status_is_blocked`가 0을 반환하지 않아 blocked 판정이 영구 누락된다. 본 SPEC의 §1(헌법에 워커 Status 전이 동작 명시)이 이 누락을 막는 유일한 안전장치다 — `WT/DONE fallback 제거`와 동일하게 헌법 명시로 상쇄되는 패턴.
- **self-referential 함정**: 본 task의 워커가 헌법을 변경하면서 동시에 자기 task의 done·blocked 신호로 자기 변경된 헌법을 따른다. 부분 적용 상태에서 검출이 깨지지 않도록 변경·검증·완료를 단일 이터로 묶거나, `feedback_self_referential_verification` 룰로 runtime artifact는 검증 대상에서 제외.
- **WT/DONE fallback 제거로 인한 안전망 상실**: SPEC 134 §위험 "워커가 label 추가에 실패해도 `$WT/DONE` 호환 OR 결합으로 완료 감지가 깨지지 않는다"가 보장하던 fallback이 사라진다. 본 task 이후 워커가 label 부착에 실패하면 검출 키가 영영 hit되지 않아 task가 무한 이터 또는 시간 제한까지 흐른다. 이 위험은 §1(헌법 명시)로 워커 부착 동작이 강제됨으로써 상쇄된다 — 두 변경이 같은 SPEC에 묶인 이유.
- **cleanup 가드 의미론 변화**: 기존 `[[ ! -f "$WT/DONE" ]]` 가드는 파일 시스템 신호 기반이었다. `task_status_is_done`으로 통일하면 cleanup이 task 저장소 조회를 매번 수행하므로 gh CLI 부재·rate limit 시 cleanup이 보수적으로 거부될 수 있다. 사용자의 명시 force 플래그(기존 `$force -eq 0` 분기)는 그대로 유지해 우회 경로를 보존한다.
