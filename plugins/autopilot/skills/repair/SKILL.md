---
name: repair
description: "버그·증상·실패 테스트를 고쳐야 할 때 가장 먼저 사용 — 'X 고쳐줘', '이 버그/에러', '테스트가 실패해' 신호에서 정적 분석으로 근본 원인을 진단하고 그 수정용 자기완결 SPEC 문서를 작성해 구현 스킬(autopilot:dispatch)을 추천. 코드·머지·외부 상태는 만들지 않는다. 호출 'Skill(skill=\"repair\", args=\"<버그/증상/실패 테스트 설명> [--resume <spec-path>]\")'."
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Skill
  - Agent
  - Bash(git log:*)
  - Bash(git status:*)
  - Bash(git diff:*)
  - Bash(ls:*)
  - Bash(cat:*)
  - Bash(find:*)
  - Bash(grep:*)
  - Bash(echo:*)
  - Bash(head:*)
  - Bash(awk:*)
  - Bash(sed:*)
  - Bash(tr:*)
  - Bash(printf:*)
  - Bash(pwd:*)
  - Bash(mkdir -p docs/specs/**)
  - Bash(mkdir -p:*)
  - ToolSearch
---

# repair

`spec` 의 **버그 전용 형제**다. 기능 의도(무엇을 만들까)가 아니라 **버그·증상·실패 테스트 설명**에서 출발해, 정적 분석으로 근본 원인을 **진단**한 뒤 그 수정에 필요한 **자기완결 SPEC 문서**를 산출한다. 코드 구현·머지·외부 상태(이슈·브랜치·원격)는 만들지 않는다 — 산출물은 SPEC 문서(들)뿐이며, `spec` 과 동일한 옵트인 핸드오프로 `autopilot:dispatch` 에 넘어간다.

repair 는 SPEC 작성 기계(템플릿·완료 조건 패턴·자체 검토·clarity 점수·범위 분해·명확화·경로 해석·옵트인 핸드오프)를 **새로 만들지 않고 `spec` 의 자산을 단일 출처로 재사용**한다. repair 고유의 추가분은 둘뿐이다: ① 증상에서 근본 원인을 정적 분석으로 좁히는 **진단 단계**(step 2), ② 그 진단 결과를 담는 **진단 섹션**(step 4의 산출물 일부).

## 호출

- 새 수정 SPEC: `Skill(skill: "repair", args: "<버그/증상/실패 테스트 설명>")`
- 마커 해결: `Skill(skill: "repair", args: "--resume <spec-path>")`

상위 자율 오케스트레이터가 호출하는 맥락에서는 step 5 의 사용자 대면 프롬프트(최종 승인·핸드오프)를 **생략**하고, repair 는 `autopilot:dispatch` 를 직접 호출하지 않고 산출된 SPEC 경로만 넘긴다(이중 기동 방지) — `spec` 과 동일 규약(아래 step 5). 증상 명확화·정적 진단·미해결 마커 가드·SPEC 산출은 그대로 수행한다.

어떤 외부 상태도 만들지 않는다. task 생성·상태 정합·원격 동기화·브랜치 작업은 호출자와 구현 스킬의 책임이며 그 절차의 단일 출처는 `rules/` 다.

## 워크플로

호출 시 단계를 TodoWrite 로 등록한다. 모든 결정·승인은 `AskUserQuestion` 으로 받는다 — 자유 텍스트 질문 종결구 금지, 한 주제씩, 한 호출의 소문항 최대 4개.

### 1. 증상 명확화 + 컨텍스트 탐색

사용자가 말한 증상을 되짚는 데서 출발해, 재현 맥락(어떤 입력·환경·시점에서 무엇이 관찰되는가, 기대 동작 대비 실제 동작)을 깔때기형으로 좁힌다. 명확화 방법론(깔때기형 흐름·내부 커버리지 체크리스트·집요함·결정 트리·추천 답·코드 우선)의 단일 출처는 `../spec/references/clarification.md` 이며 repair 는 그 방법을 증상·재현 맥락 수집에 적용한다 — 단, 진단 자리에서는 "왜 이 동작을 원하나(목적)"가 아니라 "증상이 무엇이고 어디서 관찰되나"를 묻는다. 코드·로그·에러 메시지·스택·최근 변경(`git log`, `git diff`)을 **읽어** 관련 영역을 파악한다. 탐색이 부족하면 `references/agent-prompts.md` 의 `repair-context-explorer` 를 Agent 로 위임한다(사실 수집만, 결정·합성은 메인).

### 2. 정적 분석 진단 (repair 고유)

`references/diagnosis.md` 의 절차로 증상 → 근본 원인을 좁힌다. 진단은 코드·로그·증상 설명을 **읽고 추론하는 정적 분석으로만** 수행한다 — 버그를 실행·재현하거나 디버거를 붙이거나 실패 테스트를 구동하지 않는다. 산출은 근본 원인을 **확정이 아닌 가설**로 프레이밍하고, 가설을 뒷받침하는 증거를 `파일:줄` 참조로 명시한다. 정적 분석으로 근본 원인을 모호성 없이 특정할 수 없으면 그 자리에 `[NEEDS CLARIFICATION: <구체 질문>]` 마커를 남긴다(추정으로 메우지 않는다).

### 3. 범위 분해 게이트 + 접근법 비교

`../spec/references/decomposition-gate.md` 로 다중 독립 서브시스템 여부를 확인한다 — 버그 수정은 대개 단일 단위이므로 보통 하나의 SPEC 을 발행한다. 비자명한 수정 결정(둘 이상의 수정 지점·접근)이 있으면 2–3 접근법·trade-off·추천을 제시하고, 자명하면 생략한다. `--resume` 에서는 생략한다.

### 4. 수정 SPEC 문서 작성

`../spec/references/spec-template.md` 의 placeholder 를 치환해 SPEC 본문을 만들고, 여기에 repair 진단 섹션을 더한다.

- 템플릿 섹션 전체(무엇을 만들 것인가·목적·완료 조건·범위·검증·제약·위험)를 `spec` 과 동일 규약으로 채운다. 완료 조건은 `../spec/references/ears-patterns.md` 5문장 패턴을 따르고, 각 조건은 관찰 가능·독립 검증 가능해야 한다. 검증 섹션은 진입 명령을 싣지 않는다 — 완료 조건이 인수 바의 단일 출처이고 진입 명령은 `rules/` 에서 온다.
- **진단 섹션**(repair 고유)을 `references/spec-diagnosis-section.md` 형판대로 추가한다: 증상·재현 맥락, 그리고 근본 원인 **가설**(뒷받침 증거를 `파일:줄` 로 명시). 진단이 모호한 항목은 `[NEEDS CLARIFICATION: ...]` 마커로 남긴다.
- 산출 SPEC 의 **완료 조건**은 "해당 버그가 더 이상 관찰되지 않음 + 회귀를 막는 가드"를 관찰 가능·독립 검증 가능하게 인코딩한다(구현 방법·진입 명령은 강제하지 않는다).
- 산출 경로 해석·기본값의 단일 출처는 `rules/engineering/branch-and-slug.md`(없으면 기본 `docs/specs/<날짜>-<slug>/SPEC.md`, per-spec 디렉토리 + 그 안 `SPEC.md`)다 — repair 가 별도 경로 규칙을 정의하지 않는다. 빈 slug 면 abort 하고 제목 수정을 요청한다.

작성 후 `../spec/references/self-review.md` 5축(placeholder·모순·범위·모호성·검증 가능성)으로 1회 자체 검토하고, 규모 임계가 충족되면 `../spec/references/personas.md` 세 적대 렌즈를 가산한다. 발견은 수정하거나 `[NEEDS CLARIFICATION]` 마커로 남기며, 새 사용자 질의응답 라운드는 열지 않는다(반영은 메인이 한다).

### 5. 최종 승인 + 구현 스킬 추천 (옵트인 핸드오프)

완성된 SPEC 전체를 한 번 제시하고 `AskUserQuestion` 으로 단일 승인을 받는다. 발행 개수와 무관하게 **항상 `autopilot:dispatch` 를 추천**한다. 옵트인 핸드오프 규약은 `spec` 과 동일하다:

- SPEC 에 `[NEEDS CLARIFICATION` 미해결 마커가 **없고** 사용자가 최종 승인 + "구현까지 자동 진행" 에 **명시 동의**하면 그때만 작성된 SPEC 경로(들)로 `autopilot:dispatch` 를 호출한다. 그 외에는 추천만 남기고 종료한다.
- 미해결 마커가 **남아 있으면** 자동 진행을 제안하지 않는다 — 마커가 있으면 자율(dispatch) 실행이 차단된다는 사실과 `--resume` 해결법을 안내하고 종료한다.
- **자율 오케스트레이터 맥락**: 위 두 사용자 대면 프롬프트를 모두 생략하되 repair 는 `autopilot:dispatch` 를 직접 호출하지 않고 SPEC 경로(들)만 오케스트레이터에 넘긴다(이중 기동 방지). 미해결 마커가 남아 있으면 경로를 넘기지 않고 차단·`--resume` 을 안내한다(품질 게이트 보존).

## --resume 요약

대상 SPEC 문서 경로를 인자로 받아 그 자리의 문서를 갱신한다(경로 해석의 단일 출처는 `rules/engineering/branch-and-slug.md`). 문서가 없으면 abort, `[NEEDS CLARIFICATION` 마커가 없으면 종료한다. step 3 은 생략하고, step 1–2 는 남은 마커가 가리키는 진단·증상 항목만 다시 묻고 재진단하며, step 4 는 마커 섹션만 갱신해 step 5 로 종결한다. 새 외부 상태는 만들지 않는다.

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `diagnosis.md` | 정적 분석 진단 절차(증상→근본 원인 가설, 정적 한정, 증거·마커 규칙) 단일 출처 (step 2) |
| `spec-diagnosis-section.md` | 산출 SPEC 에 더하는 진단 섹션 형판 (step 4) |
| `agent-prompts.md` | step 1·4 subagent 위임 brief (사실·발견만 보고; 결정은 메인) |

SPEC 작성 기계는 `../spec/references/` 를 단일 출처로 재사용한다(복제하지 않는다): `spec-template.md`·`ears-patterns.md`·`self-review.md`·`personas.md`·`clarity-score.md`·`decomposition-gate.md`·`clarification.md`.

## 규칙

- repair 는 target 프로젝트의 SPEC 문서만 작성한다. 코드·머지·외부 상태(이슈·브랜치·원격)는 만들지 않는다.
- 진단은 정적 분석(읽기 + 추론)으로만 한다 — 실행·재현·디버거 부착 금지. 근본 원인은 가설로 프레이밍하고 `파일:줄` 증거를 싣는다.
- 자유 텍스트 질문 종결구 금지. 모든 선택은 `AskUserQuestion`. 한 주제씩, 한 호출의 소문항 최대 4개.
- `[NEEDS CLARIFICATION` 마커가 있으면 자율 실행이 차단된다. 사용자에게 `--resume` 해결을 안내한다.
- 후속 스킬을 자동 호출하지 않는다. **유일 예외**: step 5 옵트인 핸드오프(사람 단독 호출) — 미해결 마커 없음 + 최종 승인 + 명시 동의를 모두 충족할 때만 `autopilot:dispatch` 호출. 자율 오케스트레이터 맥락에서는 사용자 대면 프롬프트를 생략하되 dispatch 를 호출하지 않고 SPEC 경로만 넘긴다.
