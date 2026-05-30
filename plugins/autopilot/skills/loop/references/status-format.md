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
