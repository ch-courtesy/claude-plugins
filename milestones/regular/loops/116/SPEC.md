---
scope:
  include: ["plugins/autopilot/skills/spec/**", "plugins/autopilot/skills/loop/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh"
ears_language: ko
---

# spec↔loop feat 브랜치·worktree 경로 단일 규약 통일

## 무엇을 만들 것인가

`autopilot:spec` 스킬이 만드는 feat 브랜치와 `autopilot:loop` 스킬이 검색·진입하는 feat 브랜치가 같은 명명 규약을 따른다. 사용자가 default milestone(`regular`)과 단일 컴포넌트 task-id를 줘도 spec→loop 라운드트립이 수동 rename·재진입 없이 성립한다.

SPEC.md 디렉토리와 loop의 worktree 디렉토리가 `milestones/<m>/loops/<input-id>-<slug>/` 단일 컨벤션으로 정합한다. SPEC.md는 그 디렉토리의 `SPEC.md`로, worktree는 그 안의 `.worktree` 서브디렉토리로 생성된다. PR phase가 SPEC.md 경로를 도출할 때도 같은 단일 컨벤션을 따른다.

slug 도출은 결정적(SPEC §1 H1 제목에서 ASCII 소문자·하이픈 슬러그화)이고, spec과 loop 양쪽이 같은 규칙으로 같은 slug에 도달한다. loop은 발견된 feat 브랜치 이름에서 slug를 추출해 디렉토리 위치를 결정한다.

사전 EnterWorktree 등 외부 메커니즘이 만든 별도 브랜치·디렉토리가 있을 경우, spec이 만든 feat 브랜치 + `<input-id>-<slug>` 디렉토리가 단일 정답 위치로 유지된다. 외부 worktree 동기화·migration은 비-목표.

## 수용 기준 (EARS)

- (Ubiquitous) SPEC 작성·자체 검토가 끝나면, spec은 `feat/<input-id>-<slug>` 브랜치를 main에서 분기·생성하고 SPEC.md를 `milestones/<m>/loops/<input-id>-<slug>/SPEC.md` 경로에 commit해야 한다.
- (Event-driven) 사용자가 spec 직후 `Skill(loop, args: "start <input-id>")`를 호출할 때, loop은 `feat/<input-id>-<slug>` 브랜치를 수동 rename·수동 개입 없이 발견해야 한다.
- (Ubiquitous) loop이 worktree를 생성할 때, 그 경로는 `milestones/<m>/loops/<input-id>-<slug>/.worktree`여야 한다. slug는 발견된 feat 브랜치 이름에서 추출된다.
- (Ubiquitous) PR phase는 SPEC.md를 `milestones/<m>/loops/<input-id>-<slug>/SPEC.md` 단일 경로에서 읽어야 한다. 다른 경로 fallback은 없다.
- (Ubiquitous) spec과 loop은 동일한 SPEC §1 H1 제목으로부터 동일한 slug 문자열에 도달해야 한다. slug 규칙은 ASCII 소문자화 후 `[a-z0-9-]` 외 모든 문자를 `-`로 치환·연속 `-` 단일화·양끝 `-` 제거.
- (Unwanted-behavior) 동일 input-id에 두 개 이상의 feat 브랜치가 매칭되면 loop은 어떤 브랜치도 자동 선택하지 않고 명시적 모호성 에러로 비-zero exit 종료해야 한다.

## 범위

포함:
- `plugins/autopilot/skills/spec/SKILL.md` — step 8 SPEC.md 디렉토리 경로(`<c>` 슬롯 slug-bearing), step 9.5.2 브랜치 명령, slug 도출 결과를 디렉토리 경로에도 적용
- `plugins/autopilot/skills/loop/references/loop.sh` — `find_feat_branch` 검색 패턴을 input-id 원형까지 확장, `compute_paths`의 `<c>` 슬롯을 feat 브랜치 이름에서 추출한 slug-bearing 값으로 처리
- `plugins/autopilot/skills/loop/references/pr-phase.sh` — `SPEC_FILE` 경로 도출이 slug-bearing 디렉토리를 가리키도록 정합
- 라운드트립 verify 스크립트(`plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh`) 신설

비-목표 / 제외:
- 기존 슬러그 없는 `milestones/<m>/loops/<input-id>/` 디렉토리(loops/65·69·71·72·75·78·79·104 등) 자동 마이그레이션
- 기존 `feat/regular/<input-id>-*` legacy 브랜치 자동 rename·삭제 (수동 정리)
- `EnterWorktree` 동작 자체 변경 (사전 외부 worktree 동기화는 비-목표)
- `autopilot:dispatch`·`autopilot:prd` 스킬 인터페이스 변경
- 다중 컴포넌트 task-id(`a/b/c` 형태)에서의 slug 위치 정의 — 본 SPEC는 단일 컴포넌트 task-id에 집중

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```
bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh
```

스크립트가 수행하는 검사:

1. slug 도출 결정성: SPEC §1 H1 "Foo Bar" → slug `foo-bar`. spec·loop 양쪽 도출 경로가 동일 결과.
2. find_feat_branch 라운드트립: 임시 git 픽스처에 `feat/<input-id>-<slug>` 브랜치 생성 후 `find_feat_branch <input-id>`가 단일 매칭 반환.
3. worktree 경로 도출: feat 브랜치 이름에서 slug 추출 → `milestones/<m>/loops/<input-id>-<slug>/.worktree` 경로 정합.
4. SPEC.md 경로 정합: spec이 작성하는 경로 = loop·pr-phase가 읽는 경로(`milestones/<m>/loops/<input-id>-<slug>/SPEC.md`).
5. 다중 매칭 die: 같은 input-id에 2+ feat 브랜치 존재 시 loop의 find_feat_branch가 비-zero exit + stderr 모호성 메시지.

모든 검사가 통과하면 exit 0, 실패 시 비-zero + 어느 검사가 깨졌는지 stderr 출력.

## 제약

- 본 작업은 self-referential 변경(spec 스킬이 spec 스킬과 sibling loop 스킬을 수정)이다. verify는 워크트리 source만 검사하며 runtime artifact(`~/.claude/plugins/cache/...` 등)는 참조하지 않는다.
- 기존 슬러그 없는 `milestones/<m>/loops/<input-id>/` 디렉토리는 본 SPEC 후 새 contract에서 인식되지 않는다. 본 SPEC는 그것들을 삭제·이동하지 않는다.
- spec→loop 라운드트립은 default milestone(`regular`) + 단일 컴포넌트 task-id 케이스를 우선 보장한다. 다중 컴포넌트는 별도 SPEC.

## 위험

- self-referential 자기 호출: 본 SPEC를 만든 spec 호출(116번)은 *현재* 코드 기준으로 step 9.5.2를 수행하므로, 본 호출이 만드는 브랜치·SPEC.md 경로는 슬러그 없는 `<c>` 형식일 수 있다. 새 contract는 본 SPEC 머지 이후의 spec 호출부터 적용된다. 본 SPEC 호출의 산출물(브랜치·디렉토리)은 검증 시점에 새 컨벤션으로 수동 정렬이 필요할 수 있다.
- 다중 매칭 die: 사용자 환경에 기존 `feat/regular/<input-id>-*` legacy 브랜치가 잔존하면 새 패턴과 동시 매칭되어 loop이 die. 수동 정리 필요(비-목표 항목으로 명시).
- multi-component task-id: dispatch가 `regular/sub-area/116` 같은 다중 컴포넌트 task-id를 만들 경우 slug 위치·worktree 경로 정의가 비자명. 본 SPEC 범위 외 — 발생 시 별도 SPEC.
