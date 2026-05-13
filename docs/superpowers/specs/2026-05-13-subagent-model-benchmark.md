# Subagent 모델 벤치마크 — 초기 보고서

**측정 시작일**: 2026-05-13
**모델 버전**: claude-opus-4-7 / claude-sonnet (시점) / claude-haiku (시점) — Anthropic SDK enum: `opus`·`sonnet`·`haiku`
**측정 대상**: autopilot 자율 루프 worker 이터의 `Agent` 도구 dispatch (3종 양식 — `plugins/autopilot/skills/loop/references/agent-prompts.md`)
**상태**: 초기 권장 + 측정 인프라 완성. **실측 데이터는 후속 세션에서 수집**.

---

## 1. 요약 (초기 권장)

| 양식 | 권장 모델 (초기) | 근거 |
|---|---|---|
| spec-compliance-reviewer | `claude-sonnet` | SPEC·코드 대조는 정밀 추론 요구. opus 대비 절반 비용으로 수렴, haiku는 다단계 verifier 일관성에서 분산 큼 (prior knowledge). |
| code-quality-reviewer | `claude-opus` | 시니어 코드 리뷰는 아키텍처·결합도·심각도 분류 등 깊은 합성 추론 요구. sonnet은 critical/important 경계에서 일관성 부족, haiku는 structural 관찰 얕음. |
| parallel-hypothesis-tester | `claude-sonnet` | read-only 관찰·최소 변경 검증은 깊이보다 follow-through 중요. 병렬 호출이 비용을 N배 증폭하므로 opus 과잉, haiku는 가설 진위 판정 분산 큼. |

이 권장은 **실측 전 prior knowledge 기반**이다. 측정 후 다르면 본 보고서 §6에 갱신 기록과 함께 `agent-prompts.md`의 `**권장 모델:**` 라인을 보정한다 (SPEC AC #6).

---

## 2. 측정 디자인

### 2.1 변이형 (variants/)

세 가지 고정 모델 할당 변이형으로 동일 task를 N회 실행해 변량 제어 (`tests/autopilot/benchmark-subagent-models/variants/`).

| 변이 | spec-compliance | code-quality | hypothesis-test | 의도 |
|---|---|---|---|---|
| A-fast | haiku | haiku | haiku | 비용·속도 최저 기준선 |
| B-deep | opus | opus | opus | 품질 천장 기준 |
| C-roles | sonnet | opus | sonnet | 역할별 최적해 가설 (=권장) |

### 2.2 Task 셋 (tasks/)

| ID | 역할 | 종류 | 측정 의도 |
|---|---|---|---|
| 01-spec-compliance | spec-compliance-reviewer | 합성 | 단일 파일 변경의 4-Level Verifier (Existence/Substantive/Wired/Runtime) 점검 정확도 |
| 02-code-quality | code-quality-reviewer | 합성 | 심각도 분류 (Critical/Important/Minor) calibration 정확도 |
| 03-hypothesis-test | parallel-hypothesis-tester | 합성 | read-only 가설 검증 시 결정 위임 회피·관찰 vs 추측 분리 |
| 04-real-loop | spec-compliance-reviewer | 실 운영 | `milestones/regular/loops/69` 의 실제 SPEC + 최종 commit. 합성의 단순화 가정 보강 |

각 task는 frontmatter `quality_rubric`에 5 항목 pass/partial/fail 체크리스트를 명시 — LLM-judge 또는 인간 채점에 동일 기준 사용.

### 2.3 실행 회수 N

기본 N=5. 분산이 큰 변이형 (예: A-fast의 02-code-quality)은 N=10으로 보강 권장.

총 셀: 4 task × 3 variant × 5 = 60 dispatch.

### 2.4 측정 지표

| 차원 | 지표 | 소스 |
|---|---|---|
| 품질 | rubric 5 항목 점수 합 (0~10, partial=1) + LLM-judge 점수 (0~5) | 사람 채점 또는 별 모델 (opus 권장) |
| 비용 | total_cost_usd (per cell) | usage.json (CC 세션 기록) + admin-aggregate.json |
| 속도 | duration_ms (start → output 완료) | timing.json (wall-clock) |

집계 통계: 평균·중앙값·표준편차 (분산 큰 셀 식별).

---

## 3. 인프라 (구축 완료)

```
tests/autopilot/benchmark-subagent-models/
  README.md                # 사용법·디렉토리 규약
  runner.sh                # 4 × 3 × N dispatch 실행기 (claude --print --output-format json --model <m>)
  collect-costs.sh         # raw/ 집계 → TSV + admin cross-check
  tasks/                   # 4 task 정의 (frontmatter: role·quality_rubric)
  variants/                # 3 변이 정의 (role → model 매핑)
  raw/                     # 실행 결과 저장 (현재 .gitkeep만)
```

실행 흐름:

```
bash tests/autopilot/benchmark-subagent-models/runner.sh
bash tests/autopilot/benchmark-subagent-models/collect-costs.sh > raw/summary.tsv
```

### 3.1 raw 셀 레이아웃

각 (variant × task × run-N) 셀은 다음을 저장한다 (runner.sh 가 생성):

```
raw/<variant>/<task>/run-N/
  input.txt        # task 본문 (frontmatter 제외)
  output.txt       # claude 응답 텍스트 (result 필드)
  session.jsonl    # CC 세션 기록 원본
  timing.json      # {started_at, ended_at, duration_ms, exit_code}
  usage.json       # {model, total_cost_usd, input_tokens, output_tokens, cache_read, cache_creation, session_id}
```

---

## 4. 두 소스 cross-check (비용 데이터)

SPEC AC #5: 두 독립 소스에서 비용 데이터 수집 → 차이 유무·근거 명시.

### 4.1 소스 정의

| 소스 | 추출 위치 | 단위 |
|---|---|---|
| #1 세션 기록 | `~/.claude/projects/<id>/<session>.jsonl` 또는 `--output-format json` 의 result jsonl `.total_cost_usd`·`.usage.*` | per-session |
| #2 관리 집계 | Anthropic admin API의 organization-level usage endpoint | per-window |

### 4.2 cross-check 방법

1. 벤치마크 측정 시작 시각·종료 시각을 ISO timestamp로 기록.
2. 종료 후 admin API의 `usage_report` 를 측정 윈도로 필터링해 `tests/autopilot/benchmark-subagent-models/raw/admin-aggregate.json` 에 저장.
3. `collect-costs.sh` 가 두 소스의 합계를 나란히 출력.
4. 보고서에 다음 표로 정리:

| 모델 | 소스 #1 합계 (USD) | 소스 #2 합계 (USD) | 차이 | 차이율 | 추정 원인 |
|---|---|---|---|---|---|
| haiku | TBD | TBD | TBD | TBD | (실측 시 기재) |
| sonnet | TBD | TBD | TBD | TBD | (실측 시 기재) |
| opus | TBD | TBD | TBD | TBD | (실측 시 기재) |

### 4.3 차이 발생 가능 원인 (사전 가설)

- **캐싱**: 세션 기록의 `cache_read_input_tokens`는 할인 가격 적용. 관리 집계는 원가 기준일 수 있음.
- **서비스 티어**: standard / batch / priority 가격 차이.
- **rounding**: 세션은 token-level, 관리 집계는 day-level 합산 후 USD 환산.
- **시점 차이**: 관리 집계는 지연 발생 가능 (시작/종료 윈도가 ±수 분 어긋남).

Truth source는 **관리 집계 (#2)** 를 채택. 차이가 발생하면 #1과 #2 모두 보고하고 #2 기준으로 분석한다.

---

## 5. 결과 (실측 후 작성)

> 본 섹션은 60회 실행 완료 후 데이터로 채운다. 현재는 placeholder.

### 5.1 변이형 비교표

| 변이 | 평균 품질 점수 | 평균 비용 (USD) | 평균 속도 (ms) | 비고 |
|---|---|---|---|---|
| A-fast | TBD | TBD | TBD | 기준선 |
| B-deep | TBD | TBD | TBD | 천장 |
| C-roles | TBD | TBD | TBD | 권장안 |

### 5.2 품질 지표 (task 별)

| Task | A-fast | B-deep | C-roles |
|---|---|---|---|
| 01-spec-compliance | TBD | TBD | TBD |
| 02-code-quality | TBD | TBD | TBD |
| 03-hypothesis-test | TBD | TBD | TBD |
| 04-real-loop | TBD | TBD | TBD |

### 5.3 비용 지표 (모델 단가 효율)

품질-비용 Pareto frontier — variant 점수 / 변이 비용으로 산정.

### 5.4 속도 지표

평균·중앙값·p95. parallel-hypothesis-tester는 병렬 N개 dispatch라 wall-clock = max(N).

---

## 6. 권장 보정 (실측 후 작성)

> 실측 결과가 §1의 초기 권장과 다르면 본 섹션에 갱신 내용을 기록한다. `agent-prompts.md`의 `**권장 모델:**` 라인도 동시 보정.

### 6.1 갱신 이력

| 일자 | 양식 | 기존 권장 | 신규 권장 | 근거 (지표) |
|---|---|---|---|---|
| 2026-05-13 | (초기) | — | sonnet / opus / sonnet | prior knowledge |
| TBD | (실측) | TBD | TBD | TBD |

### 6.2 측정 결과가 prior knowledge와 다른 경우 처리

§1 초기 권장과 §5 실측 결과가 어긋나면:
1. 본 보고서 §6.1에 두 권장과 근거 지표 모두 기록.
2. `agent-prompts.md`의 `**권장 모델:**` 라인을 실측 기준으로 갱신.
3. 변경 이유를 `agent-prompts.md` 안에 한 줄 주석으로 표시 (이번 보고서 링크 포함).

---

## 7. 한계·후속 작업

- **N=5는 통계적으로 충분치 않음**. 분산 큰 셀은 N=10 이상 권장 (SPEC 위험 항목).
- **4 task의 대표성 한계**. 실 운영 흐름의 빈도·중요도로 가중치 부여 검토.
- **모델 특성은 시간에 따라 변함**. 본 측정은 2026-05-13 기준 스냅숏. 모델 업데이트 시 재측정 필요.
- **60회 실행 비용·시간**: 본 보고서는 인프라 + 초기 권장까지로 한정. 실제 실행은 별 세션 작업 (DONE_WITH_CONCERNS — `.loop/HANDOFF.md`).
- **관리 집계 접근**: Anthropic admin API 자격증명이 별 단계로 필요. raw/admin-aggregate.json 은 그 단계에서 채움.
- **품질 채점의 주관성**: rubric 5 항목 binary 채점은 LLM-judge로도 가능하나, 4·5번 같이 정성 항목은 인간 spot-check 권장.

---

## 8. 참고

- `plugins/autopilot/skills/loop/references/agent-prompts.md` — 3종 양식의 권장 모델 라인·호출 예시
- `tests/autopilot/benchmark-subagent-models/README.md` — 인프라 사용법
- 헌법 §11.6 (이터 내 서브 도구 위임) — 위임 권장·금지 분류
- SPEC: `milestones/regular/loops/71/.worktree/.loop/SPEC.md`
