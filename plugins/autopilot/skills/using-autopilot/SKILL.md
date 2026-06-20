---
name: using-autopilot
description: Use at the start of any session in an autopilot-installed project — routes every new code-change signal to a mandatory authoring/registration entry point before any other response. Feature intent (기능 추가·지침 작성·새로 만들기) routes to the new authoring skill feature, which interviews the intent into a task body (=SPEC) and registers it via the create-task registration primitive; bug·symptom·failing-test signals (버그·증상·실패 테스트 고치기) keep their current path via create-task (a fix authoring skill does not yet exist — do not route bugs to a non-existent skill). This overrides generic brainstorming-first guidance for such work. Also routes self-improvement signals — anomalous behavior of autopilot's own task skills (create-task/execute-task/workflow-task) observed during use (wrong blocked, pointless waiting, contradictory state, unexpected failure) — to create-task: diagnose, and if a real defect, register the fix as a self-contained spec via create-task rather than just working around it.
---

# using-autopilot
**REQUIRED RUNTIME CONTRACT:** `../../references/runtime-capabilities.md`를 읽고 스킬 호출과 사용자 질문을 현재 런타임 기능에 맞춘다.


autopilot이 설치된 프로젝트의 네이티브 워크플로 진입점이다. 새 코드 변경은 **의도를 먼저 자기완결적 태스크로 등록하는 것**에서 출발한다. 작성(authoring)과 등록(registration)이 분리되어 있다 — **기능 의도는 작성자 `feature`** 가, **버그·증상·실패는 현행대로 `create-task`** 가 첫 단계다. `feature`는 명확화 인터뷰로 의도를 탐색해 태스크 본문(=SPEC)을 떠서 **등록 프리미티브 `create-task`** 로 넘겨 백엔드에 등록한다. 등록 이후 실행 단계(`execute-task` 단일 실행 / `workflow-task` 무인 드레인) 선택·안내는 `create-task`가 책임진다. 이 스킬은 **올바른 진입점(`feature`/`create-task`)으로의 라우팅까지만** 강제한다.

---

> ## 🚨 절대 우선 — 다른 어떤 것보다 먼저 (협상 불가)
>
> 새 코드 변경 신호를 감지하면, **다른 어떤 응답·도구 호출·탐색보다 먼저** 올바른 진입점을 호출한다. 분기는 신호 유형 단 하나다:
>
> - **기능 의도**(무엇을 만들까·새 동작 추가·지침 작성·문서 편집·새로 만들기·기존 SPEC/태스크 구현) → `feature` 호출 (`Skill(skill="feature", args="<자연어 기능 설명>")`). `feature`가 인터뷰로 본문(=SPEC)을 떠서 `create-task`로 등록한다.
> - **버그·증상·실패**(잘못된 동작을 고쳐달라·이 버그/에러·테스트가 실패해) → **현행대로** `create-task` 호출 (`Skill(skill="create-task", args="<자연어 task 설명>")`). 전용 버그 작성자(`fix`)는 아직 없으므로 **미존재 스킬로 라우팅하지 않는다**.
>
> 두 경로 모두 등록 이후 실행 단계(`execute-task`/`workflow-task`) 선택·안내는 `create-task`가 책임지며, 이 스킬은 거기까지의 라우팅만 강제한다.
>
> **1%라도 새 코드 변경일 가능성이 있으면 즉시 올바른 진입점으로 라우팅한다.** 사용자가 직접 경로를 지정하지 않는 한 코드·탐색·다른 도구에 손대기 전에 먼저 실행한다. **이것은 협상 대상이 아니다.**

---

## 트리거 (이 중 하나라도 해당되면 진입점 먼저)

자연어로 다음 의도가 보이면 새 코드 변경 신호다. **기능 의도는 `feature`로, 버그·증상·실패는 `create-task`(현행)로** 보낸다.

### 기능 의도 → `feature`

- **기능 추가** — "X 기능 만들어줘", "X 추가해줘", "X 붙여줘"
- **의도적 동작 변경** — "X 동작을 ...로 바꿔줘"처럼 결함이 아니라 새로 원하는 동작으로 바꾸는 변경.
- **지침 작성·문서 편집** — "X 규칙 만들어줘", "X 지침 써줘", 그리고 기존 지침·문서의 **편집·압축·축약·수정·삭제**("X 지침 줄여줘", "이 문서 정리해줘", "이 규칙 지워줘"). 문서·지침을 바꾸는 일은 동작·지침을 바꾸는 코드-변경 신호이지 "코드 변경 아님"이 아니다.
- **기존 SPEC/태스크 구현** — `<경로>/SPEC.md 구현`, "이 SPEC 구현해줘", "SPEC대로 만들어줘", "이 태스크 구현"처럼 기존 SPEC 파일·태스크의 구현·구현 확인. SPEC/태스크를 **읽기/검증**하는 것은 예외지만, 그것을 **구현**하는 것은 코드-변경 신호다.
- **새로 만들기** — "X 스킬/플러그인/모듈 만들꺼야", "X 새로 만들어줘"

### 버그·증상·실패 → `create-task` (현행)

- **버그 수정** — "X 고쳐줘", "X가 안 돼", "이 버그 잡아줘"처럼 잘못된(결함) 동작을 바로잡는 요청.
- **증상·오류** — "이 에러 나", "이 예외/크래시", "결과가 이상해"처럼 관찰된 증상·오류 신호.
- **실패 테스트** — "이 테스트가 실패해", "테스트 깨졌어"처럼 실패 테스트를 통과시켜 달라는 요청.

`feature`의 명확화 인터뷰(집요함·결정 트리·추천 답·코드 우선)가 **기능 의도**를 태스크 본문(=SPEC)으로 흡수하므로, 별도의 사전 설계 단계 없이 그것이 곧 첫 단계다. 신호 여부가 모호하면 사용자에게 한 번 확인한다. 기능과 버그가 한 요청에 섞여 있으면 분리하기 어려운 경우 사용자에게 한 번 확인하되, 명백한 기능 의도는 `feature`로, 명백한 버그·증상·실패는 `create-task`로 보낸다.

## 자가개선 트리거 — task 스킬 비정상 동작 → create-task 수정 스펙

위 트리거가 **사용자가 요청한 새 코드 변경**을 라우팅한다면, 이 절은 **autopilot 자기 도구의 비정상 동작**이라는 새 신호 유형을 `create-task`(현행 버그 경로)로 라우팅한다. 사람이 매번 "버그인지 보고 고쳐라"라고 지시하지 않아도, 비정상을 그 자리에서 자가개선 신호로 인식해 탐지→판단→수정 스펙 등록으로 잇는다. 이것은 기존 라우팅을 **대체·약화하지 않고 그 위에 가산**된다.

- **트리거** — `create-task`/`execute-task`/`workflow-task`(및 그 엔진 loop·forge·merge·review) 사용 중 비정상 동작을 관찰했을 때: 잘못된/근거 약한 `blocked`, 오지 않을 상태를 무의미하게 대기, 모순된 상태 전이, 예기치 못한 실패·오보고 등.
- **행동** — 그 비정상을 단순 우회·수동 처리로 끝내지 말고 **자가개선 판단을 시작**한다. 순서:
  1. **적대적 진단** — 그 비정상이 실제 결함인지 적대적으로 진단한다. 가능하면 결정적으로 재현·검증한다(일회성/환경 요인 배제).
  2. **수정 스펙 등록** — 실제 결함으로 판정되면 그 수정을 `create-task`(현행 버그 경로)로 자기완결 스펙으로 떠 등록한다(본문=SPEC). 관찰된 증상·재현 경로·결함 범위를 스펙에 담는다.
  3. **평소 실행 경로로 처리** — 등록된 스펙은 `create-task`가 안내하는 평소 실행 단계(`execute-task` 단일 실행 / `workflow-task` 무인 드레인)로 처리한다.
- **경계**
  - 단순 우회가 **정당한 경우는 제외**한다: 일회성 환경 이슈, 또는 사용자가 우회를 **명시적으로** 지시한 경우(사용자 지침 최우선).
  - 결함인지 **불확실하면** 보정된 신뢰도로 보고하되, 비정상이 **blocking 성격**(작업을 멈추는)이면 스펙 등록을 우선한다.
  - 무한 재귀(자기 수정의 자기 수정…) 방지를 위해 **관찰된 구체적 비정상 1건**에 한정한다.

## 합리화 구멍 차단 (이 세 합리화로 라우팅을 건너뛰지 않는다)

라우팅 누락은 거의 항상 다음 셋 중 하나의 합리화에서 나온다. 세 경우 모두 기능 의도(코드-변경) 신호이며 **`feature`가 먼저다** — 합리화가 옳아 보여도 라우팅한다.

1. **"먼저 코드를 파악·이해하고"** — 기존 코드를 이해해야 한다는 필요는 라우팅의 예외가 **아니다**. 그 탐색은 `feature`의 컨텍스트 탐색·명확화 인터뷰 단계(코드-우선 원칙)에서 수행된다. "이해가 필요하다"가 라우팅을 미룰 근거가 되지 않는다 — 먼저 `feature`를 실행하고 이해는 그 안에서 한다.
2. **"기존 SPEC/태스크를 구현/확인하는 것뿐"** — `<경로>/SPEC.md 구현`처럼 기존 SPEC 파일·태스크의 구현·구현 확인 요청은 읽기/검증 예외가 **아니라 코드-변경 신호**다. SPEC/태스크를 읽거나 검증하는 것(예외)과 그것을 구현하는 것은 다르다 — 후자는 `feature`가 먼저다.
3. **"문서·지침 편집은 코드 변경이 아니야"** — 지침·문서의 편집·압축·축약·수정·삭제는 동작·지침을 바꾸는 코드-변경 신호("지침 작성/동작 수정")다. "코드 변경 아님"으로 합리화하지 않는다 — `feature`가 먼저다.

## brainstorming-first 강제와의 관계 (명시적 override)

`superpowers:using-superpowers`는 "creating features / building components 같은 창작 작업엔 무조건 `superpowers:brainstorming`을 먼저"를 강제한다. **autopilot이 설치된 프로젝트에서, 위 트리거에 해당하는 새 코드 변경 작업에 한해 이 강제를 대체한다** — brainstorming 대신, 기능 의도면 **`feature`**, 버그·증상·실패면 **`create-task`** 가 첫 단계다.

근거(왜 이 규칙이 그 자리에서 더 구체적이고 우선하는가):

- **specificity** — brainstorming-first는 모든 "창작 작업"에 걸리는 일반 규칙이다. 본 규칙은 "autopilot 설치 + 새 코드 변경 신호"라는 더 좁은 조건에 걸린다. 구체적 규칙이 일반 규칙을 이긴다.
- **기능 동치** — `feature`의 명확화 인터뷰가 brainstorming의 의도·범위·제약 탐색을 수행한다. 설계 탐색이 빠지는 게 아니라 `feature` 안으로 들어온다.
- **파이프라인 정합** — 산출물(태스크 본문=SPEC)이 `create-task`를 통해 백엔드에 등록되어 곧바로 `execute-task`(단일 실행)·`workflow-task`(무인 드레인)의 입력이 된다.

milestone 규모(다중 독립 서브시스템)는 `feature`의 **범위 분해 게이트**가 처리하므로 별도 brainstorming이 필요 없다.

## Red flags — 이 생각이 들면 멈추고 올바른 진입점을 먼저 실행한다

| 생각 | 현실 |
|---|---|
| "일단 brainstorming부터 하자" | autopilot 프로젝트의 새 코드 변경은 진입점(기능=feature / 버그=create-task)이 첫 단계다. brainstorming이 아니다. |
| "이건 너무 사소해서 태스크까지는…" | 사소한 변경일수록 진입점이 빠르게 끝난다. 자기완결 의도 문서(태스크 본문=SPEC)는 항상 남긴다. |
| "바로 코드부터 짜자" | 의도(검증 가능한 완료 조건) 없이 구현하지 않는다. 진입점 → 구현. |
| "버그니까 그냥 바로 고치자" | 버그 수정도 의도를 먼저 태스크로 뜬다. "X 고쳐줘"·"이 에러"·"테스트 실패"는 현행대로 `create-task`가 먼저다. |
| "먼저 코드베이스를 좀 둘러보고" | 탐색은 `feature`의 컨텍스트·명확화 단계가 수행한다. 그 안에서 한다. |
| "먼저 코드를 파악·이해해야 시작하지" | 이해 필요는 라우팅의 예외가 아니다. 먼저 실행하고, 이해는 `feature`의 탐색 단계에서 한다. |
| "기존 SPEC/태스크를 구현/확인하는 것뿐이니까" | SPEC/태스크 읽기·검증은 예외지만 구현은 코드-변경 신호다. `SPEC.md 구현`은 `feature` 먼저. |
| "문서·지침 편집은 코드 변경이 아니야" | 지침·문서의 편집·압축·축약·수정·삭제는 동작·지침을 바꾸는 코드-변경 신호다. `feature` 먼저. |
| "사용자가 그냥 만들라고 했으니" | "만들어줘"는 WHAT이지 HOW가 아니다 — `feature`가 HOW 이전에 WHAT을 확정한다. |
| "task 스킬이 이상하지만 일단 수동으로 우회하자" | autopilot 자기 도구의 비정상은 자가개선 신호다. 우회로 끝내지 말고 진단→실제 결함이면 `create-task`로 수정 스펙 등록(「자가개선 트리거」). 정당한 우회(일회성 환경·사용자 명시 지시)만 예외. |

## 예외 (라우팅 불필요)

- 이미 진행 중인 워크플로의 연속, 또는 `--resume` 마커 해소.
- 새 코드 변경이 **아닌** 작업: 순수 질의응답, 코드 읽기·설명, 검색, 단순 디버깅(원인 조사·로그 분석으로 끝내고 수정은 하지 않음), 운영 명령(테스트 실행·상태 조회).
- 사용자가 라우팅을 건너뛰라고 **명시적으로** 지시한 경우(사용자 지침이 최우선).

이 예외는 위 정당한 경우에만 적용된다 — 「합리화 구멍 차단」의 세 경우(이해-먼저 탐색, SPEC/태스크 구현, 문서·지침 편집)는 예외가 아니라 코드-변경 신호이므로 여기로 끌어오지 않는다. 단순 디버깅은 원인 조사·로그 분석으로 **끝나는** 경우만 예외이며, 그 조사가 **수정 요청**으로 넘어가면 그때는 `create-task`(버그 경로)가 먼저다. 반대로, 정당한 예외(순수 질의응답·코드 읽기·검색·조사로 끝나는 디버깅·운영 명령)를 게이트로 끌어오는 것도 오류다.

## 파이프라인

```
기능 의도        → autopilot:feature (인터뷰: 태스크 본문=SPEC 작성) → autopilot:create-task (등록) ─┬→ execute-task (단일 실행)
버그·증상·실패   → autopilot:create-task (현행 등록 경로) ────────────────────────────────────────┴→ workflow-task (무인 드레인)
```

`using-autopilot`은 **올바른 진입점(`feature`/`create-task`)으로의 라우팅까지만** 책임진다. 작성자 `feature`는 인터뷰로 본문(=SPEC)을 떠서 `create-task`에 넘기고, 등록 프리미티브 `create-task`는 그 본문을 백엔드에 등록하고 등록-후 상태 전이를 소유한다. 하류(`execute-task`/`workflow-task`)는 오리엔테이션으로만 표시한 것이며, 그 선택·기동·안내는 등록 이후 `create-task`의 책임이다. 전용 버그 작성자(`fix`)는 아직 없으므로 버그 경로는 현행대로 `create-task`를 직접 진입점으로 둔다.
