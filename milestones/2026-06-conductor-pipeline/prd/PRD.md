# autopilot:conductor — spec-first 자동화 파이프라인 호출 레이어

**Milestone**: 2026-06-conductor-pipeline

## 문제

autopilot의 spec·loop·dispatch는 의도적으로 forge(GitHub PR·머지)와 task backend(Issue·Project)에 비결합이다. `rules/orchestration/forge-integration.md`와 `task-state-alignment.md`는 이 비결합을 명시하면서, 그 대신 "호출 레이어(calling layer)"가 다음을 책임진다고 **선언만** 한다:

- SPEC → 백로그 task 생성 및 상태 정합
- loop의 DONE 신호 감지 → base sync → push → PR 생성/재사용
- PR 리뷰 폴링 → 피드백 자동수정 → 승인 → 머지 → 사후 정리
- task 상태 전이 (Backlog → In Design → In Progress → Review → Done, +Blocked)

그러나 **이 호출 레이어를 구현한 스킬이 없다.** 사용자가 SPEC을 완성해도, 그 이후 task 생성·구현 위임·PR·리뷰 반영·머지·완료 전이를 모두 사람이 수동으로 오케스트레이션해야 한다. 비전의 핵심("사용자는 SPEC 완성까지만, 이후 전 과정 자동화")이 닫히지 않는다.

## 목표·비전

새 스킬 `autopilot:conductor`가 그 빈 호출 레이어를 구현해 spec-first 자동화를 엔드투엔드로 닫는다.

- 사용자는 인터뷰로 SPEC을 완성하는 것으로 요청을 종료한다(`conductor intake`).
- 완성된 SPEC은 백로그 task가 되어 상태기계를 따라 흐른다.
- conductor가 dispatch·loop·spec을 **공개 인터페이스(블랙박스)로만** 조합하고, `gh`(forge + task backend)를 만지는 **유일한** 컴포넌트가 된다. loop/dispatch의 forge-비결합 원칙은 그대로 유지된다.
- task 상태: SPEC 완성 → In Progress(구현 중); 사용자 피드백 필요(spec-gap) → In Design; 구현 완료·승인요청 → Review; 승인 → 머지 → Done.
- Review task는 PR 봇 리뷰 피드백을 다시 SPEC으로 만들어 같은 PR 브랜치에 구현·push해 해결하고, 봇이 승인하면 머지되어 Done이 된다.
- 전 과정이 전용 상시 호스트에서 `conductor poll`로 무인 자동화된다.

이 milestone은 conductor 스킬과 그 references 드라이버를 신설한다. spec·loop·dispatch의 코드는 변경하지 않는다(공개 인터페이스만 소비).

## 사용자 확정 결정

1. **머지 자동화 = 전면 무인.** 사람 개입 없이 봇이 approve까지. 워크플로 토큰의 self-approve 제약은 별도 approver 봇/PAT로 우회한다. `context.md`의 "Review→Done 명시적 신호"는 "approver-bot의 APPROVED 리뷰"로 해석한다.
2. **리뷰 루프 = 봇 리뷰만, 3라운드 캡.** `claude-review.yml` 봇의 `request_changes`에만 자동 반응한다. 사람 리뷰어 코멘트는 자동수정하지 않고 에스컬레이션한다. 3회 초과 시 사람에게 핸드오프한다.
3. **런타임 = 전용 상시 호스트.** 항상 켜진 데몬 호스트에서 `conductor poll`을 상시 폴링한다. 무인 `gh` 토큰의 신뢰 경계가 이 호스트다.

## 성공 기준

- `conductor intake "<요청>"`가 spec 인터뷰를 위임해 SPEC을 산출하고, 마커 없는 SPEC이면 백로그 task(Issue + Project item)를 생성한다. 마커가 남으면 task를 만들지 않는다.
- `conductor start <spec>`가 task 상태 정합 → 이슈 본문 동기화 → dispatch 위임(구현) → loop DONE 감지 → rebase(no force)→push→PR 생성/재사용 → task를 Review로 전이한다.
- loop terminal 신호가 task 상태로 매핑된다: DONE→Review, BLOCKED `category: spec-gap`→In Design, 그 외 하드 BLOCKED→Blocked+에스컬레이션.
- `conductor review`가 봇 `request_changes` 피드백을 `change-adoption.md` 필터로 분류해 must-reflect만 같은 PR 브랜치에 구현·push하고, 3라운드 캡·동일지적·무진전 가드로 무한루프를 방지한다.
- `conductor merge`가 approver-bot APPROVED를 확인하고, `plugins/**` 변경 시 `plugin.json` 버전 범프를 강제(versioning.md)한 뒤 ff-only 머지하고, task를 Done으로 전이하며 `loop.sh cleanup`을 호출한다.
- `conductor poll`이 백로그 + 열린 PR을 한 바퀴 idempotent하게 드레인해 각 task를 한 스텝 전진시킨다. 2회 연속 실행이 동일 상태에서 부작용(중복 PR·중복 전이) 없이 멱등이다.
- conductor가 `gh`·forge·task backend를 만지는 유일한 컴포넌트다. spec·loop·dispatch의 정의 파일은 본 milestone에서 변경되지 않는다.

## 범위

포함:

- 새 스킬 `plugins/autopilot/skills/conductor/`:
  - `SKILL.md` — 전체 공개 인터페이스(서브커맨드·상태 저장소·규칙) 정의 문서
  - `references/conductor.sh` — 서브커맨드 라우터 + spec·dispatch 블랙박스 조합 드라이버
  - `references/lib-state.sh` — `.conductor/tasks/<task-id>/` 상태 저장소 헬퍼
  - `references/task-backend.sh` — task 상태 정합 + Issue/Project Status 전이 + issue-sync 펜스
  - `references/forge.sh` — loop terminal 신호 매핑 + DONE→rebase→push→PR 통합
  - `references/review-loop.sh` — 봇 리뷰 피드백 자동수정 루프 + 무한루프 가드
  - `references/merge.sh` — approver-bot 확인 + 버전범프 게이트 + ff-only 머지 + Done + cleanup
  - `references/poll.sh` — idempotent 백로그·PR 드레인
  - `references/operational-guide.md` — 전용 상시 호스트 운영·토큰 신뢰 경계 가이드
- `.gitignore`에 `.conductor/` 추가
- `plugins/autopilot/.claude-plugin/plugin.json` 버전 범프(머지 오케스트레이션이 처리; 각 child SPEC scope에는 넣지 않음)

비-목표 / 제외:

- **spec·loop·dispatch 코드 변경 금지** — conductor는 그 공개 인터페이스(`spec` Skill 호출, `dispatch start/status/watch`+run-id, `loop.sh status/cleanup`)만 소비한다.
- **dispatch wave-barrier → dataflow 스케줄러 전환** — conductor는 dispatch를 블랙박스로 쓰므로 wave↔dataflow는 invisible. 직교하는 dispatch-내부 최적화로 별도 milestone에서 다룬다.
- **rules/ 변경** — conductor는 기존 단일 출처 룰(forge-integration·task-state-alignment·issue-sync·branch-and-slug·versioning·context·review·change-adoption)의 **실행자**일 뿐 룰 자체를 재정의하지 않는다.
- **claude-review.yml 변경** — 서버측 리뷰 워크플로는 그대로 두고 conductor가 그 출력을 `gh api`로 폴링·소비한다.
- adapter 인터페이스·다중 backend 구현 신설.

## 제약

- conductor는 `.conductor/` 디렉토리 밖 경로를 만들지 않는다(자기 스킬 정의 파일 제외). 산출 상태는 모두 `.conductor/tasks/<task-id>/` 아래에 격리한다.
- task backend의 진실의 원천은 GitHub Project Status 필드이고, `.conductor/tasks/<id>/STATE`는 크래시 복구용 로컬 미러일 뿐이다. 불일치 시 백엔드가 우선한다.
- Status vocabulary는 정확히 `Backlog`/`In Design`/`In Progress`/`Review`/`Done`/`Blocked`/`Cancelled`만 사용한다(context.md 단일 출처).
- force push 금지. 머지는 ff-only. base sync rebase는 ff 가능할 때만.
- 본 milestone은 `plugins/autopilot/` 워치 디렉토리를 변경하므로 머지 시 `plugin.json` 버전 범프가 필수다(versioning.md). 버전 범프는 머지 오케스트레이션 책임이며 child SPEC의 scope.include에는 포함하지 않는다(6개 SPEC 병렬 머지 충돌 방지).
- `feedback_no_self_apply_during_spec` 메모리 룰: 본 milestone의 어느 child SPEC도 *자신의 호출* 중 conductor contract를 자신의 산출물에 선행 적용하지 않는다.

## 위험

- **self-referential**: conductor가 autopilot 자체를 소재로 동작하면 자기 구현을 다룬다. 각 child SPEC에 `feedback_no_self_apply_during_spec`·`feedback_self_referential_verification`를 명시해, 검증은 verify·worktree source만 보고 runtime artifact(`.conductor/`·`.dispatch/`·워크트리) 직접 검사를 금지한다.
- **무한 리뷰 루프** — ⛔ **해당 없음(C3 폐기)**: 내부 봇 리뷰 ↔ 자동수정 핑퐁 위험은 C3 리뷰 피드백 루프를 폐기(제거·외부 위임)하면서 사라졌다. 리뷰는 외부 CI(GitHub PR)와 사람에게 위임하고, 통합으로 열린 미승인 PR 은 `poll` 이 "외부 승인 대기" no-op 로 둔다(자동 재구현 없음).
- **무인 자동머지의 룰 위반**: 버전 범프 누락이 가장 무거운 룰(versioning.md)을 조용히 위반할 위험. C4 머지 게이트가 `plugins/**` 변경 시 `plugin.json` 범프를 강제하고 없으면 머지를 차단한다.
- **무인 gh 권한**: 전용 상시 호스트가 신뢰 경계. 스코프된 토큰, approver-bot 신원 분리, loop 서브프로세스가 머지/push 권한을 상속하지 않도록 격리(C5 운영 가이드).
- **scope 충돌**: C1~C5가 SKILL.md를 동시 수정하면 wave 병렬 충돌. SKILL.md는 C0가 전체 인터페이스를 완전판으로 작성하고, C1~C5는 각자 `references/*.sh`만 소유해 격리한다.

## 분해 힌트

dispatch에 맡기되, 본 PRD는 6단위(C0~C5)로 분해되며 DAG는 `dispatch/DAG.md` 참조. 핵심 격리 원칙: SKILL.md는 C0 단독 소유, 각 child는 자기 references/*.sh만 수정.
