---
scope:
  include:
    - plugins/autopilot/skills/conductor/references/task-backend.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
depends_on: ["conductor-skill-scaffold-and-state-store"]
verify: "bash -c 'set -e; F=plugins/autopilot/skills/conductor/references/task-backend.sh; test -f \"$F\"; bash -n \"$F\"; grep -q \"In Design\" \"$F\"; grep -q \"In Progress\" \"$F\"; grep -q \"Backlog\" \"$F\"; grep -q \"Review\" \"$F\"; grep -q \"autopilot:spec-sync:begin\" \"$F\"; grep -qiE \"align|정합\" \"$F\"'"
ears_language: ko
---

# conductor task 백엔드 어댑터

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

conductor가 완성된 SPEC을 백로그 task로 만들고, task의 상태를 백엔드와 정합시키며, SPEC 본문을 task 본문으로 단방향 동기화하는 어댑터 모듈을 만든다. 이 모듈은 conductor가 task backend(이슈 + 프로젝트 보드)와 상호작용하는 단일 지점이다.

본 모듈이 수행하는 것:

- **상태 정합(4분기)**: 주어진 SPEC에 대응하는 task의 현재 상태를 조회하고, 프로젝트 규칙의 정합 규칙에 따라 분기한다 — (a) task가 없으면 새로 만들고 설계 상태로 둔다, (b) 설계 상태면 그대로 진행한다, (c) 백로그 상태면 설계 상태로 전이한다, (d) 이미 진행 중·리뷰·완료 상태면 새 task를 만들어 새 식별자를 쓴다.
- **task 생성·상태 전이**: 이슈와 프로젝트 보드 항목을 만들고, 상태 필드를 정확한 어휘(`Backlog`/`In Design`/`In Progress`/`Review`/`Done`/`Blocked`/`Cancelled`)로만 전이한다. 상태 전이는 conductor(에이전트)의 책임이며 사용자에게 떠넘기지 않는다.
- **이슈 본문 동기화(펜스)**: SPEC 본문을 task 본문의 자동 동기화 펜스 구역 안에 단방향으로 반영한다. 펜스 밖 사용자 작성 내용은 보존하고, 재동기화 시 펜스 안만 교체한다. task 본문의 필수 섹션(목표·배경·제안·검증 계획·완료 기준)은 프로젝트 규칙의 본문 구조를 따른다.
- **intake**: SPEC 작성을 위임받아 산출된 SPEC에 미해결 마커가 없으면 백로그 task를 생성한다(계획 섹션이 채워졌으면 설계 상태, 캡처만이면 백로그 상태). 마커가 남아 있으면 task를 만들지 않는다. 진행 로그·결정·차단 같은 기록은 정해진 코멘트 접두 규약(`[handoff]`·`[decision]`·`[blocked]`)을 따른다.
- **로컬 미러 동기화**: 백엔드 상태를 task의 로컬 상태 디렉토리에 미러링한다. 백엔드가 진실의 원천이고 로컬 미러는 크래시 복구용이며, 불일치 시 백엔드가 우선한다.

이 모듈은 conductor의 상태 저장소 헬퍼(C0가 만든 `lib-state.sh`)와 서브커맨드 라우터를 차용해 동작한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

1. 시스템은 `plugins/autopilot/skills/conductor/references/task-backend.sh`를 제공하며, 그 파일은 `bash -n` 문법 검사를 통과한다.
2. When 주어진 SPEC에 대응하는 task가 없으면, 시스템은 새 task를 만들고 설계 상태(`In Design`)로 둔다.
3. While 대응 task가 백로그 상태(`Backlog`)이면, 시스템은 그 task를 설계 상태(`In Design`)로 전이한다.
4. While 대응 task가 진행 중·리뷰·완료(`In Progress`/`Review`/`Done`) 상태이면, 시스템은 기존 task를 재사용하지 않고 새 task를 만들어 새 식별자를 사용한다.
5. 시스템이 task 상태를 설정할 때, 시스템은 정확한 상태 어휘(`Backlog`·`In Design`·`In Progress`·`Review`·`Done`·`Blocked`·`Cancelled`) 외의 값을 쓰지 않는다.
6. When SPEC 본문을 task 본문에 동기화하면, 시스템은 자동 동기화 펜스(`autopilot:spec-sync:begin`/`end`) 안의 내용만 교체하고 펜스 밖 내용은 보존한다.
7. If intake가 위임받은 SPEC에 미해결 명확화 마커(spec 스킬이 남기는 `NEEDS CLARIFICATION` 표식)가 남아 있으면, 시스템은 백로그 task를 만들지 않는다.
8. When intake가 마커 없는 SPEC을 받으면, 시스템은 백로그 task(이슈 + 프로젝트 보드 항목)를 생성하고 그 상태를 로컬 미러에 기록한다.
9. If 로컬 미러 상태와 백엔드 상태가 불일치하면, 시스템은 백엔드 상태를 진실의 원천으로 채택한다.

## 범위
포함:
- `plugins/autopilot/skills/conductor/references/task-backend.sh` — 4분기 상태 정합 + task 생성·상태 전이 + 이슈 본문 펜스 동기화 + intake task 생성 + 로컬 미러 동기화

비-목표 / 제외:
- conductor SKILL.md 수정 — 공개 인터페이스 계약은 C0가 단독 소유(완전판). 본 단위는 references 모듈만 만든다.
- DONE→push→PR forge 통합 — C2 담당
- 리뷰 피드백 루프 — C3 담당
- 머지·Done·cleanup — C4 담당
- poll 드레인 — C5 담당
- `rules/` 변경 — 본 단위는 `context.md`·`task-state-alignment.md`·`issue-sync.md`의 실행자일 뿐 규칙을 재정의하지 않는다
- 역방향 동기화(task→SPEC)·metadata 변경 — issue-sync.md의 명시 비-목표

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- task backend 상호작용은 단일 출처 규칙을 실행자로서 따른다: `rules/context.md`(이슈=task, 상태 어휘, 본문 구조, 코멘트 접두 규약), `rules/orchestration/task-state-alignment.md`(4분기 정합), `rules/orchestration/issue-sync.md`(펜스 단방향 동기화).
- 상태 어휘는 정확히 7개 값만 사용한다. 백엔드가 진실의 원천이고 로컬 미러는 복구용이다.
- 본 단위는 C0의 `lib-state.sh` 상태 헬퍼와 라우터 계약(SKILL.md)에 의존한다(`depends_on`).
- `feedback_no_self_apply_during_spec`: 본 SPEC 구현 호출 중 conductor contract를 그 호출 산출물에 선행 적용하지 않는다.

## 위험
- **self-referential**: `feedback_self_referential_verification`에 따라 검증은 verify·worktree source만 보고 runtime artifact(`.conductor/`·실제 이슈·보드)를 직접 검사하지 않는다. task backend 동작 검증은 mock 인터페이스로 한다.
- **상태 어휘 드리프트**: 백엔드 상태 필드 명칭이 규칙과 어긋나면 전이가 실패한다. 어휘는 한 곳(이 모듈)에 모아 규칙과 일치시킨다.
