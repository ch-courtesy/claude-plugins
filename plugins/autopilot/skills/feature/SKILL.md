---
name: feature
description: 새 기능·변경·지침 의도를 명확화 인터뷰로 탐색해 자기완결적 태스크 본문(목표·배경·제안·검증 계획·완료 기준)을 작성하려 할 때 사용 — 인터뷰로 본문을 떠서 등록 프리미티브 create-task에 넘겨 태스크 백엔드에 등록한다. 본문이 곧 SPEC이며 별도 SPEC 파일은 만들지 않는다. 작성만 책임지고 등록·상태 전이는 create-task가 소유한다. 호출 'Skill(skill="feature", args="<자연어 기능 설명>")'.
allowed-tools:
  - AskUserQuestion
  - Read
  - Bash(git rev-parse:*)
  - Bash(git log:*)
  - Bash(ls:*)
  - Bash(cat:*)
  - Bash(bash * adapter.sh:link_dependency)
---

# feature

기능 의도(새 기능·동작 변경·지침 작성·새로 만들기)를 **명확화 인터뷰**로 탐색해 자기완결적 **태스크
본문**으로 뜨는 **작성자(authoring) 스킬**이다. 작성이 끝나면 본문을 **등록 프리미티브 `create-task`** 에
넘겨 백엔드에 등록한다. 태스크 본문이 곧 설계(SPEC)의 단일 출처이며 별도 SPEC 파일을 만들지 않는다.

이 스킬은 **작성만** 책임진다 — 등록, 백엔드 준비, 등록-후 상태 전이는 `create-task`가 소유한다. 작성과
등록을 분리해, 작성 방법론을 한 곳(이 스킬의 `references/`)에 모은다.

이 스킬은 플러그인 자기완결이다 — 컨슈밍 프로젝트의 `rules/` 지침이나 다른 스킬의 풍부 참조(spec 스킬 등)에
의존하지 않는다. 인터뷰 방법론은 이 스킬의 `references/`가 소유한다.

## 워크플로

호출 시 단계를 TodoWrite로 등록한다. 모든 결정·승인은 `AskUserQuestion`으로 받는다(자유 텍스트 질문 종결구 금지).

1. **컨텍스트 탐색** — `git log --oneline -5`, `ls -A`, 얕은 구조 파악으로 컨벤션만 요약한다(코드 우선 — 기존
   코드에서 답이 보이면 묻기 전에 먼저 확인). 백엔드 준비·등록은 하지 않는다(그것은 `create-task`의 몫).
2. **범위 분해 게이트** — `references/decomposition-gate.md`로 다중 독립 서브시스템 여부 판정. 다중이면 N개
   본문을 작성하고, 아니면 1개. (분해는 발행 개수만 정한다.)
3. **명확화 인터뷰** — `references/clarification.md`의 깔때기형 단일 흐름으로 의도·제약·완료 조건을 짚는다.
   내부 커버리지 체크리스트(목적·성공기준·제약·위험)로 충분성만 점검한다.
4. **접근법 비교** — 비자명한 결정이 있으면 2-3안·trade-off·추천을 제시(자명하면 생략).
5. **태스크 본문 작성** — `references/task-body-template.md` 구조(목표/배경/제안/검증 계획/완료 기준)로 본문을
   작성한다. 본문이 SPEC이다. 미해결 항목은 `[NEEDS CLARIFICATION: <질문>]` 마커로 남긴다.
6. **자체 검토** — `references/self-review.md` 5축(placeholder·모순·범위·모호성·검증 가능성)을 점검·수정.
7. **등록 위임** — 완성 본문 전체를 한 번 제시해 `AskUserQuestion`으로 단일 승인을 받은 뒤, **`create-task`를
   호출해 등록**한다:
   ```
   Skill(skill="create-task", args="<제목>\n\n<본문>")
   ```
   분해 발행(N개)이면 의존 순서대로 각 본문을 `create-task`로 등록하고(각 호출의 보고에서 `task_id`를 받는다),
   `slug→task_id` 룩업으로 **이 스킬이 직접 `link_dependency`를 호출해 선후 의존을 연결**한다 — 등록 전용
   `create-task`의 `args="<제목>\n\n<본문>"`엔 의존을 전달할 수단이 없기 때문이다:
   ```bash
   ADAPTER="$(git rev-parse --show-toplevel)/plugins/autopilot/task-backend/adapter.sh"
   bash "$ADAPTER" link_dependency --task-id "<후행 task_id>" --depends-on-id "<선행 task_id>"
   ```

   등록 결과(task_id·url·최종 상태)와 다음 단계(`execute-task start <id>` 또는 `workflow-task start`) 안내는
   `create-task`가 책임진다. 이 스킬은 본문을 넘기는 데서 끝난다.

## 규칙

- 대화형 작성자다(무인 폴러는 호출하지 않는다). 의존성은 `depends_on`으로만 표현한다.
- **작성만** 한다 — 어댑터(`create_task`/`set_body`/`set_status`)를 직접 호출하지 않고, 파일을 만들지 않는다
  (본문=SPEC, 백엔드가 SoT). 등록·전이는 `create-task`에 위임한다.
- 다른 스킬·`rules/`를 doc-link하지 않는다(플러그인 자기완결). spec 스킬의 참조를 사용하지 않는다.
- `[NEEDS CLARIFICATION` 마커가 남아 있으면 무인 실행이 차단됨을 안내한다(잔존 시 등록 후 `create-task`가
  `in_design`으로 둔다).

## references

| 파일 | 역할 |
|---|---|
| `clarification.md` | 명확화 인터뷰 방법론(깔때기형 흐름·내부 커버리지·추천 답) |
| `task-body-template.md` | 태스크 본문(=SPEC) 구조 |
| `decomposition-gate.md` | 다중 서브시스템 감지·발행 규칙 |
| `self-review.md` | 자체 검토 5축 |
