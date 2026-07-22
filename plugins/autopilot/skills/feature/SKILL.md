---
name: feature
description: 새 기능·변경·지침 의도를 명확화 인터뷰로 탐색해 자기완결적 태스크 본문(frontmatter-first 스펙)을 작성하려 할 때 사용 — 인터뷰로 본문을 떠서 등록 프리미티브 create-task에 넘겨 태스크 백엔드에 등록한다. 본문이 곧 SPEC이며 별도 SPEC 파일은 만들지 않는다. 작성만 책임지고 등록·상태 전이는 create-task가 소유한다. 신규 작성은 현재 런타임의 스킬 호출 기능으로 feature 호출(인자: "<자연어 기능 설명>"), 미완성 in_design 태스크를 인터뷰로 이어 완성하는 재개는 현재 런타임의 스킬 호출 기능으로 feature 호출(인자: "resume <task-id>").
allowed-tools:
  - AskUserQuestion
  - Read
  - Bash(git rev-parse:*)
  - Bash(git log:*)
  - Bash(ls:*)
  - Bash(cat:*)
  - Bash(bash * adapter.sh:link_dependency)
  - Bash(bash * adapter.sh:get_body)
---

# feature

경로 표기: 본문·bash 블록의 `<플러그인 루트>` = 이 스킬 베이스 디렉터리의 두 단계 상위(`../..`) — 실행 시 그 경로로 치환한다.

기능 의도(새 기능·동작 변경·지침 작성·새로 만들기)를 **명확화 인터뷰**로 탐색해 자기완결적 **태스크
본문**으로 뜨는 **작성자(authoring) 스킬**이다. 작성이 끝나면 본문을 **등록 프리미티브 `create-task`** 에
넘겨 백엔드에 등록한다. 태스크 본문이 곧 설계(SPEC)의 단일 출처이며 별도 SPEC 파일을 만들지 않는다.

작성과 등록을 분리해 작성·인터뷰 방법론을 한 곳(이 스킬의 `references/`)에 모은다 — 작성만·플러그인
자기완결 경계의 완결 서술은 「규칙」이 소유한다.

## 워크플로

호출 시 단계를 현재 런타임의 할 일(단계) 추적 기능으로 등록한다. 모든 결정·승인은 현재 런타임의 구조화된 사용자 질문 기능으로 받는다(자유 텍스트 질문 종결구 금지).

1. **컨텍스트 탐색** — `git log --oneline -5`, `ls -A`, 얕은 구조 파악으로 컨벤션만 요약한다(코드 우선 — 기존
   코드에서 답이 보이면 묻기 전에 먼저 확인). 백엔드 준비·등록은 하지 않는다(그것은 `create-task`의 몫).
2. **범위 분해 게이트** — `references/decomposition-gate.md`로 다중 독립 서브시스템 여부 판정. 다중이면 N개
   본문을 작성하고, 아니면 1개. (분해는 발행 개수만 정한다.)
3. **명확화 인터뷰** — `references/clarification.md`의 깔때기형 단일 흐름으로 의도·제약·완료 조건을 짚는다.
   내부 커버리지 체크리스트(목적·성공기준·제약·위험)로 충분성만 점검한다.
4. **접근법 비교** — 비자명한 결정이 있으면 2-3안·trade-off·추천을 제시(자명하면 생략).
5. **태스크 본문 작성** — 공용 `<플러그인 루트>/lib/references/task-body-template.md` frontmatter-first
   구조(scope frontmatter + 무엇을 만들 것인가/목적/완료 조건(EARS)/범위/검증/제약/위험)로 본문을 작성한다.
   `scope.include` 는 step 1 에서 식별한 변경 대상으로 채운다(불명확하면 보수적으로 넓게). 완료 조건은 공용
   `<플러그인 루트>/lib/references/ears-patterns.md` 5문장 패턴으로. 본문이 SPEC이다. 미해결 항목은
   `[NEEDS CLARIFICATION: <질문>]` 마커로 남긴다.
6. **자체 검토** — 공용 `<플러그인 루트>/lib/references/self-review.md` 점검 축(placeholder·모순·범위·모호성·
   검증 가능성·scope.include)을 점검·수정. 규모 임계 시 적대 렌즈 가산의 정의 단일 출처는 공용
   `<플러그인 루트>/lib/references/personas.md`.
7. **등록 위임** — 완성 본문 전체를 한 번 제시해 현재 런타임의 구조화된 사용자 질문 기능으로 단일 승인을
   받은 뒤, **`create-task`를 호출해 등록**한다:
   ```
   현재 런타임의 스킬 호출 기능으로 create-task 호출(인자: "<제목>\n\n<본문>")
   ```
   분해 발행(N개)이면 의존 순서대로 각 본문을 `create-task`로 등록하고(각 호출의 보고에서 `task_id`를 받는다),
   `slug→task_id` 룩업으로 **이 스킬이 직접 `link_dependency`를 호출해 선후 의존을 연결**한다 — 등록 전용
   `create-task`의 `args="<제목>\n\n<본문>"`엔 의존을 전달할 수단이 없기 때문이다:
   ```bash
   ADAPTER="<플러그인 루트>/lib/task-backend/adapter.sh"
   bash "$ADAPTER" link_dependency --task-id "<후행 task_id>" --depends-on-id "<선행 task_id>"
   ```

   등록 결과(task_id·url·최종 상태)와 다음 단계(`execute-task start <id>` 또는 `workflow-task start`) 안내는
   `create-task`가 책임진다. 이 스킬은 본문을 넘기는 데서 끝난다.

## 재개(resume) 모드 — in_design 태스크 이어 완성

`args="resume <task-id>"`로 호출되면 **신규 작성이 아니라 이미 등록된 `in_design`(미해결 항목이 남은) 태스크의
본문을 인터뷰로 이어 완성**한다. 자율 분석이 아닌 **대화형 인터뷰 재개**다(자율 생성은 별도 경로). 이때 위
워크플로 1·2(컨텍스트 탐색·범위 분해)는 건너뛰고 다음으로 대체한다:

1. **기존 본문 로드** — 읽기 전용 동사로 현재 본문과 남은 `[NEEDS CLARIFICATION]` 마커를 불러온다(작성만 —
   write 동사가 아니므로 경계를 깨지 않는다):
   ```bash
   ADAPTER="<플러그인 루트>/lib/task-backend/adapter.sh"
   bash "$ADAPTER" get_body --task-id "<task-id>"
   ```
2. **부족분 인터뷰** — `references/clarification.md` 깔때기 흐름으로, 본문의 `[NEEDS CLARIFICATION: <질문>]`
   마커가 가리키는 **남은 항목만** 채운다(이미 잡힌 부분은 다시 묻지 않는다). 채워지면 해당 마커를 제거한다.
3. **자체 검토** — 공용 `<플러그인 루트>/lib/references/self-review.md` 점검 축으로 갱신 본문을 점검한다.
4. **재개 위임** — 완성 본문 전체를 한 번 제시해 현재 런타임의 구조화된 사용자 질문 기능으로 단일 승인을
   받은 뒤, **기존 태스크의 본문 갱신·상태 전이를 `create-task` 재개 경로로 위임**한다(신규 등록이 아니다):
   ```
   현재 런타임의 스킬 호출 기능으로 create-task 호출(인자: "resume <task-id>\n\n<갱신 본문>")
   ```
   `create-task`가 `set_body`로 본문을 교체하고, 마커가 0이면 `in_design → backlog`로 전이하며(남아 있으면
   `in_design` 유지) 결과를 안내한다. 인터뷰로도 다 못 채워 마커가 남으면 본문에 마커를 남긴 채 넘긴다.

## 규칙

- 대화형 작성자다(무인 폴러는 호출하지 않는다). 의존성은 `depends_on`으로만 표현한다.
- **작성만** 한다 — 어댑터의 **write 동사**(`create_task`/`set_body`/`set_status`)를 직접 호출하지 않고, 파일을
  만들지 않는다(본문=SPEC, 백엔드가 SoT). 등록·전이는 `create-task`에 위임한다. 재개 모드의 `get_body`는
  **읽기 전용**(컨텍스트 로드)이라 이 경계를 깨지 않는다.
- 다른 스킬·`rules/`를 doc-link하지 않는다(플러그인 자기완결). 외부 스킬의 참조를 사용하지 않는다.
- `[NEEDS CLARIFICATION` 마커가 남아 있으면 무인 실행이 차단됨을 안내한다(잔존 시 등록 후 `create-task`가
  `in_design`으로 둔다).

## references

| 파일 | 역할 |
|---|---|
| `references/clarification.md` | 명확화 인터뷰 방법론(깔때기형 흐름·내부 커버리지·추천 답) |
| `references/decomposition-gate.md` | 다중 서브시스템 감지·발행 규칙 |
| `<플러그인 루트>/lib/references/task-body-template.md` | 태스크 본문(=SPEC) 구조 — 작성자 공용 단일 출처 |
| `<플러그인 루트>/lib/references/ears-patterns.md` | 완료 조건 5문장 패턴·언어 모드 — 작성자 공용 단일 출처 |
| `<플러그인 루트>/lib/references/self-review.md` | 자체 검토 축(+scope.include) — 작성자 공용 단일 출처 |
