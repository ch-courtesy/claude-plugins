# 벤치마크 재현 절차

## 전제

- Claude Code v2.1.154+ (Workflow 도구 / 동적 워크플로우 가용).
- 현재 repo 루트에서 실행(에이전트가 repo-상대 경로 `plugins/.../SKILL.md`를 읽음).
- `/config`에서 Dynamic workflows 활성(Pro 플랜은 명시 활성 필요).

## 측정 방식

각 전략 스크립트는 백그라운드 워크플로로 실행되며, 완료 시 `<task-notification>`이 다음을 격리 측정해 돌려준다:

- `duration_ms` — 워크플로 벽시계 (런타임 측정, **1차 지표**).
- `subagent_tokens` — 입력+출력 합산 총 토큰.
- `agent_count` — 사용된 에이전트 수.
- `<result>` — 스크립트 반환값: `{strategy, tokens(=budget.spent() 출력 토큰 delta), items}`.

> 외부 `date` 브래킷 대신 런타임 `duration_ms`를 쓴다 — 워크플로별로 격리돼 알림 지연·메인루프 활동에 오염되지 않는다. `budget.spent()` delta는 turn 전역 풀 공유라 메인루프 토큰에 오염될 수 있어 **2차 참고용**.

## 절차

1. **순차 실행 필수.** 한 워크플로가 완료된 뒤 다음을 띄운다. 동시 실행은 CPU/API 경합으로 `duration_ms`를 왜곡한다.
2. 전략 5종을 각 2회, 총 10회 실행:
   ```
   Workflow({scriptPath: "strategies/s0-monolith.js"})
   Workflow({scriptPath: "strategies/s1-serial.js"})
   Workflow({scriptPath: "strategies/s2-parallel.js"})
   Workflow({scriptPath: "strategies/s3-pipeline.js"})
   Workflow({scriptPath: "strategies/s4-parallel-2stage.js"})
   ```
   (경로는 이 디렉토리 기준 상대. 실제 호출 시 절대경로 권장.)
3. 각 완료 알림에서 `duration_ms`·`subagent_tokens`·`agent_count`·`<result>`를 뽑아 `results/runs.jsonl`에 한 줄씩 적재.
4. 성공 판정: `<result>.items`의 각 원소 `skillName`·`subcommands`를 [`task.md`](./task.md)의 ground truth와 대조(집합 일치). `purpose`는 채점 제외.
5. `results/summary.md`에 전략별 평균·대조표 작성.

## 주의

- 토큰을 소비하는 실측 작업이다(이 표준 규모 10런 ≈ 누적 총 토큰 1.7M·출력 ~45k 수준).
- 스크립트 내 `Date.now()`/`Math.random()`은 사용 불가(resume 호환). 타이밍은 외부/런타임 측정에 의존.
- 재현 변동: 모델 응답 시간·API 지연으로 `duration_ms`는 런마다 다소 흔들린다(여기 측정 변동 ±5~10%). 방향성(S2<S1, S3<S4) 확인이 목적.
- resume: 스크립트 편집 후 `Workflow({scriptPath, resumeFromRunId})`로 완료 에이전트 캐시 재사용 가능(동일 세션 한정).
