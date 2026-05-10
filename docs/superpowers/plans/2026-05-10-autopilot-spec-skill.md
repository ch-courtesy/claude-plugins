# autopilot `spec` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** autopilot에 새로운 최상위 스킬 `spec`을 추가하여 대화형으로 `.loops/<task-id>/SPEC.md`를 생성. 기존 `loop prepare`는 help-text 스텁으로 대체.

**Architecture:** 신규 디렉터리 `plugins/autopilot/skills/spec/` 안에 SKILL.md + 4개 references. EARS 포맷·WHAT/HOW 방어선·`[NEEDS CLARIFICATION]` 마커·Independent-Test 규칙을 강성 장치로 도입. `loop start`는 SPEC.md에 잔존 마커 발견 시 abort.

**Tech Stack:** Claude Code skill (Markdown), Bash (loop.sh subcommand 수정), 기존 bash 통합 테스트(`tests/autopilot/test-loop-sh.sh`).

**Spec:** [docs/superpowers/specs/2026-05-10-autopilot-spec-skill-design.md](../specs/2026-05-10-autopilot-spec-skill-design.md)

---

## File Structure

**Create:**
- `plugins/autopilot/skills/spec/SKILL.md` — 스킬 진입점 (9단계 대화 흐름)
- `plugins/autopilot/skills/spec/references/spec-template.md` — 확장된 SPEC 템플릿 (EARS 슬롯·WHAT/HOW 방어선)
- `plugins/autopilot/skills/spec/references/ears-patterns.md` — 5개 EARS 패턴 사례·치팅 시트
- `plugins/autopilot/skills/spec/references/self-review.md` — 자체 검토 5항목 체크리스트
- `plugins/autopilot/skills/spec/references/decomposition-gate.md` — 다중 서브시스템 감지 가이드

**Modify:**
- `plugins/autopilot/skills/loop/SKILL.md` — prepare 서브커맨드 항목 삭제, spec 스킬 안내 추가
- `plugins/autopilot/skills/loop/references/loop.sh` — `cmd_start`에 마커 검사 게이트 추가, `cmd_prepare`를 help-text 스텁으로 교체
- `tests/autopilot/test-loop-sh.sh` — 기존 TEST 1·3 등 prepare 의존 테스트 갱신, 마커 게이트 신규 테스트 추가

**Delete:**
- `plugins/autopilot/skills/loop/references/prepare.md`
- `plugins/autopilot/skills/loop/references/spec-template.md` (spec 스킬로 이동된 후)

---

## Task 1: spec 스킬 디렉터리 + SKILL.md skeleton

**Files:**
- Create: `plugins/autopilot/skills/spec/SKILL.md`
- Create: `plugins/autopilot/skills/spec/references/.gitkeep`

- [ ] **Step 1: 디렉터리 + .gitkeep 생성**

```bash
mkdir -p plugins/autopilot/skills/spec/references
touch plugins/autopilot/skills/spec/references/.gitkeep
```

- [ ] **Step 2: SKILL.md skeleton 작성 (frontmatter만)**

`plugins/autopilot/skills/spec/SKILL.md`:
```markdown
---
name: spec
description: autopilot loop이 입력으로 받는 SPEC.md를 대화형으로 생성. 한 질문씩 명확화·섹션별 승인·EARS 포맷·[NEEDS CLARIFICATION] 마커로 자율 loop이 도중 질문 없이 완수 가능한 자기완결적 SPEC을 만듭니다. 호출 'Skill(skill: \"spec\", args: \"<task-id>\")' 또는 '<task-id> --resume'.
---

# spec

(본문은 Task 6에서 작성)
```

- [ ] **Step 3: 파일 존재 확인**

```bash
ls plugins/autopilot/skills/spec/SKILL.md
ls plugins/autopilot/skills/spec/references/
```
Expected: 두 경로 모두 출력됨, references는 `.gitkeep`만.

- [ ] **Step 4: 커밋**

```bash
git add plugins/autopilot/skills/spec/
git commit -m "feat(autopilot): spec 스킬 디렉터리 골격 생성"
```

---

## Task 2: spec/references/spec-template.md (확장 SPEC 템플릿)

**Files:**
- Create: `plugins/autopilot/skills/spec/references/spec-template.md`

이 템플릿은 기존 `plugins/autopilot/skills/loop/references/spec-template.md`에서 출발해 EARS 가이드와 WHAT/HOW 방어선을 추가한 형태. 기존 파일은 Task 10에서 삭제.

- [ ] **Step 1: 확장된 템플릿 작성**

`plugins/autopilot/skills/spec/references/spec-template.md`:
```markdown
---
scope:
  include:
    - src/**
    - tests/**
  exclude:
    - rules/**
    - .loops/**
    - CLAUDE.md
verify: "<실행 가능한 명령. 예: pnpm test --filter=feature-x. 0 exit이면 검증 통과>"
# test_paths (선택): 테스트 약화 게이트가 추적할 경로/파일명 패턴 (git pathspec).
#   미지정 시 기본 컨벤션(tests/·test/·__tests__/·spec/·src/test/ 디렉토리 +
#   *.test.{js,ts,jsx,tsx,py}·*.spec.{js,ts,rb}·*_test.{go,py,rb}·test_*.py·*_spec.rb)
#   비표준 컨벤션·언어(예: C++ *.t.cpp, Elixir test/) 시 명시.
# test_paths:
#   - "custom/test/**"
#   - "**/*.t.cpp"
---

# {{task_title}}

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 이 섹션은 *무엇을* 만드는지만 적습니다. 기술 스택·파일 경로·라이브러리·클래스명 등 구현 결정은 "제약" 섹션으로 옮기세요. loop이 자율적으로 접근법을 조정할 수 있도록 의도를 기술-중립적으로. -->
{{task_description}}

## 수용 기준 (EARS)
<!-- 5개 EARS 패턴 중 하나로 작성. 자세한 사례는 references/ears-patterns.md 참조.
  - Ubiquitous: "The system shall <응답>"
  - Event-driven: "When <트리거>, the system shall <응답>"
  - State-driven: "While <상태>, the system shall <지속 응답>"
  - Optional: "Where <조건>, the system shall <응답>"
  - Unwanted: "If <불가용/오류>, then the system shall <복구·거부>"
각 기준이 verify 명령 안에서 *어떤 형태로든* fail 가능해야 합니다 (Independent-Test 규칙). 불가능한 기준은 [NEEDS CLARIFICATION: <질문>]으로 표시. -->
{{acceptance_criteria}}

## 범위
포함:
{{scope_in}}

비-목표 / 제외:
{{scope_out}}

## 검증
이 명령이 0 exit으로 끝나야 합니다:
{{verify_command}}

## 제약 (있을 때만)
<!-- 환경·도구·호환성·성능 등 알려진 제약. 워커가 이를 모르면 잘못된 가정으로 시간 낭비.
  WHAT/HOW 방어선 결과 "무엇을 만들 것인가"에서 빠진 기술 스택·라이브러리·테스트 스타일 가이드도 여기에. -->
{{constraints}}

## 위험 (있을 때만)
<!-- 이미 알려진 dead-end·함정·금지 영역. 워커의 NOTES.md "실패한 접근"의 사전 시드. -->
{{risks}}
```

- [ ] **Step 2: 파일 검증**

```bash
test -f plugins/autopilot/skills/spec/references/spec-template.md && echo OK
grep -q '^## 수용 기준 (EARS)$' plugins/autopilot/skills/spec/references/spec-template.md && echo OK
grep -q 'WHAT/HOW 방어선' plugins/autopilot/skills/spec/references/spec-template.md && echo OK
```
Expected: `OK` 세 번 출력.

- [ ] **Step 3: 커밋**

```bash
git add plugins/autopilot/skills/spec/references/spec-template.md
git commit -m "feat(autopilot/spec): EARS·WHAT/HOW 가이드 포함 SPEC 템플릿 추가"
```

---

## Task 3: spec/references/ears-patterns.md (EARS 치팅 시트)

**Files:**
- Create: `plugins/autopilot/skills/spec/references/ears-patterns.md`

- [ ] **Step 1: EARS 패턴 가이드 작성**

`plugins/autopilot/skills/spec/references/ears-patterns.md`:
```markdown
# EARS 패턴 가이드

EARS = Easy Approach to Requirements Syntax. 5개 패턴으로 모호성 없는 수용 기준을 작성.

## 5개 패턴

### 1. Ubiquitous (무조건)
형식: `The system shall <응답>`

용례: 시스템의 *기본 행동*. 트리거나 조건 없이 항상 성립.

예시:
- The system shall log all authentication attempts.
- The system shall expire idle sessions after 30 minutes.

### 2. Event-driven (이벤트 기반)
형식: `When <트리거>, the system shall <응답>`

용례: 외부 입력·내부 이벤트로 촉발되는 행동.

예시:
- When a user submits an empty password, the system shall reject the request with a 400 status.
- When the refresh token expires, the system shall invalidate the session.

### 3. State-driven (상태 기반)
형식: `While <상태>, the system shall <지속 응답>`

용례: 시스템이 특정 상태일 때만 *지속적으로* 성립.

예시:
- While the database is in read-only mode, the system shall reject all write operations with 503.
- While a user is impersonated, the system shall include "X-Impersonated-By" in every response.

### 4. Optional (조건부 기능)
형식: `Where <조건>, the system shall <응답>`

용례: 특정 환경·feature flag·구성에서만 활성.

예시:
- Where the audit-log feature flag is enabled, the system shall record every state mutation.
- Where MFA is configured, the system shall require a second factor on login.

### 5. Unwanted behavior (불가용·오류)
형식: `If <불가용/오류>, then the system shall <복구·거부>`

용례: 실패·예외 상황의 명시적 처리.

예시:
- If the database connection fails, then the system shall return 503 with a retry-after header.
- If a webhook delivery fails three times, then the system shall mark the subscription as inactive.

## 자유 텍스트 → EARS 변환 가이드

자체 검토 단계에서 자유 텍스트가 발견되면 다음 휴리스틱으로 변환 시도:

| 자유 텍스트 시그널 | 추천 패턴 |
|---|---|
| "사용자가 X 하면 Y" | Event-driven (When) |
| "X 동안에는 Y" | State-driven (While) |
| "X 환경에서만 Y" | Optional (Where) |
| "X 실패 시 Y", "X 안 되면 Y" | Unwanted (If/then) |
| 위 어디에도 안 맞음 | Ubiquitous (그대로 "shall") |

변환 후 사용자에게 `AskUserQuestion`으로 적용 여부 확인. 거절 시 `[NEEDS CLARIFICATION: EARS 패턴으로 재작성 필요 — 원문: "<원문>"]` 마커 박음.

## Independent-Test 규칙

각 EARS 기준은 verify 명령 안에서 *어떤 형태로든 fail 가능*해야 합니다. 그렇지 않다면 검증되지 않는 기준이며 무의미.

자체 검토 시 각 기준에 대해:
- "이 기준이 위반되면 verify 명령이 0이 아닌 exit를 낼 수 있는가?"
- "어떤 테스트를 작성하면 이 기준의 위반을 잡을 수 있는가?" (loop이 결정할 일이지만, *원리적으로 가능한가*만 확인)

불가능한 기준은 `[NEEDS CLARIFICATION: 검증 가능한 형태로 재작성 — 어떤 fail 시나리오?]` 마커.
```

- [ ] **Step 2: 검증**

```bash
grep -q '^### 1. Ubiquitous' plugins/autopilot/skills/spec/references/ears-patterns.md && echo OK
grep -q 'Independent-Test' plugins/autopilot/skills/spec/references/ears-patterns.md && echo OK
```
Expected: `OK` 두 번.

- [ ] **Step 3: 커밋**

```bash
git add plugins/autopilot/skills/spec/references/ears-patterns.md
git commit -m "feat(autopilot/spec): EARS 5패턴 가이드 + Independent-Test 규칙 추가"
```

---

## Task 4: spec/references/self-review.md (자체 검토 체크리스트)

**Files:**
- Create: `plugins/autopilot/skills/spec/references/self-review.md`

- [ ] **Step 1: 자체 검토 체크리스트 작성**

`plugins/autopilot/skills/spec/references/self-review.md`:
```markdown
# SPEC 자체 검토 체크리스트

스킬은 SPEC.md 작성 직후 (단계 7 이후, 사용자 검토 단계 전) 다음 5항목을 자체 점검합니다. 발견 시 인라인 수정만 — 재루프 없음.

## 1. Placeholder 스캔

다음 패턴이 SPEC.md에 남아 있으면 안 됨:
- `{{...}}` 미치환 placeholder
- `TBD`, `TODO`, `FIXME`, `XXX`
- 빈 섹션 (헤더만 있고 본문 없음 — Constraints·Risks 제외)

발견 시: 가능하면 빠진 정보를 사용자에게 묻기 (`AskUserQuestion`) 또는 `[NEEDS CLARIFICATION: <구체 질문>]`로 박기.

## 2. 내부 모순 검사

다음 모순 패턴 자동 검사:
- "무엇을 만들 것인가"가 X를 명시했는데 "수용 기준"에 X 관련 기준 없음
- "범위.포함"과 "범위.비-목표"가 같은 경로 패턴을 모두 포함
- "검증" 명령이 "범위.포함"에 없는 디렉터리를 빌드·테스트
- frontmatter `scope.include`와 본문 "범위.포함"이 불일치

발견 시: 사용자에게 어느 쪽이 정답인지 묻고 통일.

## 3. 범위 검사

다음 신호가 있으면 범위 분해 필요:
- 수용 기준이 2개 이상의 *독립적* 기능 영역을 포함 (예: "로그인" + "결제")
- "무엇을 만들 것인가"에 "그리고", "또한", "추가로" 같은 접속사가 다중 등장
- `scope.include`가 5개 이상의 서로 다른 최상위 디렉터리를 포함

발견 시: 사용자에게 분해 제안 (`references/decomposition-gate.md` 참조).

## 4. 모호성 검사

다음 어휘는 모호 신호:
- "적절한", "충분한", "합리적인", "필요한 만큼" — *얼마나*가 안 정해짐
- "유저 친화적", "직관적", "심플하게" — 측정 불가
- "또는 비슷한", "등등", "기타" — 열거 미완

발견 시: 구체화 (수치·기준·예시) 또는 `[NEEDS CLARIFICATION: <구체 질문>]`.

## 5. EARS fail-가능성 검사

각 수용 기준에 대해:
- EARS 5패턴 중 하나에 맞는가? 안 맞으면 변환 시도 (`references/ears-patterns.md` 변환 가이드).
- verify 명령 안에서 *원리적으로* fail 가능한가? (실제 테스트 작성은 loop의 일이지만, 검증 가능성은 spec 단계에서 확인.)

불가능하면 `[NEEDS CLARIFICATION: 검증 가능한 형태로 재작성 — 어떤 fail 시나리오?]`.

## 검토 출력 형식

자체 검토 후 사용자에게:
- 0개 발견: "자체 검토 통과. 사용자 최종 검토로 진행합니다."
- 1개 이상: "자체 검토에서 N개 항목 인라인 수정·N개 마커 박음. 변경된 SPEC.md를 사용자 최종 검토하세요."
```

- [ ] **Step 2: 검증**

```bash
grep -c '^## ' plugins/autopilot/skills/spec/references/self-review.md
```
Expected: `6` (5 항목 + 검토 출력 형식 = 6 sections).

- [ ] **Step 3: 커밋**

```bash
git add plugins/autopilot/skills/spec/references/self-review.md
git commit -m "feat(autopilot/spec): 자체 검토 5항목 체크리스트 추가"
```

---

## Task 5: spec/references/decomposition-gate.md (범위 분해 가이드)

**Files:**
- Create: `plugins/autopilot/skills/spec/references/decomposition-gate.md`

- [ ] **Step 1: 분해 게이트 가이드 작성**

`plugins/autopilot/skills/spec/references/decomposition-gate.md`:
```markdown
# 범위 분해 게이트

단계 3에서 사용자 의도가 다중 독립 서브시스템을 포함하는지 검사하고, 그렇다면 분해를 제안합니다.

## 다중 서브시스템 감지 휴리스틱

다음 신호 중 2개 이상이 모이면 다중 가능성 높음:

1. **접속사 다중**: 사용자 발화에 "그리고", "또한", "+", "and"가 2회 이상 등장하며 각각 다른 명사를 잇는다 (예: "로그인 *그리고* 결제 *그리고* 메일링").
2. **명사 영역 다양성**: 핵심 명사들이 의미적으로 별 도메인 (auth · payment · notification · analytics 등).
3. **파일 트리 분산**: 관련 코드가 사전 컨텍스트 탐색에서 3개 이상의 최상위 디렉터리에 흩어져 있다.
4. **테스트 셋 분리**: 각 부분이 별도의 테스트 그룹·verify 명령을 요구한다.

## 분해 제안 흐름

다중 감지 시 사용자에게 `AskUserQuestion`:

```
"이 task는 N개의 독립 영역을 포함하는 것 같습니다:
  1. <영역 A 요약>
  2. <영역 B 요약>
  ...
이 경우 각각 별도 SPEC으로 진행하면 loop이 더 안정적으로 작동합니다.

(a) 분해 — 첫 영역만 본 spec 호출에서 진행, 나머지는 사용자가 별도 task-id로 새로 호출
(b) 단일로 강행 — 위험을 SPEC Risks에 기록하고 통합 SPEC 작성
(c) 다른 task-id로 시작 — 현재 호출 abort, 사용자가 다른 이름으로 다시"
```

## "단일 강행" 선택 시 처리

사용자가 (b) 선택 시:
- SPEC 작성 단계에서 "위험" 섹션에 한 줄 자동 추가:
  ```
  - 다중 영역으로 보일 수 있으나 단일 task로 진행 (사용자 확인됨, 2026-MM-DD).
  ```
- 진행하되 자체 검토 단계 #3 (범위 검사)에서 한 번 더 경고 (사용자 확인 받았음을 알고 통과시킬지, 아니면 마커 박을지는 자체 검토가 결정).

## "분해" 선택 시 처리

사용자가 (a) 선택 시:
- 첫 영역만 본 호출에서 진행
- 나머지 영역은 SPEC 작성 단계에서 본문 끝에 메모 추가:
  ```
  ## 후속 task (분해됨)
  이 SPEC은 분해된 첫 부분입니다. 후속:
  - <영역 B 요약> — 별도 task-id로 `Skill(skill: "spec", args: "<id-b>")` 호출
  - <영역 C 요약> — `Skill(skill: "spec", args: "<id-c>")` 호출
  ```
- 사용자에게 후속 호출 안내.

## 위양성 대응

게이트가 잘못 분해를 제안할 수 있음 (실제로는 단일 task인데 영역이 많아 보이는 경우). 사용자가 "단일 강행" 선택을 선택할 수 있게 옵션 (b)를 *항상* 제공.
```

- [ ] **Step 2: 검증**

```bash
grep -q '## 다중 서브시스템 감지 휴리스틱' plugins/autopilot/skills/spec/references/decomposition-gate.md && echo OK
grep -q '단일 강행' plugins/autopilot/skills/spec/references/decomposition-gate.md && echo OK
```
Expected: `OK` 두 번.

- [ ] **Step 3: 커밋**

```bash
git add plugins/autopilot/skills/spec/references/decomposition-gate.md
git commit -m "feat(autopilot/spec): 범위 분해 게이트 가이드 추가"
```

---

## Task 6: spec/SKILL.md 본문 작성 (9단계 + --resume)

**Files:**
- Modify: `plugins/autopilot/skills/spec/SKILL.md`

- [ ] **Step 1: SKILL.md 본문 추가**

`plugins/autopilot/skills/spec/SKILL.md` (기존 frontmatter 유지하고 그 아래에 본문 추가):
```markdown
---
name: spec
description: autopilot loop이 입력으로 받는 SPEC.md를 대화형으로 생성. 한 질문씩 명확화·섹션별 승인·EARS 포맷·[NEEDS CLARIFICATION] 마커로 자율 loop이 도중 질문 없이 완수 가능한 자기완결적 SPEC을 만듭니다. 호출 'Skill(skill: \"spec\", args: \"<task-id>\")' 또는 '<task-id> --resume'.
---

# spec

`autopilot:loop` 스킬이 입력으로 받는 `.loops/<task-id>/SPEC.md`를 대화형으로 생성. 자율 loop이 도중 질문 없이 완수할 수 있는 자기완결적 SPEC이 목표.

## 호출 방법

- 새 SPEC: `Skill(skill: "spec", args: "<task-id>")`
- 마커 해결 모드: `Skill(skill: "spec", args: "<task-id> --resume")`

또는 사용자가 자연어로 의도 전달 시 모델이 자동 호출.

## 9단계 워크플로

호출 시 다음 9단계를 TodoWrite로 등록·실행. 각 단계는 사용자 결정·승인을 `AskUserQuestion`으로 받습니다.

### 1. 사전 검사

- task-id 형식 검증: 비어 있거나 `..` / `/` 포함 시 abort
- **일반 모드**: `.loops/<task-id>/` 존재 시 abort + `AskUserQuestion`으로 3옵션 (다른 task-id / `--resume` / 백업 후 새로)
- **--resume 모드**: `.loops/<task-id>/SPEC.md` 부재 시 abort. 잔존 `[NEEDS CLARIFICATION` 마커 0개 시 "해결할 마커 없음" 안내 후 종료

### 2. 컨텍스트 탐색

다음 명령으로 프로젝트 컨텍스트 자동 수집 (사용자에게 요약만):
```
git log --oneline -5
ls -A          # 최상위 트리만 (재귀 없음)
cat CLAUDE.md  # 있으면
ls rules/      # 있으면
find . -maxdepth 3 -type d \( -name 'tests' -o -name 'test' -o -name '__tests__' -o -name 'spec' \) 2>/dev/null | head -5
```

목적: 테스트 컨벤션·CLAUDE.md 룰·디렉터리 구조 파악. 모노레포여도 단계 4에서 좁힐 것이므로 깊이 탐색 안 함.

### 3. 범위 분해 게이트

`references/decomposition-gate.md` 휴리스틱으로 다중 서브시스템 검사. 감지 시 사용자에게 분해 제안.

`--resume` 모드: 이 단계 생략 (이미 SPEC 존재).

### 4. 명확화 라운드

한 번에 한 질문 (`AskUserQuestion`, 가능하면 멀티초이스). 답변이 다음 질문 형태를 결정.

수집할 정보:
- task의 핵심 목적 (한 줄)
- 성공 기준 (어떻게 "완료"를 판정하는가)
- 알려진 제약 (환경·도구·호환성)
- 알려진 위험 (이미 시도한 dead-end·금지 영역)

`--resume` 모드: 마커가 박힌 섹션 관련 질문만.

### 5. 접근법 비교 (조건부)

명확화에서 task가 비-자명한 설계 결정을 포함한다고 판단되면 2-3 접근법 + 트레이드오프 + 추천 제시. 자명하면 생략.

판단 기준 (하나라도 해당):
- 사용자가 "어떻게 할까?" 묻거나 모호한 요구를 표현
- 영향 받는 코드 영역이 둘 이상의 명확히 다른 패턴 사이에서 선택을 요구
- 외부 의존성·라이브러리 선택이 task 결과에 큰 영향

### 6. 섹션별 SPEC 제시·승인

다음 순서로 한 섹션씩 사용자에게 제시 → `AskUserQuestion`으로 "이 섹션 OK?" 확인:
1. 제목
2. 무엇을 만들 것인가 (WHAT/HOW 방어선 적용 — 기술 스택·파일 경로·라이브러리·클래스명 금지)
3. 수용 기준 (EARS, `references/ears-patterns.md` 참조)
4. 범위 (포함·비-목표)
5. 검증 (실행 가능한 명령)
6. 제약 (있을 때만)
7. 위험 (있을 때만)

승인 안 받은 섹션은 다시 제시·수정. 한 번에 통째로 보여주지 않음.

`--resume` 모드: 마커가 박힌 섹션만.

### 7. SPEC.md 작성

`references/spec-template.md` 읽어 placeholder 치환:
- `{{task_title}}` → 단계 6에서 합의된 제목 (없으면 task-id 그대로)
- `{{task_description}}` → 섹션 2 합의 내용
- `{{acceptance_criteria}}` → 섹션 3 합의 내용 (EARS 포맷)
- `{{scope_in}}` / `{{scope_out}}` → 섹션 4
- `{{verify_command}}` → 섹션 5
- `{{constraints}}` / `{{risks}}` → 섹션 6/7. 빈 값이면 빈 줄 한 줄로 치환 (헤더는 남김)
- frontmatter `scope.include`·`verify`도 동일 치환

미해결 항목은 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 박은 채 작성.

`mkdir -p .loops/<task-id>` 후 SPEC.md 기록.

### 8. 자체 검토

`references/self-review.md` 5항목 체크 (placeholder · 모순 · 범위 · 모호성 · EARS fail-가능성). 발견 시 인라인 수정 후 SPEC.md 재기록. 재루프 없음.

### 9. 사용자 최종 검토

SPEC.md 경로·요약 안내 + `AskUserQuestion`으로 검토 결과 수집:
- 승인: 다음 단계 안내 출력 — *"SPEC 완성: .loops/<task-id>/SPEC.md\n다음 단계: Skill(skill: \"loop\", args: \"start <task-id>\")"*
- 변경: 어느 섹션을 변경할지 묻고 단계 6/7 재진입

## --resume 모드 요약

위 9단계 중:
- 1: 마커 0개 시 즉시 종료
- 3, 4, 5: 마커 위치 기준으로 좁힘
- 6: 마커 박힌 섹션만
- 나머지 동일

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `spec-template.md` | SPEC.md placeholder 템플릿 (EARS 가이드·WHAT/HOW 방어선 주석 포함) |
| `ears-patterns.md` | 5개 EARS 패턴 사례·자유 텍스트→EARS 변환 가이드·Independent-Test 규칙 |
| `self-review.md` | 자체 검토 5항목 체크리스트 |
| `decomposition-gate.md` | 다중 서브시스템 감지 휴리스틱·분해 제안 흐름 |

## 규칙

- 본 스킬은 target 프로젝트의 `.loops/<task-id>/SPEC.md`만 작성한다. 다른 파일 생성·수정 안 함.
- 모든 결정·선택·확인은 `AskUserQuestion`으로. 자유 텍스트 끝에 질문 종결구 다는 방식 금지 (CLAUDE.md 규칙).
- 한 번에 한 질문. 여러 질문 묶어 묻지 않는다 (단, `AskUserQuestion` 호출은 최대 4문항까지 가능).
- `[NEEDS CLARIFICATION` 마커는 `loop start`에서 차단됨. 사용자에게 명시적으로 마커가 박혔음을 알리고 `--resume`으로 해결하도록 안내.
```

- [ ] **Step 2: 검증**

```bash
grep -c '^### [0-9]\.' plugins/autopilot/skills/spec/SKILL.md
grep -q 'NEEDS CLARIFICATION' plugins/autopilot/skills/spec/SKILL.md && echo OK
grep -q '\-\-resume' plugins/autopilot/skills/spec/SKILL.md && echo OK
```
Expected: `9` (9단계), `OK`, `OK`.

- [ ] **Step 3: 커밋**

```bash
git add plugins/autopilot/skills/spec/SKILL.md
git commit -m "feat(autopilot/spec): 9단계 대화 흐름 + --resume 모드 SKILL.md"
```

---

## Task 7: loop.sh의 cmd_start에 [NEEDS CLARIFICATION] 차단 게이트 (TDD)

**Files:**
- Modify: `tests/autopilot/test-loop-sh.sh` (테스트 추가)
- Modify: `plugins/autopilot/skills/loop/references/loop.sh` (`cmd_start` 수정)

- [ ] **Step 1: 실패하는 테스트 추가**

먼저 현재 마지막 TEST 번호를 확인:

```bash
grep -n '^echo "=== TEST' tests/autopilot/test-loop-sh.sh | tail -1
```
Expected: `TEST 20` 라인이 마지막. 따라서 새 테스트는 `TEST 21`. (만약 다른 task가 새 테스트를 미리 추가했다면 그 번호 + 1로 조정.)

`tests/autopilot/test-loop-sh.sh`의 파일 끝(마지막 `echo "OK"` 다음)에 다음 블록을 그대로 추가:

```bash

echo "=== TEST 21: SPEC.md에 [NEEDS CLARIFICATION] 잔존 시 start 거부 ==="
# task 디렉터리·SPEC 시드
mkdir -p .loops/needs-clar-task
cat > .loops/needs-clar-task/SPEC.md <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Test SPEC

## 무엇을 만들 것인가
Test task with unresolved marker

## 수용 기준
- A1: When the user logs in, the system shall authenticate.
- [NEEDS CLARIFICATION: 어떤 인증 방식? OAuth/SSO/email-password?]

## 범위
포함:
src/

비-목표 / 제외:
none

## 검증
true
EOF

set +e
output=$(MAX_ITERATIONS=1 loop start needs-clar-task 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 마커 잔존 SPEC으로 start가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "NEEDS CLARIFICATION\|spec.*resume" || { echo "FAIL: 마커 안내 메시지 없음. got: $output"; exit 1; }
# 락 안 잡혀야 함
[[ ! -f .loops/locks/needs-clar-task.lock ]] || { echo "FAIL: 차단 됐어야 하는데 락 잡힘"; exit 1; }
echo "OK"
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
bash tests/autopilot/test-loop-sh.sh
```
Expected: 새 TEST에서 FAIL 출력 (현재 코드는 마커 검사 없음).

- [ ] **Step 3: cmd_start에 마커 검사 추가**

`plugins/autopilot/skills/loop/references/loop.sh`의 `cmd_start` 함수 안에, "# 2. SPEC.md 존재 확인" 블록 *직후·*"# 3. placeholder 검사" 블록 *직전*에 새 블록을 삽입.

Edit으로 이 정확한 텍스트를 매칭해서 교체:

old:
```
  # 2. SPEC.md 존재 확인
  local spec_path_local="$LOOPS_DIR/SPEC.md"
  if [[ ! -f "$spec_path_local" ]]; then
    die "SPEC.md가 없습니다. 먼저 실행하세요: $0 prepare $task_id"
  fi

  # 3. placeholder 검사
```

new:
```
  # 2. SPEC.md 존재 확인
  local spec_path_local="$LOOPS_DIR/SPEC.md"
  if [[ ! -f "$spec_path_local" ]]; then
    die "SPEC.md가 없습니다. 먼저 실행하세요: Skill(skill: \"spec\", args: \"$task_id\")"
  fi

  # 2.5. [NEEDS CLARIFICATION] 마커 검사 (락 획득 전)
  if grep -q '\[NEEDS CLARIFICATION' "$spec_path_local"; then
    die "SPEC.md에 미해결 [NEEDS CLARIFICATION] 마커가 있습니다.\n해결: Skill(skill: \"spec\", args: \"$task_id --resume\")"
  fi

  # 3. placeholder 검사
```

(이 교체로 두 가지가 함께 처리됨: 마커 차단 게이트 추가 + 기존 prepare 안내 메시지를 spec 스킬 안내로 갱신. prepare 서브커맨드는 Task 8에서 스텁화되므로 안내 메시지 정합성을 미리 맞춤.)

- [ ] **Step 4: 테스트 통과 확인**

```bash
bash tests/autopilot/test-loop-sh.sh
```
Expected: 모든 TEST PASS.

- [ ] **Step 5: 커밋**

```bash
git add plugins/autopilot/skills/loop/references/loop.sh tests/autopilot/test-loop-sh.sh
git commit -m "feat(autopilot/loop): start에 [NEEDS CLARIFICATION] 차단 게이트 추가"
```

---

## Task 8: loop.sh cmd_prepare를 help-text 스텁으로 교체 (TDD)

**Files:**
- Modify: `tests/autopilot/test-loop-sh.sh` (TEST 1 갱신, TEST 3·10·11 보조 setup 변경)
- Modify: `plugins/autopilot/skills/loop/references/loop.sh` (`cmd_prepare` 함수 단순화)

- [ ] **Step 1: TEST 1을 "스텁 동작 검증"으로 재작성**

`tests/autopilot/test-loop-sh.sh`의 기존 TEST 1 블록 전체를 다음 블록으로 Edit 교체. 매칭 anchor는 `echo "=== TEST 1:`로 시작해서 다음 `echo "=== TEST 2:` 직전까지 (사이의 `echo "OK"` 포함). Edit으로 old 블록 전체를 인용 → new 블록으로 치환.

new 블록:
```bash
echo "=== TEST 1: prepare는 spec 스킬로 안내하는 스텁 ==="
set +e
output=$(loop prepare test-task-1 2>&1)
result=$?
set -e
# 스텁이므로 0이 아닌 exit + 안내 메시지
[[ $result -ne 0 ]] || { echo "FAIL: 스텁이 0 exit으로 끝남 (사용자가 sp 스킬로 가도록 유도해야)"; exit 1; }
echo "$output" | grep -q "spec\|이전" || { echo "FAIL: spec 스킬 안내 없음. got: $output"; exit 1; }
# .loops 디렉터리·SPEC.md 미생성 확인
[[ ! -d "$PROJECT/.loops/test-task-1" ]] || { echo "FAIL: 스텁이 디렉터리 만들면 안 됨"; exit 1; }
echo "OK"
```

- [ ] **Step 2: prepare 의존 setup을 명시적 mkdir로 갱신**

먼저 prepare에 의존하는 모든 위치를 스캔:

```bash
grep -n 'loop prepare\|LOOPS_TASK_DIR=' tests/autopilot/test-loop-sh.sh
```

TEST 1이 더 이상 `.loops/<id>/` 디렉터리·SPEC.md를 만들어 두지 않으므로, 그 결과물에 의존하던 후속 TEST에 명시적 setup을 추가. 영향받는 위치 (현재 파일 기준):

1. **TEST 3 직전**: 기존엔 TEST 1이 만든 `LOOPS_TASK_DIR` 변수와 디렉터리에 의존. Edit으로 `echo "=== TEST 3: start로 워크트리 생성 + 1 이터 (mock claude로 즉시 DONE) ==="` 라인 *직전*에 다음 두 줄 삽입:
   ```bash
   LOOPS_TASK_DIR="$PROJECT/.loops/test-task-1"
   mkdir -p "$LOOPS_TASK_DIR"
   ```

2. **TEST 10·11**: `grep -n 'loop prepare' tests/autopilot/test-loop-sh.sh` 결과로 위치 확인. 각 `loop prepare <id>` 호출 라인을 Edit으로 `mkdir -p "$PROJECT/.loops/<id>"` (해당 task-id로 치환)으로 교체. SPEC.md 자체가 필요한 테스트라면 그 다음 `cat > "$PROJECT/.loops/<id>/SPEC.md" <<'EOF' ... EOF` 구문을 추가.

3. **다른 위치 발견 시**: 위 grep이 잡은 모든 라인에 동일 패턴 적용. 변수에 의존하는지(`$LOOPS_TASK_DIR` 등) 확인하고 필요 시 명시적 정의.

- [ ] **Step 3: 테스트 실행 — 일부는 PASS, TEST 1은 FAIL 예상**

```bash
bash tests/autopilot/test-loop-sh.sh
```
Expected: TEST 1에서 FAIL (현재 코드는 prepare가 SPEC.md를 정상 생성하므로).

- [ ] **Step 4: cmd_prepare를 help-text 스텁으로 교체**

`plugins/autopilot/skills/loop/references/loop.sh`의 `cmd_prepare()` 함수 본문 전체를 스텁으로 교체.

위치 anchor: `cmd_prepare() {` 라인부터 다음 함수 정의 `cmd_start() {` *직전* 닫는 `}` 까지 (그 사이 빈 줄 1줄 포함). Edit으로 그 블록 전체를 인용해 다음 블록으로 치환:

```bash
cmd_prepare() {
  cat >&2 <<'EOF'
prepare 서브커맨드는 제거되었습니다.
새 spec 스킬을 사용하세요:

  Skill(skill: "spec", args: "<task-id>")

대화형으로 SPEC.md를 생성합니다. 자세한 내용:
  plugins/autopilot/skills/spec/SKILL.md
EOF
  exit 2
}
```

URL 대신 저장소 내부 상대 경로를 사용해 외부 호스팅 변경에 비의존적으로. 함수 종료 후 빈 줄 1줄을 그대로 두고 `cmd_start() {`로 이어지도록 유지.

- [ ] **Step 5: 테스트 통과 확인**

```bash
bash tests/autopilot/test-loop-sh.sh
```
Expected: 모든 TEST PASS.

- [ ] **Step 6: 커밋**

```bash
git add plugins/autopilot/skills/loop/references/loop.sh tests/autopilot/test-loop-sh.sh
git commit -m "feat(autopilot/loop): prepare 서브커맨드를 help-text 스텁으로 교체"
```

---

## Task 9: loop SKILL.md 갱신 (prepare 항목 제거 + spec 안내)

**Files:**
- Modify: `plugins/autopilot/skills/loop/SKILL.md`

- [ ] **Step 1: prepare 서브커맨드 항목 삭제**

`plugins/autopilot/skills/loop/SKILL.md`에서 "### prepare <task-id>" 섹션 전체를 삭제. Edit으로 다음 정확한 텍스트(끝의 빈 줄 1개 포함)를 매칭해서 빈 문자열로 치환:

old:
```
### prepare <task-id>

새 task를 위한 SPEC.md를 인터랙티브하게 생성.

자세한 절차는 `references/prepare.md` 참조.

요약:
1. `.loops/<task-id>/` 이미 있으면 abort
2. `mkdir -p .loops/<task-id>`
3. `AskUserQuestion`으로 task 정보 수집 (task title, task description, acceptance criteria, scope.include/exclude, verify 명령)
4. 수집된 값으로 `references/spec-template.md` placeholder 치환 후 `.loops/<task-id>/SPEC.md` 작성
5. 사용자에게 다음 단계(start) 안내

```

new (빈 문자열). 이 교체로 그 다음 `### start <task-id>` 섹션이 바로 이어짐.

- [ ] **Step 2: spec 스킬 안내를 "Subcommand" 섹션 위에 추가**

"## Subcommand" 헤더 *바로 위*에 새 섹션 추가:
```markdown
## SPEC.md 생성

새 task의 SPEC.md는 별도 스킬 `autopilot:spec`에서 대화형으로 생성합니다:

```
Skill(skill: "spec", args: "<task-id>")
```

자세한 흐름은 `plugins/autopilot/skills/spec/SKILL.md` 참조. SPEC 작성이 끝나면 본 스킬의 `start` 서브커맨드로 이어 호출.

```

- [ ] **Step 3: 모듈 구성 표에서 prepare.md·spec-template.md 행 삭제**

Edit으로 다음 두 행을 각각 빈 문자열로 치환 (한 행씩 정확히 매칭):

old (1):
```
| `spec-template.md` | 새 task SPEC.md 시드 (placeholder 7종) |
```
→ 삭제 (spec 스킬로 이동).

old (2):
```
| `prepare.md` | prepare 인터랙티브 절차 상세 |
```
→ 삭제.

- [ ] **Step 4: "첫 호출 시 setup" 섹션의 prepare 언급 제거**

Edit으로:

old:
```
target 프로젝트에 `.loops/locks/` 부재 시 prepare/start 첫 호출에 자동:
```

new:
```
target 프로젝트에 `.loops/locks/` 부재 시 start 첫 호출에 자동:
```

- [ ] **Step 5: 검증**

```bash
grep -q '^### prepare' plugins/autopilot/skills/loop/SKILL.md && { echo FAIL; exit 1; } || echo OK
grep -q 'autopilot:spec\|Skill(skill: "spec"' plugins/autopilot/skills/loop/SKILL.md && echo OK
grep -q '`prepare.md`\|`spec-template.md`' plugins/autopilot/skills/loop/SKILL.md && { echo FAIL; exit 1; } || echo OK
```
Expected: `OK` 세 번.

- [ ] **Step 6: 커밋**

```bash
git add plugins/autopilot/skills/loop/SKILL.md
git commit -m "docs(autopilot/loop): SKILL.md에서 prepare 항목 제거, spec 스킬 안내 추가"
```

---

## Task 10: 구파일 정리 (prepare.md·spec-template.md 삭제 + 최종 검증)

**Files:**
- Delete: `plugins/autopilot/skills/loop/references/prepare.md`
- Delete: `plugins/autopilot/skills/loop/references/spec-template.md`

- [ ] **Step 1: 두 파일 삭제**

```bash
git rm plugins/autopilot/skills/loop/references/prepare.md
git rm plugins/autopilot/skills/loop/references/spec-template.md
```

- [ ] **Step 2: 다른 파일에서 두 파일 참조 잔존 검사**

```bash
grep -rn 'references/prepare\.md\|loop/references/spec-template' plugins/ tests/ docs/ 2>/dev/null
```
Expected: 결과 없음 (또는 historical 문서·이 plan 자체만 매치).

만약 참조가 남아 있으면 해당 파일을 함께 수정. (loop.sh의 `$SCRIPT_DIR/spec-template.md` 참조는 cmd_prepare 스텁화 시점에 이미 제거됨.)

- [ ] **Step 3: 전체 테스트 실행**

```bash
bash tests/autopilot/test-loop-sh.sh
bash tests/autopilot/test-skill-install.sh
```
Expected: 둘 다 모든 TEST PASS.

- [ ] **Step 4: 수동 smoke verification (선택, 환경 허용 시)**

실제 Claude Code 환경에서:
1. `Skill(skill: "spec", args: "smoke-1")` → 9단계 대화 진행 → SPEC.md 생성 확인
2. SPEC.md에 일부러 `[NEEDS CLARIFICATION: 임시]` 추가
3. `Skill(skill: "loop", args: "start smoke-1")` → exit 2 + 안내 출력 확인
4. 마커 제거 후 다시 start → 정상 시작 확인

수동 검증을 자동화 못 하면 이 단계는 변경 후 PR 리뷰에서 reviewer가 시연하도록 메모.

- [ ] **Step 5: 커밋**

```bash
git commit -m "chore(autopilot/loop): 사용되지 않는 prepare.md·spec-template.md 삭제"
```

---

## Verification

### 자동 검증 (PR CI/로컬)

```bash
# loop.sh 통합 테스트
bash tests/autopilot/test-loop-sh.sh

# 스킬 설치 테스트
bash tests/autopilot/test-skill-install.sh

# 새 spec 스킬의 references 파일 존재
ls plugins/autopilot/skills/spec/references/
# Expected: ears-patterns.md  self-review.md  spec-template.md  decomposition-gate.md

# loop SKILL.md에 prepare 흔적 없음
grep -q '^### prepare' plugins/autopilot/skills/loop/SKILL.md && echo "FAIL: prepare 흔적" || echo OK

# 구파일 부재
[[ ! -f plugins/autopilot/skills/loop/references/prepare.md ]] && echo OK
[[ ! -f plugins/autopilot/skills/loop/references/spec-template.md ]] && echo OK
```

### 수동 시나리오 (실제 사용 시뮬레이션)

1. **Happy path**: 빈 task-id로 spec 스킬 호출 → 9단계 진행 → 마커 없는 SPEC.md → `loop start` 정상 동작
2. **마커 차단**: 마커 박힌 SPEC으로 `loop start` → exit 2 + spec --resume 안내 출력
3. **--resume**: 마커 잔존 SPEC에 `Skill(skill: "spec", args: "id --resume")` → 마커 섹션만 묻고 나머지 안 건드림
4. **prepare 호출**: `Skill(skill: "loop", args: "prepare foo")` → exit 2 + spec 스킬 안내 출력, SPEC.md 미생성
5. **EARS 변환**: 자유 텍스트 acceptance 입력 → 자체 검토에서 자동 변환 제안
6. **분해 게이트**: 다중 서브시스템 task 입력 → 분해 제안 표시
7. **WHAT/HOW 방어선**: "무엇을 만들 것인가"에 "FastAPI로 구현" 같은 기술 스택 → 자체 검토에서 Constraints 이동 권유

### 회귀 가능성

- 기존 `.loops/<task-id>/SPEC.md`이 이미 있는 사용자 — 새 spec 스킬은 디렉터리 존재 시 abort + 3옵션 (다른 id / `--resume` / 백업). 데이터 손실 없음.
- 기존 `loop start --spec <외부파일>` 사용자 — 영향 없음 (외부 SPEC을 직접 전달하는 경로는 그대로).
- prepare를 자동화 스크립트에서 호출하던 사용자 — exit 2 + 안내. 스크립트 갱신 필요 (의도된 변경).
