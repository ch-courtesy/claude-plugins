---
name: fix
description: 버그·증상·실패 신호를 정적 분석으로 진단해 자기완결적 태스크 본문(진단 섹션 포함)을 자율 작성하고 등록 프리미티브 create-task에 넘겨 태스크 백엔드에 등록하려 할 때 사용 — 'X 버그/에러', '테스트가 실패해' 신호에서 코드·로그를 읽고 근본 원인을 가설로 좁혀 본문을 뜬다. 본문이 곧 SPEC이며 별도 SPEC 파일은 만들지 않는다. 작성만 책임지고 등록·상태 전이는 create-task가 소유한다. feature의 정적분석 짝(feature=대화형 인터뷰, fix=무인 정적분석). 직접 호출 'Skill(skill="fix", args="<버그/증상/실패 신호>")'.
allowed-tools:
  - AskUserQuestion
  - Read
  - Skill
  - Agent
  - Bash(git rev-parse:*)
  - Bash(git log:*)
  - Bash(git diff:*)
  - Bash(git status:*)
  - Bash(ls:*)
  - Bash(cat:*)
  - Bash(find:*)
  - Bash(grep:*)
  - Bash(head:*)
  - Bash(awk:*)
  - Bash(sed:*)
  - Bash(pwd:*)
---

# fix

버그·증상·실패 신호를 **정적 분석으로 진단**해 자기완결적 **태스크 본문**(진단 섹션 포함)으로 뜨는
**작성자(authoring) 스킬**이다. 작성이 끝나면 본문을 **등록 프리미티브 `create-task`** 에 넘겨 백엔드에
등록한다. 태스크 본문이 곧 설계(SPEC)의 단일 출처이며 별도 SPEC 파일을 만들지 않는다.

`feature`(대화형 인터뷰 작성자)의 **정적분석 짝**이다 — `feature`는 사람과의 명확화 인터뷰로 기능 의도를
뜨고, `fix`는 코드·로그·실패 신호를 **읽고 추론**해 무인으로 버그 본문을 뜬다.

작성과 등록을 분리해 진단·작성 방법론을 한 곳(이 스킬의 `references/`)에 모은다 — 작성만·플러그인
자기완결 경계의 완결 서술은 「규칙」이 소유한다.

## 호출

- 새 버그 작성: `Skill(skill="fix", args="<버그/증상/실패 신호>")`
- **자율 오케스트레이터 맥락**(workflow-task 드레인자가 버그 신호를 감지해 중앙에서 호출): 사용자 대면
  프롬프트(최종 승인)를 **생략**하고 무인으로 진단·본문 작성 후 `create-task`로 등록한다. 미해결 마커가
  남으면 차단을 알리지 않고 본문에 마커를 남긴 채 등록한다(create-task가 `in_design`으로 둔다).

## 워크플로

호출 시 단계를 현재 런타임의 계획 추적 기능으로 등록한다. 직접 호출 맥락의 결정·승인은 `AskUserQuestion`으로
받는다(자유 텍스트 질문 종결구 금지). 자율 오케스트레이터 맥락에서는 사용자 대면 프롬프트를 생략한다.

1. **컨텍스트 탐색** — 증상이 가리키는 코드·로그·에러 메시지·스택·최근 변경(`git log`·`git diff`)을 **읽어**
   관련 영역을 파악한다(코드 우선). 탐색이 넓거나 분산되면 `references/agent-prompts.md`의
   `fix-context-explorer`를 Agent로 위임한다(사실 수집만 — 결정·합성·진단 확정은 메인).
2. **정적 분석 진단** — `references/diagnosis.md` 절차로 증상 → 근본 원인을 좁힌다. 진단은 코드·로그·증상을
   **읽고 추론하는 정적 분석으로만** 한다 — 버그를 실행·재현하거나 디버거를 붙이거나 실패 테스트를 구동하지
   않는다. 근본 원인은 **확정이 아닌 가설**로 프레이밍하고 증거를 `파일:줄`로 싣는다. 모호성 없이 특정할 수
   없으면 그 자리에 `[NEEDS CLARIFICATION: <구체 질문>]` 마커를 남긴다(추정으로 메우지 않는다).
3. **태스크 본문 작성** — 공용 `plugins/autopilot/references/task-body-template.md` frontmatter-first
   구조(scope frontmatter + 무엇을 만들 것인가/목적/진단/완료 조건(EARS)/범위/검증/제약/위험)로 본문을
   작성한다. `scope.include` 는 step 2 진단에서 식별한 변경 대상으로 채운다(불명확하면 보수적으로 넓게).
   본문이 SPEC이다. **진단 섹션**(fix 전용)에 step 2 결과(증상·재현 맥락·근본 원인 가설·증거·마커)를 담고,
   **완료 조건**은 공용 `plugins/autopilot/references/ears-patterns.md`
   5문장 패턴으로 "해당 버그가 더 이상 관찰되지 않음 + 회귀를 막는 가드"를 관찰 가능·독립 검증 가능하게
   인코딩한다(구현 방법·진입 명령은 강제하지 않는다). 버그 수정은 대개 단일 단위이므로 보통 본문 하나를
   작성한다 — 둘 이상 독립 수정 지점이 분명하면 본문을 나눠 의존 순서로 등록한다.
4. **자체 검토** — 공용 `plugins/autopilot/references/self-review.md`의 점검 축(placeholder·모순·범위·
   모호성·검증 가능성·scope.include) + 진단 섹션 전용 점검(fix 전용)을 1회 수행한다. 규모 임계 시 적대 렌즈
   가산의 정의 단일 출처는 공용 `plugins/autopilot/references/personas.md`. 발견은 수정하거나 `[NEEDS CLARIFICATION]` 마커로 남긴다(새 Q&A 라운드를 열지 않는다).
5. **등록 위임** — 완성 본문을 한 번 제시해(직접 호출 맥락) 단일 승인을 받은 뒤 **`create-task`를 호출해
   등록**한다(자율 맥락은 승인 생략):
   ```
   Skill(skill="create-task", args="<제목>\n\n<본문>")
   ```
   `create-task`가 등록하고 본문의 `[NEEDS CLARIFICATION` 마커 유무로 상태를 전이한다 — 마커가 **없으면**(완성)
   `backlog`, **남아 있으면**(자율 분석 불충분) `in_design`. 결과(task_id·url·최종 상태)와 다음 단계 안내는
   `create-task`가 책임진다. 이 스킬은 본문을 넘기는 데서 끝난다.

## 미해결 마커 — in_design 후 인터뷰 재개로 완성

정적 분석만으로 근본 원인을 특정할 수 없어 `[NEEDS CLARIFICATION]` 마커가 남으면, `create-task`가 그 태스크를
`in_design`으로 둔다(무인 실행 차단). 남은 항목은 **`feature`의 인터뷰 재개**로 사람과 함께 이어 완성한다:
`Skill(skill="feature", args="resume <task-id>")`. 즉 자율 정적 작성(fix)이 닿지 못한 모호성은 대화형 작성
재개(feature)가 메운다 — fix는 자체 재개 경로를 두지 않는다.

## 규칙

- **작성만** 한다 — 진단·본문 작성·자체검토만 하고, 어댑터 write 동사(`create_task`/`set_body`/`set_status`)를
  **직접 호출하지 않으며** 파일을 만들지 않는다(본문=SPEC, 백엔드가 SoT). 등록·전이는 `create-task`에 위임한다.
- 진단은 **정적 분석(읽기 + 추론)으로만** 한다 — 절차·정적 한정·증거·마커 규칙의 단일 출처는
  `references/diagnosis.md`(step 2에서 적용).
- 다른 스킬·`rules/`를 doc-link하지 않는다(플러그인 자기완결). 외부 스킬의 참조를 사용하지 않는다.
- `[NEEDS CLARIFICATION` 마커가 남으면 무인 실행이 차단됨을 안내하고 `feature` 인터뷰 재개로 완성하도록 한다.
- 후속 스킬을 자동 호출하지 않는다. **유일 예외**: step 5 등록 위임의 `create-task` 호출(작성→등록 핸드오프).

## references

| 파일 | 역할 |
|---|---|
| `references/diagnosis.md` | 정적 분석 진단 절차(증상→근본 원인 가설, 정적 한정, 증거·마커 규칙) 단일 출처 (step 2) |
| `references/agent-prompts.md` | step 1·4 subagent 위임 brief (사실·발견만 보고; 결정은 메인) |
| `plugins/autopilot/references/task-body-template.md` | 태스크 본문(=SPEC) 구조 + 진단 섹션 형판 — 작성자 공용 단일 출처 (step 3) |
| `plugins/autopilot/references/ears-patterns.md` | 완료 조건 5문장 패턴·언어 모드 — 작성자 공용 단일 출처 (step 3) |
| `plugins/autopilot/references/self-review.md` | 자체 검토 축 + 진단 전용 점검 — 작성자 공용 단일 출처 (step 4) |
