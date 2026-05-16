---
scope:
  include: ["plugins/autopilot/skills/spec/SKILL.md", "plugins/autopilot/skills/loop/SKILL.md", "plugins/autopilot/skills/prd/SKILL.md", "plugins/autopilot/skills/dispatch/SKILL.md"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; for F in plugins/autopilot/skills/spec/SKILL.md plugins/autopilot/skills/loop/SKILL.md plugins/autopilot/skills/prd/SKILL.md plugins/autopilot/skills/dispatch/SKILL.md; do test -f \"$F\" && ! grep -qE \"gh issue|prefix comment|issue body|\\[done\\]|\\[blocked\\]|Project Status field|GitHub Project\" \"$F\"; done'"
ears_language: ko
---

# SKILL.md 4개(spec·loop·prd·dispatch) backing-neutral 어휘 재작성

## 무엇을 만들 것인가

autopilot 스킬 패키지의 4개 SKILL.md(spec·loop·prd·dispatch)에서 task의 backing system을 가리키는 모든 backing-specific 표현을 backing-neutral 추상 어휘로 일관 재작성한다. 추상 어휘는 sibling child(헌법 재작성)이 헌법에 정의한 단위(task 메모리·task 신호·task 상태·task 식별자)를 그대로 차용한다 — 본 child가 새 단위를 신설하지 않는다.

SKILL.md는 사용자가 스킬을 호출하기 전 읽는 인터페이스 문서이므로 추상 어휘가 일관되어야 헌법-스킬-드라이버 세 층의 표현이 정합한다. 본 child의 산출물은 4개 파일에 한정되며 다른 sibling이 다루는 영역(헌법 본문·드라이버 셸·보조 references)은 손대지 않는다.

각 SKILL.md에서 추상화 대상:

- **spec/SKILL.md** — step 2 "task 상태 정합"의 backing 매핑 표 부분이 유일하게 backing-specific 표현을 명시 등장시키는 영역(GitHub Project + Issue 매핑). 그 외 본문은 추상 어휘로 일관 재작성. 매핑 표 자체는 backing-specific section이므로 보존하되 §외부에서 backing-specific 용어 직접 노출 금지.
- **loop/SKILL.md** — DONE phase·blocked phase·이터간 메모리 운영 안내가 backing-specific 표현을 사용. 추상 어휘로 재작성.
- **prd/SKILL.md** — 비교적 backing-neutral하지만 milestone-id ↔ issue 매핑 언급이 있다면 추상화.
- **dispatch/SKILL.md** — child task ↔ issue 매핑·sentinel 신호 검출 안내 등 backing-specific 표현 추상화.

## 수용 기준 (EARS)

1. `plugins/autopilot/skills/{spec,loop,prd,dispatch}/SKILL.md` 4개 파일 모두 존재할 때, 시스템은 각 본문 전체에서 다음 backing-specific 표현 어느 것도 매칭하지 않는다: `gh issue`, `prefix comment`, `issue body`, `[done]`, `[blocked]`, `Project Status field`, `GitHub Project`.
2. spec/SKILL.md의 step 2 "task 상태 정합" 절차가 추상 어휘로 재작성될 때, 시스템은 task 상태의 4갈래 분기(부재·설계 상태·설계 이전·설계 이후)를 동일한 의미로 보존하되 GitHub Project 구체 매핑을 본문에서 분리한다.
3. loop/SKILL.md의 DONE phase·blocked 관련 안내가 추상 어휘로 재작성될 때, 시스템은 완료·정지 신호의 의미를 보존하되 매체 표현(comment·label·status field)에 대한 직접 언급을 본문에서 제거한다.
4. 본 child가 4개 SKILL.md를 재작성하는 동안, 시스템은 sibling child(헌법·loop.sh·기타 references)의 파일을 수정하지 않는다.
5. 4개 SKILL.md 중 어느 위치에도 backing-specific 표현이 잔존하는 경우, 시스템은 verify 명령으로 그 잔존을 검출하고 0이 아닌 exit으로 실패 신호를 낸다.

## 범위

포함:

- `plugins/autopilot/skills/spec/SKILL.md`의 backing-specific 표현 추상 어휘로 재작성
- `plugins/autopilot/skills/loop/SKILL.md`의 backing-specific 표현 추상 어휘로 재작성
- `plugins/autopilot/skills/prd/SKILL.md`의 backing-specific 표현 추상 어휘로 재작성
- `plugins/autopilot/skills/dispatch/SKILL.md`의 backing-specific 표현 추상 어휘로 재작성

비-목표 / 제외:

- 헌법(`constitution.md`) 재작성 — sibling child-a 담당. 본 child는 헌법이 정의한 추상 어휘를 차용한다.
- `loop.sh`·기타 phase script 코드 변경 — sibling child-c 담당
- 보조 references *.md(operational-guide·troubleshooting·status-format·agent-prompts) — sibling child-d 담당
- `rules/context.md` 변경 — 본 milestone의 명시 비-목표
- adapter 인터페이스 신설 — 본 milestone의 명시 비-목표
- SKILL.md의 워크플로 단계 자체 변경 — 본 child는 어휘 재작성만, 단계 추가·삭제 금지

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash -c 'set -e; for F in plugins/autopilot/skills/spec/SKILL.md plugins/autopilot/skills/loop/SKILL.md plugins/autopilot/skills/prd/SKILL.md plugins/autopilot/skills/dispatch/SKILL.md; do test -f "$F" && ! grep -qE "gh issue|prefix comment|issue body|\[done\]|\[blocked\]|Project Status field|GitHub Project" "$F"; done'
```

## 제약

- `feedback_no_self_apply_during_spec` 메모리 룰: 본 SPEC.md를 작성하는 *현재* spec 호출에는 새 어휘 contract를 선행 적용하지 않는다.
- `feedback_self_referential_verification` 메모리 룰: 워커는 verify·worktree source(직접 변경한 4개 SKILL.md)만 검사하고 runtime artifact(다른 issue·SPEC·도구 출력)는 검사 대상에서 제외한다.
- 추상 어휘 단위는 sibling child-a가 헌법에 정의한 것을 그대로 사용한다 — 본 child가 새 단위를 신설하지 않는다.
- 본 child는 wave 2에 속하며 wave 1의 child-a 산출물(헌법의 어휘 정의)을 입력으로 사용한다. wave 1이 완료되지 않은 상태에서 본 child가 실행되면 추상 어휘가 본문 안에서만 정의되어 헌법과 단절될 위험이 있으므로 dispatch의 wave 순서를 준수한다.

## 위험

- **self-referential 함정**: 본 child가 spec/SKILL.md·loop/SKILL.md를 수정하는 동안, 워커가 그 SKILL.md를 따라 자기 spec/loop 흐름을 진행한다. 중간 상태 SKILL.md가 워커의 다음 동작을 결정할 수 있으므로 verify는 worktree source의 grep으로 한정한다.
- **adapter 유혹**: SKILL.md에서 추상 어휘를 도입하면서 "이참에 adapter 인터페이스 호출 절차도 SKILL.md에 명시하면 좋겠다"는 유혹. 비-목표에 명시 금지.
- **매핑 표 위치 모호**: spec/SKILL.md의 step 2 매핑 표를 본문에 그대로 두면 verify가 잡을 수 있다. 매핑 표는 표제 또는 명시 marker로 backing-specific section임을 표시하고 본문에서 분리하거나, `rules/context.md`로 참조 위임. 본 SPEC §"무엇을 만들 것인가"의 4번 결정.
