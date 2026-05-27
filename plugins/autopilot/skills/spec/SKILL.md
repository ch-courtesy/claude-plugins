---
name: spec
description: "기능 추가·동작 수정·지침 작성·새로 만들기 등 새 코드 변경을 정의하는 자연어 신호에 대응. 명확화 인터뷰로 도중 질문 없이 수행 가능한 자기완결적 SPEC 문서(들)를 `docs/specs/<날짜>-<slug>.md`에 작성하고, 구현 스킬(autopilot:dispatch)을 추천합니다. 외부 상태(이슈·브랜치·원격)는 만들지 않습니다. 호출 'Skill(skill=\"spec\", args=\"<자연어 task 설명> [--resume <spec-path>]\")'."
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Skill
  - Agent
  - Bash(git log:*)
  - Bash(git status:*)
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
  - ToolSearch
---

# spec

명확화 인터뷰로 자기완결적 SPEC 문서(들)를 작성하고 구현 스킬을 추천하는 경량 스킬이다. 세 책임만 갖는다: ① 명확화 인터뷰, ② SPEC 문서 작성, ③ 구현 스킬 추천. 외부 상태(task·이슈·브랜치·원격)는 만들지 않는다 — 산출물은 SPEC 문서(들)뿐이다.

산출 SPEC은 구현 스킬이 중간 질문 없이 수행할 수 있을 만큼 자기완결적이어야 한다. SPEC은 의도(검증 가능한 EARS 수용 기준)만 싣고, 검증을 실행하는 진입 명령은 프로젝트 규칙(`rules/`)에 둔다.

## 호출

- 새 SPEC: `Skill(skill: "spec", args: "<자연어 task 설명>")`
- 마커 해결: `Skill(skill: "spec", args: "--resume <spec-path>")`

어떤 후속 스킬도 자동 호출하지 않고, 어떤 외부 상태(task·이슈·브랜치·원격)도 만들지 않는다. task 생성·상태 정합·원격 동기화·브랜치 작업이 필요하면 그것은 호출자(사용자 또는 상위 오케스트레이터)와 구현 스킬의 책임이며, 관련 절차는 `rules/` 아래 지침이 단일 출처다.

## 워크플로

호출 시 단계를 TodoWrite로 등록한다. 모든 결정·승인은 `AskUserQuestion`으로 받는다 — 자유 텍스트 질문 종결구 금지.

### 1. 컨텍스트 탐색

`git log --oneline -5`, `ls -A`, 선택적 `cat CLAUDE.md`, `ls rules/`, 얕은 테스트 디렉터리 탐색으로 테스트 컨벤션·룰·구조만 요약한다. 부족하면 `references/agent-prompts.md`의 `spec-context-explorer`를 Agent로 위임한다. 권장 도입 휴리스틱: 적용 룰이 많음, 기존 SPEC 선례가 많음, multi-file 영향, 자연어 의도만 있음. subagent는 사실 수집만 하며 결정·합성은 메인 책임이다(헌법 §11.6, 이터 내 서브 도구 위임).

### 2. 범위 분해 게이트

`references/decomposition-gate.md`로 다중 독립 서브시스템 여부를 확인한다. 다중 분해를 선택하면 한 번의 명확화 인터뷰에서 N개 SPEC 문서를 발행하고, 감지되지 않으면 정확히 하나를 발행한다. 이 게이트는 **발행 문서 개수만 결정하며 구현 스킬 추천을 가르지 않는다**(추천은 항상 dispatch, step 8). `--resume`에서는 생략한다.

### 3. 명확화 라운드

목적·성공기준·제약·위험을 결정 트리 기반 적응적 인터뷰로 수집한다. 인터뷰 방법(집요함·결정 트리·추천 답·코드 우선 네 원칙, "충분" 종결 조건, step 1과의 역할 경계)은 `references/clarification.md`가 단일 출처다. 전달 매체는 `AskUserQuestion`(한 번에 한 질문, 추천 답을 첫 선택지로) — 자유 텍스트 질문 금지. `--resume`에서는 마커 섹션만 묻는다. 검증 진입 명령·테스트 sweep 화이트리스트·리뷰 트리거 같은 구현-검증 관심사는 묻지 않는다 — 그 출처는 프로젝트 규칙(`rules/`)이다.

### 4. 접근법 비교

비자명한 결정(모호 요구, 둘 이상의 패턴, 외부 의존성 선택)이 있으면 2-3 접근법, trade-off, 추천을 제시한다. 자명하면 생략한다.

### 5. 섹션별 SPEC 승인

제목, 무엇을 만들 것인가(WHAT/HOW 방어선: 기술 스택·파일 경로·라이브러리·클래스명 금지), 수용 기준(EARS), 범위, 검증, 제약, 위험을 한 섹션씩 제시하고 승인받는다. 검증 섹션은 검증 진입 명령을 싣지 않는다 — EARS 수용 기준이 인수 바의 단일 출처이고 진입 명령은 프로젝트 규칙(`rules/`)에서 온다는 명시 문구만 둔다. EARS 언어(`en`/`ko`/`hybrid`, 기본 `ko`)와 5패턴은 `references/ears-patterns.md`를 따른다.

### 6. SPEC 문서 작성

`references/spec-template.md` placeholder를 치환한다: `{{task_title}}`, `{{task_description}}`, `{{acceptance_criteria}}`, `{{scope_in}}`, `{{scope_out}}`, `{{scope_include}}`, `{{depends_on}}`, `{{constraints}}`, `{{risks}}`. 템플릿은 검증 진입 명령·테스트 sweep 화이트리스트·리뷰 트리거 키를 더 이상 담지 않는다 — 검증 섹션은 EARS 수용 기준이 단일 출처이고 진입 명령은 프로젝트 규칙에서 온다는 명시 문구만 둔다. 미해결 항목은 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 남긴다.

분해 발행(step 2의 N개)에서는 단위마다 템플릿을 한 번씩 치환해 문서를 만들고, 각 문서의 `{{depends_on}}`에 선행 단위 slug 목록을 기록한다(`depends_on: ["<slug>"]`). 단일 발행이면 `{{depends_on}}` 줄을 제거한다.

산출 경로는 `docs/specs/<YYYY-MM-DD>-<slug>.md`다. `<YYYY-MM-DD>`는 작성일(로컬 날짜), `<slug>`는 SPEC 제목에서 파생한다 — slug 파생·파일명 규칙은 `rules/engineering/branch-and-slug.md`가 단일 출처다. 빈 slug는 fallback 없이 abort하고 제목 수정을 요청한다. `docs/specs/` 디렉터리가 없으면 만든다.

### 7. 자체 검토

`references/self-review.md` 5축(placeholder, 모순, 범위, 모호성, EARS fail-가능성)을 검사한다. 수정 또는 `[NEEDS CLARIFICATION]` 마커만 남기고 사용자 Q&A와 재루프는 하지 않는다. 초안이 100줄 이상이거나 마커 2개 이상이면 `references/agent-prompts.md`의 `spec-self-reviewer`를 권장 도입한다. subagent는 발견만 보고하고 수정·마커 박기는 메인이 한다.

### 8. 구현 스킬 추천

SPEC 경로(들)·요약과 함께 구현 스킬을 추천하고 종료한다. 발행 문서 개수와 무관하게 **항상 `autopilot:dispatch`를 추천한다** — 단일 문서면 dispatch가 N=1로 처리하고, 다중 문서면 SPEC set으로 처리한다(볼륨에 따른 loop/dispatch 분기는 없다). 추천은 안내일 뿐 어떤 후속 스킬도 자동 호출하지 않는다 — 실행 여부·방법은 사용자가 결정한다. `[NEEDS CLARIFICATION` 마커가 남아 있으면 자율 실행이 차단된다는 사실과 `--resume` 해결 방법을 함께 안내한다.

## --resume 요약

대상 SPEC 문서 경로를 인자로 받는다. 문서가 없으면 abort, `[NEEDS CLARIFICATION` 마커가 없으면 종료한다. step 2는 생략, step 3은 남은 마커 섹션만 다시 묻는다. step 5-7은 마커 섹션만 갱신·재작성하고, step 8로 종결한다. 새 외부 상태는 만들지 않는다.

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `spec-template.md` | SPEC 문서 placeholder 템플릿 |
| `ears-patterns.md` | EARS 5패턴·언어 규칙 |
| `self-review.md` | 자체 검토 5항목 |
| `decomposition-gate.md` | 다중 서브시스템 감지 |
| `agent-prompts.md` | step 1·7 subagent dispatch 양식 (헌법 §11.6) |
| `clarification.md` | 명확화 인터뷰 방법론(집요함·결정 트리·추천 답·코드 우선) 단일 출처 |

## 규칙

- 본 스킬은 target 프로젝트의 SPEC 문서만 작성한다. 이슈·브랜치·원격 등 외부 상태는 만들지 않는다.
- 자유 텍스트 질문 종결구 금지. 모든 선택은 `AskUserQuestion`.
- 한 주제씩 묻고, 한 호출의 관련 소문항은 최대 4개.
- `[NEEDS CLARIFICATION` 마커가 있으면 자율 실행이 차단된다. 사용자에게 `--resume` 해결을 안내한다.
- 후속 스킬을 자동 호출하지 않는다.
