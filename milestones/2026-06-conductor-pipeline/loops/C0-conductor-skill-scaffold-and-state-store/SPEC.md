---
scope:
  include:
    - plugins/autopilot/skills/conductor/SKILL.md
    - plugins/autopilot/skills/conductor/references/conductor.sh
    - plugins/autopilot/skills/conductor/references/lib-state.sh
    - .gitignore
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; D=plugins/autopilot/skills/conductor; test -f \"$D/SKILL.md\"; test -x \"$D/references/conductor.sh\"; bash -n \"$D/references/conductor.sh\"; bash -n \"$D/references/lib-state.sh\"; grep -qE \"^name: conductor\" \"$D/SKILL.md\"; for s in intake start review merge poll status list stop; do grep -q \"conductor $s\" \"$D/SKILL.md\"; done; ! grep -qE \"(^|[^a-zA-Z._-])gh \" \"$D/references/conductor.sh\"; grep -q \".conductor/tasks\" \"$D/references/lib-state.sh\"; grep -q \"^.conductor/\" .gitignore'"
ears_language: ko
---

# conductor 스킬 스캐폴드 + 상태 저장소

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

autopilot 플러그인에 새 스킬 `conductor`의 골격을 세운다. conductor는 spec/loop/dispatch가 의도적으로 비워둔 "forge 호출 레이어"를 구현하는 오케스트레이터로, spec-first 자동화 파이프라인을 엔드투엔드로 닫는 컴포넌트다. 본 단위는 그 스킬의 **정의 문서·서브커맨드 라우터·상태 저장소 골격**까지만 만든다 — 실제 forge(`gh`)·task backend 연동은 후속 단위(C1~C5)가 각자의 references 모듈에 채운다.

본 단위가 세우는 것:

- **스킬 정의 문서**: conductor가 무엇이고, 어떤 공개 인터페이스(서브커맨드)를 갖고, 어디에 상태를 보관하며, 어떤 불변식(loop/dispatch를 공개 인터페이스로만 조합, 자기 상태 디렉토리 밖 경로 미생성)을 지키는지를 한 곳에 기술하는 단일 출처. 후속 단위들이 이 계약을 입력 컨텍스트로 차용하므로, 6개 서브커맨드(intake·start·review·merge·poll·status/list/stop)의 책임과 입출력 계약을 **완전판으로** 기술한다.
- **서브커맨드 라우터**: 호출을 받아 해당 서브커맨드 핸들러로 분기하고, 프로젝트 루트를 탐지하며, 상태 저장소를 초기화하는 진입 드라이버. 본 단위 시점에서 `intake`·`start`는 **spec·dispatch 조합까지만** 수행한다 — 즉 SPEC 작성 위임 결과로 얻은 SPEC 경로(들)를 모아 dispatch에 위임하고 그 run을 상태 저장소에 기록한다. forge·task backend 동작(이슈 생성·PR·머지·상태 전이)은 본 단위에서 구현하지 않고 후속 단위의 자리(stub 또는 미구현 핸들러)로 남긴다.
- **상태 저장소 헬퍼**: task 단위의 진행 상태를 프로젝트 루트 하위의 전용 디렉토리에 보관·조회·기록하는 헬퍼 모음. task별로 상태(로컬 미러)·SPEC 경로·브랜치·PR 번호·소유한 dispatch run·append-only 로그·리뷰 라운드 카운터·마지막 head 식별자를 담는 격리된 디렉토리를 갖는다. 이 디렉토리는 git 추적에서 제외한다.

이 단위는 conductor가 `gh`나 forge를 직접 호출하지 않는 골격 상태에서 출발함을 보장한다. spec·loop·dispatch의 정의 파일은 일절 건드리지 않으며, conductor는 그들의 공개 인터페이스만 소비한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

1. 시스템은 `plugins/autopilot/skills/conductor/SKILL.md`를 제공하며, 그 frontmatter는 `name: conductor`를 포함한다.
2. `conductor`의 SKILL.md가 존재할 때, 시스템은 그 본문에서 여섯 서브커맨드 `conductor intake`·`conductor start`·`conductor review`·`conductor merge`·`conductor poll`·`conductor status`(및 `list`·`stop`)의 책임과 입출력 계약을 각각 기술한다.
3. 시스템은 실행 가능한 `plugins/autopilot/skills/conductor/references/conductor.sh`를 제공하며, 그 파일은 `bash -n` 문법 검사를 통과한다.
4. 시스템은 `plugins/autopilot/skills/conductor/references/lib-state.sh`를 제공하며, 그 파일은 `bash -n` 문법 검사를 통과하고 `.conductor/tasks` 경로 하위에 task별 상태 디렉토리를 만드는 헬퍼를 정의한다.
5. `conductor.sh`가 제공될 때, 시스템은 그 파일 안에서 `gh ` 명령을 직접 호출하지 않는다(forge 연동은 후속 단위 references 모듈의 책임).
6. When 빈 상태에서 `conductor list`가 호출되면, 시스템은 오류 없이(0 exit) 빈 run 목록 또는 그에 준하는 정상 출력을 낸다.
7. When `conductor start`가 SPEC 경로(들)로 호출되면, 시스템은 자율 실행기 오케스트레이터(dispatch)를 그 공개 서브커맨드로 위임 호출하고 그 run 식별자를 해당 task의 상태 디렉토리에 기록한다.
8. 시스템은 `.gitignore`에 conductor 상태 디렉토리(`.conductor/`)를 git 추적 제외 항목으로 포함한다.
9. 본 단위가 conductor 골격을 세우는 동안, 시스템은 spec·loop·dispatch 스킬의 정의 파일을 수정하지 않는다.

## 범위
포함:
- `plugins/autopilot/skills/conductor/SKILL.md` — 스킬 정의·6 서브커맨드 공개 인터페이스 계약·상태 저장소 레이아웃·불변식의 단일 출처(완전판)
- `plugins/autopilot/skills/conductor/references/conductor.sh` — 서브커맨드 라우터 + 프로젝트 루트 탐지 + intake/start의 spec·dispatch 블랙박스 조합(forge 없음)
- `plugins/autopilot/skills/conductor/references/lib-state.sh` — `.conductor/tasks/<task-id>/` 상태 저장소 헬퍼(set/get state·log_event·run-id 기록 등)
- `.gitignore`에 `.conductor/` 추가

비-목표 / 제외:
- task backend(Issue/Project) 생성·상태 전이·이슈 동기화 — 후속 C1 담당
- DONE→push→PR forge 통합 — 후속 C2 담당
- 리뷰 피드백 루프 — 후속 C3 담당
- 머지·Done·cleanup — 후속 C4 담당
- poll 드레인·상시 호스트 운영 가이드 — 후속 C5 담당
- spec·loop·dispatch 정의 파일 변경 — 본 milestone 전체의 명시 비-목표
- `plugin.json` 버전 범프 — 머지 오케스트레이션 책임(본 단위 scope 제외)
- dispatch wave→dataflow 전환 — 별도 milestone

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- conductor는 `.conductor/` 디렉토리 밖 경로를 만들지 않는다(자기 스킬 정의 파일 제외). 참조 구현 패턴은 `plugins/autopilot/skills/dispatch/references/dispatch.sh`의 run-dir 관리·`log_event`·state 파일·`spec_slug`/`hash7` 유틸을 차용한다.
- 라우터는 bash 3.2+ 호환으로 작성한다(dispatch.sh와 동일 제약).
- spec 작성은 spec 스킬의 공개 호출(`Skill(skill: "spec", ...)`)로, 구현 위임은 dispatch의 공개 서브커맨드(`dispatch start <spec...>`)로만 한다. 그 내부 신호 파일·워크트리를 직접 들여다보지 않는다.
- `feedback_no_self_apply_during_spec`: 본 SPEC을 작성·구현하는 호출 중에 conductor contract를 그 호출 자신의 산출물에 선행 적용하지 않는다 — 새 동작은 다음 호출부터 적용된다.

## 위험
- **self-referential**: conductor는 autopilot 자체를 다루는 스킬이므로, 본 단위를 자율 loop이 구현할 때 자기 골격을 수정한다. `feedback_self_referential_verification`에 따라 검증은 verify 명령과 worktree source 파일만 보고, runtime artifact(`.conductor/`·`.dispatch/`·워크트리)를 직접 검사하지 않는다.
- **계약 조기 확정 부담**: SKILL.md가 6 서브커맨드 계약을 완전판으로 적어야 후속 단위가 충돌 없이 병렬 진행된다. 계약이 모호하면 후속 단위가 SKILL.md를 동시 수정하려 해 wave 충돌이 난다 — 이를 막기 위해 SKILL.md는 C0 단독 소유로 고정한다.
