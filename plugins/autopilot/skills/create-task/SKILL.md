---
name: create-task
description: 새 작업(기능·변경·지침)을 태스크 백엔드에 등록하려 할 때 사용 — 명확화 인터뷰로 의도를 탐색해 태스크 본문(목표·배경·제안·검증 계획·완료 기준)을 작성하고, 선택된 백엔드(filesystem/github-project/beads)에 태스크로 등록한다. 본문이 곧 SPEC이며 별도 SPEC 파일은 만들지 않는다. 호출 'Skill(skill="create-task", args="<자연어 task 설명>")'.
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Bash(bash * adapter.sh:*)
  - Bash(bash * persist-backend-config.sh:*)
  - Bash(git rev-parse:*)
  - Bash(git log:*)
  - Bash(ls:*)
  - Bash(git remote:*)
  - Bash(gh:*)
  - Bash(python3:*)
  - Bash(cat:*)
---

# create-task

자연어 의도를 **명확화 인터뷰**로 탐색해 자기완결적 **태스크 본문**으로 떠서 태스크 백엔드에 **등록**하는
진입점이다. 태스크 본문이 곧 설계(SPEC)의 단일 출처이며 별도 SPEC 파일을 만들지 않는다. 등록된 태스크는
이후 `execute-task`(단일 실행)나 `workflow-task`(무인 드레인)가 실행한다.

이 스킬은 플러그인 자기완결이다 — 컨슈밍 프로젝트의 `rules/` 지침이나 다른 스킬을 참조하지 않는다. 필요한
방법론·계약은 이 스킬의 `references/`와 플러그인 `task-backend/contract.md`가 소유한다.

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

## 워크플로

호출 시 단계를 TodoWrite로 등록한다. 모든 결정·승인은 `AskUserQuestion`으로 받는다(자유 텍스트 질문 종결구 금지).

1. **컨텍스트 탐색 · 백엔드 준비** — `git log --oneline -5`, `ls -A`, 얕은 구조 파악으로 컨벤션만 요약한다.
   백엔드 미설정이면 `adapter init`(선택은 `AskUserQuestion`) 후 위 「백엔드 선택 SoT 영속화」 헬퍼를 실행해
   config를 메인까지 영속화한다(멱등).
2. **범위 분해 게이트** — `references/decomposition-gate.md`로 다중 독립 서브시스템 여부 판정. 다중이면 N개
   태스크를 발행하고, 아니면 1개.
3. **명확화 인터뷰** — `references/clarification.md`의 깔때기형 단일 흐름으로 의도·제약·완료 조건을 짚는다.
   내부 커버리지 체크리스트(목적·성공기준·제약·위험)로 충분성만 점검한다.
4. **접근법 비교** — 비자명한 결정이 있으면 2-3안·trade-off·추천을 제시(자명하면 생략).
5. **태스크 본문 작성** — `references/task-body-template.md` 구조(목표/배경/제안/검증 계획/완료 기준)로 본문을
   작성한다. 본문이 SPEC이다. 미해결 항목은 `[NEEDS CLARIFICATION: <질문>]` 마커로 남긴다.
6. **자체 검토** — `references/self-review.md` 5축(placeholder·모순·범위·모호성·검증 가능성)을 점검·수정.
7. **등록** — 완성 본문 전체를 한 번 제시해 `AskUserQuestion`으로 단일 승인을 받고 등록한다:
   ```
   bash "$ADAPTER" create_task --title "<제목>" --body "<본문>"     # → task_id
   ```
   분해 발행(N개)이면 의존 순서대로 등록하며 `slug→task_id` 룩업으로 의존을 연결한다:
   ```
   bash "$ADAPTER" link_dependency --task-id "<후행>" --depends-on-id "<선행>"
   ```
   등록 후 `bash "$ADAPTER" set_status --task-id <id> --status in_design` 로 전이하고, 결과(task_id·url)와
   다음 단계(`execute-task start <id>` 또는 `workflow-task start`)를 안내한다.

## 규칙

- 대화형 진입점이다(무인 폴러는 호출하지 않는다). 의존성은 `depends_on`으로만 표현한다.
- 다른 스킬·`rules/`를 doc-link하지 않는다(플러그인 자기완결). 후속 스킬을 자동 호출하지 않는다 — 등록 후
  안내만 남긴다.
- `[NEEDS CLARIFICATION` 마커가 남아 있으면 무인 실행이 차단됨을 안내한다.

## references

| 파일 | 역할 |
|---|---|
| `clarification.md` | 명확화 인터뷰 방법론(깔때기형 흐름·내부 커버리지·추천 답) |
| `task-body-template.md` | 태스크 본문(=SPEC) 구조 |
| `decomposition-gate.md` | 다중 서브시스템 감지·발행 규칙 |
| `self-review.md` | 자체 검토 5축 |
