# status 출력 형식

`status [<spec-path>]` 호출 시 다음 형식으로 출력. 인자가 있으면 해당 스펙 한 줄, 없으면 작업트리를 스캔해 전체 실행을 열거.

```
KEY            STATE     FILES                ITERS  LAST-UPDATE          SPEC
9e02e26a1655   running   -                    12     2026-05-27T14:22Z    docs/specs/2026-05-27-foo/SPEC.md
3f1461d10812   terminal  DONE                 8      2026-05-26T10:15Z    docs/specs/2026-05-26-bar/SPEC.md
a1b2c3d4e5f6   terminal  BLOCKED              5      2026-05-27T11:33Z    /abs/path/other-spec/SPEC.md
b2c3d4e5f6a7   terminal  DONE,NOTES.txt       7      2026-05-27T09:11Z    /abs/path/multi-sig/SPEC.md
```

- `KEY`: 스펙 절대 경로 sha256 앞 12자 (실행 단위 고유 식별자).
- `STATE`: `running`(lock PID 활성) · `stale`(lock 있으나 PID 비활성) · `terminal`(`.loop/signals/` 비어 있지 않음) · `idle`(그 외). driver 는 `signals/` 내 파일 이름·내용을 파싱하지 않는다.
- `FILES`: `.loop/signals/` 안 파일명 ls 그대로(쉼표 구분). 의미 해석은 워커 컨벤션(SoT: `references/constitution.md §작업 매체`).
- `ITERS`: `.loop/iterations/`의 로그 수.
- `LAST-UPDATE`: 최신 이터 로그 mtime (UTC).
- `SPEC`: 스펙 파일 경로.

상태별 색상은 미적용 (text-only).

## `--json` 구조화 출력 (기계 판독)

`status --json [<spec-path>]` 는 위 표 대신 기계 판독 가능한 JSON 을 출력한다. 호출 레이어(예: `execute-task`/`workflow-task`)가 종료 상태를 판정할 때 **컬럼 위치·자유 텍스트 부분 문자열 일치에 의존하지 않도록** 하는 단일 출처다.

- 인자에 `<spec-path>` 가 있으면 JSON object 1줄. 기록이 없으면 `state` 가 `absent`.
- 인자가 없으면 전체 스캔 결과를 JSON array 1줄로(기록 없으면 `[]`).

object 필드:

```json
{"key":"9e02e26a1655","state":"terminal","signals":["DONE"],"iters":8,"last":"2026-05-26T10:15Z","spec":"/abs/path/SPEC.md"}
```

- `key`·`state`·`iters`·`last`·`spec`: 표의 동명 컬럼과 같은 의미. `state` 값 집합도 동일(`running`·`stale`·`terminal`·`idle`, 단일 spec 기록 부재 시 `absent`).
- `signals`: `.loop/signals/` 안 파일명의 **배열**(표의 `FILES` 를 구조화한 것). raw fact 이며 `DONE`/`BLOCKED` 등의 의미 해석은 호출자 컨벤션이다 — driver 는 이름·내용을 파싱하지 않는다(SoT: `references/constitution.md §작업 매체`). 종료 상태를 판정하는 호출자는 이 배열에서 자신의 신호 이름을 **정확 일치 멤버십**으로 찾는다(부분 문자열 일치 아님).
- JSON 은 yq 로 파싱 가능하다(flow-style 은 valid YAML — `yq -r '.state'`).
