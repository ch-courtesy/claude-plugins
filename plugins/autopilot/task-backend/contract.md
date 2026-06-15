# task-backend 어댑터 계약 (플러그인 자체 단일 출처)

autopilot 태스크 중심 스킬(create-task·execute-task·workflow-task)이 태스크를 백엔드에 등록·조회·전이하기
위해 호출하는 런타임 CRUD 어댑터의 계약이다. **이 문서가 플러그인 자체 단일 출처**다 — 컨슈밍 프로젝트의
`rules/` 지침이나 다른 스킬을 참조하지 않는다. 플러그인은 `rules/`가 없는 프로젝트에서도 동작해야 한다.

## 호출

```
bash <plugin>/task-backend/adapter.sh <verb> [args...]
```

`<plugin>` = `$(git rev-parse --show-toplevel)/plugins/autopilot`. 모든 출력은 한 줄 JSON(또는 JSON array).
실패는 비-0 exit + stderr 메시지.

## 백엔드 선택

어댑터는 컨슈밍 프로젝트 루트의 **`.autopilot/task-backend.json`**(벤더-중립 도구 네임스페이스 dotdir)을 읽어
백엔드를 고른다. `.claude/` 같은 벤더 전용 경로를 쓰지 않으므로 Claude·Codex가 같은 경로를 읽는다.

```json
{
  "backend": "filesystem | github-project | beads",
  "github_project_url": "https://github.com/users/<owner>/projects/<n>",
  "github_owner": "<owner>",
  "github_repo": "<repo>",
  "lease_ttl_seconds": 300,
  "heartbeat_interval_seconds": 60
}
```

- `backend` 필수. 나머지는 백엔드별 선택.
- config 부재 시 어댑터는 `init` 안내 후 비-0 exit(조용한 폴백 없음).
- `lease_ttl_seconds` 기본 300, `heartbeat_interval_seconds` 기본 60(ttl보다 작아야 함).

## 상태 집합 (플러그인 자체 정의)

```
backlog → in_design → in_progress → review → done
보조: blocked(사유 기록 후 진입/복귀), cancelled
```

라이프사이클 이벤트 → 목표 상태 (고정):

| 이벤트 | 목표 상태 |
|---|---|
| 최초 등록 | backlog |
| 본문(설계) 작성 완료 | in_design |
| 구현 시작 | in_progress |
| 구현 완료(리뷰 진입) | review |
| 머지/완료 | done |
| 차단 발견 | blocked |
| 차단 해제 | in_progress |

## 태스크 본문 구조 (= SPEC, 플러그인 자체 정의)

별도 SPEC 파일을 두지 않는다. 태스크 본문이 설계의 단일 출처다. 본문 섹션 순서(고정):

```markdown
## 목표
측정·확인 가능한 결과 상태 1~3문장.

## 배경
문제·상황·리스크.

## 제안
접근·구현 순서·대안과 선택 이유.

## 검증 계획
DoD 확인 방법(테스트·관찰 지표·수동 단계).

## 완료 기준 (Definition of Done)
- [ ] ...
```

`get_body`는 위 본문을 반환하고, `materialize`는 `# <title>` H1을 앞에 붙여 임시 spec 파일로 쓴다.

## 의존성 (depends_on 단일 축)

- 태스크 간 순서 의존은 **`depends_on`**으로만 표현한다. `list_ready` 게이팅은 `depends_on`이 모두 `done`인지로만
  판정한다.
- `parent`는 조직/서브태스크 계층 메타데이터일 뿐 ready 판정에 쓰지 않는다.

## heartbeat lease (in_progress 회수)

- `set_status in_progress` 진입 시 lease를 초기화(`lease_renewed_at`=now, `lease_owner`).
- 실행 중 워커는 `renew_lease`로 주기적으로 `lease_renewed_at`을 갱신한다.
- `list_ready`는 lease가 **stale**(now − lease_renewed_at > `lease_ttl_seconds`)인 in_progress 태스크를 ready로
  반환한다(크래시·행 워커 회수). lease가 신선하면 제외(이중 실행 방지).

## 동사 (9개)

모든 동사는 성공 시 한 줄 JSON을 stdout에 쓴다.

| 동사 | 인자 | 반환 |
|---|---|---|
| `create_task` | `--title <s> --body <s> [--depends-on <id,...>]` | `{"task_id","status":"backlog","url":<s|null>}` |
| `get_task` | `--task-id <id>` | `{"task_id","title","status","depends_on":[...],"url"}` |
| `get_body` | `--task-id <id>` | `{"task_id","title","body"}` |
| `set_status` | `--task-id <id> --status <state> [--reason <s>]` | `{"task_id","status"}` |
| `link_dependency` | `--task-id <id> --depends-on-id <id>` | `{"task_id","depends_on":[...]}` |
| `list_ready` | (없음) | `[{"task_id","title"},...]` (depends_on 충족 + stale-lease in_progress) |
| `append_log` | `--task-id <id> --marker decision|handoff|blocked --text <s>` | `{"task_id","logged":true}` |
| `materialize` | `--task-id <id>` | `{"task_id","spec_path"}` (`.task-work/<id>/SPEC.md`) |
| `renew_lease` | `--task-id <id> [--owner <s>]` | `{"task_id","lease_renewed_at"}` |

관리 동사: `init`(config 생성/갱신), `selftest`(계약 자체 검증), `backend`(현재 백엔드 출력).

## 백엔드별 저장 레이아웃 (플러그인 소유)

- **filesystem**: `.tasks/T-NNN.md` — YAML frontmatter(`id,title,status,depends_on,parent,owner,created,
  lease_renewed_at,lease_owner`) + 본문 섹션. git 커밋 대상. 의존성 없는 참조 구현.
- **github-project**: Issue=태스크(번호=id), Project Status field=status, body=본문(design-sync 영역),
  comments=진행 로그, sub-issue/본문 cross-ref=depends_on. lease는 API 빈발 호출 회피 위해 로컬 미러
  `.autopilot/leases/<id>`(gitignore).
- **beads**: `.beads/*.jsonl`(`bd` CLI). `bd dep`=depends_on, `bd ready`=list_ready 베이스, notes=로그.

미설치 CLI(gh/bd)에 의존하는 백엔드는 미설치 시 hard-abort(조용한 폴백 없음).
