# status 출력 형식

`status [<spec-path>]` 호출 시 다음 형식으로 출력. 인자가 있으면 해당 스펙 한 줄, 없으면 작업트리를 스캔해 전체 실행을 열거.

```
KEY            STATE     ITERS  LAST-UPDATE          SPEC
9e02e26a1655   running   12     2026-05-27T14:22Z    docs/specs/2026-05-27-foo.md
3f1461d10812   done      8      2026-05-26T10:15Z    docs/specs/2026-05-26-bar.md
a1b2c3d4e5f6   blocked   5      2026-05-27T11:33Z    /abs/path/other-spec.md
```

- `KEY`: 스펙 절대 경로 sha256 앞 12자 (실행 단위 고유 식별자).
- `STATE`: `running`(lock PID 활성) · `stale`(lock 있으나 PID 비활성) · `done`(`.loop/DONE` 존재) · `blocked`(`.loop/BLOCKED` 존재) · `idle`(그 외).
- `ITERS`: `.loop/iterations/`의 로그 수.
- `LAST-UPDATE`: 최신 이터 로그 mtime (UTC).
- `SPEC`: 스펙 파일 경로.

상태별 색상은 미적용 (text-only).
