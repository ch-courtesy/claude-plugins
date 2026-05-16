---
scope:
  include: ["plugins/autopilot/skills/loop/references/constitution.md"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; F=plugins/autopilot/skills/loop/references/constitution.md; test -f \"$F\" && grep -qE \"LOOP_DONE_LABEL|loop:done\" \"$F\" && grep -qE \"Status[^a-zA-Z0-9_]+Blocked|상태.*Blocked|Blocked.*전이\" \"$F\"'"
ears_language: ko
---

# constitution.md 워커 신호 매체 부착 동작 명시 (done·blocked)

## 무엇을 만들 것인가

`autopilot:loop` 드라이버는 워커가 발행한 신호의 *검출*을 task 저장소에 부속된 매체(완료 = 부속 label 존재, 정지 = 상태 field 값)로 한정한다. 그러나 워커 헌법(`constitution.md`)은 추상 어휘만 사용해 "`done` 신호 발행"·"task 상태를 `blocked`로 전이"라고만 적혀 있고, 드라이버가 보는 구체 매체(label 부착·Status 전이)의 동작은 본문에 나타나지 않는다. 워커가 추상 어휘만 읽고 구체 매체 동작을 모르는 채로 종료하면 드라이버의 검출 키가 hit되지 않아 완료·정지 판정이 누락된다.

본 task는 헌법 본문에 워커가 `done`·`blocked` 신호 발행 시 부속 매체 동작을 함께 수행해야 한다는 지침을 명시한다.

헌법에 추가되는 동작은 두 줄:

- `done` 신호 발행 시, task 저장소에 `LOOP_DONE_LABEL` 값과 일치하는 label을 추가한다.
- `blocked` 신호 발행 시, task 상태 field 값을 `Blocked`로 전이한다.

추가 위치는 헌법의 "이터레이션 종료 절차" 섹션(현행 line 361 부근). 기존 추상 어휘 명시 옆에 매체 부착 동작이 첨가된다.

## 수용 기준 (EARS)

1. `plugins/autopilot/skills/loop/references/constitution.md`가 존재할 때, 시스템은 워커가 `done` 신호를 발행할 때 task 저장소에 `LOOP_DONE_LABEL` 값과 일치하는 label을 추가하는 동작을 본문에 명시한다.
2. `plugins/autopilot/skills/loop/references/constitution.md`가 존재할 때, 시스템은 워커가 `blocked` 신호를 발행할 때 task 상태 field 값을 `Blocked`로 전이하는 동작을 본문에 명시한다.

## 범위

포함:

- `plugins/autopilot/skills/loop/references/constitution.md` 본문에 워커의 done·blocked 신호 매체 부착 동작 명시 추가

비-목표 / 제외:

- `loop.sh` 등 드라이버 코드 변경 (SPEC 134의 검출 로직 그대로)
- `rules/context.md` 매핑표 변경 (별도 범위)
- `SKILL.md` 변경
- 기존 발행된 `[done]`·`[blocked]` prefix comment 히스토리 마이그레이션
- `LOOP_DONE_LABEL` 기본값(`loop:done`) 변경
- 드라이버의 escalation 자동 `[blocked]` comment 발행 동작(`gh_post_blocked_comment`) 변경

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash -c 'set -e; F=plugins/autopilot/skills/loop/references/constitution.md; test -f "$F" && grep -qE "LOOP_DONE_LABEL|loop:done" "$F" && grep -qE "Status[^a-zA-Z0-9_]+Blocked|상태.*Blocked|Blocked.*전이" "$F"'
```

## 제약

- AC1·AC2의 두 동작 명시는 헌법의 "이터레이션 종료 절차" 섹션 내부에 위치시킨다 (verify 명령으로 위치는 검증되지 않으므로 본 제약으로 보강).
- 본 task가 헌법을 수정하는 동안 sibling 파일(`loop.sh`, `rules/context.md`, `SKILL.md` 등 헌법 외 파일)을 수정하지 않는다 — `scope.include`가 `constitution.md` 단일 파일이므로 다른 파일 변경은 워크플로 게이트에서 차단된다.
- `feedback_no_self_apply_during_spec` 룰: 본 SPEC을 작성하는 *현재* spec 호출은 헌법을 변경하지 않는다 — 변경은 loop 실행 시점.
- `feedback_self_referential_verification` 룰: 워커는 verify·worktree source(직접 변경한 `constitution.md`)만 검사하고, 자기 task의 issue label·다른 task의 검출 동작은 검사하지 않는다.
- `LOOP_DONE_LABEL` 기본값은 `loop.sh`의 단일 위치(`: "${LOOP_DONE_LABEL:=loop:done}"`)에서 결정되며 본 SPEC은 그 이름을 변경하지 않는다.

## 위험

- **SPEC 133 AC3 ('매체 표현 본문에서 제거') 원칙과의 마찰**: SPEC 133은 헌법 본문에서 매체 표현(comment·label·status field)에 대한 직접 언급을 제거하라고 명시. 본 SPEC은 워커 행동을 헌법에 명시할 필요 때문에 매체 표현(`LOOP_DONE_LABEL`·`Status=Blocked`)을 의도적으로 본문에 다시 노출한다. 사용자 결정으로 수용 — 추상 어휘 원칙보다 워커 행동 명확성을 우선.
- **드라이버 자동 부착과의 중복**: `loop.sh:803`의 `gh_post_blocked_comment`는 escalation 시점에 드라이버가 자동으로 `[blocked]` comment + Status 전이를 시도한다. 본 SPEC이 명시하는 워커 책임과 드라이버 자동 동작이 둘 다 존재 — 의도된 안전망(워커가 누락해도 escalation 시점에 드라이버가 보완)으로 수용.
- **self-referential 함정**: 본 task의 워커가 헌법을 변경하면서 동시에 자기 task의 done·blocked 신호로 자기 변경된 헌법을 따른다. 부분 적용 상태에서 검출이 깨지지 않도록 변경·검증·완료를 단일 이터로 묶거나, `feedback_self_referential_verification` 룰로 runtime artifact는 검증 대상에서 제외.
