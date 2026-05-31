---
scope:
  include:
    - plugins/autopilot/skills/conductor/references/forge.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
depends_on: ["conductor-skill-scaffold-and-state-store"]
verify: "bash -c 'set -e; F=plugins/autopilot/skills/conductor/references/forge.sh; test -f \"$F\"; bash -n \"$F\"; grep -q \"loop.sh\" \"$F\" || grep -qi \"loop_status\" \"$F\"; grep -q \"spec-gap\" \"$F\"; grep -q \"Review\" \"$F\"; grep -q \"In Design\" \"$F\"; grep -q \"Blocked\" \"$F\"; ! grep -q -- \"--force\" \"$F\"; ! grep -q \"push --force\" \"$F\"; ! grep -q \"push -f\" \"$F\"'"
ears_language: ko
---

# conductor DONE→push→PR 통합

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

conductor가 자율 실행기의 종료 신호를 읽어 task 상태로 매핑하고, 구현이 완료된 task를 원격에 올려 승인 요청(PR)을 만드는 통합 모듈을 만든다. 이 모듈은 "구현 완료"와 "승인 요청 상태(Review)" 사이의 다리다.

본 모듈이 수행하는 것:

- **종료 신호 매핑**: 자율 실행기의 공개 상태 인터페이스만으로 각 child의 종료 의도를 읽고 task 상태로 매핑한다. (1) 완료 신호(DONE, 차단 없음)면 task를 진행 중에서 리뷰 상태로 전이하고 아래 통합 단계를 실행한다. (2) 차단 신호의 범주가 "스펙 부족(spec-gap)"이면 task를 설계 상태로 되돌리고 차단 기록을 남기며 사용자 재개(`--resume`) 경로를 표면화한다. (3) 그 외 하드 차단 범주(설정·환경·아키텍처 부족, 게이트 위반, 기타)면 task를 차단 상태로 두고 사람에게 에스컬레이션하며 push·PR을 하지 않는다.
- **base sync**: 완료된 작업 브랜치를 기본 브랜치(main)에 정합시킨다 — fast-forward 가능할 때만 rebase하고, force는 절대 쓰지 않는다.
- **push**: 작업 결과를 정해진 명명 규약의 작업 브랜치(`feat/<task-id>-<slug>`)로 원격에 올린다. force push는 금지한다.
- **PR 생성/재사용**: 같은 head 브랜치에 이미 열린 승인 요청이 있으면 재사용하고, 없으면 새로 만든다(중복 생성 금지). PR 생성 후 인계 기록을 남기고 task를 리뷰 상태로 둔다.

이 모듈은 conductor의 상태 저장소 헬퍼(C0)와 라우터 계약(SKILL.md)을 차용하며, 종료 신호 판정은 dispatch가 자율 실행기를 읽는 것과 동일한 공개 인터페이스(상태/신호 컬럼) 패턴을 따른다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

1. 시스템은 `plugins/autopilot/skills/conductor/references/forge.sh`를 제공하며, 그 파일은 `bash -n` 문법 검사를 통과한다.
2. When 자율 실행기가 완료 신호(DONE, 차단 없음)로 종료하면, 시스템은 해당 task를 진행 중(`In Progress`)에서 리뷰(`Review`) 상태로 전이한다.
3. When 완료된 task를 원격에 통합하면, 시스템은 base sync(rebase, fast-forward 가능할 때만) → push → PR 생성/재사용 순서로 수행한다.
4. When 자율 실행기가 차단 신호의 범주 "스펙 부족(spec-gap)"으로 종료하면, 시스템은 해당 task를 설계(`In Design`) 상태로 전이하고 차단 기록을 남긴다.
5. If 자율 실행기가 스펙 부족 외의 하드 차단 범주로 종료하면, 시스템은 task를 차단(`Blocked`) 상태로 두고 push·PR을 수행하지 않는다.
6. When 같은 head 브랜치에 이미 열린 승인 요청이 있는 채로 통합이 실행되면, 시스템은 새 승인 요청을 만들지 않고 기존 것을 재사용한다.
7. 시스템은 어떤 push·rebase에서도 force(강제) 옵션을 사용하지 않는다.
8. 시스템은 자율 실행기의 종료 상태를 그 공개 인터페이스(상태/신호 컬럼)로만 읽고, child 워크트리·내부 신호 파일을 직접 들여다보지 않는다.
9. 시스템이 만드는 작업 브랜치 이름은 `feat/<task-id>-<slug>` 형식을 따른다.

## 범위
포함:
- `plugins/autopilot/skills/conductor/references/forge.sh` — 종료 신호 매핑(DONE→Review / spec-gap→In Design / 하드 BLOCKED→Blocked+에스컬레이션) + base sync(rebase, ff-only) + push(no force) + PR 생성/재사용

비-목표 / 제외:
- conductor SKILL.md 수정 — C0 단독 소유
- task 생성·상태 전이 헬퍼의 정의 — C1이 제공(본 단위는 그 전이를 호출)
- 리뷰 피드백 루프 — C3 담당
- 머지·Done·cleanup — C4 담당
- poll 드레인 — C5 담당
- `rules/` 변경 — `forge-integration.md`·`branch-and-slug.md`의 실행자일 뿐
- 자율 실행기(loop)·dispatch 코드 변경 — 공개 인터페이스만 소비

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- forge 통합은 단일 출처 규칙을 실행자로서 따른다: `rules/orchestration/forge-integration.md`(책임표·신호 계약·DONE 통합 흐름), `rules/engineering/branch-and-slug.md`(브랜치명·커밋·원격 동기화 절차).
- 종료 신호 판정은 자율 실행기의 공개 상태 인터페이스로만 한다 — 참조 패턴은 `dispatch.sh`의 `loop_status_state`/`loop_status_files`/`child_terminal_state`.
- force push 금지, 머지 ff-only(머지는 C4 책임이나 push/rebase 단계에서도 force 금지 불변식 유지).
- 본 단위는 C0의 상태 헬퍼·라우터 계약, C1의 상태 전이 헬퍼에 런타임 의존하나, `depends_on`은 C0만 명시한다(C1과는 병렬 wave로 파일 충돌이 없고, 전이 헬퍼는 동일 모듈군의 공개 함수로 호출). C1 전이 함수가 아직 없을 환경에서도 본 모듈은 자기 함수 정의·문법이 독립 검증된다.
- `feedback_no_self_apply_during_spec`: 본 SPEC 구현 호출 중 contract 선행 적용 금지.

## 위험
- **self-referential**: `feedback_self_referential_verification`에 따라 검증은 verify·worktree source만 보고 runtime artifact(실제 PR·브랜치·워크트리)를 직접 검사하지 않는다. forge 동작은 mock 인터페이스로 검증한다.
- **C1 결합도**: 상태 전이를 C1 헬퍼에 의존한다. 두 단위가 같은 wave(C0 이후)라 동시 작성되므로, 전이 호출은 SKILL.md(C0)에 적힌 공개 함수 계약명으로만 참조해 결합 모호를 피한다.
