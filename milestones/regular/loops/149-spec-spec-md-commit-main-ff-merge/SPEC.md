---
scope:
  include: ["plugins/autopilot/skills/spec/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh && grep -q 'origin/main' plugins/autopilot/skills/spec/SKILL.md && grep -q 'fast-forward' plugins/autopilot/skills/spec/SKILL.md && grep -q 'push origin' plugins/autopilot/skills/spec/SKILL.md"
ears_language: ko
---

# spec: SPEC.md commit을 main에 자동 ff-merge 단계 추가

## 무엇을 만들 것인가
autopilot:spec 스킬이 SPEC.md를 feat 브랜치에 commit한 직후, 그 commit이 원격 default 브랜치 최신 위로 정렬되어 default 브랜치에도 fast-forward 형태로 반영되고 원격 저장소에 즉시 push되도록 한다. feat 브랜치도 그대로 유지되며 원격에 push되어 후속 loop 실행·협업이 이어진다. 충돌·push 거부 등 실패 상황에서는 호출 이전 상태로 안전하게 복구되고 사용자에게 실패 사유와 복구 방법이 명시적으로 안내된다.

## 수용 기준 (EARS)
- **AC1 (Event-driven):** SPEC.md가 feat 브랜치에 commit되면, 시스템은 원격 저장소로부터 default 브랜치의 최신 상태를 가져온다.
- **AC2 (Event-driven):** 원격 default 브랜치 최신 상태 수집이 성공하면, 시스템은 feat 브랜치를 원격 default 브랜치 위로 rebase한다.
- **AC3 (Event-driven):** feat 브랜치의 rebase가 성공하면, 시스템은 default 브랜치로 전환해 feat 브랜치로부터 fast-forward merge를 적용한다.
- **AC4 (Event-driven):** default 브랜치의 fast-forward merge가 성공하면, 시스템은 사용자 재확인 없이 default 브랜치와 feat 브랜치를 원격 저장소에 push한다.
- **AC5 (Unwanted):** feat 브랜치 rebase 중 충돌이 발생하면, 시스템은 rebase를 중단하고 feat 브랜치·호출 시점의 원래 브랜치·default 브랜치 작업트리를 호출 이전 상태로 복구한 뒤 사용자에게 충돌 사실과 복구 방법을 알린다.
- **AC6 (Unwanted):** default 브랜치 또는 feat 브랜치의 push가 원격 저장소에 의해 거부되면, 시스템은 강제 push를 시도하지 않고 feat 브랜치 commit·SPEC.md 작업트리·로컬 default 브랜치 상태를 보존한 채 사용자에게 push 거부 사실과 복구 안내를 제공한다.
- **AC7 (Ubiquitous):** 전체 흐름이 종료되면, 시스템은 호출 시점의 원래 브랜치로 복귀한다.
- **AC8 (Ubiquitous):** 전체 흐름이 종료되면, 시스템은 default 브랜치 작업트리의 staged·unstaged·untracked 상태를 호출 이전과 동일하게 유지한다.
- **AC9 (Ubiquitous):** spec 스킬 본문에는 위 절차·실패 처리·복구 흐름이 명시적으로 기술되어 있고, 기존 슬러그화 규칙과 SPEC.md commit 절차는 변경되지 않는다.

## 범위
포함:
- autopilot:spec 스킬 본문(§9.5 영역)에 SPEC.md commit 이후 원격 default 브랜치 rebase·default 브랜치 fast-forward merge·원격 push·feat 브랜치 원격 push 단계 추가
- 충돌·push 거부 등 실패 시 안전 중단(abort) 및 호출 이전 상태 복구 로직 명시
- 호출 시점의 원래 브랜치 복귀와 default 브랜치 작업트리 무손상 검증
- autopilot:spec 스킬 하위 테스트 자산(`plugins/autopilot/skills/spec/` 내 contract·sweep 테스트)을 새 절차에 맞춰 갱신·확장

비-목표 / 제외:
- pr-phase·rebase-phase·loop 등 sibling 스킬 본문 수정
- PR 자동 생성 흐름·base·머지 정책 변경
- protected branch 환경에서 push가 항상 거부될 때의 PR fallback 자동 전환
- push 권한·원격 정책 사전 검사 도입

## 검증
이 명령이 0 exit으로 끝나야 합니다:
bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh && grep -q 'origin/main' plugins/autopilot/skills/spec/SKILL.md && grep -q 'fast-forward' plugins/autopilot/skills/spec/SKILL.md && grep -q 'push origin' plugins/autopilot/skills/spec/SKILL.md

## 제약 (있을 때만)
- 본 SPEC은 autopilot:spec 스킬 자신을 수정하는 self-referential SPEC이다. 따라서 이 SPEC을 작성·수락하는 spec 스킬 호출 자체에는 새 §9.5 동작(default 브랜치 rebase·fast-forward merge·원격 push)을 적용하지 않고 현행 §9.5(feat 브랜치 분기·SPEC commit·원래 브랜치 복귀)로만 처리한다.
- 기존 슬러그화 규칙(§9.5.1)과 SPEC.md commit 절차(§9.5.2)는 변경하지 않는다 — 본 변경은 그 절차 *이후*에 새 단계를 덧붙이는 형태로만 이뤄진다.
- 검증은 자기 자신의 driver를 갱신하는 self-referential task의 안전 제약을 따른다: runtime artifact(실제 push 결과·원격 상태)를 직접 검사하지 않고, frontmatter `verify` 명령의 0 exit과 SKILL.md 본문에 대한 정적 grep만으로 수용 기준을 fail 가능하게 만든다.

## 위험 (있을 때만)
- default 브랜치가 protected branch로 설정된 환경에서는 직접 push가 항상 거부될 수 있다. 본 SPEC은 이 경우 AC6의 abort 분기로 처리하지만, 사용자 환경에 따라 결과(자동 흐름의 사실상 비활성화)가 달라질 수 있다.
- SPEC.md가 default 브랜치에 직접 반영되면 후속 코드 변경에 대한 PR의 diff에서 SPEC.md가 제외되어 리뷰어가 PR 페이지만 보고는 SPEC을 확인하기 어려울 수 있다. 이는 본 변경의 의도된 설계 결과이며 호출자의 선택이다.
- rebase 시점에 default 브랜치 작업트리에 staged·unstaged 변경이 남아 있으면 rebase가 거부될 수 있다. 본 SPEC은 이 경우에도 AC5/AC8을 통해 abort + 원상태 복구로 처리하지만, 사용자는 호출 전 작업트리를 정리해두는 편이 안전하다.
