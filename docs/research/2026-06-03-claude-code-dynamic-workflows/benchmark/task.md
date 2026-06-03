# 벤치마크 Task 정의

## Task

8개의 `SKILL.md` 파일 각각에서 다음 구조를 추출한다 (structured output, schema 강제):

```json
{ "skillName": "<frontmatter name>", "subcommands": ["..."], "purpose": "<한 줄 요약>" }
```

- `skillName`: frontmatter의 `name` 값 그대로.
- `subcommands`: description 안에 `(a/b/c)` 형태로 명시된 호출 서브커맨드 목록. 없으면 `[]`.
- `purpose`: 스킬이 하는 일의 한 줄 요약(자유 텍스트, 채점 제외 — 정성).

각 아이템은 독립적이라 병렬화 가능하고, 비용이 대략 균일하다(파일 크기 차이로 약간의 편차 존재).

## 고정 입력 (8개 SKILL.md, repo-root 상대 경로)

1. `plugins/autopilot/skills/dispatch/SKILL.md`
2. `plugins/autopilot/skills/fsd/SKILL.md`
3. `plugins/autopilot/skills/loop/SKILL.md`
4. `plugins/autopilot/skills/spec/SKILL.md`
5. `plugins/autopilot/skills/using-autopilot/SKILL.md`
6. `plugins/project-init/skills/bootstrap/SKILL.md`
7. `plugins/project-init/skills/context-rule-creator/SKILL.md`
8. `plugins/project-init/skills/engineering-rule-creator/SKILL.md`

## Ground Truth (채점 기준)

`skillName`과 `subcommands`를 정답과 정확히 대조한다. `subcommands`는 순서 무관 집합 일치.

| # | skillName | subcommands (정답) |
|---|---|---|
| 1 | `dispatch` | `start, list, status, stop, watch` |
| 2 | `fsd` | `intake, start, review, merge, poll, status, list, stop` |
| 3 | `loop` | `start, status, stop, list, cleanup, logs` |
| 4 | `spec` | _(없음)_ `[]` |
| 5 | `using-autopilot` | _(없음)_ `[]` |
| 6 | `bootstrap` | _(없음)_ `[]` |
| 7 | `context-rule-creator` | _(없음)_ `[]` |
| 8 | `engineering-rule-creator` | _(없음)_ `[]` |

**성공 판정 (per item):** `skillName` 일치 **AND** `subcommands` 집합 일치. `purpose`는 채점하지 않음.

근거: subcommand는 description 끝의 `'Skill(skill="X", args="<subcommand> [<args>]")' (a/b/c)` 패턴에서 추출된다. spec은 자연어 args + `--resume` 플래그만 받고 서브커맨드 체계가 없으므로 `[]`. project-init 3종과 using-autopilot은 자동 활성 스킬로 서브커맨드가 없다.
