---
scope:
  include:
    - plugins/autopilot/skills/conductor/references/poll.sh
    - plugins/autopilot/skills/conductor/references/operational-guide.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
depends_on: ["conductor-task-backend-adapter", "conductor-done-to-push-pr-integration", "conductor-review-feedback-loop", "conductor-merge-and-done"]
verify: "bash -c 'set -e; D=plugins/autopilot/skills/conductor/references; test -f \"$D/poll.sh\"; bash -n \"$D/poll.sh\"; grep -qiE \"idempotent|멱등|reconcile|정합\" \"$D/poll.sh\"; test -f \"$D/operational-guide.md\"; grep -qiE \"token|토큰\" \"$D/operational-guide.md\"; grep -qiE \"approver\" \"$D/operational-guide.md\"; grep -qiE \"scope|스코프|권한\" \"$D/operational-guide.md\"'"
ears_language: ko
---

# conductor poll + 상시 호스트 운영 글루

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

백로그와 열린 승인 요청을 한 바퀴 훑어 각 task를 한 스텝씩 전진시키는 멱등 드레인(`poll`)과, 이 자동화를 전용 상시 호스트에서 무인 운영하기 위한 운영 가이드를 만든다. 이 단위가 앞선 모든 호출 레이어(C1~C4)를 하나의 반복 가능한 단위로 묶어 "전 과정 자동화"를 닫는다.

본 단위가 수행하는 것:

- **멱등 드레인(poll)**: conductor의 로컬 상태를 task backend·승인 요청의 실제 진실과 정합(reconcile)시키고, 각 task를 그 시점에 가능한 다음 한 스텝으로 전진시킨다 — 미시작 백로그 task는 구현 시작(C2 경로)으로, 봇 변경 요청이 달린 열린 승인 요청은 리뷰 자동수정(C3)으로, 승인된 승인 요청은 머지(C4)로. 한 번의 드레인은 부작용 없이 다시 실행해도 같은 상태에서 같은 결과를 내야 한다(멱등) — 이미 처리한 전이를 중복 수행하거나 중복 승인 요청을 만들지 않는다. 상태는 conductor 상태 저장소에 두고, 드레인 호출은 호출 단위로 무상태(stateless-per-invocation)여서 크래시 후 재시작이 안전하다.
- **백엔드 우선 정합**: 드레인 시 로컬 미러와 백엔드가 불일치하면 백엔드를 진실의 원천으로 채택해 미러를 갱신한다.
- **상시 호스트 운영 가이드**: 이 드레인을 전용 상시 호스트에서 주기적으로 돌리는 방법과, 무인 자격증명의 신뢰 경계를 문서화한다 — 자격증명 토큰의 권한 스코프, 승인 권한 신원(approver)의 분리, 자율 실행기 서브프로세스가 머지·push 권한을 상속하지 않도록 하는 격리, 폴링 주기.

이 단위는 C1(task backend)·C2(forge)·C3(리뷰 루프)·C4(머지)의 공개 동작을 조합한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

1. 시스템은 `plugins/autopilot/skills/conductor/references/poll.sh`를 제공하며, 그 파일은 `bash -n` 문법 검사를 통과한다.
2. When `poll`이 실행되면, 시스템은 백로그와 열린 승인 요청을 한 바퀴 훑어 각 task를 가능한 다음 한 스텝(미시작→구현 시작, 봇 변경요청→리뷰 자동수정, 승인됨→머지)으로 전진시킨다.
3. When `poll`이 동일한 상태에서 연속 두 번 실행되면, 시스템은 두 번째 실행에서 중복 전이나 중복 승인 요청 생성 같은 부작용을 내지 않는다(멱등).
4. If 로컬 미러 상태와 백엔드 상태가 불일치하면, 시스템은 백엔드 상태를 진실의 원천으로 채택해 미러를 갱신한다.
5. 시스템은 `plugins/autopilot/skills/conductor/references/operational-guide.md`를 제공하며, 그 문서는 무인 자격증명 토큰의 권한 스코프를 명시한다.
6. operational-guide.md가 제공될 때, 시스템은 그 문서에 승인 권한 신원(approver)의 분리와 자율 실행기 서브프로세스의 머지·push 권한 미상속(격리)을 명시한다.
7. operational-guide.md가 제공될 때, 시스템은 그 문서에 전용 상시 호스트에서의 폴링 주기·실행 방식을 명시한다.

## 범위
포함:
- `plugins/autopilot/skills/conductor/references/poll.sh` — 멱등 백로그·승인 요청 드레인 + 백엔드 우선 정합 + 각 task 한 스텝 전진
- `plugins/autopilot/skills/conductor/references/operational-guide.md` — 전용 상시 호스트 운영·토큰 스코프·approver 신원 분리·자율 실행기 권한 격리·폴링 주기

비-목표 / 제외:
- conductor SKILL.md 수정 — C0 단독 소유
- 각 스텝의 동작 정의(task 전이·forge·리뷰·머지) — C1~C4 제공(호출만)
- 실제 데몬/스케줄러 프로세스 구성(systemd 유닛 등 호스트별 설정 파일) — 운영 가이드로 문서화하되 호스트 설정 산출물은 만들지 않는다
- `rules/` 변경
- 자율 실행기·dispatch 코드 변경 — 공개 인터페이스만 소비

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 사용자 확정 결정: **런타임은 전용 상시 호스트.** 운영 가이드는 그 호스트를 무인 `gh` 토큰의 신뢰 경계로 명시한다.
- 드레인은 멱등·호출 단위 무상태로 작성한다. 상태는 conductor 상태 저장소(C0)에 둔다.
- 각 스텝은 C1~C4의 공개 함수 계약(SKILL.md)으로 호출한다. 본 단위는 그 네 단위에 의존한다(`depends_on`).
- 스케줄링은 기존 하니스 수단(`/schedule`·`/loop`) 또는 호스트 cron으로 안내하되, 본 단위는 그 글루를 문서화할 뿐 호스트별 설정 파일을 산출하지 않는다.
- `feedback_no_self_apply_during_spec`: 본 SPEC 구현 호출 중 contract 선행 적용 금지.

## 위험
- **멱등 위반**: 드레인이 부분 실패 후 재실행 시 중복 전이·중복 승인 요청을 만들 위험. 상태 저장소를 단일 진실로 삼고 각 전이 전 현재 상태를 재확인해 멱등을 보장한다.
- **무인 권한 과다**: 토큰 스코프가 넓거나 자율 실행기가 머지 권한을 상속하면 사고 반경이 커진다. 운영 가이드가 스코프 최소화·approver 신원 분리·서브프로세스 권한 격리를 명시한다.
- **self-referential**: `feedback_self_referential_verification`에 따라 검증은 verify·worktree source만 보고 runtime artifact(실제 보드·승인 요청)를 직접 검사하지 않는다. 드레인 멱등은 mock으로 검증한다.
