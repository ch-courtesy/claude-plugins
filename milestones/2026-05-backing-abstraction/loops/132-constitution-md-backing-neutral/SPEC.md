---
scope:
  include: ["plugins/autopilot/skills/loop/references/constitution.md"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; F=plugins/autopilot/skills/loop/references/constitution.md; test -f \"$F\" && ! grep -qE \"gh issue|prefix comment|issue body|\\[done\\]|\\[blocked\\]|Project Status field|GitHub Project\" \"$F\"'"
ears_language: ko
---

# constitution.md backing-neutral 어휘 재작성

## 무엇을 만들 것인가

autopilot 헌법(`constitution.md`)에서 task의 backing system(구체적 task storage·workflow 백엔드. 현 프로젝트의 경우 GitHub Issue + Project)을 가리키는 모든 backing-specific 표현 — 예: "task issue body", "prefix comment", "Project Status field", "GitHub Project" — 을 backing-neutral 추상 어휘로 일관 재작성한다. 헌법은 자율 loop의 워커가 매 이터마다 콜드 스타트로 읽는 단일 출처(single source of truth) 이므로 추상 어휘 layer는 헌법 본문에서 시작되어야 한다.

추상 어휘의 단위:

- **task 메모리** — 헌법이 "task issue body"·"task issue body의 계획 섹션"이라 부르는 것은 backing-neutral 표현으로는 "task 메모리"·"task 메모리의 계획 섹션". 매 이터의 콜드 스타트 입력이자, 진전·DoD·핸드오프가 누적되는 단일 영구 영역.
- **task 신호** — `[done]`·`[handoff]`·`[notes]`·`[blocked]`·`[unblocked]`·`[resume]` 같은 prefix comment는 추상에서 "task 신호"로 부른다. 각 신호의 의미(완료·인계·메모·정지·해제·재개)는 유지하되, 매체 표현("prefix comment")은 추상화한다.
- **task 상태** — `Project Status field`의 `In Design`·`In Progress`·`Blocked` 등 단계는 "task 상태"로 부른다. 상태 전이를 트리거하는 동작은 "task 상태를 X로 전이" 같은 추상 동작어를 사용한다.
- **task 식별자** — `issue number`는 "task 식별자".

본 child는 헌법 본문에서 위 단어들을 추상 어휘로 교체해 backing-specific 표현이 직접 노출되지 않도록 한다. 추상 동작이 실제 어떤 GitHub 호출(`gh issue comment`·`gh project item-edit` 등)로 수행되는지는 헌법의 범위 밖이며, 그 매핑은 sibling child의 SKILL.md·드라이버 코드와 `rules/context.md`(본 milestone의 비-목표)가 맡는다.

## 수용 기준 (EARS)

1. `plugins/autopilot/skills/loop/references/constitution.md`가 존재할 때, 시스템은 본문 전체에서 다음 backing-specific 표현 어느 것도 매칭하지 않는다: `gh issue`, `prefix comment`, `issue body`, `[done]`, `[blocked]`, `Project Status field`, `GitHub Project`.
2. 헌법의 §11(이터간 컨텍스트 운영)이 backing-neutral 어휘로 재작성될 때, 시스템은 "task 메모리"·"task 신호"·"task 상태"·"task 식별자" 같은 추상 어휘를 이용해 같은 매커니즘(이터간 상태 위임·콜드 스타트 입력·신호 발행)을 동일한 의미로 기술한다.
3. 헌법의 §5(정지)·§3.4(완료 판정)이 backing-neutral 어휘로 재작성될 때, 시스템은 완료·정지·해제·재개 신호의 의미를 보존하되 매체(comment·label·status field)에 대한 직접 언급은 본문에서 제거한다.
4. 헌법의 어느 위치에도 backing-specific 표현이 잔존하는 경우, 시스템은 verify 명령으로 그 잔존을 검출하고 0이 아닌 exit으로 실패 신호를 낸다.
5. 본 child가 헌법을 재작성하는 동안, 시스템은 sibling child(SKILL.md·loop.sh·기타 references)의 파일을 수정하지 않는다.

## 범위

포함:

- `plugins/autopilot/skills/loop/references/constitution.md` 본문의 backing-specific 표현 추상 어휘로 재작성
- 추상 어휘 사전(task 메모리·task 신호·task 상태·task 식별자)의 정의 본문 또는 본문 부속 절에 명시

비-목표 / 제외:

- SKILL.md(spec·loop·prd·dispatch) 어휘 재작성 — sibling child-b 담당
- `loop.sh`·기타 phase script의 신호 검출·발행 코드 교체 — sibling child-c 담당
- 보조 references *.md(operational-guide·troubleshooting·status-format·agent-prompts) 잔존 표현 정리 — sibling child-d 담당
- `rules/context.md` 변경 — 본 milestone의 명시 비-목표 (의도적 GitHub 구체화 채택)
- adapter 인터페이스 신설 — 본 milestone의 명시 비-목표
- 다른 backing 구현 추가 — 본 milestone의 명시 비-목표
- 기존 [done]·[blocked] prefix comment 히스토리 마이그레이션 — 본 milestone의 명시 비-목표

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash -c 'set -e; F=plugins/autopilot/skills/loop/references/constitution.md; test -f "$F" && ! grep -qE "gh issue|prefix comment|issue body|\[done\]|\[blocked\]|Project Status field|GitHub Project" "$F"'
```

## 제약

- `feedback_no_self_apply_during_spec` 메모리 룰: 본 SPEC.md를 작성하는 *현재* spec 호출에는 새 어휘 contract를 선행 적용하지 않는다. 본 SPEC.md·issue body·본 spec 호출이 생성한 모든 산출물에서는 backing-specific 표현이 그대로 등장할 수 있으며, verify는 헌법 본문에만 적용된다.
- `feedback_self_referential_verification` 메모리 룰: 본 child는 autopilot 자체를 소재로 한다. 워커는 verify·worktree source(직접 변경한 헌법 본문)만 검사하고 runtime artifact(예: 다른 issue의 prefix comment, 다른 SPEC.md, 자신이 호출한 다른 도구의 출력)는 검사 대상에서 제외한다.
- 추상 어휘의 단위(task 메모리·task 신호·task 상태·task 식별자)는 본 SPEC §"무엇을 만들 것인가"에서 정의된 것을 그대로 사용한다 — 새 단위 신설 금지.
- 헌법은 워커가 콜드 스타트마다 읽는 단일 출처이므로 분량은 현 수준을 크게 늘리지 않는다(기존 대비 ±20% 이내 권고).

## 위험

- **self-referential 함정**: 본 child가 헌법을 수정하는 동안, 워커가 헌법 안의 "완료 판정" 절차를 따라 자기 task의 완료를 판단하려 한다. 헌법이 새 어휘로 재작성되는 중간 상태에서는 일부 절차가 더 이상 본문에 명시되지 않을 수 있다. 워커는 verify 명령(헌법 본문 grep)만 통과하면 완료로 판정해야 하며, 추상 동작의 GitHub 매핑까지 검증하지 않는다.
- **adapter 유혹**: 추상 어휘 도입 중 "adapter 인터페이스를 헌법에 명시하는 게 깔끔하다"는 유혹. PRD·본 SPEC의 비-목표에 adapter 신설 금지가 명시됨. 어휘 정의는 본문 단어 수준이고 인터페이스 객체·dispatcher는 만들지 않는다.
- **추상 어휘 단위 누수**: 헌법이 GitHub-specific 동작(예: GraphQL `updateProjectV2ItemFieldValue` 호출 절차)을 직접 기술하면 추상 layer가 깨진다. 헌법은 추상 동작어("task 상태를 X로 전이")만 사용하고, 실제 호출 코드는 sibling child(loop.sh·SKILL.md)가 책임진다.
