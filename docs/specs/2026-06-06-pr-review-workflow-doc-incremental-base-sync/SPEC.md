---
scope:
  include:
    - docs/codex/pr-review-workflow.md
    - docs/claude/pr-review-workflow.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# PR 리뷰 워크플로 문서의 증분 base·위조 방지 현행화

## 무엇을 만들 것인가
PR 리뷰 워크플로 설계·상태 문서(`docs/codex/pr-review-workflow.md`와 짧은 자매
`docs/claude/pr-review-workflow.md`)의 "현재 상황"을, 이미 머지된 증분 리뷰 base 변경에 맞춰
사실 일치시킨다. 두 가지를 반영한다.

1. **Context Modes의 incremental 설명 갱신** — 현재 두 문서의 incremental 모드 설명은
   "직전 push head(이전 head)부터 현재 head까지의 패치를 보낸다"는 옛 동작을 기술한다. 이를
   "해당 리뷰어가 **마지막으로 성공적으로 리뷰한 커밋**(리뷰어가 남긴 공식 리뷰 마커의
   head 커밋, 작성자가 신뢰된 리뷰 봇인지 검증)부터 현재 head까지"로 바꾼다. 그런 마커가
   없거나 현재 head의 조상이 아니면 전체(full) diff로 떨어진다는 점도 함께 적는다.

2. **codex 문서에 현행화 항목 추가** — `docs/codex/pr-review-workflow.md`에, 위 변경의 동기인
   **리뷰 커버리지 공백**(어떤 push의 리뷰가 실패하면 다음 push의 옛 base 계산이 그 미검토
   커밋을 건너뛰어 영구히 리뷰되지 않던 문제)과 그 **위조 방지 강화**(마커를 신뢰된 리뷰 봇
   작성자가 남긴 것만 인정해, 사람·다른 봇이 가짜 마커로 base를 조작하지 못하게 함)를
   설명하는 항목을 추가한다. 이 항목은 새 공유 모듈과 prep 단계 변화도 언급한다 — 마커 파싱·
   작성자 검증을 담당하는 공유 스크립트(`.github/scripts/pr-review-incremental-base.js`)와,
   신뢰 봇 신원을 동적으로 얻기 위해 prep 단계에 추가된 GitHub App 토큰 스텝.

자매 문서(`docs/claude/pr-review-workflow.md`)는 incremental 모드 설명 갱신만 반영한다(현행화
항목 본문은 codex 문서에 둔다 — claude 문서는 그 codex 문서를 참조한다).

## 목적 (왜)
문서가 옛 동작(직전 push head 기준 증분)을 기술해 실제 구현(마지막 성공 리뷰 SHA 기준 +
작성자 검증)과 어긋난다. 이 문서를 정본 설계·상태 기준으로 삼는 독자나 재구현자가 잘못된
동작을 사실로 받아들이지 않도록, 머지된 현실에 문서를 일치시킨다. 동작을 바꾸는 변경이
아니라 이미 일어난 변경을 기록하는 문서 정합 작업이다.

## 완료 조건
- 항상 `docs/codex/pr-review-workflow.md`의 incremental 모드 설명은, 증분 base가 직전 push
  head가 아니라 "그 리뷰어가 마지막으로 성공적으로 리뷰한 마커 head 커밋(작성자가 신뢰된
  리뷰 봇인지 검증)"이며 적격 마커가 없으면 full로 떨어진다는 것을 기술한다.
- 항상 `docs/claude/pr-review-workflow.md`의 incremental 모드 설명도 같은 의미로 갱신된다.
- 항상 `docs/codex/pr-review-workflow.md`에는 리뷰 커버리지 공백(실패한 리뷰의 커밋이 옛 base
  계산으로 영구 스킵되던 문제)과 그 위조 방지 강화(신뢰 봇 작성자 마커만 인정)를 설명하는
  현행화 항목이 존재한다.
- 항상 그 현행화 항목은 공유 모듈 `.github/scripts/pr-review-incremental-base.js`와 prep 단계의
  GitHub App 토큰 스텝(신뢰 봇 신원 동적 확보)을 언급한다.
- 항상 기존 문서의 단계별 상태 마커(✅ 구현됨 / ❌ 미구현)·날짜·구조·서술 스타일은
  보존되며, 실제 워크플로 동작을 바꾸는 서술은 추가하지 않는다(문서만 수정).
- 두 문서를 모두 갱신했을 때, 어느 문서에도 옛 "직전 push head/이전 head 기준 증분" 서술이
  현행 설명과 모순된 채로 남아 있지 않다.

## 범위
포함:
- `docs/codex/pr-review-workflow.md` — Context Modes incremental 설명 갱신 + 현행화 항목 추가.
- `docs/claude/pr-review-workflow.md` — Context Modes incremental 설명 갱신.

비-목표 / 제외:
- 워크플로(`.github/workflows/*`)·스크립트(`.github/scripts/*`)의 동작 변경. 이 SPEC은 문서만
  수정한다(해당 동작 변경은 이미 머지됨).
- 위조 방지 강화를 별도 Phase로 승격하는 것(Phase 1~5는 codex 워크플로 빌드 단계이고
  incremental은 교차 관심사라, Context Modes 갱신 + 현행화 항목으로 기록한다).
- 두 문서의 그 외 섹션(목표·운영 원칙·플랫폼 공통화 등) 재작성.

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로
본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로
정의한다.

## 제약
- 용어는 음차 "하드닝" 대신 우리말("위조 방지 강화" 등)을 쓴다.
- 사실 출처: 증분 base = 마지막 성공 리뷰 마커 head, 작성자 검증 = 신뢰 봇 login(리뷰 App
  봇 `<app-slug>[bot]` + 기본 토큰 `github-actions[bot]`), 마커 부재·비조상 시 full fallback.
  이 사실들과 어긋나게 적지 않는다.
