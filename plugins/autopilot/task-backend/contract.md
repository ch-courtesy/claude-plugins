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

별도 SPEC 파일을 두지 않는다. 태스크 본문이 설계의 단일 출처다. 본문은 **frontmatter-first 스펙 문서**다 —
맨 앞 frontmatter(`scope`/선택 `ears_language`) + 본문 섹션(고정 순서). `# 제목` H1·`depends_on`은 본문에 두지
않는다 — 제목·depends_on·status는 백엔드가 단일 저장한다(중복 회피). 섹션 세부는 작성자 스킬(`feature`/`fix`)의
`task-body-template.md`가 소유하며 아래와 일치한다:

```markdown
---
scope:
  include:
    - <변경 대상 glob>
  exclude:
    - rules/**
    - milestones/**
    - AGENTS.md
    - CLAUDE.md
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

## 무엇을 만들 것인가
## 목적 (왜)
## 완료 조건          # 5문장 패턴(EARS); 작성자 스킬의 ears-patterns.md
## 범위               # 포함 / 비-목표·제외
## 검증
## 제약 (있을 때만)
## 위험 (있을 때만)
```

`get_body`는 위 본문(frontmatter 포함)을 반환하고, `set_body`는 위 본문만 교체(status·메타 보존)하며,
`materialize`는 본문 frontmatter 블록 뒤에 `# <title>` 을 주입해(frontmatter-first + 제목, 본문에 제목 중복
없음) 임시 spec 파일로 쓴다. 본문에 frontmatter 가 없는 구형 태스크는 폴백으로 `# <title>` 을 앞에 붙인다.

## 의존성 (depends_on 단일 축)

- 태스크 간 순서 의존은 **`depends_on`**으로만 표현한다. `list_ready` 게이팅은 `depends_on`이 모두 `done`인지로만
  판정한다.
- `parent`는 조직/서브태스크 계층 메타데이터일 뿐 ready 판정에 쓰지 않는다.

## heartbeat lease (in_progress 회수)

- `set_status in_progress` 진입 시 lease를 초기화(`lease_renewed_at`=now, `lease_owner`).
- 실행 중 워커는 `renew_lease`로 주기적으로 `lease_renewed_at`을 갱신한다.
- `list_ready`는 lease가 **stale**(now − lease_renewed_at > `lease_ttl_seconds`)인 in_progress 태스크를 ready로
  반환한다(크래시·행 워커 회수). lease가 신선하면 제외(이중 실행 방지).

## 동사 (11개)

모든 동사는 성공 시 한 줄 JSON을 stdout에 쓴다.

| 동사 | 인자 | 반환 |
|---|---|---|
| `create_task` | `--title <s> --body <s> [--depends-on <id,...>]` | `{"task_id","status":"backlog","url":<s|null>}` |
| `get_task` | `--task-id <id>` | `{"task_id","title","status","depends_on":[...],"url"}` |
| `get_body` | `--task-id <id>` | `{"task_id","title","body"}` |
| `set_body` | `--task-id <id> --body <s>` | `{"task_id"}` (본문만 교체, status·depends_on·meta 보존) |
| `set_status` | `--task-id <id> --status <state> [--reason <s>]` | `{"task_id","status"}` |
| `link_dependency` | `--task-id <id> --depends-on-id <id>` | `{"task_id","depends_on":[...]}` |
| `list_ready` | (없음) | `[{"task_id","title"},...]` (depends_on 충족 + stale-lease in_progress) |
| `append_log` | `--task-id <id> --marker decision|handoff|blocked --text <s>` | `{"task_id","logged":true}` |
| `materialize` | `--task-id <id>` | `{"task_id","spec_path"}` (`.autopilot/runs/<id>/SPEC.md`) |
| `renew_lease` | `--task-id <id> [--owner <s>]` | `{"task_id","lease_renewed_at"}` |
| `claim` | `--task-id <id> --owner <s>` | `{"task_id","claimed":true|false}` (stale 판정의 단일 진입점 — stale lease 탈취 + 신규 점유 원자적 게이트) |

관리 동사: `init`(config 생성/갱신), `selftest`(계약 자체 검증), `backend`(현재 백엔드 출력).

### claim (stale 판정 + 실행권 획득의 단일 진입점)

`claim` 은 **stale 판정의 단일 진입점**이다 — lease가 **stale**(크래시·행 워커)이면 자동으로 탈취해 실행권을
획득하고, 신선한 점유가 없으면 신규로 원자적 점유한다. `list_ready` 조회와 in_progress 전이 사이의 경쟁도
차단하므로, 실행자는 구현 시작 **전에 반드시 `claim` 을 호출**한다(단순 `set_status in_progress` 금지). 성공
시 `claimed:true`(+ status를 in_progress로 전이, lease 초기화), 이미 신선한 lease로 점유 중이면
`claimed:false`(실행자는 조용히 skip).

- **filesystem**: `.autopilot/runs/.claims/<id>` 디렉토리 `mkdir`(원자적 CAS)로 게이트. 종단 상태(done/blocked/
  cancelled) 전이 시 자동 해제. `.claims` 는 `.autopilot/runs/` 아래 유일한 **비-태스크-id 항목**이다 —
  `runs/` 를 태스크 id 로 순회하는 코드는 `.claims` 를 제외해야 한다.
- **github-project/beads**: 공유 store 전반의 진정한 원자성은 원격 CAS가 필요하며 v1은 **단일 호스트 범위**의
  best-effort(현재 상태+lease 확인 후 전이). github의 stale 회수는 **로컬 lease 미러가 존재하고 stale일 때만**
  수행한다(미러 부재 시 회수하지 않음 — 타 체크아웃의 실행 중 태스크 오회수 방지).

## 백엔드별 저장 레이아웃 (플러그인 소유)

- **filesystem**: `.tasks/T-NNN.md` — YAML frontmatter(`id,title,status,depends_on,parent,owner,created,
  lease_renewed_at,lease_owner`) + 본문 섹션. git 커밋 대상. 의존성 없는 참조 구현.
- **github-project**: Issue=태스크(번호=id), 라벨 `status:<state>`=status, body=본문(SPEC), comments=진행 로그,
  본문 마커 `<!-- autopilot:depends_on: ... -->`=depends_on. **lease는 이슈당 전용 코멘트**
  `<!-- autopilot:lease at=<epoch> owner=<o> -->`를 in-place PATCH(모든 체크아웃/호스트 공유). 본문과 독립이라
  heartbeat가 본문(SPEC·depends_on)을 read-modify-write하지 않는다 → 동시 본문 수정 clobber 없음. github은
  `heartbeat_interval_seconds`를 넉넉히 둘 것.
- **beads**: `.beads/*.jsonl`(`bd` CLI). `bd dep`=depends_on, `bd ready`=list_ready 베이스, notes=로그.

미설치 CLI(gh/bd)에 의존하는 백엔드는 미설치 시 hard-abort(조용한 폴백 없음).
