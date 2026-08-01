# 측정 기록: roundtable-pilot-20260802

## 측정 메타데이터

- skill: roundtable
- model-id: claude-fable-5
- fixture-path: tests/thinktank/fixtures/roundtable/scenario-01.md
- fixture-hash: sha256:896d285da38b482d292475b2a512bc166a9bc8648eb2b016e44531141691ffc6
- threshold-dissent-forcing: yes
- threshold-rebuttal-min: 1
- threshold-core-claim-min: 1
- decision-mode: 1회 충족
- measured-at: 2026-08-02
- gate-status: active
- gate-pass-count: 3
- pilot-run-count: 3
- measured-variance: active 지표 3회 판정 전부 일치 — dissent yes/yes/yes, rebuttal 합계 1/2/2, core-claim 3/6/4

## 측정 방법

픽스처(scenario-01)의 아젠다·로스터를 입력으로 roundtable 스킬 계약(SKILL.md + references)을
실제로 수행하는 세션을 서브에이전트로 구동했다(측정 모드: 승인 게이트는 픽스처로 사전 승인 간주,
운영·참여 역할은 단일 컨텍스트 내 순차 수행 — 중첩 에이전트 불가 환경의 한계로 기록함).
세션에는 측정 목표 지표를 알리지 않았다. 산출물 원본은 `sessions/` 하위에 보존한다.

## 파일럿 실행과 판정 (하니스 `measure-session.sh --skill roundtable --record <세션> --judge`)

| 실행 | 세션 산출물 | dissent (any-yes) | rebuttal (합계) | core-claim (개수) | 판정 |
|---|---|---|---|---|---|
| 1 | sessions/roundtable-run1.md | yes | 1 | 3 | PASS (exit 0) |
| 2 (원본) | sessions/roundtable-run2.md | — | — | — | 파싱 실패: 마커 값 산문 주석 (형식 위반, 판정 제외) |
| 2 (재파일럿) | sessions/roundtable-run2b.md | yes | 2 | 6 | PASS (exit 0) |
| 3 | sessions/roundtable-run3.md | yes | 2 | 4 | PASS (exit 0) |

run2 원본의 형식 위반을 계기로 문서 템플릿에 "마커 값은 순수 값만(주석 금지)" 규칙을 추가했고,
정책(시나리오·규약 조정 후 재파일럿 1회 상한)에 따라 run2b로 1회 대체했다. run2 원본도
내용상으로는 반대 강제가 발동(Round 3)했고 원본 세션 파일을 증거로 보존한다.

## 게이트 판정 요약

| 지표 | 실측 범위 | 임계치 | gate-status |
|---|---|---|---|
| dissent-forcing-triggered | yes (3/3) | yes | active |
| rebuttal-exchange | 1~2 | ≥1 | active |
| core-claim | 3~6 | ≥1 | active |

- 게이트 승인: 2026-08-02 (사용자 승인 — CHANGELOG `## thinktank 1.2.0` 섹션 마커 참조)
