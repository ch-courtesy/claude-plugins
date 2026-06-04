# DAG — 2026-06-conductor-pipeline

`milestones/2026-06-conductor-pipeline/prd/PRD.md`의 분해 결과. 새 스킬 `autopilot:conductor`(spec-first 자동화 호출 레이어)를 6단위(C0~C5)로 분해한다.

생성 시각: 2026-06-01T00:00Z

## 단위 목록

- **C0**: conductor 스킬 스캐폴드 + 상태 저장소 + spec·dispatch 블랙박스 조합
  - slug: `conductor-skill-scaffold-and-state-store`
  - 영향 파일: plugins/autopilot/skills/conductor/SKILL.md, plugins/autopilot/skills/conductor/references/conductor.sh, plugins/autopilot/skills/conductor/references/lib-state.sh, .gitignore
  - verify: SKILL.md frontmatter `name: conductor` 존재 + 6개 서브커맨드 문서화 + conductor.sh bash 문법 통과·실행권한 + `.conductor/tasks/<id>/` 레이아웃 헬퍼 grep + conductor.sh에 `gh ` 호출 부재 grep + .gitignore에 `.conductor/` 존재
  - 의존성: 없음
- **C1**: task 백엔드 어댑터 (상태 정합 + Issue/Project Status 전이 + issue-sync 펜스 + intake)
  - slug: `conductor-task-backend-adapter`
  - 영향 파일: plugins/autopilot/skills/conductor/references/task-backend.sh
  - verify: task-backend.sh bash 문법 통과 + 4분기 정합 함수 grep + Status vocabulary(Backlog/In Design/In Progress/Review/Done/Blocked/Cancelled) 문자열 grep + issue-sync 펜스(`autopilot:spec-sync:begin`) grep + mock `gh`로 intake가 마커 SPEC에 task 미생성 단언
  - 의존성: C0 (lib-state.sh 상태 헬퍼·라우터 차용)
- **C2**: loop terminal 신호 매핑 + DONE→rebase→push→PR 통합
  - slug: `conductor-done-to-push-pr-integration`
  - 영향 파일: plugins/autopilot/skills/conductor/references/forge.sh
  - verify: forge.sh bash 문법 통과 + 신호 매핑(DONE→Review / spec-gap→In Design / 하드 BLOCKED→Blocked) grep + `loop.sh status` 공개 IF 소비 grep + `--force` 부재 grep + mock으로 DONE→rebase→push→PR 순서·PR 재사용 단언
  - 의존성: C0 (lib-state.sh 상태 헬퍼·라우터 차용)
- **C3** — ⛔ **폐기됨 (제거·외부 위임)**: 봇 리뷰 피드백 자동수정 루프 + 무한루프 가드
  - 폐기 사유: 내부 자동 리뷰·재구현 고리가 프로덕션 경로에서 끊겨 있었고(자율 실행기 미연결·워크트리→브랜치 이식 부재), 외부 CI 리뷰(`claude-review`·`codex-review`)가 같은 역할을 독립 수행한다. 리뷰는 외부 CI(GitHub PR)와 사람에게 위임하고 `review-loop.sh`·`autopilot:review` 스킬·`review-round` 상태는 제거됐다. 통합으로 열린 PR 의 승인은 외부가 수행하며 `poll` 은 미승인 PR 을 "외부 승인 대기" no-op 로 둔다.
  - slug: `conductor-review-feedback-loop` (구현물 제거됨)
  - ~~영향 파일: review-loop.sh~~ (삭제됨)
- **C4**: approver-bot 확인 + 버전범프 게이트 + ff-only 머지 + Done + cleanup
  - slug: `conductor-merge-and-done`
  - 영향 파일: plugins/autopilot/skills/conductor/references/merge.sh
  - verify: merge.sh bash 문법 통과 + approver-bot APPROVED 확인 grep + 버전범프 게이트(plugins/** 변경 시 plugin.json 범프 강제) grep + ff-only(`--ff-only` 또는 merge ff) grep + Done 전이·`loop.sh cleanup` 호출 grep + mock으로 범프 누락 시 머지 차단 단언
  - 의존성: C2 (forge.sh PR 헬퍼 차용)
- **C5**: idempotent 백로그·PR 드레인(poll) + 전용 상시 호스트 운영 가이드
  - slug: `conductor-poll-and-daemon-glue`
  - 영향 파일: plugins/autopilot/skills/conductor/references/poll.sh, plugins/autopilot/skills/conductor/references/operational-guide.md
  - verify: poll.sh bash 문법 통과 + 백로그·열린 PR 한 바퀴 드레인 로직 grep + 멱등(2회 연속 동일 상태 부작용 없음) mock 단언 + operational-guide.md에 토큰 스코프·신뢰 경계·approver-bot 신원 분리·loop 권한 미상속 명시 grep
  - 의존성: C1, C2, C3, C4 (전체 호출 레이어 조합)

## 의존성·wave 정렬

```
C0 ──┬── C1 ──┬── C3 ── C5
     └── C2 ──┴── C4 ──┘
```

- **wave 1** (스캐폴드 선행): [C0]
- **wave 2** (depends on C0, parallel-safe): [C1, C2]
- **wave 3** (depends on C1·C2, parallel-safe): [C3, C4]
- **wave 4** (전체 조합): [C5]

(wave 정렬은 가독용. dispatch는 frontmatter `depends_on`으로 위상정렬해 실제 실행 순서를 정한다.)

## 메모

**scope 격리(핵심)**: SKILL.md는 C0가 전체 공개 인터페이스를 완전판으로 작성·단독 소유한다. C1~C5는 각자 자기 `references/*.sh`(+ C5는 operational-guide.md)만 수정하므로 같은 wave 내 동시 실행 시 파일 충돌이 없다. C0의 SKILL.md 산출물은 wave 2~4의 입력 컨텍스트(인터페이스 계약)로만 차용되고 파일 동시 수정은 일어나지 않는다.

- wave 2: C1=task-backend.sh, C2=forge.sh — 서로 다른 파일, 충돌 없음.
- wave 3: C3=review-loop.sh, C4=merge.sh — 서로 다른 파일, 충돌 없음.
- wave 4: C5=poll.sh + operational-guide.md — 단독.

**plugin.json 버전 범프**: 본 milestone은 `plugins/autopilot/`를 변경하므로 머지 시 `plugin.json` 버전 범프가 필수다(versioning.md). 6개 child가 각자 plugin.json을 건드리면 머지 충돌이 나므로, 버전 범프는 어느 child SPEC의 scope.include에도 넣지 않고 머지 오케스트레이션(conductor의 C4 머지 게이트 또는 사람 머지) 책임으로 둔다.

**self-referential 위험**: conductor가 autopilot 자체를 다루므로, 각 child SPEC에 `feedback_no_self_apply_during_spec`(현재 호출 중 contract 선행 적용 금지)·`feedback_self_referential_verification`(검증은 verify·worktree source만, runtime artifact 직접 검사 금지)를 명시한다.

**forge-agnostic 보존**: 어느 child도 spec·loop·dispatch의 정의 파일을 수정하지 않는다. conductor는 그 공개 인터페이스만 소비한다 — 이 불변식은 각 child의 verify에서 `gh ` 호출이 conductor references에만 존재하고 loop/dispatch에는 없음을 확인하는 방식으로는 검사하지 않으며(범위 밖 파일 미접근), 각 child의 scope.exclude가 spec/loop/dispatch 경로를 포함하지 않음으로 보장한다.
