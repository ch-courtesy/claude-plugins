---
scope:
  include:
    - plugins/autopilot/skills/spec/**
    - plugins/autopilot/.claude-plugin/plugin.json
    - rules/orchestration/**
    - rules/engineering/**
  exclude:
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; SK=plugins/autopilot/skills/spec/SKILL.md; ! grep -qE \"task 상태 정합|Issue body sync|feat 브랜치|task-state-alignment|feat-branch-commit\" \"$SK\"; grep -qF \"docs/specs/\" \"$SK\"; grep -qiE \"autopilot:loop\" \"$SK\"; test -f rules/orchestration/task-state-alignment.md; test -f rules/orchestration/issue-sync.md; test -f rules/engineering/branch-and-slug.md; ! grep -q \"\\\"version\\\": \\\"0.5.6\\\"\" plugins/autopilot/.claude-plugin/plugin.json'"
# test_sweep_paths: reviewed-no-sweep
# ears_language: ko
request_review: true
---

# spec 경량화: 외부 의존성 분리 (externalize deps)

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
spec 스킬을 "명확화 인터뷰 → SPEC 문서 작성 → 구현 스킬 추천"의 세 책임만 갖는 경량 스킬로 단순화한다. 현재 spec이 떠안고 있는 외부 의존성 — task-id 검증·사전검사·라우팅, GitHub Issue 생성과 상태 정합, Issue body 동기화, feat 브랜치·slug·파일명 생성, loop 자동 연계 — 를 spec 본체에서 제거한다. 제거한 절차는 폐기하지 않고 각 성격에 맞는 rules 카테고리 지침으로 옮겨 손실 없이 보존한다. 결과적으로 spec은 외부 상태(이슈·브랜치·원격)를 만들지 않고 SPEC 문서 하나만 산출한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 verify에서 fail 가능해야 함. -->
1. spec SKILL.md는 명확화·SPEC 문서 작성·구현 스킬 추천 외의 책임을 기술하지 않아야 한다. 특히 task-id 검증·사전검사·검증 실패 라우팅·task 상태 정합·Issue body sync·feat 브랜치 생성 단계를 포함하지 않아야 한다.
2. When spec가 SPEC 문서를 작성하면, 산출 경로는 `docs/specs/<YYYY-MM-DD>-<slug>.md` 형식이어야 한다.
3. When SPEC 문서 작성이 끝나면, spec는 SPEC 내용에 적합한 구현 스킬을 추천하되 자율 실행이 적합하면 autopilot:loop을 우선 추천하고, 어떤 후속 스킬도 자동 호출하지 않아야 한다.
4. task 상태 정합, Issue body sync, 브랜치/slug/파일명 규칙은 각각 rules/ 아래 카테고리 지침 문서로 존재해야 하며, spec SKILL.md는 이 절차들을 직접 기술하지 않아야 한다.
5. If spec SKILL.md 또는 그 references가 제거·이전된 문서를 가리키는 참조를 남기면, 그 dangling 참조는 존재하지 않아야 한다.
6. plugins/ 변경을 동반하므로 plugin.json 버전이 0.5.6에서 SemVer 규약에 따라 상향되어야 한다.
7. Where --resume 기능이 유지되는 경우, spec는 대상 SPEC 문서의 `[NEEDS CLARIFICATION]` 마커만 다시 물어 해소해야 한다.

## 범위
포함:
- spec SKILL.md 본문 단순화 (제거 단계 삭제, 산출 경로 변경, loop 추천으로 종결)
- spec references 정리 (이전된 문서 제거, clarification.md 등 dangling 참조 수정, references 표·spec-template 산출 경로 갱신)
- rules 분리처 지침 신설: `rules/orchestration/task-state-alignment.md`, `rules/orchestration/issue-sync.md`, `rules/engineering/branch-and-slug.md`
- plugin.json 버전 상향

비-목표 / 제외:
- loop·pr-phase가 docs/specs 경로를 읽도록 하는 연동 변경 → 후속 task
- test-spec-loop-contract.sh 의 경로 단언 갱신 → 후속 task
- 신설 rules 지침을 loop 실행 흐름에 실제로 배선하는 변경 → 후속 task

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash -c 'set -e; SK=plugins/autopilot/skills/spec/SKILL.md; \
  ! grep -qE "task 상태 정합|Issue body sync|feat 브랜치|task-state-alignment|feat-branch-commit" "$SK"; \
  grep -qF "docs/specs/" "$SK"; \
  grep -qiE "autopilot:loop" "$SK"; \
  test -f rules/orchestration/task-state-alignment.md; \
  test -f rules/orchestration/issue-sync.md; \
  test -f rules/engineering/branch-and-slug.md; \
  ! grep -q "\"version\": \"0.5.6\"" plugins/autopilot/.claude-plugin/plugin.json'
```

## 제약 (있을 때만)
- 이번 호출(현 spec)이 정의하는 새 동작을 이 SPEC 산출물 자신에는 선행 적용하지 않는다 (self-apply 금지). 이 SPEC은 현 컨벤션대로 `milestones/regular/loops/220-spec-externalize-deps/` 아래에 둔다.
- `rules/`는 본래 SPEC scope.exclude 기본값이나, 분리처 지침을 신설해야 하므로 의도적으로 scope.include에 포함한다.
- 검증은 런타임 산출물이 아니라 정적 grep + 파일 존재로만 한다 (self-referential 검증 원칙).

## 위험 (있을 때만)
- **계약 일시 분리**: 산출 경로를 docs/specs로 바꾸면 spec↔loop↔pr-phase 경로 계약과 test-spec-loop-contract.sh(T1e·T4)가 깨진다. loop 연동·계약 테스트 갱신을 후속 task로 분리했으므로, 이 task 머지 후 해당 계약 테스트는 후속 완료 전까지 red 상태가 된다 — 의도된 일시 분리.
- **no-task-no-work 책임 이동**: spec이 더 이상 이슈를 만들지 않으므로 대상 프로젝트의 task 생성 책임이 rules/loop로 이동한다. 후속 배선 전까지 공백이 생기지 않도록 분리처 지침에 책임 소재를 명시한다.

## 후속 task 메모
- loop/pr-phase의 docs/specs 경로 연동 + test-spec-loop-contract.sh 갱신
- 신설 rules 지침을 loop 실행 흐름에 배선
