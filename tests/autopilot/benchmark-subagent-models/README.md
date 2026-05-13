# Subagent 모델 벤치마크

`plugins/autopilot/skills/loop/references/agent-prompts.md`의 3종 서브에이전트 양식에 대해 모델 선택(opus/sonnet/haiku)이 품질·비용·속도에 미치는 영향을 측정한다.

자율 루프 worker 이터 안에서 `Agent` 도구로 호출되는 dispatch를 대상으로 한다.

## 디렉토리 레이아웃

```
tests/autopilot/benchmark-subagent-models/
  README.md                   # 본 파일 — 사용법·디렉토리 규약
  runner.sh                   # 4 task × 3 variant × N회 dispatch 실행기
  collect-costs.sh            # raw/ 결과에서 비용·token·latency 집계 + 두 소스 cross-check
  tasks/
    01-spec-compliance.task.md     # 합성 task #1: spec-compliance-reviewer 시나리오
    02-code-quality.task.md        # 합성 task #2: code-quality-reviewer 시나리오
    03-hypothesis-test.task.md     # 합성 task #3: parallel-hypothesis-tester 시나리오
    04-real-loop.task.md           # 실 운영 task: 완료된 milestones/regular/loops/<n> 참조
  variants/
    A-fast.json     # 전원 "빠른 모델" (haiku)
    B-deep.json     # 전원 "깊은 모델" (opus)
    C-roles.json    # 역할별 분리 (agent-prompts.md 권장 라인 그대로)
  raw/
    <variant>/<task>/<run-N>/    # 각 실행의 입력·출력·session.jsonl·timing
      input.txt
      output.txt
      timing.json     # {started_at, ended_at, duration_ms, exit_code}
      usage.json      # {model, total_cost_usd, input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens, session_id}
      session.jsonl   # CC 세션 기록 원본 (cross-check 소스 #1)
    admin-aggregate.json  # Anthropic admin API 집계 (cross-check 소스 #2)
```

## 변이형 (variants/)

세 가지 고정 변이형으로 동일 task를 N회 실행해 변량 제어.

| 변이 | spec-compliance-reviewer | code-quality-reviewer | parallel-hypothesis-tester |
|---|---|---|---|
| A-fast | haiku | haiku | haiku |
| B-deep | opus | opus | opus |
| C-roles | sonnet (권장) | opus (권장) | sonnet (권장) |

## 실행

> **권한 모델**: runner.sh는 `claude --print --dangerously-skip-permissions ...`로
> 호출한다. tasks 03·04가 Bash·Read 도구를 필요로 하며, 헤드리스 실행에서 권한 프롬프트가
> 뜨면 runner가 무한 대기하기 때문. 본 벤치마크는 사전 정의 task만 사용하고 운영자가
> 명시적으로 invoke하므로 적합. 외부 입력을 받는 환경에서는 사용하지 말 것.

```
# 기본 N=5
bash tests/autopilot/benchmark-subagent-models/runner.sh

# 분산 큰 변이형은 N=10
N=10 VARIANT=A-fast bash tests/autopilot/benchmark-subagent-models/runner.sh
```

실행 종료 후:

```
bash tests/autopilot/benchmark-subagent-models/collect-costs.sh > raw/summary.tsv
```

## 두 소스 cross-check

비용·token 카운트는 두 독립 소스에서 수집한다:

1. **세션 기록**: `claude --print --output-format json --model ...` 의 결과 jsonl. `usage.json`은 result jsonl의 `usage`·`total_cost_usd`·`session_id` 필드를 추출 (session_id는 CC가 자동 부여).
2. **관리 집계**: Anthropic admin API의 organization-level usage 집계. 측정 윈도(시작~끝 ISO timestamp)로 필터링.

두 소스의 input/output token 합계, 추정 비용을 보고서에 나란히 표시한다. 차이가 있으면 그 원인(캐싱·서비스 티어·rounding)을 명시하고 truth source를 지정한다.

## 비고

- 권장 모델 라인은 `agent-prompts.md` 안에서 `**권장 모델:**` 프리픽스로 grep 가능.
- 본 벤치마크의 실제 60회 실행은 admin API 접근·예산 산정이 필요해 별 세션 작업으로 분리한다.
- raw/ 안의 디렉토리 규약은 위 레이아웃을 따른다 — 빈 디렉토리는 `.gitkeep`로 유지.
- 실측 결과가 초기 권장과 다르면 `agent-prompts.md`의 권장 라인을 갱신하고 변경 근거를 보고서에 기록한다 (SPEC AC #6).

## 측정 지표

각 (variant, task, run) 셀에서 다음을 측정:

- **품질**: task별 기준 산출물(`tasks/*.task.md` 안의 "기대 응답 체크리스트")에 대한 binary pass/fail 합산 + LLM-judge 점수 (0~5)
- **비용**: usage.json의 `total_cost_usd` (CC 세션 기록) + admin-aggregate.json 항목 (관리 집계)
- **속도**: timing.json의 `duration_ms`

집계는 평균·중앙값·표준편차를 모두 산출한다 (분산 큰 변이 식별용).
