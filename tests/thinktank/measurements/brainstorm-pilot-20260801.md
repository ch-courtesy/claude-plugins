# 측정 기록: brainstorm-pilot-20260801

## 측정 메타데이터

- skill: brainstorm
- model-id: claude-fable-5
- fixture-path: tests/thinktank/fixtures/brainstorm/scenario-01.md
- fixture-hash: sha256:b140901b1e670f8f84e695164ef3e1150d8d618e18756aa6246f401412da2ff3
- threshold-core-fact-min: 1
- threshold-independent-sources-min: 2
- decision-mode: 1회 충족
- measured-at: 2026-08-01
- gate-status: active
- gate-pass-count: 3
- pilot-run-count: 3
- measured-variance: active 지표(core-fact·park·elim)는 전 실행 판정 일치, independent-sources 최대값은 1/3(+판정 불가 2회)로 분산 — shadow 강등
- shadow-metric: independent-sources
- shadow-reason: 실측 최대값 1~5 분산, 문서 템플릿 규약 조정·재파일럿 1회 상한 후에도 통과/실패 판정이 갈림 — 기록 전용으로 강등 (2026-08-01 사용자 승인)

## 측정 방법

픽스처(scenario-01)의 브리프·제약을 입력으로 brainstorm 스킬 계약(SKILL.md + references)을
실제로 수행하는 세션을 서브에이전트로 구동했다(측정 모드: 승인 게이트는 픽스처로 사전 승인 간주,
생성자 렌즈는 단일 컨텍스트 내 순차 수행, 최소 리서치는 실제 WebSearch 사용, validation_approval
상태에서 종료). 세션에는 측정 목표 지표를 알리지 않았다. 산출물 원본은 `sessions/` 하위에 보존한다.

## 파일럿 실행과 판정 (하니스 `measure-session.sh --skill brainstorm --record <세션> --judge`)

| 실행 | 세션 산출물 | core-fact (개수) | independent-sources (최대) | park/elim 필수 필드 | 판정 |
|---|---|---|---|---|---|
| 1 | sessions/brainstorm-run1.md | 27 | 1 | 100% | active 지표 PASS / ind-sources 미충족(현 shadow) |
| 2 | sessions/brainstorm-run2.md | 27 | — (주석 오염 7건) | 100% | 파싱 실패 (형식 위반, 판정 제외 — 내용상 최대 ~5) |
| 3 | sessions/brainstorm-run3.md | 25 | — (주석 오염 2건) | 100% | 파싱 실패 (형식 위반, 판정 제외 — 내용상 최대 2) |
| 4 (재파일럿) | sessions/brainstorm-run4.md | 26 | 3 | 100% | PASS (exit 0) |

run2·run3의 형식 위반을 계기로 문서 템플릿에 "마커 값은 순수 값만(주석 금지, 출처 신뢰도 부연은
연구 컨텍스트 서술로)" 규칙을 추가했고, 정책에 따라 run4로 재파일럿 1회를 수행했다.
independent-sources는 판정 가능 실행에서 1(미충족)/3(충족)으로 갈려 shadow 강등했다.
스킬별 안정 지표 최소 1개 요건은 core-fact·park-recondition·elimination-reason으로 충족한다.

## 게이트 판정 요약

| 지표 | 실측 범위 | 임계치 | gate-status |
|---|---|---|---|
| core-fact | 25~27 | ≥1 | active |
| park-recondition 충족률 | 100% | 100% (fail-loud) | active |
| elimination-reason 충족률 | 100% | 100% (fail-loud) | active |
| independent-sources | 최대 1~5 (분산) | ≥2 | shadow (기록 전용) |

- 게이트 승인: 2026-08-01 (사용자 승인 — CHANGELOG `## thinktank 1.2.0` 섹션 마커 참조)
