---
scope:
  include: ["plugins/autopilot/skills/spec/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; test -f plugins/autopilot/skills/spec/SKILL.md && grep -qE \"auto-synced\" plugins/autopilot/skills/spec/SKILL.md && grep -qE \"자리표시 2줄|placeholder.*유지|placeholder.*보존\" plugins/autopilot/skills/spec/SKILL.md && grep -qE \"abort|중단\" plugins/autopilot/skills/spec/SKILL.md && grep -qE \"feedback_no_self_apply_during_spec|현재 호출.*선행\" plugins/autopilot/skills/spec/SKILL.md'"
---

# spec: SPEC.md 작성·갱신 시 GitHub Issue body 자동 sync

## 무엇을 만들 것인가
`autopilot:spec` 스킬이 SPEC.md를 작성·갱신할 때마다, 같은 내용이 task에 해당하는 GitHub Issue body에도 자동으로 반영된다. Issue 페이지만 열어도 사용자가 SPEC 전문을 그대로 읽을 수 있는 상태를 유지하도록 스킬을 확장한다.

## 수용 기준 (EARS)
1. SPEC.md가 `milestones/<m>/loops/<c>/SPEC.md` 경로에 (재)기록될 때, 시스템은 해당 task의 Issue body 내 동기화 블록을 SPEC.md 전문으로 갱신한다.
2. 시스템은 Issue body를 [자리표시 2줄 + `---` + `## SPEC.md (auto-synced)` heading + SPEC.md 전문 + 닫는 `---`] 구조로 유지한다.
3. 시스템은 sync 시 동기화 블록 바깥의 사용자 추가 내용을 보존한다.
4. Issue body update 호출이 0이 아닌 exit으로 실패하면, 시스템은 명확한 에러로 abort하고 자동 roll-back을 수행하지 않는다.

## 범위
포함:
- `plugins/autopilot/skills/spec/SKILL.md`에 «SPEC.md write → Issue body sync» 절차 추가
- 자리표시 2줄 보존·구분자 구조·SPEC 전문 append·실패 처리·self-referential 규약·현재 호출 면제 예외 모두 문서화

비-목표 / 제외:
- 기존 비표준 Issue body(수동 생성·구분자 없음)의 retroactive migration
- 역방향 sync (Issue body → SPEC.md)
- 라벨·assignee 등 다른 metadata 변경
- 본 SPEC.md를 작성하는 현재 spec 호출에 새 contract 선행 적용

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```bash
bash -c 'set -e; \
  test -f plugins/autopilot/skills/spec/SKILL.md && \
  grep -qE "auto-synced" plugins/autopilot/skills/spec/SKILL.md && \
  grep -qE "자리표시 2줄|placeholder.*유지|placeholder.*보존" plugins/autopilot/skills/spec/SKILL.md && \
  grep -qE "abort|중단" plugins/autopilot/skills/spec/SKILL.md && \
  grep -qE "feedback_no_self_apply_during_spec|현재 호출.*선행" plugins/autopilot/skills/spec/SKILL.md'
```

## 제약
- 메모리 노트 `feedback_no_self_apply_during_spec`에 따라 본 SPEC.md를 작성하는 *현재* spec 호출에서는 새 contract를 선행 적용하지 않는다 — 새 동작은 다음 spec 호출부터 적용된다. (self-referential 규약, 단 현재 호출 면제)
- Issue body update는 `gh issue edit <id> --body ...` (GitHub CLI)를 사용한다. step 2의 기존 `gh` 호출 실패 처리 규약과 일관하게 abort하며 roll-back은 수행하지 않는다.
- `rules/context.md`의 Issue body 구조 규약을 손상하지 않는다 — step 2가 설치한 자리표시 2줄은 첫 sync 이후에도 유지된다.

## 위험
- Issue body가 구분자를 포함하지 않는 (비표준) 상태일 경우 sync 동작이 정의되지 않음 — 본 SPEC 범위는 spec 스킬이 step 2에서 만든 표준 구조의 issue로 한정. 비표준 입력은 abort.
- 큰 SPEC.md의 경우 Issue body 길이 한도(GitHub 65536 chars)를 초과할 가능성. 일반 SPEC 규모로는 드물지만, 초과 시 abort + 사용자 안내.
- 동일 task에 다중 spec 호출이 동시 실행되면 Issue body update 순서에 경쟁 조건. 일반적으로 spec 호출은 대화형으로 직렬화되므로 실무 발생 확률 낮음 — 경쟁 탐지·잠금은 본 SPEC 범위 외.
