# Issue body 동기화 지침

SPEC 문서를 단일 출처로 두고 그 전문을 외부 task의 Issue body로 동기화하는 절차입니다. spec 스킬은 더 이상 이 동기화를 하지 않으므로(SPEC 문서만 산출), 이 책임은 **SPEC 문서를 task에 반영하는 구현 스킬·오케스트레이터(loop/dispatch)**가 집니다.

구체 백엔드(GitHub Issue/Project, CLI)는 `rules/context.md`가 단일 출처입니다.

## trigger

SPEC 문서 최초 작성, 자체 검토 재작성, 변경 재진입, `--resume` 재작성마다 단일 trigger로 task의 body를 sync합니다. body 머리말 placeholder는 `rules/orchestration/task-state-alignment.md`의 새 task body 표준과 일치해야 하며, 불일치 시 abort합니다.

## body 구조

```text
<task body 머리말 line 1>
<task body 머리말 line 2: SPEC 문서 경로>

<!-- autopilot:spec-sync:begin -->
## SPEC (auto-synced)

<SPEC 문서 전문 그대로>
<!-- autopilot:spec-sync:end -->
```

sync 영역은 `<!-- autopilot:spec-sync:begin -->` / `<!-- autopilot:spec-sync:end -->` fence로만 식별합니다.

- first-sync: placeholder 아래에 fence 블록을 append합니다.
- re-sync: fence 사이(`## SPEC (auto-synced)` + SPEC 전문)만 replace하고, fence 바깥의 사용자 내용은 보존합니다.

## 절차

현재 body 조회 → SPEC 문서 전문 읽기 → tempfile 경유로 body 갱신, 순서로 수행합니다. 백엔드 한도 초과, 비표준 body, 호출 실패는 abort합니다. 역방향 sync(task → SPEC 문서)와 metadata 변경은 범위 밖입니다.
