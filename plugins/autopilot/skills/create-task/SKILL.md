---
name: create-task
description: 외부 작성자(feature·fix)가 만든 자기완결적 태스크 본문(=SPEC)을 받아 선택된 백엔드(filesystem/github-project/beads)에 태스크로 등록하려 할 때 사용하는 등록 프리미티브 — 등록과 등록-후 상태 전이(완성→backlog / 미해결 잔존→in_design)를 소유하고, 본문 갱신은 백엔드 set_body 동사에 위임한다. 인터뷰·정적분석 같은 작성 로직은 갖지 않는다(작성은 feature·fix가 소유). 본문이 곧 SPEC이며 별도 SPEC 파일은 만들지 않는다. 호출 'Skill(skill="create-task", args="<제목>\n\n<태스크 본문>")'.
allowed-tools:
  - AskUserQuestion
  - Read
  - Bash(bash * adapter.sh:*)
  - Bash(bash * persist-backend-config.sh:*)
  - Bash(bash * scope-coverage-check.sh:*)
  - Bash(git rev-parse:*)
  - Bash(git log:*)
  - Bash(ls:*)
  - Bash(git remote:*)
  - Bash(gh:*)
  - Bash(python3:*)
  - Bash(cat:*)
---

# create-task

외부 작성자(`feature` 인터뷰 작성자, `fix` 정적분석 작성자)가 떠 준 자기완결적 **태스크 본문**을 받아 태스크
백엔드에 **등록**하는 **등록 프리미티브**다. 등록과 **등록-후 상태 전이**를 소유하며, 본문 갱신은 백엔드
`set_body` 동사에 위임한다. 태스크 본문이 곧 설계(SPEC)의 단일 출처이며 별도 SPEC 파일을 만들지 않는다.
등록된 태스크는 이후 `execute-task`(단일 실행)나 `workflow-task`(무인 드레인)가 실행한다.

이 스킬은 **등록만** 한다 — 인터뷰·범위 분해·정적분석 같은 **작성 로직을 갖지 않는다**. 그 작성
방법론은 작성자 스킬(`feature`/`fix`)이 소유한다. 본 스킬에 넘어오는 본문은 이미 작성·자체검토가 끝난
완성본으로 간주한다.

이 스킬은 플러그인 자기완결이다 — 컨슈밍 프로젝트의 `rules/` 지침이나 다른 스킬을 참조하지 않는다. 필요한
계약은 플러그인 `task-backend/contract.md`가 소유한다.

## 백엔드 어댑터

```
ADAPTER="$(git rev-parse --show-toplevel)/plugins/autopilot/task-backend/adapter.sh"
bash "$ADAPTER" <verb> [args]
```

동사·상태 집합·태스크 본문 구조의 단일 출처는 `task-backend/contract.md`다. 백엔드 미설정 시
`bash "$ADAPTER" init --backend <filesystem|github-project|beads>`를 안내한다(선택은 `AskUserQuestion`).

### 백엔드 선택 SoT 영속화

`adapter init` 이 만드는 `.autopilot/task-backend.json` 은 백엔드 선택의 단일 출처(SoT)다(`.gitignore`가
추적 대상으로 명시). init 직후 이 SoT를 **메인 브랜치까지 영속화**해 새 체크아웃·CI·다른 세션에서도 동일
백엔드가 설정되게 한다. 전용 헬퍼가 멱등적으로 처리한다(이미 메인에 동일 내용이 추적되면 중복 PR/커밋 없이
건너뜀):

```
bash "$(git rev-parse --show-toplevel)/plugins/autopilot/skills/create-task/persist-backend-config.sh"
```

헬퍼는 config 파일 **단독** 변경만 커밋한다(태스크 본문·다른 변경 미동반). origin 이 있으면 config-only
브랜치 push → PR 생성 → 저장소 auto-merge 경로로 메인 머지까지 진행하고, origin 이 없으면 로컬 메인에 merge
한다. `.autopilot/` 는 워치 디렉토리(=`plugins/`)가 아니므로 이 config PR 엔 plugin.json 범프를 넣지 않는다.
머지 진행 상황은 사용자에게 보고하되, 자율 오케스트레이터 맥락에선 별도 사용자 프롬프트 없이 진행한다.

헬퍼는 한 줄 JSON `{status}`를 반환한다 — `persisted`(메인 머지/auto-merge 예약 확인) 또는 `skip`(이미 추적, 멱등)이면 성공이다. `pending`(gh 미가용 — 브랜치만 push) · `pr_created`(PR 은 생성됐으나 auto-merge 예약 실패)는 **메인 영속화 미완**(exit 3)이므로, 그 사실과 수동 완료가 필요함을 사용자에게 보고한다(메인 영속화가 확인되지 않았는데 완료로 보고하지 않는다).

## 워크플로

호출 시 단계를 TodoWrite로 등록한다. 결정·승인은 `AskUserQuestion`으로 받는다(자유 텍스트 질문 종결구 금지).

1. **입력 수신·경로 분기** — 작성자(`feature`/`fix`)가 넘긴 **완성 태스크 본문**(제목 + frontmatter-first 스펙:
   scope frontmatter·무엇을 만들 것인가·완료 조건(EARS) 등)을 입력으로 받는다. 본문 작성·인터뷰·분해는 하지
   않는다(작성자의 몫). 입력 첫 줄이
   `resume <task-id>`로 시작하고 **그 `<task-id>`가 실제 태스크로 해석되면** **신규 등록이 아니라 기존 태스크
   본문 갱신(재개)** 경로다(아래 「재개(resume) 경로」로 분기). 그 외에는 받은 입력에서 제목과 본문을 분리해
   신규 등록을 진행한다.
   - **재개 신호 검증 (제목 충돌 방지)** — 신규 등록 입력은 `<제목>\n\n<본문>`이라 **제목이 첫 줄**이므로,
     제목이 "resume…"으로 시작하는 신규 작성을 재개로 오인할 수 있다. 첫 줄이 `resume <task-id>` 꼴일 때
     `bash "$ADAPTER" get_task --task-id <task-id>`로 그 id가 **실존 태스크로 해석되는지** 확인한다. 해석
     성공이면 재개, 해석 실패(유효 task-id 형식이 아니거나 없는 id)면 첫 줄을 자연어 제목으로 보고 **신규
     등록으로 처리**한다(전체 입력 = `<제목>\n\n<본문>`).
2. **백엔드 준비** — 백엔드 미설정이면 `adapter init`(선택은 `AskUserQuestion`) 후 위 「백엔드 선택 SoT
   영속화」 헬퍼를 실행해 config를 메인까지 영속화한다(멱등).
3. **scope-coverage 검증** — 등록 전에 scope-coverage 검증을 수행한다. 본문 frontmatter의
   `scope.include`에서 소스 경로를 읽어, 그 소스를 덮는 **기존** 테스트 경로가 scope.include에 함께 있는지
   확인한다. 매핑 관례의 단일 출처는 `references/scope-coverage-map.md`다:
   ```
   CHECKER="$(git rev-parse --show-toplevel)/plugins/autopilot/skills/create-task/scope-coverage-check.sh"
   echo "<본문>" | bash "$CHECKER"
   ```
   누락이 있으면 `SCOPE_COVERAGE_WARNING` 과 누락 경로 목록을 출력한다. **등록을 막지 않는다** — 경고를
   작성자에게 보고하고 다음 단계로 진행한다. 인터랙티브 맥락에서는 `AskUserQuestion`으로 scope.include에
   추가할지 확인할 수 있다. 스크립트는 항상 0 exit이므로 경고 유무와 관계없이 다음 단계로 진행된다.
4. **등록** — 받은 본문을 그대로 등록한다(`create_task`의 초기 상태는 `backlog`다). 작성자가 의존 관계를
   넘겼으면 `--depends-on`으로 함께 전달한다:
   ```
   bash "$ADAPTER" create_task --title "<제목>" --body "<본문>" [--depends-on "<선행id,...>"]   # → task_id
   ```
   여러 본문을 의존 순서대로 받으면 `slug→task_id` 룩업으로 의존을 연결한다:
   ```
   bash "$ADAPTER" link_dependency --task-id "<후행>" --depends-on-id "<선행>"
   ```
5. **등록-후 상태 전이 (소유)** — 등록 직후 본문의 `[NEEDS CLARIFICATION` 마커 유무로 최종 상태를 분기한다.
   이 전이는 이 등록 프리미티브가 소유한다:
   - 마커가 **없으면**(완성 SPEC) 초기 상태 `backlog`를 유지한다 — 전이를 생략하거나 명시적으로
     `bash "$ADAPTER" set_status --task-id <id> --status backlog` 를 호출한다.
   - 마커가 **남아 있으면**(미해결 잔존) `bash "$ADAPTER" set_status --task-id <id> --status in_design` 로
     상태를 전이한다.
6. **본문 갱신은 set_body에 위임** — 등록된 태스크의 본문을 나중에 갱신해야 하면(예: `in_design` 태스크의
   SPEC 보강) 직접 구현하지 않고 백엔드 `set_body` 동사에 위임한다(본문만 교체, status·`depends_on`·메타
   보존):
   ```
   bash "$ADAPTER" set_body --task-id <id> --body "<갱신 본문>"
   ```
   `set_body`의 정의·구현은 백엔드 소관이다(`task-backend/contract.md`). 이 스킬은 그 동사를 **노출·호출**할
   뿐 정의하지 않는다.
7. **안내** — 최종 상태(`backlog`/`in_design`)와 함께 결과(task_id·url)와 다음 단계(`execute-task start <id>`
   또는 `workflow-task start`)를 안내한다.

## 재개(resume) 경로 — 기존 in_design 태스크 본문 갱신

입력이 `resume <task-id>`로 시작하고 그 `<task-id>`가 실존 태스크로 해석되면 신규 `create_task`가 아니라
**이미 등록된 `in_design` 태스크의 본문을 갱신**하고 상태를 재평가한다(작성자 `feature` 재개 모드가 인터뷰로
이어 완성한 본문이 들어온다). 신규 등록의 2단계(백엔드 준비)는 이미 등록된 태스크이므로 생략한다.

0. **재개 대상 검증 (get_task — in_design 가드)** — 본문을 교체하기 **전에** 대상 태스크의 status를 확인한다.
   1단계의 재개 신호 검증에서 이미 호출한 `get_task` 결과(또는 여기서 `bash "$ADAPTER" get_task --task-id
   <task-id>`)의 `status`가 **`in_design`이 아니면**(`done`·`in_progress`·`review`·`backlog`·`blocked`·
   `cancelled`) — 즉 **비-in_design 태스크면** 재개를 **거부**하고 즉시 **중단**한다 — `set_body`·상태
   전이를 하지 않는다. 재개는 "미해결
   항목이 남은 `in_design` 태스크 이어 완성"만을 위한 경로이므로, 종단·진행 중 태스크에 본문 덮어쓰기 +
   `backlog` 회귀를 적용하면 완료·진행 작업을 훼손한다. `in_design`이면 아래로 진행한다.
1. **본문 교체 (set_body)** — 기존 `task-id`의 본문을 받은 갱신 본문으로 교체한다. 직접 구현하지 않고 위 5단계와
   동일하게 백엔드 `set_body` 동사에 위임한다(본문만 교체, status·`depends_on`·메타 보존):
   ```
   bash "$ADAPTER" set_body --task-id <task-id> --body "<갱신 본문>"
   ```
2. **상태 재평가·전이 (소유)** — 갱신 본문의 `[NEEDS CLARIFICATION` 마커 유무로 4단계와 동일한 기준으로 전이한다:
   - 마커가 **없으면**(완성) `bash "$ADAPTER" set_status --task-id <task-id> --status backlog`로 `in_design →
     backlog` 전이한다.
   - 마커가 **남아 있으면** `in_design`을 유지한다(추가 재개를 기다린다).
3. **안내** — 최종 상태(`backlog`/`in_design`)와 결과(task_id·url), 다음 단계를 6단계와 동일하게 안내한다.

## 규칙

- **등록만** 한다 — 작성(인터뷰·분해·정적분석·자체검토)은 작성자(`feature`/`fix`)가 소유한다. 본 스킬은
  완성 본문을 받아 등록·전이만 한다.
- 의존성은 `depends_on`으로만 표현한다. 본문 갱신은 `set_body`에 위임(직접 구현 금지).
- 다른 스킬·`rules/`를 doc-link하지 않는다(플러그인 자기완결). 후속 스킬을 자동 호출하지 않는다 — 등록 후
  안내만 남긴다.
- `[NEEDS CLARIFICATION` 마커가 남아 있으면 무인 실행이 차단됨을 안내한다.
