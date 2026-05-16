---
scope:
  include: ["plugins/autopilot/skills/loop/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh"
ears_language: ko
request_review: true
---

# loop review phase: 모든 inline review thread comment에 1:1 응답 (타당 시 코드 수정 / 부당 시 thread reply)

## 무엇을 만들 것인가
PR review 폴링 단계가 새 inline review thread comment를 발견했을 때, 그 comment가 reviewer 관점에서 타당하면 해당 의견을 반영한 코드 수정으로, 타당하지 않으면 같은 inline thread에 reply 코멘트로 응답한다. 모든 새 inline thread comment는 두 분기 중 정확히 하나로 처리되며 누락 없이 1:1 응답한다. 같은 thread에는 phase 한 사이클 동안 최대 1개 reply만 게시한다(재폴링 시 중복 금지). PR-level comment·review summary·owner cmd(`/done` 등) 처리 경로는 본 변경의 영향을 받지 않고 기존 동작을 보존한다.

## 수용 기준 (EARS)
- AC1: 새 inline review thread comment가 발견되면, 본 시스템은 그 comment 단위로 두 분기 중 정확히 하나(코드 수정 또는 thread reply)로 응답해야 한다.
- AC2: 본 시스템이 inline comment를 타당하다고 판단했을 때, 그 의견을 반영한 코드 변경을 commit·push 해야 한다.
- AC3: 본 시스템이 inline comment를 부당하다고 판단했을 때, 그 inline thread 안에 reply comment 1개를 게시해야 한다 (PR-level comment 아님).
- AC4: 같은 inline thread는 같은 phase 사이클 동안 최대 1개의 reply만 받아야 한다 (동일 thread 재폴링 시 중복 reply 미게시).
- AC5: 본 시스템은 한 phase 사이클 동안 서로 다른 inline thread들에 대한 reply 게시 횟수에 상한을 두지 않는다 (기존 'phase당 1회' 가드 제거).
- AC6: PR-level comment, review summary, owner cmd 처리 경로는 본 변경의 영향을 받지 않고 기존 동작을 보존해야 한다.

## 범위
포함:
- inline comment에 대한 응답 분기(타당→코드 수정, 부당→해당 inline comment에 reply)
- reply 게시 위치(같은 inline comment 맥락 안)
- 동일 inline comment 중복 reply 차단 가드
- 기존 phase당 1회 dispute 가드의 inline 경로 제거

비-목표 / 제외:
- PR-level comment / review summary / owner cmd 동작 변경
- 자동 머지(reviewDecision=APPROVED, owner cmd) 로직 변경
- PR state(MERGED/CLOSED) 분기 변경
- reply 본문의 LLM 자율성 평가·필터링 메커니즘
- 같은 phase 종료 후 재시작 시 reply 이력 영속화 (phase 사이클 내 중복만 차단)

## 검증
이 명령이 0 exit으로 끝나야 합니다:
bash plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh

신규 케이스 커버:
- (a) inline comment 타당 → 코드 수정 push 1회
- (b) inline comment 부당 → 해당 inline thread에 reply 1개 게시
- (c) 같은 inline thread 재폴링 시 중복 reply 미게시
- (d) 같은 phase 사이클에 서로 다른 inline thread 2개 부당 판정 → 각 thread에 reply 1개씩(총 2개)
- (e) PR-level comment·review summary·owner cmd 분기는 기존 동작 보존

## 제약 (있을 때만)
- 기존 GitHub Issues backing(rules/context.md)·SPEC 123 골격(폴링·rebase·claude fix 세션·commit·push)을 깨지 않는다 — 본 SPEC는 inline thread 응답 경로만 변경한다.
- 사용 GitHub API 또는 동등 수단이 PR review thread 안으로 reply를 게시할 수 있어야 한다 (PR-level comment로 fallback 금지).

## 위험 (있을 때만)
- thread reply 본문 LLM 자율성으로 사소한 의견에 과도하게 반박해 reviewer-bot 갈등을 유발할 수 있음 → fix 세션 프롬프트에서 "타당성 판정은 보수적으로(불확실하면 fix 쪽)"라는 가이드 보강으로 완화.
- thread 단위 dedup은 phase 사이클 내에만 적용되므로 phase 재시작 시 같은 thread에 새 reply가 추가될 수 있음 (의도된 trade-off — background 폴링이라 짧은 주기 재시작은 빈번하지 않다고 가정).
