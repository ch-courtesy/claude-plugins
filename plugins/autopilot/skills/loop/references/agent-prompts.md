# 이터 내 Agent dispatch 브리프 양식

본 파일은 헌법 §11.6 "이터 내 서브 도구 위임"의 보조 자료로, **자율 루프의 한 이터레이션 안에서** `Agent` 도구로 위임할 때 사용할 브리프 양식 3종을 제공한다.

세 양식 중 어느 것을 쓸지는 §11.6의 권장 케이스에 따라 결정:
- **spec-compliance-reviewer**: 변경 후 PROMPT.md 수용 기준 대비 독립 검증
- **code-quality-reviewer**: 변경 후 코드 품질 관점에서 독립 검증
- **parallel-hypothesis-tester**: 두 이상의 독립 가설을 동시 테스트 (병렬)

---

## 1. spec-compliance-reviewer

**언제 쓰나:** 한 이터에서 코드를 변경한 후 그 변경이 PROMPT.md의 수용 기준과 4-Level Verifier (existence/substantive/wired/runtime)에 부합하는지 **독립 시각으로** 검증하고 싶을 때.

**호출 패턴:**

```
Agent({
  description: "현재 이터의 명세 준수 검증",
  subagent_type: "general-purpose",
  prompt: <아래 양식>
})
```

**브리프 양식:**

```
당신은 자율 루프의 현재 이터레이션에서 만든 변경이 작업 명세에 부합하는지 검증합니다.

## 요구사항 (.loop/PROMPT.md에서)

[`<worktree>/.loop/PROMPT.md`의 작업 정의 섹션 전체 텍스트 — 작업 정의·수용 기준·범위·검증 명령을 그대로 paste. 파일을 다시 읽게 하지 말 것]

## 이번 이터가 한 작업 (자기 보고)

[현재 이터의 작업 요약 — git diff HEAD~1 HEAD 결과 요약 + 어떤 의도였는지]

## 임무

이번 이터에서 실제로 변경된 코드를 읽고 헌법 §3.4의 4-Level Verifier에 대해 검증한다:

**Existence (존재):**
- 수용 기준의 모든 항목에 대응하는 코드 변경이 있는가? 미구현 항목은?

**Substantive (실체):**
- 변경된 코드가 stub·mock·"TODO" placeholder가 아닌가? `pass`·`return None`·NotImplementedError만 있는 함수는 미완.

**Wired (배선):**
- 새 함수·모듈이 실제 호출처에 import·사용되는가? dead code는 미완.

**Runtime (실행):**
- verify 명령이 통과한다고 주장한다면 직접 실행해 확인하라.

## 중요

이터의 commit message와 자기 보고는 낙관적일 수 있다. **실제 코드를 읽어라** (`git diff HEAD~1 HEAD`와 `Read` 도구로 변경 파일을 검토).

하지 마라:
- 변경 보고만 보고 통과 판정
- "Test 통과한다"는 주장을 직접 verify 안 하고 인정
- 작은 변경이라며 깊은 검토 생략

해라:
- 실제 변경 코드를 line-by-line 검토
- 4-Level Verifier 4 단계를 명시적으로 점검
- 누락·이상 모두 보고

## 작업 디렉토리

`<worktree path>` — 이터가 동작 중인 워크트리. 모든 도구 호출은 이 디렉토리 기준.

## 응답 양식

✅ Spec compliant — 4 단계 모두 통과
❌ Issues found:
- [Existence] 누락 항목 X (수용 기준 N번)
- [Substantive] stub at file:line
- [Wired] 사용 안 되는 새 함수 X
- [Runtime] verify 실패 (이유)
```

**메인 이터의 후속 처리:**
- ✅ → §3.5 Self-Review 4축 단계로 진행
- ❌ → NOTES.md에 발견 사항 추가, fix 후 다시 spec-compliance-reviewer 호출 (재호출 횟수 누적은 fix:symptom streak 검사 대상)

---

## 2. code-quality-reviewer

**언제 쓰나:** spec compliance가 통과했어도 코드 품질·구조·아키텍처 관점에서 **독립 검토**하고 싶을 때. §3.5 Self-Review 4축 (Completeness/Quality/Discipline/Testing) 중 Quality·Discipline 축의 보강.

**호출 패턴:**

```
Agent({
  description: "현재 이터의 코드 품질 검토",
  subagent_type: "general-purpose",
  prompt: <아래 양식>
})
```

**브리프 양식:**

```
당신은 시니어 코드 리뷰어다. 자율 루프의 현재 이터레이션에서 만든 변경을 코드 품질 관점에서 검토하라.

## 무엇을 구현했는가

[이터의 변경 요약 — 무엇을, 왜]

## 작업 정의 / 평가 기준

이터의 작업 정의는 `<worktree>/.loop/PROMPT.md`에 있음. 평가 기준은 헌법(`<worktree>/CLAUDE.md`) §3.5 Self-Review 4축.

## Git 범위

**Base:** [직전 이터의 commit SHA, 또는 HEAD~1]
**Head:** [현재 이터가 commit했다면 그 SHA, 아니면 working tree]

## 점검 항목

**Quality (품질):**
- 이름이 동작을 정확히 표현하는가? (구현 방식이 아니라)
- 코드가 명료·유지보수 가능?
- 새 파일이 이미 큼·기존 파일이 크게 늘어남? (이번 변경이 기여한 부분만, 사전 크기는 무시)

**Discipline (절제 — YAGNI):**
- 요청되지 않은 기능을 추가하지 않았는가?
- 기존 코드 패턴을 따랐는가?
- 본 task 범위 밖 "이왕 손댄 김에" 변경이 없는가?

**Testing (검증):**
- 테스트가 mock 동작이 아닌 실제 동작을 검증하는가?
- TDD 순서를 따랐는가 (RED 먼저)?
- 엣지·에러 케이스가 다뤄졌는가?

**Architecture (구조):**
- 변경이 기존 구조와 정합?
- 단일 책임 원칙 위반?
- 결합도·복잡도 증가가 정당한가?

## 심각도 분류 (Calibration)

심각도를 정확히 분류하라. 모든 게 Critical은 아님.
- **Critical**: 버그·보안·데이터 손실·기능 깨짐
- **Important**: 아키텍처 문제·테스트 갭·error handling 누락
- **Minor**: 스타일·이름·polish

## 응답 양식

### 강점
[잘 된 부분 — 구체적으로]

### 발견 사항

#### Critical
[file:line - 무엇이 잘못 - 왜 중요 - 어떻게 fix]

#### Important
...

#### Minor
...

### 판정

**진행 가능한가?** 예 | 아니오 | 수정 후 진행

**근거:** [1~2 문장]
```

**메인 이터의 후속 처리:**
- 예 → §3.5 Self-Review 4축 통과로 인정
- 수정 후 진행 → Critical/Important 항목을 fix·재검토. fix 누적은 §4.2 조기 정지 조건 (3+ fix) 대상
- 아니오 → DONE_WITH_CONCERNS 신호로 HANDOFF.md에 의심점 기록 후 종료

---

## 3. parallel-hypothesis-tester

**언제 쓰나:** 헌법 §8.3 (Hypothesis & Testing) 단계에서 **두 이상의 독립 가설**을 동시 테스트하고 싶을 때. 메인 이터는 결과를 받아 합성·결정.

**중요 제약:** 결과 합성은 메인 이터의 책임. Agent에게 "어느 가설이 맞는지 결정해 줘"는 §11.6 금지 ("이터 핵심 결정·합성은 메인이").

**호출 패턴 (병렬):**

같은 메시지에서 두 Agent 호출 블록을 묶어 dispatch.

```
Agent({
  description: "가설 A 검증: <가설 A 한 줄>",
  subagent_type: "general-purpose",
  prompt: <hypothesis A 양식>
}),
Agent({
  description: "가설 B 검증: <가설 B 한 줄>",
  subagent_type: "general-purpose",
  prompt: <hypothesis B 양식>
})
```

**브리프 양식 (각 hypothesis별):**

```
당신은 자율 루프 이터레이션의 디버깅 Phase 3에서 단일 가설을 테스트한다.

## 검증할 가설

<가설 한 줄. 예: "X가 root cause다 — 근거는 Y">

## 테스트 셋업

[이 가설을 검증하기 위해 무엇을 변경/관찰해야 하는지 — 메인 이터가 명시]

## 할 일

1. 워크트리(`<worktree path>`)에서 가설을 검증할 수 있는 **최소 변경**만 적용 또는 **읽기만으로 관찰** (변경 없이 검증 가능하면 read-only)
2. 결과를 관찰하고 가설이 지지되는지 반박되는지 판단
3. 변경했다면 stash·revert로 깨끗한 상태로 복원 (메인 이터가 합성 후 결정)

## 중요

- 다른 가설을 추측·테스트하지 마라. 본 가설만.
- 메인 이터의 결정을 대신 내리지 마라.
- 워크트리 git history에 commit 남기지 마라 (stash·revert).

## 응답

```
가설: <가설 한 줄 재진술>
결과: 지지 | 반박 | 불명확
근거: <관찰한 사실 — 추측 금지>
변경 여부: 없음 | stash됨 (이름: <stash name>)
다음 단계 권고: <메인 이터에게>
```
```

**메인 이터의 후속 처리:**
- 두 가설의 보고를 합성·비교
- 더 잘 지지되는 가설을 §8.4 Implementation 단계로
- 둘 다 반박되면 새 가설로 §8.3 재시작 (조기 정지 조건 검사)

---

## 공통 주의

### 브리프 품질 (헌법 §11.6 핵심 원칙)

세 양식 모두 "자기완결 브리프" 원칙을 따른다. Agent는 메인 이터의 컨텍스트를 보지 못하므로 브리프에:
- **무엇을** — 정확한 작업·결과 형식
- **왜** — 상위 작업 맥락 (Agent가 판단할 수 있게)
- **이미 시도한 것** — 반복 방지
- **건너뛸 영역** — 범위 밖 표시
- **응답 포맷** — 메인 이터의 후속 처리에 필요한 형태

명령형 단문("X를 분석해 줘")은 얕은 결과를 부른다. 새로 출근한 시니어가 콜드 시작으로 작업 가능할 만큼의 정보를 담는다.

### Agent의 응답 검증

Agent의 보고는 **의도**이지 **사실**이 아니다 — 메인 이터는 보고를 받은 후:
- 변경 주장이 있으면 실제 git diff·파일 read로 확인
- 검증 통과 주장이 있으면 직접 명령 재실행
- 보고를 사용자에게 그대로 전달하지 않고 합성·요약

### 중첩 dispatch 금지

Agent가 또 Agent를 부르지 않는다. 합성·관찰 책임이 메인에서 이탈한다.

### 결정 위임 금지

"이 일을 누구에게 시킬지 정해 줘", "결과 보고 다음 단계도 정해서 진행해 줘" 같은 자기 위임은 §11.6 금지. Agent는 단일 패스 워커.
