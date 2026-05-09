# status 출력 형식

`status [<task-id>]` 호출 시 다음 형식으로 출력.

## 단일 task

```
TASK-ID: <task-id>
STATE: <prepared|running|idle|escalated|done|archived>
WORKTREE: <path or N/A>
LOCK PID: <pid or none>
ITERATIONS: <count>
LAST UPDATE: <ISO timestamp>
NOTES: <한 줄 상태 요약>
```

## 전체 (인자 없음)

```
TASK-ID                STATE       ITERS  LAST-UPDATE
my-task                running     12     2026-05-09T14:22Z
another-task           prepared    -      -
done-task              archived    8      2026-05-08T10:15Z
escalated-task         escalated   5      2026-05-09T11:33Z (config-gap)
```

상태별 색상은 미적용 (text-only). ESCALATION 카테고리는 괄호 표시.
