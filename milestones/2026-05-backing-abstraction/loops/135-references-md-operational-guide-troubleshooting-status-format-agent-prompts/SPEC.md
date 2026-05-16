---
scope:
  include: ["plugins/autopilot/skills/loop/references/operational-guide.md", "plugins/autopilot/skills/loop/references/troubleshooting.md", "plugins/autopilot/skills/loop/references/status-format.md", "plugins/autopilot/skills/loop/references/agent-prompts.md"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; for F in plugins/autopilot/skills/loop/references/operational-guide.md plugins/autopilot/skills/loop/references/troubleshooting.md plugins/autopilot/skills/loop/references/status-format.md plugins/autopilot/skills/loop/references/agent-prompts.md; do test -f \"$F\" && ! grep -qE \"gh issue|prefix comment|issue body|\\[done\\]|\\[blocked\\]|Project Status field|GitHub Project\" \"$F\"; done'"
ears_language: ko
---

# references 보조 .md(operational-guide·troubleshooting·status-format·agent-prompts) 잔존 표현 정리

## 무엇을 만들 것인가

autopilot loop 스킬의 보조 references 4개(`operational-guide.md`·`troubleshooting.md`·`status-format.md`·`agent-prompts.md`)에서 backing-specific 표현 잔존을 추상 어휘로 정리한다. 추상 어휘는 sibling child(헌법 재작성)이 정의한 단위(task 메모리·task 신호·task 상태·task 식별자)를 차용한다 — 본 child가 새 단위를 신설하지 않는다.

각 파일의 역할상 backing-specific 표현이 등장하는 위치:

- **operational-guide.md** — 사용자가 워크플로를 운영할 때 참조하는 가이드. status·blocked 운영·신호 발행 안내가 backing-specific 표현을 사용할 수 있음.
- **troubleshooting.md** — ESCALATION 카테고리별 처리. 워커의 신호와 차단 절차 안내에 backing 매체 표현이 등장할 수 있음.
- **status-format.md** — status 출력 형식. status field 매핑 표현이 backing-specific일 수 있음.
- **agent-prompts.md** — 이터 내 Agent dispatch 브리프 양식. backing 의존성이 낮을 가능성이 높으나 점검.

본 child의 산출물은 4개 파일에 한정된다. 다른 sibling이 다루는 영역(헌법 본문·SKILL.md·드라이버 셸)은 손대지 않는다.

## 수용 기준 (EARS)

1. `plugins/autopilot/skills/loop/references/{operational-guide,troubleshooting,status-format,agent-prompts}.md` 4개 파일 모두 존재할 때, 시스템은 각 본문 전체에서 다음 backing-specific 표현 어느 것도 매칭하지 않는다: `gh issue`, `prefix comment`, `issue body`, `[done]`, `[blocked]`, `Project Status field`, `GitHub Project`.
2. 본 child가 4개 보조 references를 정리하는 동안, 시스템은 sibling child(헌법·SKILL.md·loop.sh)의 파일을 수정하지 않는다.
3. 4개 보조 references 중 어느 위치에도 backing-specific 표현이 잔존하는 경우, 시스템은 verify 명령으로 그 잔존을 검출하고 0이 아닌 exit으로 실패 신호를 낸다.
4. 보조 references의 워크플로·카테고리·운영 절차 의미는 변경 없이 어휘만 추상화된다 — 절차 추가·삭제 금지.

## 범위

포함:

- `plugins/autopilot/skills/loop/references/operational-guide.md`의 backing-specific 표현 추상 어휘로 정리
- `plugins/autopilot/skills/loop/references/troubleshooting.md`의 backing-specific 표현 추상 어휘로 정리
- `plugins/autopilot/skills/loop/references/status-format.md`의 backing-specific 표현 추상 어휘로 정리
- `plugins/autopilot/skills/loop/references/agent-prompts.md`의 backing-specific 표현 추상 어휘로 정리

비-목표 / 제외:

- 헌법(`constitution.md`) 재작성 — sibling child-a 담당
- SKILL.md(spec·loop·prd·dispatch) 어휘 변경 — sibling child-b 담당
- `loop.sh`·기타 phase script 코드 변경 — sibling child-c 담당
- `rules/context.md` 변경 — 본 milestone의 명시 비-목표
- adapter 인터페이스 신설 — 본 milestone의 명시 비-목표
- 보조 references의 운영 절차·ESCALATION 카테고리·status 출력 형식 자체 변경 — 본 child는 어휘 정리만

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash -c 'set -e; for F in plugins/autopilot/skills/loop/references/operational-guide.md plugins/autopilot/skills/loop/references/troubleshooting.md plugins/autopilot/skills/loop/references/status-format.md plugins/autopilot/skills/loop/references/agent-prompts.md; do test -f "$F" && ! grep -qE "gh issue|prefix comment|issue body|\[done\]|\[blocked\]|Project Status field|GitHub Project" "$F"; done'
```

## 제약

- `feedback_no_self_apply_during_spec` 메모리 룰: 본 SPEC.md 작성하는 *현재* spec 호출에는 새 어휘 contract를 선행 적용하지 않는다.
- `feedback_self_referential_verification` 메모리 룰: 워커는 verify·worktree source(직접 변경한 4개 보조 references)만 검사한다.
- 추상 어휘 단위는 sibling child-a가 헌법에 정의한 것을 그대로 사용한다 — 본 child가 새 단위를 신설하지 않는다.
- 본 child는 wave 2에 속하며 wave 1의 child-a 산출물(헌법의 어휘 정의)을 입력으로 사용한다.

## 위험

- **self-referential 함정**: 본 child가 `troubleshooting.md`의 ESCALATION 카테고리별 처리 안내를 수정하면, 워커가 ESCALATION 발생 시 그 안내를 따라 동작한다. 중간 상태 안내가 워커의 다음 동작을 결정할 수 있으므로 verify는 worktree source의 grep으로 한정한다.
- **adapter 유혹**: 보조 references에서 backing 추상화를 다루면서 "이참에 backing adapter 매핑 표를 여기에 두자"는 유혹. 비-목표에 명시 금지. 매핑은 sibling child의 SKILL.md·`rules/context.md`에 위임.
- **빈 파일 가능성**: 일부 보조 references는 이미 backing-specific 표현이 0건일 수 있다. 그 경우 본 child의 verify는 즉시 통과하고 변경 commit 없이 완료될 수 있다 — 정상 동작. 워커는 verify 통과만 보고 완료 판정.
