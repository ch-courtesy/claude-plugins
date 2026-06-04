---
scope:
  include:
    - plugins/autopilot/skills/conductor/references/review-loop.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
depends_on: ["conductor-task-backend-adapter", "conductor-done-to-push-pr-integration"]
verify: "bash -c 'set -e; F=plugins/autopilot/skills/conductor/references/review-loop.sh; test -f \"$F\"; bash -n \"$F\"; grep -qi \"request_changes\" \"$F\"; grep -qE \"REVIEW_ROUNDS|round\" \"$F\"; grep -q \"3\" \"$F\"; grep -qiE \"change-adoption|must-reflect|must_reflect|adopt\" \"$F\"; grep -qiE \"escalat|에스컬|handoff\" \"$F\"; ! grep -q -- \"--force\" \"$F\"; ! grep -q \"push -f\" \"$F\"'"
ears_language: ko
---

> ⛔ **폐기됨 (제거·외부 위임).** 이 C3 리뷰 피드백 자동수정 루프는 더 이상 파이프라인에
> 포함되지 않는다. 내부 자동 리뷰·재구현 고리가 프로덕션 경로에서 끊겨 있었고, 외부 CI
> 리뷰(`claude-review`·`codex-review`)가 같은 역할을 독립 수행한다. 리뷰는 외부 CI(GitHub PR)와
> 사람에게 위임하며, `review-loop.sh`·`autopilot:review` 스킬·`review-round` 상태는 제거됐다.
> 통합으로 열린 PR 의 승인은 외부가 수행하고 `poll` 은 미승인 PR 을 "외부 승인 대기" no-op 로
> 둔다. 아래 본문은 폐기 전 명세의 역사적 기록일 뿐 구현 대상이 아니다.

# conductor 리뷰 피드백 자동수정 루프

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

리뷰 상태의 task에 대해, 자동 리뷰 봇의 변경 요청 피드백을 다시 SPEC으로 만들어 같은 승인 요청(PR) 브랜치에 구현·반영하고 재리뷰를 받는 루프를 만든다. 이 루프가 비전의 핵심("리뷰 상태 task는 피드백을 다시 스펙으로 만들어 같은 PR 브랜치에 구현·푸시해 해결, 승인까지 반복")을 구현한다.

본 모듈이 수행하는 것:

- **트리거 판정**: 열린 승인 요청의 최신 정식 리뷰가 **자동 리뷰 봇**의 "변경 요청"이고, 그 리뷰 대상 head 식별자가 직전에 처리한 식별자보다 새로울 때만 한 라운드를 시작한다. **사람** 리뷰어의 변경 요청은 자동수정 대상이 아니며 사람에게 에스컬레이션한다.
- **피드백 수집·필터**: 봇 리뷰의 요약·인라인 지적·이슈 수준 지적을 구조화해 수집하고, 변경 채택 규칙으로 각 지적을 "반드시 반영(must-reflect)"·"후속으로 미룸(defer)"·"반영 불필요(no-need)"로 분류한다. 안전 경계(테스트·범위·권한·보안·계약) 지적은 강등하지 않는다. 후속으로 미룬 지적은 이 PR에 섞지 않고 별도 백로그 task로 분리한다.
- **피드백→SPEC→구현→같은 브랜치 push**: 반드시 반영할 지적을 SPEC 델타(미해결 마커가 있으면 재개, 없으면 같은 SPEC 계보에 증분)로 만들고, task 본문을 재동기화한 뒤, 그 SPEC을 **승인 요청의 head 브랜치 위에서** 자율 실행기로 구현한다. 완료되면 같은 head 브랜치로 push해 승인 요청을 갱신한다(새 승인 요청을 만들지 않음). force push는 금지한다. push로 인한 재리뷰는 서버측 리뷰 워크플로가 자동 발화한다.
- **무한루프 가드**: 라운드 수 상한(기본 3)을 초과하면 자동수정을 멈추고 차단 기록·사람 알림을 남기되 승인 요청은 리뷰 상태로 유지한다. "반드시 반영" 지적이 0인데도 여전히 변경 요청이면(무진전) 에스컬레이션한다. 차단성 지적의 집합이 직전 라운드와 동일하면(동일 지적 반복) 에스컬레이션해 봇↔conductor 핑퐁을 차단한다.

이 모듈은 C1의 task backend 어댑터(상태·본문 동기화·후속 task 생성)와 C2의 forge 통합(브랜치·push)을 차용한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

1. 시스템은 `plugins/autopilot/skills/conductor/references/review-loop.sh`를 제공하며, 그 파일은 `bash -n` 문법 검사를 통과한다.
2. When 열린 승인 요청의 최신 정식 리뷰가 자동 리뷰 봇의 "변경 요청"이고 그 head 식별자가 직전 처리분보다 새로우면, 시스템은 한 자동수정 라운드를 시작한다.
3. If 변경 요청이 사람 리뷰어의 것이면, 시스템은 자동수정을 시작하지 않고 사람에게 에스컬레이션한다.
4. When 봇 피드백을 수집하면, 시스템은 각 지적을 "반드시 반영"·"후속으로 미룸"·"반영 불필요"로 분류하고, 안전 경계 지적을 강등하지 않는다.
5. When 후속으로 미룰 지적이 있으면, 시스템은 그 지적을 현재 승인 요청에 섞지 않고 별도 백로그 task로 분리한다.
6. When 반드시 반영할 지적을 구현하면, 시스템은 그 결과를 같은 승인 요청 head 브랜치로 push하고 새 승인 요청을 만들지 않는다.
7. 시스템은 어떤 push에서도 force(강제) 옵션을 사용하지 않는다.
8. If 자동수정 라운드 수가 상한(3)을 초과하면, 시스템은 자동수정을 멈추고 사람에게 에스컬레이션하며 승인 요청을 리뷰 상태로 유지한다.
9. If 한 라운드에서 "반드시 반영" 지적이 0인데도 여전히 변경 요청이면, 시스템은 에스컬레이션한다.
10. If 차단성 지적의 집합이 직전 라운드와 동일하면, 시스템은 에스컬레이션한다.

## 범위
포함:
- `plugins/autopilot/skills/conductor/references/review-loop.sh` — 봇 변경요청 트리거 판정 + 피드백 수집·채택 필터 + SPEC 델타·구현·같은 브랜치 push + 3라운드 캡·무진전·동일지적 가드

비-목표 / 제외:
- conductor SKILL.md 수정 — C0 단독 소유
- task 생성·상태 전이·본문 동기화 정의 — C1 제공(호출만)
- push·PR 헬퍼 정의 — C2 제공(호출만)
- 머지·Done — C4 담당
- 사람 리뷰어 코멘트 자동수정 — 사용자 결정상 범위 밖(에스컬레이션만)
- 서버측 리뷰 워크플로(`claude-review.yml`) 변경 — 그 출력을 소비만
- `rules/` 변경 — `review.md`·`change-adoption.md`의 실행자

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 사용자 확정 결정: **봇 리뷰만, 3라운드 캡.** 사람 리뷰어 코멘트는 자동수정하지 않는다.
- 피드백 채택은 `rules/change-adoption.md`(반드시 반영/미룸/불필요 결정 프레임워크)와 `rules/review.md`의 실행자로서 따른다.
- 피드백 출처는 서버측 리뷰 워크플로 출력(요약·인라인·이슈 수준 지적)을 폴링해 소비한다. 트리거는 승인 요청 상태이며 별도 웹훅을 요구하지 않는다.
- 같은 브랜치 push, force 금지. SPEC 델타는 마커 유무에 따라 재개 또는 같은 계보 증분.
- 본 단위는 C1·C2에 의존한다(`depends_on`). 상태·본문·push 동작은 그 공개 함수 계약(SKILL.md)으로 호출한다.
- `feedback_no_self_apply_during_spec`: 본 SPEC 구현 호출 중 contract 선행 적용 금지.

## 위험
- **무한 리뷰 루프**: 봇↔conductor 핑퐁. 3라운드 캡 + 동일지적 해시 + 무진전 가드 세 겹으로 차단하고 초과 시 사람에게 넘긴다.
- **안전 경계 강등**: 채택 필터가 보안·테스트·계약 지적을 "불필요"로 잘못 분류할 위험. 안전 경계 지적은 강등 금지로 못박는다.
- **self-referential**: `feedback_self_referential_verification`에 따라 검증은 verify·worktree source만 보고 runtime artifact(실제 PR 리뷰·브랜치)를 직접 검사하지 않는다. 봇 리뷰 입력은 mock으로 검증한다.
