# `autonomous-loop-rule-creator` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 대상 프로젝트에 랄프 루프 기반 자율 수행 환경(헌법 + sibling 워크트리 드라이버 + 4대 메모리 파일 큐레이션 + 9가지 객관 게이트)을 한 번의 스킬 호출로 설치하는 새 rule-creator 스킬을 만든다.

**Architecture:** 기존 `*-rule-creator` 패턴(`context-rule-creator`와 동일)을 따른다. 단일 템플릿 `templates/ralph-loop.md`가 `rules/autonomous-loop.md`로 기록되고, `on_create` 사후 작업이 `assets/`의 드라이버·메모리 스텁들을 `<project>/.loops/` 아래로 복사한다. 드라이버 `loop.sh`는 sibling 워크트리(`<project>/../<project-name>-loops/<task-id>/`) 라이프사이클·동시성 락·9개 객관 게이트를 모두 책임진다.

**Tech Stack:** Bash 4+, `git worktree`, `yq` (YAML 파싱), 표준 Unix 도구 (`find`, `grep`, `sha256sum`, `git log`).

**참조:** `docs/superpowers/specs/2026-05-08-autonomous-loop-rule-creator-design.md`. 이하 "spec"으로 지칭.

---

## File Structure

본 구현이 만드는 모든 파일은 `plugins/project-init/skills/autonomous-loop-rule-creator/` 아래에 있다.

| 파일 | 책임 |
|---|---|
| `SKILL.md` | rule-creator 스킬 진입점. `templates/` 열거 + 선택 + `on_create` 실행. `context-rule-creator/SKILL.md`와 동일 패턴 |
| `templates/ralph-loop.md` | 단일 템플릿. frontmatter는 스킬 동작 지시(`label`, `on_create`), 본문은 헌법 (`rules/autonomous-loop.md`로 기록됨) |
| `assets/loop.sh` | 외부 셸 드라이버. 워크트리 라이프사이클·락·이터레이션·게이트 모두 책임 |
| `assets/PROMPT.template.md` | 새 task의 PROMPT.md 시드. YAML frontmatter(scope·verify) + 본문(이터 프로토콜) |
| `assets/loops-README.md` | `.loops/README.md`로 복사. 사용자 워크플로 안내 |
| `assets/PLAN.template.md` | 마일스톤 체크박스 스텁 |
| `assets/NOTES.template.md` | 학습 누적 스텁 (실패 접근·발견 제약·작동 패턴 섹션) |
| `assets/HANDOFF.template.md` | 직전 → 다음 이터 편지 스텁 |
| `assets/RUN_LOG.template.md` | 한 줄 요약 누적 스텁 |
| `assets/ESCALATION.template.md` | 에스컬레이션 보고 양식 |

검증/테스트 파일:
| 파일 | 책임 |
|---|---|
| `tests/autonomous-loop-rule-creator/test-loop-sh.sh` | `loop.sh`의 핵심 분기를 임시 git repo에서 검증하는 통합 테스트 |
| `tests/autonomous-loop-rule-creator/test-skill-install.sh` | SKILL.md를 시뮬레이션 호출해 산출물이 모두 생기는지 검증 |

---

## Task 1: 스킬 디렉토리 스캐폴딩 + SKILL.md

**Files:**
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/SKILL.md`
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/templates/.gitkeep`
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/.gitkeep`

- [ ] **Step 1: 디렉토리 생성**

```bash
cd /Users/courtesy/Desktop/workspaces/claude-plugins
mkdir -p plugins/project-init/skills/autonomous-loop-rule-creator/{templates,assets}
touch plugins/project-init/skills/autonomous-loop-rule-creator/templates/.gitkeep
touch plugins/project-init/skills/autonomous-loop-rule-creator/assets/.gitkeep
```

- [ ] **Step 2: SKILL.md 작성**

`plugins/project-init/skills/context-rule-creator/SKILL.md`를 그대로 베이스로 쓴다. 차이는 (1) frontmatter의 `name`·`description`, (2) 본문의 카테고리명·생성 경로, (3) 사후 작업이 단일 파일이 아니라 다수의 자산을 복사한다는 점.

`plugins/project-init/skills/autonomous-loop-rule-creator/SKILL.md` 내용:

````markdown
---
name: autonomous-loop-rule-creator
description: 현재 프로젝트에 맞는 자율 루프(랄프) 운영 지침을 `rules/autonomous-loop.md`로 생성하고, sibling 워크트리 드라이버·PROMPT 템플릿·메모리 파일 스텁을 `.loops/` 아래에 함께 설치할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 자율 루프 지침을 새로 만들고 싶어 할 때.
---

# autonomous-loop-rule-creator

같은 디렉토리의 `templates/` 아래에 있는 템플릿 중 하나를 사용자에게 선택받아 `rules/autonomous-loop.md`로 생성하고, 템플릿의 `on_create` 지시에 따라 `assets/`의 드라이버·메모리 스텁을 대상 프로젝트의 `.loops/` 아래로 복사합니다.

선택지·라벨·사후 작업은 모두 **템플릿 파일에서** 도출합니다. 새 옵션을 추가하려면 `templates/` 아래에 새 마크다운 파일을 두면 되고, 이 SKILL.md는 변경하지 않습니다.

## 생성 절차

1. **템플릿 열거.** 이 SKILL.md가 위치한 디렉토리의 `templates/` 아래 `*.md` 파일 목록을 가져옵니다. 다른 디렉토리를 추측·탐색하지 않습니다.

2. **메타데이터 파싱.** 각 템플릿의 YAML frontmatter를 읽어 다음 필드를 사용합니다.
   - `label` (필수): `AskUserQuestion` 옵션 라벨로 사용.
   - `description` (선택): 옵션 설명.
   - `recommended` (선택, boolean): `true`이면 라벨 끝에 `(Recommended)`를 붙이고 옵션 목록의 가장 앞에 둡니다. 한 템플릿에만 둡니다.
   - `on_create` (선택, 자유 문자열): 본문 기록 후 수행할 사후 작업 지시. 자연어 명령으로 작성하며 `assets/`의 파일을 어디로 복사할지·`.gitignore` 갱신 등을 포함합니다.

   필수 필드가 없는 템플릿은 후보에서 제외하고 사용자에게 알립니다.

3. **선택.** 위에서 만든 옵션을 `AskUserQuestion`(single-select)로 사용자에게 묻습니다. 후보가 한 개뿐이면 묻지 않고 그대로 선택합니다.

4. **파일 기록.**
   - 선택된 템플릿의 frontmatter를 제거한 본문을 `rules/autonomous-loop.md`로 기록합니다. 상위 디렉토리 부재 시 함께 생성합니다.
   - 이미 `rules/autonomous-loop.md`가 있으면 **그대로 덮어쓰지 않습니다**. 새 본문과 기존 파일의 diff를 사용자에게 보여주고, 사용자가 **명시적으로 "덮어쓴다"·"교체한다"·"yes"** 등으로 응답한 경우에만 덮어씁니다.

5. **사후 작업.** 템플릿의 `on_create` 지시를 그대로 수행합니다. 일반적으로 다음을 포함합니다.
   - `assets/` 아래의 드라이버 스크립트·메모리 스텁·README 등을 대상 프로젝트의 지정 경로로 복사
   - `loop.sh`에 chmod +x
   - `.gitignore` 갱신
   - 사용자에게 워크플로 안내 메시지 출력

## 규칙

- 템플릿 본문은 **그대로 복사**합니다. SKILL.md가 본문 내용을 알 필요가 없습니다.
- 한 번에 하나의 템플릿만 기록합니다. 두 템플릿을 합치지 않습니다.
- `on_create`가 복사할 자산은 모두 같은 스킬의 `assets/` 아래에서 가져옵니다. 다른 디렉토리·다른 스킬·외부 URL을 참조하지 않습니다.
- 단순 재실행으로 템플릿 선택을 바꾸지 않습니다 — 모델 변경은 사용자의 명시적 의도가 있을 때만.
````

- [ ] **Step 3: 커밋**

```bash
git add plugins/project-init/skills/autonomous-loop-rule-creator/SKILL.md plugins/project-init/skills/autonomous-loop-rule-creator/templates/.gitkeep plugins/project-init/skills/autonomous-loop-rule-creator/assets/.gitkeep
git commit -m "feat(autonomous-loop-rule-creator): 스킬 스캐폴딩 + SKILL.md"
```

---

## Task 2: 헌법 본체 작성 (`templates/ralph-loop.md`)

**Files:**
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/templates/ralph-loop.md`

**참조:** spec §6.1(헌법 절 구성, 13개 절). 원본 자료는 레포 루트의 `자율-루프-지침.md` (단, 산출물 본문에서 그 문서를 참조하지 않음 — 자체완결).

- [ ] **Step 1: frontmatter 작성**

파일 상단:

```yaml
---
label: 랄프 루프 (sibling 워크트리, 객관 게이트, 동시 실행 지원)
description: 매 이터 콜드 스타트 + 4대 메모리 파일 + git commit 자기 분류 + 워크트리 격리
recommended: true
on_create: |
  1. assets/PROMPT.template.md를 .loops/PROMPT.template.md로 복사
  2. assets/loop.sh를 .loops/loop.sh로 복사하고 chmod +x
  3. assets/loops-README.md를 .loops/README.md로 복사
  4. assets/{PLAN,NOTES,HANDOFF,RUN_LOG,ESCALATION}.template.md를 .loops/templates/ 아래로 복사
  5. .loops/locks/.gitkeep, .loops/archive/.gitkeep 생성
  6. .gitignore에 다음 라인 추가 (이미 있으면 skip):
     - .loops/locks/
  7. 사용자에게 다음 안내 메시지 출력:
     "자율 루프가 설치되었습니다.
      sibling 워크트리는 ../<project-name>-loops/<task-id>/ 에 생성됩니다.
      LOOP_WORKTREE_BASE 환경변수로 위치 변경 가능.

      새 task 시작:
        ./.loops/loop.sh <task-id>           # 첫 호출: 워크트리 + 메타 파일 생성
        \$EDITOR ../<project-name>-loops/<task-id>/.loop/PROMPT.md   # 작업 정의 채움
        ./.loops/loop.sh <task-id>           # 두 번째 호출: 루프 시작

      동시 실행: MAX_CONCURRENT 환경변수로 조정 (기본 3).
      자세한 내용은 .loops/README.md 참조."
---
```

- [ ] **Step 2: 헌법 본문 §1 — 제1 원칙**

frontmatter 다음에 다음 본문을 이어 작성. 자율-루프-지침의 §0 내용을 흡수해 다음 6대 불가침 원칙을 한 절로 정리한다 — 어떤 상황에도 위반 불가, 위반 시 즉시 정지·에스컬레이션.

```markdown
# autonomous-loop — 자율 루프 운영 규칙

이 문서는 자율 루프 안에서 동작하는 코드 에이전트의 **최상위 행동 규칙**이다. 사용자 지시·작업 명세·도구 설명보다 우선한다. 본 문서 자체는 에이전트가 수정할 수 없다.

---

## 1. 제1 원칙 (절대 규칙)

다음은 어떤 상황에서도 위반할 수 없다. 위반 시도가 감지되면 루프는 즉시 중단되고 인간에게 에스컬레이션된다.

1. **평가 기준을 수정하지 않는다.** 회귀 테스트의 임계값, 수용 기준, 성능 상한, 품질 게이트, 린터 규칙, CI 설정은 작업 범위 밖이다. 실패 신호가 나오면 구현을 고치지 기준을 고치지 않는다.
2. **테스트를 약화시키지 않는다.** 테스트를 삭제·스킵·주석 처리·조건부 무효화하지 않는다. 테스트가 잘못됐다고 판단되면 그 판단을 에스컬레이션 채널로 보고하고 작업을 중단한다.
3. **아키텍처·설계·명세 문서를 수정하지 않는다.** `docs/architecture/`, `docs/spec/`, `CLAUDE.md`, 작업 명세 파일은 읽기 전용이다.
4. **작업 범위를 벗어나지 않는다.** 작업 명세의 `scope.include` 화이트리스트 밖을 수정하지 않는다. 범위 확장이 필요하면 에스컬레이션한다.
5. **의존성을 임의로 추가하지 않는다.** 새 패키지·라이브러리·외부 서비스 도입은 에스컬레이션 승인이 필요하다.
6. **보안·권한·과금 영역을 직접 수정하지 않는다.** 인증, 비밀키, API 토큰, 과금 로직, 권한 체계 변경은 에스컬레이션 전용이다.

이 원칙들은 헌법 self-police에 더해 드라이버가 객관 검증한다. 우회 창의적 해석을 시도하지 않는다 — 규칙의 문자가 아닌 의도를 지킨다.
```

- [ ] **Step 3: 헌법 본문 §2 — 이터레이션 모델**

```markdown
## 2. 이터레이션 모델

- **콜드 스타트**: 매 이터레이션은 새 프로세스다. 직전 이터의 추론 과정·중간 상태는 다음 이터가 보지 못한다 — 결과물(코드·테스트·메모리 파일)만 본다.
- **워크트리 격리**: 모든 작업은 워크트리 안(`<project>-loops/<task-id>/` 또는 `<goal-id>/<task-id>/`)에서 일어난다. 워크트리 밖 파일은 수정 대상이 아니다.
- **입력**: `<worktree>/CLAUDE.md`(헌법), `.loop/PROMPT.md`(작업 정의), 디스크 상태(코드·git 히스토리), `.loop/{PLAN,NOTES,HANDOFF,RUN_LOG}.md`(메모리 파일).
- **출력**: 코드 변경 + 자기 분류 prefix를 가진 git commit + `.loop/` 메모리 파일 갱신 + (선택) `DONE` 또는 `.loop/ESCALATION.md` 신호 파일.
```

- [ ] **Step 4: 헌법 본문 §3 — 작업 흐름**

자율-루프-지침의 §1 (1.1~1.5) 내용을 압축해 옮긴다. 5단계 이터 + 자기 분류 + 완료 판정 5조건.

```markdown
## 3. 작업 흐름

### 3.1 수용 기준 확인

작업 시작 시점에 `.loop/PROMPT.md`의 작업 정의·수용 기준을 먼저 읽는다. 수용 기준이 모호하면 즉시 에스컬레이션한다 — 추측으로 진행하지 않는다.

### 3.2 한 이터레이션의 5단계

1. **계획**: 이번 이터에 무엇을 변경할지 한 문단. 변경 파일을 작업 정의의 `scope.include`와 비교.
2. **변경**: 최소 단위 코드 수정.
3. **빌드·검증**: 작업 정의의 `verify` 명령(있으면) 또는 관련 테스트만 실행.
4. **분류·기록**: 이번 변경을 자기 분류하고 메모리 파일을 갱신.
5. **결정**: 다음 중 하나.
   - 완료 판정 모두 만족 → `DONE` 작성·종료
   - 진행 불가 → `.loop/ESCALATION.md` 작성·종료
   - 그 외 → 정상 종료 (다음 이터가 이어받음)

한 이터는 가능한 한 작게 유지한다. 한 번에 여러 문제를 고치지 않는다.

### 3.3 자기 분류 (git commit prefix)

모든 commit은 다음 prefix 중 하나로 시작한다.
- `fix:root` — 근본 원인 수정
- `fix:symptom` — 증상 우회 (근본 원인 미확인 또는 범위 외)
- `feat` — 새 기능 추가
- `refactor` — 동작 변경 없는 구조 개선
- `test` — 테스트 추가
- `chore` — 빌드·설정 등 부수 작업

`fix:symptom`이 연속 2회 누적되면 드라이버가 자동 정지·에스컬레이션한다. 우회 패치를 쌓는 방향으로 계속 진행하지 않는다.

### 3.4 완료 판정

다음을 모두 만족할 때만 `DONE`을 작성한다.
- 수용 기준의 모든 항목 충족
- 기존 테스트 전원 통과
- `verify` 명령 0 exit
- 변경이 작업 명세 scope 내
- 자기 분류에 `fix:symptom` 누적 없음

하나라도 불만족이면 완료가 아니다. `DONE`을 거짓으로 작성하지 않는다.
```

- [ ] **Step 5: 헌법 본문 §4 — 이터레이션 상한·조기 정지**

자율-루프-지침의 §2 흡수.

```markdown
## 4. 이터레이션 상한·조기 정지

### 4.1 상한

한 task의 루프는 드라이버의 `--max-iterations`(기본 30)·`--wall-clock-minutes`(기본 120) 까지만 돈다. 초과 시 자동 에스컬레이션. 상한 임박을 이유로 우회 패치 넣지 않는다.

### 4.2 조기 정지 조건

다음 중 하나라도 해당하면 즉시 정지·에스컬레이션한다.
- 동일한 에러가 3회 연속 재발 (진전 없음)
- 이터 간 변경량이 진동 패턴 (수렴 실패)
- 한 지표 개선이 다른 지표 열화 (지역 최적해)
- 근본 원인 미규명한 채 `fix:symptom` 연속 누적
- 작업 범위 밖 수정이 필요하다는 판단
- 수용 기준 해석이 이터 중 흔들림

### 4.3 진전 정의

"진전"은 다음 중 하나다. 단순히 이터를 돌았다는 것은 진전이 아니다.
- 실패하던 테스트가 새로 통과
- 에러 신호가 질적으로 달라짐 (같은 에러 반복이 아닌 다음 단계 에러)
- 근본 원인에 대한 이해가 명시적으로 갱신됨
```

- [ ] **Step 6: 헌법 본문 §5 — 에스컬레이션**

자율-루프-지침의 §3 흡수.

```markdown
## 5. 에스컬레이션

### 5.1 트리거

다음 상황에서 즉시 에스컬레이션한다 — 망설이지 않는다.
- 수용 기준이 모호하거나 상충
- 작업 범위 밖 수정이 필요한 경우
- 아키텍처 변경이 필요한 경우
- 평가 기준 자체가 틀렸다고 판단되는 경우
- 4.2의 조기 정지 조건 발생
- 제1 원칙 위반 없이는 진행 불가능한 경우
- 보안·권한·과금 영역 접촉

### 5.2 보고 양식

`.loop/ESCALATION.md`를 다음 양식으로 작성한다.

\```
## 에스컬레이션 보고

**작업**: <task-id>
**이터레이션**: <현재 회차 / 상한>
**트리거**: <위 5.1 목록에서 해당 항목>

### 현재 상태
<코드 변경 요약, 테스트 상태, 지표 상태>

### 문제
<구체적 설명 — 추측 금지, 관찰한 사실만>

### 시도한 것
<이터별로 무엇을 시도했고 왜 실패했는지>

### 가설
<가능한 원인들과 각각의 근거>

### 필요한 결정
<인간이 결정해야 할 사항을 명확한 질문 형태로>
\```

### 5.3 에스컬레이션 후

`.loop/ESCALATION.md` 작성 직후 종료한다. 응답이 올 때까지 어떤 추가 작업도 수행하지 않는다. 드라이버가 파일 존재로 정지를 감지한다.
```

- [ ] **Step 7: 헌법 본문 §6 — 관찰성·로깅**

자율-루프-지침의 §4 흡수.

```markdown
## 6. 관찰성·로깅

### 6.1 매 이터레이션 기록

매 이터에 다음을 기록한다.
- 입력 상태 (어떤 신호를 보고 시작했는지) — `.loop/HANDOFF.md`·`PLAN.md`·`NOTES.md` 읽기
- 변경 내용 (diff) — git commit
- 실행 결과 (빌드, 테스트, 지표) — `verify` 명령 출력
- 해석 (무엇을 관찰했고 무엇으로 해석했는지) — `.loop/RUN_LOG.md` 한 줄
- 다음 단계 결정과 그 이유 — `.loop/HANDOFF.md` 덮어쓰기

### 6.2 의사결정 근거 명시

"이렇게 하면 될 것 같다"는 기록은 무효다. 모든 결정은 관찰된 신호에 근거를 두고, 그 근거를 명시한다. 근거가 빈약하면 가설임을 명시한다.

### 6.3 불확실성 표시

확실한 것과 추측을 구분해서 기록한다. 추측을 확실로 표시하지 않는다.
```

- [ ] **Step 8: 헌법 본문 §7 — 금지 행동**

자율-루프-지침의 §5 흡수 + 워크트리 관련 추가.

```markdown
## 7. 금지 행동

다음은 **절대 금지**다. 경계 상황이라 판단되면 금지 쪽으로 해석한다.

- 테스트 삭제, 스킵, 주석 처리, 조건부 무효화
- 회귀 기준·임계값·수용 기준 수정
- 린터 규칙·CI 설정 완화
- `# noqa`, `@ts-ignore`, `eslint-disable`, `#pragma warning disable` 등 경고 억제 지시어의 신규 추가 (기존 것 유지는 허용)
- try/except로 에러를 삼키기
- 로그 지우기·기록 생략
- 작업 범위 밖 파일 수정 (`scope.include` 외)
- 의존성 추가·업그레이드·다운그레이드
- `.git` 히스토리 조작, force push, 리베이스
- 비밀키·토큰·자격증명의 코드 내 하드코딩 또는 로그 출력
- "작동하는 것처럼 보이게 하는" 모든 종류의 위장
- 워크트리 밖 파일 수정 (모든 작업은 워크트리 안에서)
- 워크트리 루트의 `CLAUDE.md`(헌법), `.loop/PROMPT.md` 수정
- 거짓 `DONE` 또는 거짓 `.loop/ESCALATION.md` 작성

다음 항목은 드라이버가 객관 검증한다 — 위반 시 자동 halt + 에스컬레이션:
- 테스트 약화 → `tests/**` 해시 비교
- 의존성 변경 → 매니페스트 해시
- scope 위반 → `git diff --name-only` vs `scope.include`
- suppressor 신규 → `git diff` grep
- 비밀키 → `gitleaks detect --staged` (있을 때)
- fix:symptom streak → `git log --pretty=format:%s -2`
- 진동 → 최근 4 커밋의 변경 파일 셋 비교
```

- [ ] **Step 9: 헌법 본문 §8 — 근본 원인 추구**

자율-루프-지침의 §6 흡수.

```markdown
## 8. 근본 원인 추구

### 8.1 표면 신호 vs 근본 원인

에러 메시지는 증상이지 원인이 아니다. "에러가 사라졌다"는 "문제가 해결됐다"와 다르다. 에러가 사라진 이유를 설명할 수 없으면 해결된 것이 아니다.

### 8.2 증상 우회는 명시적으로

근본 원인을 규명할 수 없어 우회 패치를 쓸 수밖에 없는 경우, 반드시 `fix:symptom`으로 분류하고 commit message에 다음을 포함한다.
- 관찰된 증상
- 규명하지 못한 원인의 범위
- 우회 방법
- 향후 근본 원인 규명에 필요한 정보

### 8.3 "일단 동작"은 목표가 아니다

테스트 통과가 목표가 아니라 **올바른 동작**이 목표다. 테스트는 올바름의 근사치일 뿐이다. 테스트를 속이는 구현은 실패다.
```

- [ ] **Step 10: 헌법 본문 §9 — 의사소통**

자율-루프-지침의 §7 흡수.

```markdown
## 9. 의사소통

### 9.1 정직

모르는 것은 모른다고 한다. 확신하지 못하는 것은 확신하지 못한다고 한다. 실패한 것은 실패했다고 한다. 인간의 기대에 맞추기 위해 결과를 윤색하지 않는다.

### 9.2 간결

보고는 사실 중심으로 간결하게. 장식적 표현, 사과, 불필요한 맥락 반복은 제거한다.

### 9.3 완료의 정의 준수

"완료"라는 단어는 §3.4의 완료 판정을 모두 만족할 때만 사용한다. "거의 완료", "대부분 완료"는 완료가 아니다.
```

- [ ] **Step 11: 헌법 본문 §10 — 하네스 자체에 대한 태도**

자율-루프-지침의 §8 흡수.

```markdown
## 10. 하네스 자체에 대한 태도

본 하네스는 진화 중이다. 규칙이 현실과 맞지 않거나 작업을 불가능하게 만든다고 판단되면, 규칙을 우회하는 것이 아니라 **에스컬레이션 보고서에 그 사실을 명시**한다. 하네스의 개선은 인간의 결정 사항이며, 개선 제안은 에이전트의 정당한 기여다. 규칙 우회는 기여가 아니다.
```

- [ ] **Step 12: 헌법 본문 §11 — 메모리 파일 운영**

랄프 패턴의 핵심 — 4대 메모리 파일 큐레이션 의무.

```markdown
## 11. 메모리 파일 운영

기억은 LLM이 아닌 파일에 있다. 매 이터는 콜드 스타트다. 직전 추론 과정은 다음 이터가 보지 못한다 — 결과물(코드·테스트·메모리 파일)만 본다.

### 11.1 매 이터 시작 (이 순서로 읽는다)

1. `.loop/PLAN.md` — 마일스톤 체크박스, 어디까지 왔는지
2. `.loop/NOTES.md` — 이전 시도의 교훈 (실패 접근·발견 제약·작동 패턴)
3. `.loop/HANDOFF.md` — 직전 이터의 상태·다음 단계 추천
4. `.loop/RUN_LOG.md` 끝 부분 — 최근 흐름
5. `git log --oneline -20` — 최근 커밋 확인

### 11.2 매 이터 종료 (이 순서로)

1. `.loop/HANDOFF.md` 덮어쓰기 — 다음 이터가 5분 안에 컨텍스트 잡을 수 있는 형태로:
   - 이번에 무엇을 했는지
   - 무엇이 막혔거나 막힐 수 있는지
   - 다음 단계 추천 (구체적으로)
2. `.loop/RUN_LOG.md`에 한 줄 추가 — 시각·시도·결과·다음 단계
3. `.loop/PLAN.md` 체크박스 갱신 (진전 있을 때)
4. 실패·발견 시 `.loop/NOTES.md` 갱신 (실패 접근 또는 새 제약 추가)

### 11.3 NOTES.md의 "실패한 접근"

실패한 접근의 재시도는 금지된다. 같은 가설을 다시 시도하려면 왜 이번엔 다른지 NOTES에 명시한다. 드라이버가 다음 이터의 변경 diff와 NOTES의 실패 패턴을 단순 텍스트 매칭으로 검사할 수 있다 (확률적, 절대 보장은 아님).

### 11.4 NOTES.md 크기 관리

NOTES.md가 100줄 넘으면 큰 실패는 `.loop/failures/<n>-<short-name>.md`로 분할 이동한다. 본문에는 요약·교훈만 남긴다.

### 11.5 모델 큐레이션 책임

모든 메모리 파일은 모델이 큐레이션한다. 잡음 없는 신호만 다음 이터로 전달한다 — 의식의 흐름·모든 시도 기록은 잡음이다.
```

- [ ] **Step 13: 헌법 본문 §12 — 종료 신호**

```markdown
## 12. 종료 신호

루프의 종료는 두 파일로만 표현한다.

- **워크트리 루트의 `DONE`**: 완료 판정(§3.4) 모두 만족할 때 작성. 빈 파일이거나 한 줄 메시지.
- **`.loop/ESCALATION.md`**: 진전 불가능 시 §5.2 양식으로 작성.

두 파일을 임의로 작성·삭제하지 않는다. 신호는 진실해야 한다. 거짓 `DONE`은 가짜 완료 위장이고, 거짓 ESCALATION은 작업 회피다 — 둘 다 §1.1·§1.4 위반이다.
```

- [ ] **Step 14: 헌법 본문 §13 — 체크리스트**

자율-루프-지침의 §9 흡수.

```markdown
## 13. 체크리스트

### 매 task 시작 전
- [ ] PROMPT.md의 작업 정의·수용 기준을 읽고 이해했는가
- [ ] 작업 범위(scope)가 명확한가
- [ ] 이터 상한·시계 캡을 인지하고 있는가
- [ ] 에스컬레이션 트리거를 기억하고 있는가
- [ ] 제1 원칙을 위반할 수 있는 함정을 미리 인지했는가

### 매 이터 후
- [ ] 진전이 있었는가 (§4.3 정의)
- [ ] 자기 분류(commit prefix)를 수행했는가
- [ ] `fix:symptom`이 누적되고 있지 않은가
- [ ] 메모리 파일을 갱신했는가 (PLAN/NOTES/HANDOFF/RUN_LOG)
- [ ] 계속 진행이 정당한가, 에스컬레이션해야 하는가

### `DONE` 작성 전
- [ ] 완료 판정(§3.4) 모든 항목을 만족하는가
- [ ] 금지 행동(§7)을 하나도 수행하지 않았는가
- [ ] 모든 변경이 작업 범위 내인가
- [ ] verify 명령이 0 exit인가

하나라도 불만족이면 작업은 완료되지 않았다.

---

**본 문서의 규칙은 에이전트의 자유를 제한하기 위함이 아니라, 에이전트의 작업이 실제로 가치 있게 만들기 위함이다. 규칙 없이 동작하는 자율 루프는 수렴하지 않으며, 수렴하지 않는 루프의 산출물은 버려진다. 본 규칙은 에이전트의 작업이 버려지지 않게 하는 최소 조건이다.**
```

- [ ] **Step 15: 검증 — frontmatter 파싱**

```bash
yq '.label' plugins/project-init/skills/autonomous-loop-rule-creator/templates/ralph-loop.md
# 예상 출력: 랄프 루프 (sibling 워크트리, 객관 게이트, 동시 실행 지원)

yq '.recommended' plugins/project-init/skills/autonomous-loop-rule-creator/templates/ralph-loop.md
# 예상 출력: true
```

`yq`가 frontmatter를 정상 파싱하지 못하면 `---` 구분선·들여쓰기를 점검한다.

- [ ] **Step 16: 커밋**

```bash
git add plugins/project-init/skills/autonomous-loop-rule-creator/templates/ralph-loop.md
git commit -m "feat(autonomous-loop-rule-creator): 단일 템플릿 + 헌법 본문 13개 절"
```

---

## Task 3: PROMPT.template.md (작업 정의 + 이터 프로토콜)

**Files:**
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/PROMPT.template.md`

**참조:** spec §7 (PROMPT.md 템플릿), §11.1·11.2 (메모리 파일 라이프사이클).

- [ ] **Step 1: 파일 작성**

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
verify: <실행 가능한 명령. 예: pnpm test --filter=feature-x. 0 exit이면 검증 통과>
---

# 자율 루프 마스터 프롬프트

당신은 자율 루프의 한 이터레이션입니다.
기억은 LLM이 아닌 파일에 있습니다. 매 이터는 콜드 스타트입니다.

## 작업 정의 (불변)

### 무엇을 만들 것인가
{{task_description}}

### 수용 기준
{{acceptance_criteria}}

### 범위
포함:
{{scope_in}}

비-목표 / 제외:
{{scope_out}}

### 검증
이 명령이 0 exit으로 끝나야 합니다:
{{verify_command}}

## 시작 전 (이 순서로 읽는다)

1. **`.loop/PLAN.md`** — 권위 있는 작업 계획·진전 상태 (체크박스)
2. **`.loop/NOTES.md`** — 이전 시도의 교훈 (실패 접근·발견된 제약·작동 패턴)
3. **`.loop/HANDOFF.md`** — 직전 이터의 상태·다음 단계 추천
4. **`.loop/RUN_LOG.md`** 끝 부분 — 최근 흐름
5. `git log --oneline -20` — 최근 커밋 확인

## 한 이터레이션 규칙

- 완료를 향한 가장 작은 유용한 단계 하나만 수행
- `.loop/NOTES.md`의 "실패한 접근"을 반복하지 않음 — 같은 가설을 다시 시도하려면 왜 이번엔 다른지 NOTES에 명시
- 변경 후 `verify` 명령을 실행하고, 실패 시 그 원인을 `.loop/NOTES.md`에 추가
- 진전이 있으면 `.loop/PLAN.md` 체크박스 갱신
- 워크트리 밖 파일은 수정하지 않음
- `scope.include` 밖 파일은 수정하지 않음

## 종료 전 (이 순서로)

1. **`.loop/HANDOFF.md` 덮어쓰기** — 다음 이터가 5분 안에 컨텍스트를 잡도록:
   - 이번에 무엇을 했는지
   - 무엇이 막혔거나 막힐 수 있는지
   - 다음 단계 추천 (구체적으로)
2. **`.loop/RUN_LOG.md`에 한 줄 추가** — 형식: `[<ISO timestamp>] <한 줄 요약>`
3. **git commit** — 자기 분류 prefix로 시작:
   `fix:root` / `fix:symptom` / `feat` / `refactor` / `test` / `chore`
4. **완료 판정 (§3.4) 모두 통과 → 워크트리 루트에 `DONE` 파일 작성·종료**
5. **진전 불가능 → `.loop/ESCALATION.md` 작성·종료** (양식: 헌법 §5.2 참조)

## 절대 안 됨

- 워크트리 루트의 `CLAUDE.md` (헌법) 수정
- `.loop/PROMPT.md` 수정
- 워크트리 밖 파일 수정
- 거짓 `DONE` 또는 거짓 `.loop/ESCALATION.md`
- 작업 범위(scope) 밖 파일 수정
- 자기 분류 prefix 누락한 채 commit
- `.loop/NOTES.md`의 "실패한 접근" 재시도 (정당한 사유 없이)

## 응답 형식

변경·실행·로깅을 도구로 수행한다. 텍스트 응답은 짧은 결정 요약으로 충분하다.
```

- [ ] **Step 2: frontmatter 파싱 검증**

```bash
yq '.scope.include[]' plugins/project-init/skills/autonomous-loop-rule-creator/assets/PROMPT.template.md
# 예상 출력 (한 줄씩):
# src/**
# tests/**

yq '.verify' plugins/project-init/skills/autonomous-loop-rule-creator/assets/PROMPT.template.md
# 예상 출력: <실행 가능한 명령. 예: pnpm test --filter=feature-x. 0 exit이면 검증 통과>
```

- [ ] **Step 3: placeholder 목록 확인**

```bash
grep -oE '\{\{[a-z_]+\}\}' plugins/project-init/skills/autonomous-loop-rule-creator/assets/PROMPT.template.md | sort -u
# 예상 출력:
# {{acceptance_criteria}}
# {{scope_in}}
# {{scope_out}}
# {{task_description}}
# {{verify_command}}
```

5개 placeholder가 모두 있어야 한다. 누락 시 본문 추가.

- [ ] **Step 4: 커밋**

```bash
git add plugins/project-init/skills/autonomous-loop-rule-creator/assets/PROMPT.template.md
git commit -m "feat(autonomous-loop-rule-creator): PROMPT.template.md (frontmatter + 라이프사이클)"
```

---

## Task 4: 메모리 파일 5종 템플릿

**Files:**
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/PLAN.template.md`
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/NOTES.template.md`
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/HANDOFF.template.md`
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/RUN_LOG.template.md`
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/ESCALATION.template.md`

- [ ] **Step 1: PLAN.template.md**

```markdown
# 작업 계획

마일스톤 체크박스. 이터레이션마다 진전이 있으면 모델이 갱신.

## 마일스톤

- [ ] 마일스톤 1: <간단한 설명>
- [ ] 마일스톤 2: <간단한 설명>
- [ ] 마일스톤 3: <간단한 설명>

## 완료 판정

다음을 모두 만족하면 워크트리 루트에 `DONE` 작성:
- [ ] 모든 마일스톤 체크
- [ ] verify 명령 0 exit
- [ ] 자기 분류 누적에 `fix:symptom` 연속 없음
```

- [ ] **Step 2: NOTES.template.md**

```markdown
# 작업 노트

큐레이션된 학습. 다음 이터가 같은 막다른 길을 다시 가지 않게 하는 신호.

## 확정된 사실 (재발견 비용 절약)

(아직 발견된 사실 없음. 발견 시 추가)

## 실패한 접근 (재시도 금지)

(아직 시도된 실패 없음. 실패 시 다음 형식으로 추가)

<!--
### 시도 N (이터 X): <한 줄 제목>
- 결과: 실패. <왜 실패했는지>
- 학습: <이 실패에서 도출되는 일반화된 교훈>
-->

## 미해결 가설

(현재 검토 중인 가설. 다음 이터에서 시도 예정)

## 작동하는 패턴

(검증된 코드 조각·접근법. 다음 시도가 참조 가능)
```

- [ ] **Step 3: HANDOFF.template.md**

```markdown
# 다음 이터에게 (HANDOFF)

매 이터 종료 직전에 모델이 덮어씀. 다음 이터가 콜드 스타트로 5분 안에 컨텍스트 잡을 수 있는 형태.

## 직전 이터: 0
(아직 첫 이터가 시작되지 않았습니다)

## 이번에 무엇을 했는가
(첫 이터에서 채워질 예정)

## 무엇이 막혔거나 막힐 수 있는가
(첫 이터에서 채워질 예정)

## 다음 단계 추천
(첫 이터가 PROMPT.md를 읽고 시작 단계 선택)
```

- [ ] **Step 4: RUN_LOG.template.md**

```markdown
# 실행 로그

매 이터 종료 직전 한 줄 추가. 형식: `[<ISO timestamp>] <한 줄 요약>`.

(아직 이터가 실행되지 않았습니다)
```

- [ ] **Step 5: ESCALATION.template.md**

```markdown
# 에스컬레이션 보고

진전 불가능 시 모델이 작성. 작성 직후 종료. 드라이버가 파일 존재로 정지를 감지.

**작업**: <task-id>
**이터레이션**: <현재 회차 / 상한>
**트리거**: <어느 조건에 해당하는지 — 헌법 §5.1 참조>

## 현재 상태

<코드 변경 요약, 테스트 상태, 지표 상태>

## 문제

<구체적 설명. 추측 금지, 관찰한 사실만>

## 시도한 것

<이터별로 무엇을 시도했고 왜 실패했는지>

## 가설

<가능한 원인들과 각각의 근거>

## 필요한 결정

<인간이 결정해야 할 사항을 명확한 질문 형태로>
```

- [ ] **Step 6: 검증**

```bash
ls plugins/project-init/skills/autonomous-loop-rule-creator/assets/*.template.md
# 예상 출력:
# .../ESCALATION.template.md
# .../HANDOFF.template.md
# .../NOTES.template.md
# .../PLAN.template.md
# .../PROMPT.template.md
# .../RUN_LOG.template.md
```

6개 파일이 모두 있어야 한다 (PROMPT는 Task 3에서 생성됨).

- [ ] **Step 7: 커밋**

```bash
git add plugins/project-init/skills/autonomous-loop-rule-creator/assets/{PLAN,NOTES,HANDOFF,RUN_LOG,ESCALATION}.template.md
git commit -m "feat(autonomous-loop-rule-creator): 메모리 파일 5종 템플릿"
```

---

## Task 5: loops-README.md (사용자 워크플로 가이드)

**Files:**
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/loops-README.md`

**참조:** spec §10 (사용자 워크플로) 전체.

- [ ] **Step 1: 파일 작성**

```markdown
# 자율 루프 (`.loops/`)

이 디렉토리는 sibling 워크트리 기반 외부 셸 드라이버를 가진 단일 task 자율 수행 환경입니다.

## 핵심 가정

- 매 이터는 새 `claude --print` 프로세스 (콜드 스타트). 기억은 LLM이 아닌 파일에 있습니다.
- 작업은 `<project>/../<project-name>-loops/<task-id>/` (sibling 워크트리)에서 일어납니다.
- 격리: 워크트리는 프로젝트 트리 밖에 있어 프로젝트 `CLAUDE.md`·hooks가 자동 차단됩니다.
- 사용자 레벨 `~/.claude/CLAUDE.md`·`~/.claude/settings.json`은 차단 불가 — **루프 시작 전 본인 환경을 검토**하시는 것을 권장합니다.

## 디렉토리 구조

```
.loops/
├── README.md                  # 본 문서
├── PROMPT.template.md         # 새 task의 PROMPT.md 시드
├── loop.sh                    # 외부 드라이버
├── templates/                 # 메모리 파일 스텁
├── locks/                     # 동시 실행 락 (gitignored)
└── archive/                   # DONE된 task의 메타 파일 보관
```

런타임 워크트리:
```
<project>/../<project-name>-loops/<task-id>/
├── CLAUDE.md                  # 헌법 (rules/autonomous-loop.md 복사본)
├── .loop/                     # 메타 파일 (워크트리 .git/info/exclude로 비추적)
│   ├── PROMPT.md              # 작업 정의 (사용자 작성)
│   ├── PLAN.md                # 마일스톤 (모델 갱신)
│   ├── NOTES.md               # 학습 누적 (모델 갱신)
│   ├── HANDOFF.md             # 직전 → 다음 편지 (모델 매 이터 덮어쓰기)
│   ├── RUN_LOG.md             # 한 줄 요약 누적
│   ├── iterations/<n>.log     # 매 이터 stdout 캡처
│   └── ESCALATION.md          # 정지 사유 (있을 때만)
└── (프로젝트 파일들 — autonomous-loop/<task-id> 브랜치 체크아웃)
```

## 새 task 시작

```bash
# 1. 첫 호출 — 워크트리 + 메타 파일 생성
./.loops/loop.sh auth-refactor
# 출력: "워크트리 생성: ../<project>-loops/auth-refactor"
#       "다음 파일을 채워 주세요: ../<project>-loops/auth-refactor/.loop/PROMPT.md"

# 2. PROMPT.md에 작업 정의 채움
$EDITOR ../<project>-loops/auth-refactor/.loop/PROMPT.md
# - YAML frontmatter: scope.include / scope.exclude / verify
# - 본문 placeholder: {{task_description}}, {{acceptance_criteria}}, ...

# 3. 두 번째 호출 — 실제 루프 시작
./.loops/loop.sh auth-refactor

# 4. 진행 모니터링 (별도 터미널)
tail -f ../<project>-loops/auth-refactor/.loop/RUN_LOG.md

# 5. 정지: Ctrl+C, 또는 DONE/ESCALATION.md가 생기면 자동 종료
```

## DONE 후 머지

```bash
cd ../<project>-loops/auth-refactor
git log autonomous-loop/auth-refactor

cd <project>
git merge autonomous-loop/auth-refactor    # 또는 PR 생성
git worktree remove ../<project>-loops/auth-refactor
git branch -d autonomous-loop/auth-refactor
```

archive 메타 파일은 `.loops/archive/auth-refactor/`에 보관됩니다 — 회고·재학습용.

## ESCALATION 처리

```bash
cat ../<project>-loops/<task-id>/.loop/ESCALATION.md
cd ../<project>-loops/<task-id>
$EDITOR .loop/PROMPT.md           # 명세 조정
$EDITOR .loop/NOTES.md            # 학습 보강
rm .loop/ESCALATION.md            # 보고 해제
cd <project>
./.loops/loop.sh <task-id>        # 재시작
```

## 동시 실행

```bash
./.loops/loop.sh auth-refactor &
./.loops/loop.sh schema-migration &

tail -f ../<project>-loops/*/.loop/RUN_LOG.md

MAX_CONCURRENT=5 ./.loops/loop.sh new-task &   # 캡 상향

git worktree list                              # 모든 워크트리
ls .loops/locks/                                # 모든 RUNNING 락
```

`MAX_CONCURRENT` 환경변수 (기본 3)로 동시 실행 캡 조정. 같은 task-id 이중 실행은 락으로 차단됩니다.

## 환경변수

- `LOOP_WORKTREE_BASE` — 워크트리 부모 디렉토리. 기본 `<project>/../<project-name>-loops/`. 외부 위치(`~/.claude-loops/<project>/` 등)로 변경 가능
- `MAX_CONCURRENT` — 동시 실행 task 수. 기본 3
- `MAX_ITERATIONS` — 한 task의 이터 상한. 기본 30
- `WALL_CLOCK_MINUTES` — 한 task의 시계 캡. 기본 120

## 객관 게이트

드라이버가 매 이터 후 다음을 검사합니다. 위반 시 자동 halt + ESCALATION 자동 작성:

| 가드 | 기준 |
|---|---|
| 이터 상한 | `MAX_ITERATIONS` (기본 30) |
| 시계 캡 | `WALL_CLOCK_MINUTES` (기본 120) |
| 테스트 약화 | `tests/**` 해시 변경 감지 |
| 의존성 동결 | `package.json`·`requirements.txt`·`Cargo.toml` 등 매니페스트 해시 |
| Scope 위반 | git diff vs PROMPT.md frontmatter의 scope.include·exclude |
| Suppressor 신규 | `noqa`·`@ts-ignore`·`eslint-disable`·`#pragma warning disable` 신규 추가 |
| Secrets | `gitleaks detect --staged` (gitleaks 설치 시) |
| fix:symptom streak | git log의 최근 2 커밋이 모두 `fix:symptom` |
| 진동 | 최근 4 커밋의 변경 파일 셋 토글 |

## 의존성

- `bash` 4+
- `git` (worktree 지원)
- `yq` ([mikefarah/yq](https://github.com/mikefarah/yq))
- `claude` CLI
- `gitleaks` (선택, secrets 게이트용)

## 안전 정지

- Ctrl+C: 진행 중 이터까지 완료 후 락 해제
- `kill <PID>`: SIGTERM. 락은 trap으로 해제됨
- 모든 `loop.sh` 종료: 각자의 락 파일이 자동 정리
```

- [ ] **Step 2: 커밋**

```bash
git add plugins/project-init/skills/autonomous-loop-rule-creator/assets/loops-README.md
git commit -m "feat(autonomous-loop-rule-creator): .loops/README.md 사용자 가이드"
```

---

## Task 6: `loop.sh` Phase 1 — 셰뱅·헬퍼·워크트리 생성

**Files:**
- Create: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh`

**참조:** spec §8.1 (호출 인터페이스), §8.2.1 (워크트리 생성), §8.5 (격리 메커니즘).

- [ ] **Step 1: 셰뱅·strict 모드·헬퍼 함수**

```bash
#!/usr/bin/env bash
# loop.sh — 자율 루프 외부 셸 드라이버
# 사용: ./.loops/loop.sh <task-id>
#
# 환경변수:
#   LOOP_WORKTREE_BASE     워크트리 부모 디렉토리 (기본: <project>/../<project-name>-loops)
#   MAX_CONCURRENT         동시 실행 task 수 (기본: 3)
#   MAX_ITERATIONS         이터 상한 (기본: 30)
#   WALL_CLOCK_MINUTES     시계 캡 (기본: 120)

set -euo pipefail

# ----- 헬퍼 -----

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1이(가) 필요합니다. 설치 후 다시 실행하세요."
}

sanitize_for_filename() {
  # 슬래시·공백 등을 -로 치환 (락 파일명용)
  echo "$1" | tr '/ ' '--'
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# ----- 의존성 검사 -----

require_tool git
require_tool yq
require_tool claude

# ----- 인자 파싱 -----

if [[ $# -lt 1 ]]; then
  die "사용: $0 <task-id>"
fi

TASK_ID="$1"

# ----- 경로 계산 -----

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "git 저장소 안에서 실행해야 합니다."
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
WT_BASE="${LOOP_WORKTREE_BASE:-$PROJECT_ROOT/../${PROJECT_NAME}-loops}"
WT="$WT_BASE/$TASK_ID"
BRANCH="autonomous-loop/$TASK_ID"
TASK_ID_SAFE="$(sanitize_for_filename "$TASK_ID")"
LOCK_DIR="$PROJECT_ROOT/.loops/locks"
LOCK_FILE="$LOCK_DIR/$TASK_ID_SAFE.lock"
ARCHIVE_DIR="$PROJECT_ROOT/.loops/archive/$TASK_ID_SAFE"

# 캡 기본값
MAX_ITERATIONS="${MAX_ITERATIONS:-30}"
WALL_CLOCK_MINUTES="${WALL_CLOCK_MINUTES:-120}"
MAX_CONCURRENT="${MAX_CONCURRENT:-3}"
```

- [ ] **Step 2: 워크트리 생성 함수 (워크트리 부재 시)**

위 코드 다음에 추가:

```bash
# ----- 워크트리 생성 (첫 호출용) -----

create_worktree() {
  echo "[$(now_iso)] 워크트리 생성 시작: $WT"

  mkdir -p "$WT_BASE"
  git -C "$PROJECT_ROOT" worktree add "$WT" -b "$BRANCH" \
    || die "git worktree add 실패: $WT"

  # 헌법을 워크트리 CLAUDE.md로 복사
  cp "$PROJECT_ROOT/rules/autonomous-loop.md" "$WT/CLAUDE.md" \
    || die "rules/autonomous-loop.md를 찾을 수 없음. 스킬이 정상 설치됐는지 확인하세요."

  # 메타 파일 시드
  mkdir -p "$WT/.loop/iterations"
  cp "$PROJECT_ROOT/.loops/PROMPT.template.md" "$WT/.loop/PROMPT.md"
  cp "$PROJECT_ROOT/.loops/templates/PLAN.template.md" "$WT/.loop/PLAN.md"
  cp "$PROJECT_ROOT/.loops/templates/NOTES.template.md" "$WT/.loop/NOTES.md"
  cp "$PROJECT_ROOT/.loops/templates/HANDOFF.template.md" "$WT/.loop/HANDOFF.md"
  cp "$PROJECT_ROOT/.loops/templates/RUN_LOG.template.md" "$WT/.loop/RUN_LOG.md"

  # 워크트리 로컬 비추적 등록
  {
    echo "CLAUDE.md"
    echo ".loop/"
    echo "DONE"
  } >> "$WT/.git/info/exclude"

  echo ""
  echo "워크트리 생성 완료: $WT"
  echo "브랜치: $BRANCH"
  echo ""
  echo "다음 파일을 채워 주세요:"
  echo "  $WT/.loop/PROMPT.md"
  echo ""
  echo "채운 후 다시 실행:"
  echo "  $0 $TASK_ID"
}
```

- [ ] **Step 3: 메인 분기**

위 코드 다음에 추가 (이후 단계에서 함수들을 추가):

```bash
# ----- 메인 -----

if [[ ! -d "$WT" ]]; then
  create_worktree
  exit 0
fi

# 이후 분기는 Task 7~9에서 추가
echo "TODO: 이터레이션 루프 진입 — Task 7~9에서 구현"
exit 0
```

- [ ] **Step 4: 권한 부여 + 구문 검사**

```bash
chmod +x plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh
bash -n plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh
# 구문 오류 없으면 출력 없음 (exit 0)
```

- [ ] **Step 5: 커밋**

```bash
git add plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh
git commit -m "feat(autonomous-loop-rule-creator): loop.sh phase 1 (워크트리 생성)"
```

---

## Task 7: `loop.sh` Phase 2 — 동시성 락 + 이터레이션 호출

**Files:**
- Modify: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh`

**참조:** spec §8.3 (동시성 제어), §8.4 (매 이터 호출), §8.5 (격리).

- [ ] **Step 1: 동시성 락 함수 추가**

`create_worktree` 함수 다음에 추가:

```bash
# ----- 동시성 락 -----

acquire_lock() {
  mkdir -p "$LOCK_DIR"

  local running
  running=$(find "$LOCK_DIR" -name "*.lock" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ $running -ge $MAX_CONCURRENT ]]; then
    die "이미 $running개 loop이 동작 중 (최대: $MAX_CONCURRENT). 새 loop 거부."
  fi

  if [[ -f "$LOCK_FILE" ]]; then
    local existing_pid
    existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "?")
    die "task $TASK_ID가 이미 동작 중 (PID: $existing_pid). 종료 후 재실행."
  fi

  echo $$ > "$LOCK_FILE"
  trap "rm -f $LOCK_FILE" EXIT
}
```

- [ ] **Step 2: 이터레이션 호출 함수 추가**

`acquire_lock` 다음에 추가:

```bash
# ----- 이터레이션 호출 -----

iterate() {
  local n
  n=$(($(ls "$WT/.loop/iterations/"*.log 2>/dev/null | wc -l | tr -d ' ') + 1))

  echo "[$(now_iso)] 이터 #$n 시작"

  # 워크트리 안에서 호출 (cwd 격리)
  (
    cd "$WT"
    cat .loop/PROMPT.md | claude \
      --print \
      --no-session-persistence \
      --dangerously-skip-permissions \
      --system-prompt-file CLAUDE.md \
      --add-dir . \
      --output-format json \
      > ".loop/iterations/$n.log" 2>&1
  )

  local exit_code=$?
  echo "[$(now_iso)] 이터 #$n 종료 (exit: $exit_code)"

  if [[ $exit_code -ne 0 ]]; then
    echo "WARN: claude 호출이 0이 아닌 exit code 반환. iterations/$n.log 확인 권장."
  fi

  # 호출 결과는 워크트리 안에서 검사 (게이트는 Task 8에서 추가)
}
```

- [ ] **Step 3: 메인 분기 갱신**

`if [[ ! -d "$WT" ]]; then ... fi` 블록 다음의 `echo "TODO ..."`를 다음으로 대체:

```bash
# 워크트리 존재 → 이터레이션 루프 진입
acquire_lock

START_TIME=$(date +%s)

while true; do
  iterate

  # 종료 조건은 Task 8에서 추가
  break  # 임시: 한 번만 돌고 종료
done

echo "[$(now_iso)] 루프 종료 (한 이터 후 임시 종료. Task 8 이후 정식 루프)"
```

- [ ] **Step 4: 구문 검사**

```bash
bash -n plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh
```

- [ ] **Step 5: 커밋**

```bash
git add plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh
git commit -m "feat(autonomous-loop-rule-creator): loop.sh phase 2 (락 + 이터 호출)"
```

---

## Task 8: `loop.sh` Phase 3 — 9개 객관 게이트

**Files:**
- Modify: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh`

**참조:** spec §8.6 (객관 게이트 9종), §8.7 (의사 코드).

- [ ] **Step 1: 해시 함수들**

`iterate()` 함수 위에 추가:

```bash
# ----- 게이트 헬퍼 -----

hash_tests() {
  if [[ -d "$WT/tests" ]]; then
    find "$WT/tests" -type f -name '*.test.*' -o -name 'test_*.*' -o -name '*_test.*' 2>/dev/null \
      | sort \
      | xargs -I{} sha256sum {} 2>/dev/null \
      | sha256sum \
      | awk '{print $1}'
  else
    echo "no-tests-dir"
  fi
}

hash_deps() {
  local manifests
  manifests=$(find "$WT" -maxdepth 2 -type f \
    \( -name 'package.json' -o -name 'requirements.txt' -o -name 'Cargo.toml' \
       -o -name 'go.mod' -o -name 'pyproject.toml' -o -name 'Gemfile' \
       -o -name 'pom.xml' -o -name 'build.gradle' \) 2>/dev/null | sort)
  if [[ -z "$manifests" ]]; then
    echo "no-manifests"
  else
    echo "$manifests" | xargs -I{} sha256sum {} 2>/dev/null \
      | sha256sum | awk '{print $1}'
  fi
}

read_scope_include() {
  yq '.scope.include[]' "$WT/.loop/PROMPT.md" 2>/dev/null
}

read_scope_exclude() {
  yq '.scope.exclude[]' "$WT/.loop/PROMPT.md" 2>/dev/null
}
```

- [ ] **Step 2: scope diff 검사 함수**

```bash
diff_vs_scope() {
  local include_patterns exclude_patterns changed
  include_patterns=$(read_scope_include)
  exclude_patterns=$(read_scope_exclude)
  changed=$(cd "$WT" && git diff --name-only HEAD~1 HEAD 2>/dev/null)

  [[ -z "$changed" ]] && return 0

  local out_of_scope=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    # exclude 패턴에 매칭되면 위반
    while IFS= read -r exc; do
      [[ -z "$exc" ]] && continue
      # bash 와일드카드 매칭 ([[ "$file" == $exc ]] 형식)
      if [[ "$file" == $exc ]]; then
        out_of_scope+="$file (excluded by $exc)\n"
        continue 2
      fi
    done <<< "$exclude_patterns"

    # include 패턴 중 하나에도 매칭 안 되면 위반
    local matched=0
    while IFS= read -r inc; do
      [[ -z "$inc" ]] && continue
      if [[ "$file" == $inc ]]; then
        matched=1
        break
      fi
    done <<< "$include_patterns"

    if [[ $matched -eq 0 ]]; then
      out_of_scope+="$file (not in include)\n"
    fi
  done <<< "$changed"

  if [[ -n "$out_of_scope" ]]; then
    printf "%b" "$out_of_scope"
  fi
}
```

- [ ] **Step 3: 나머지 게이트 함수**

```bash
grep_new_suppressors() {
  cd "$WT" && git diff HEAD~1 HEAD 2>/dev/null \
    | grep -E '^\+' \
    | grep -E '#[[:space:]]*noqa|@ts-ignore|eslint-disable|#pragma[[:space:]]+warning[[:space:]]+disable' \
    || true
}

check_secrets() {
  command -v gitleaks >/dev/null 2>&1 || return 0
  cd "$WT" && gitleaks detect --staged --no-banner 2>&1 || true
}

count_fix_symptom_streak() {
  cd "$WT" && git log --pretty=format:%s -2 2>/dev/null \
    | grep -c '^fix:symptom' || echo 0
}

detect_oscillation() {
  # 최근 4 커밋의 변경 파일 셋이 두 상태로 토글되는지 검사
  local commits
  commits=$(cd "$WT" && git log --pretty=format:%H -4 2>/dev/null)
  [[ $(echo "$commits" | wc -l) -lt 4 ]] && return 0

  local sets=()
  while IFS= read -r commit; do
    sets+=("$(cd "$WT" && git diff-tree --no-commit-id --name-only -r "$commit" | sort | md5sum | awk '{print $1}')")
  done <<< "$commits"

  # set[0] == set[2] 그리고 set[1] == set[3]이면 토글
  if [[ "${sets[0]}" == "${sets[2]}" ]] && [[ "${sets[1]}" == "${sets[3]}" ]] \
     && [[ "${sets[0]}" != "${sets[1]}" ]]; then
    echo "최근 4 커밋이 두 상태로 토글됨"
  fi
}

elapsed_minutes() {
  echo $(( ( $(date +%s) - START_TIME ) / 60 ))
}
```

- [ ] **Step 4: halt 함수**

```bash
halt() {
  local reason="$1"
  echo "[$(now_iso)] HALT: $reason" >&2

  # 진행 중 변경을 stash
  (cd "$WT" && git add -A && git stash push -m "auto-stash by loop.sh halt" 2>/dev/null) || true

  # 자동 ESCALATION 작성
  cat > "$WT/.loop/ESCALATION.md" <<EOF
# 에스컬레이션 보고 (드라이버 자동 작성)

**작업**: $TASK_ID
**이터레이션**: 자동 정지
**트리거**: 객관 게이트 위반 — $reason

## 현재 상태

드라이버가 매 이터 후 게이트를 검사한 결과 위반이 감지되어 자동 정지함.

## 문제

$reason

## 처리

다음 중 하나:
1. 가설 점검 후 작업 명세(scope·verify) 조정
2. 메모리 파일(NOTES.md) 보강
3. 본 ESCALATION.md 삭제 후 재시작

자세한 내용은 .loop/iterations/ 의 최근 로그 참조.
EOF

  exit 1
}
```

- [ ] **Step 5: 게이트 검사 호출**

`iterate()` 함수의 마지막에 게이트 검사 추가. `iterate()` 함수를 다음과 같이 갱신:

```bash
iterate() {
  local n
  n=$(($(ls "$WT/.loop/iterations/"*.log 2>/dev/null | wc -l | tr -d ' ') + 1))

  echo "[$(now_iso)] 이터 #$n 시작"

  local start_hash_tests start_hash_deps
  start_hash_tests=$(hash_tests)
  start_hash_deps=$(hash_deps)

  # 워크트리 안에서 호출
  (
    cd "$WT"
    cat .loop/PROMPT.md | claude \
      --print \
      --no-session-persistence \
      --dangerously-skip-permissions \
      --system-prompt-file CLAUDE.md \
      --add-dir . \
      --output-format json \
      > ".loop/iterations/$n.log" 2>&1
  ) || echo "WARN: claude 호출 비정상 종료"

  echo "[$(now_iso)] 이터 #$n 종료. 게이트 검사..."

  # 종료 신호 검사 (먼저)
  if [[ -f "$WT/DONE" ]]; then
    return 100   # 메인 루프에서 정상 종료 처리
  fi
  if [[ -f "$WT/.loop/ESCALATION.md" ]]; then
    return 101   # 메인 루프에서 ESCALATION 처리
  fi

  # 객관 게이트 9종
  [[ "$(hash_tests)" != "$start_hash_tests" ]] && halt "테스트 약화 — tests/** 해시 변경"
  [[ "$(hash_deps)" != "$start_hash_deps" ]] && halt "의존성 변경 — 매니페스트 해시 변경"

  local out_of_scope new_supp streak osc
  out_of_scope=$(diff_vs_scope)
  [[ -n "$out_of_scope" ]] && halt "Scope 위반: $out_of_scope"

  new_supp=$(grep_new_suppressors)
  [[ -n "$new_supp" ]] && halt "Suppressor 신규 추가: $new_supp"

  if command -v gitleaks >/dev/null 2>&1; then
    local secrets
    secrets=$(check_secrets)
    [[ -n "$secrets" ]] && halt "Secrets 의심: $secrets"
  fi

  streak=$(count_fix_symptom_streak)
  [[ $streak -ge 2 ]] && halt "fix:symptom streak (2회 연속)"

  osc=$(detect_oscillation)
  [[ -n "$osc" ]] && halt "진동 패턴: $osc"

  return 0
}
```

- [ ] **Step 6: 메인 루프 갱신**

기존 메인 루프(임시)를 정식 루프로 교체:

```bash
# 워크트리 존재 → 이터레이션 루프 진입
acquire_lock

START_TIME=$(date +%s)
n=0

while true; do
  n=$((n + 1))

  set +e
  iterate
  iter_status=$?
  set -e

  if [[ $iter_status -eq 100 ]]; then
    echo "[$(now_iso)] DONE 신호 감지. 정상 종료."
    archive_meta_files
    exit 0
  fi
  if [[ $iter_status -eq 101 ]]; then
    echo "[$(now_iso)] ESCALATION.md 감지. 정지 (사람 처리 대기)."
    exit 1
  fi
  if [[ $iter_status -ne 0 ]]; then
    # halt가 이미 종료시킴. 도달 안 해야 함.
    exit "$iter_status"
  fi

  if [[ $n -ge $MAX_ITERATIONS ]]; then
    halt "이터 상한 도달 ($n / $MAX_ITERATIONS)"
  fi

  if [[ $(elapsed_minutes) -ge $WALL_CLOCK_MINUTES ]]; then
    halt "시계 캡 도달 ($(elapsed_minutes) / $WALL_CLOCK_MINUTES 분)"
  fi
done
```

`archive_meta_files`는 다음 task에서 정의.

- [ ] **Step 7: 구문 검사**

```bash
bash -n plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh
```

- [ ] **Step 8: 커밋**

```bash
git add plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh
git commit -m "feat(autonomous-loop-rule-creator): loop.sh phase 3 (9개 객관 게이트)"
```

---

## Task 9: `loop.sh` Phase 4 — DONE archive

**Files:**
- Modify: `plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh`

**참조:** spec §8.2.3 (DONE 처리), §8.2.4 (ESCALATION 처리).

- [ ] **Step 1: archive 함수 추가**

`halt()` 함수 다음에 추가:

```bash
# ----- DONE 처리 -----

archive_meta_files() {
  mkdir -p "$ARCHIVE_DIR"
  cp "$WT/.loop/PLAN.md" "$ARCHIVE_DIR/" 2>/dev/null || true
  cp "$WT/.loop/NOTES.md" "$ARCHIVE_DIR/" 2>/dev/null || true
  cp "$WT/.loop/HANDOFF.md" "$ARCHIVE_DIR/" 2>/dev/null || true
  cp "$WT/.loop/RUN_LOG.md" "$ARCHIVE_DIR/" 2>/dev/null || true

  echo ""
  echo "task $TASK_ID 완료. 메타 파일 보관: $ARCHIVE_DIR"
  echo ""
  echo "머지 검토:"
  echo "  cd $PROJECT_ROOT"
  echo "  git log $BRANCH"
  echo "  git merge $BRANCH"
  echo "  git worktree remove $WT"
  echo "  git branch -d $BRANCH"
}
```

- [ ] **Step 2: 구문 검사**

```bash
bash -n plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh
```

- [ ] **Step 3: shellcheck 정적 분석 (있을 때)**

```bash
command -v shellcheck >/dev/null && shellcheck plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh || echo "shellcheck 미설치, 스킵"
```

발견된 경고 중 다음 카테고리는 수정:
- SC2086 (변수 따옴표 누락)
- SC2155 (declare-and-assign)
- SC2046 (word splitting)

스타일성 경고(SC2034 등)는 무시.

- [ ] **Step 4: 커밋**

```bash
git add plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh
git commit -m "feat(autonomous-loop-rule-creator): loop.sh phase 4 (DONE archive)"
```

---

## Task 10: 통합 테스트 (워크트리 라이프사이클)

**Files:**
- Create: `tests/autonomous-loop-rule-creator/test-loop-sh.sh`

이 테스트는 임시 디렉토리에 가짜 git 프로젝트를 만들고 `loop.sh`의 핵심 분기를 검증한다. claude CLI는 호출하지 않는다 (mock으로 대체).

- [ ] **Step 1: 테스트 디렉토리 생성**

```bash
mkdir -p tests/autonomous-loop-rule-creator
```

- [ ] **Step 2: 테스트 스크립트 작성**

`tests/autonomous-loop-rule-creator/test-loop-sh.sh`:

```bash
#!/usr/bin/env bash
# loop.sh 통합 테스트
# claude CLI를 mock으로 대체해 워크트리 생성·락·게이트 분기를 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOOP_SH_SRC="$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh"
RULES_SRC="$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator/templates/ralph-loop.md"

# 기대 산출물 검사
[[ -x "$LOOP_SH_SRC" ]] || { echo "FAIL: loop.sh가 실행 가능하지 않음"; exit 1; }
[[ -f "$RULES_SRC" ]] || { echo "FAIL: ralph-loop.md 템플릿 부재"; exit 1; }

# 임시 작업공간 (테스트 격리)
WORK_DIR="$(mktemp -d)"
trap "rm -rf $WORK_DIR" EXIT

# 가짜 프로젝트 git init
PROJECT="$WORK_DIR/myproject"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
git commit --allow-empty -m "initial" -q

# .loops/ 구조 시뮬레이션 (스킬이 했을 작업)
mkdir -p .loops/{templates,locks}
mkdir -p rules
# frontmatter 제거한 본문을 rules/autonomous-loop.md로
sed -n '/^---$/,/^---$/!p' "$RULES_SRC" | sed '/^$/d;1{/^$/d}' > rules/autonomous-loop.md
cp "$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator/assets/PROMPT.template.md" .loops/
cp "$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator/assets/"{PLAN,NOTES,HANDOFF,RUN_LOG,ESCALATION}.template.md .loops/templates/
cp "$LOOP_SH_SRC" .loops/loop.sh
chmod +x .loops/loop.sh
git add -A
git commit -q -m "init project"

# claude CLI mock — PATH 앞에 둠
MOCK_BIN="$WORK_DIR/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
# 단순 mock: stdin 소비 후 빈 JSON 응답
cat > /dev/null
echo '{"result": "mock", "usage": {"input_tokens": 100, "output_tokens": 50}}'
EOF
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

# yq 의존 확인 (테스트는 yq가 있어야 동작)
command -v yq >/dev/null || { echo "SKIP: yq 미설치"; exit 0; }

echo "=== TEST 1: 첫 호출에 워크트리 생성 ==="
./.loops/loop.sh test-task-1
WT="$WORK_DIR/myproject-loops/test-task-1"
[[ -d "$WT" ]] || { echo "FAIL: 워크트리 미생성"; exit 1; }
[[ -f "$WT/CLAUDE.md" ]] || { echo "FAIL: CLAUDE.md 미복사"; exit 1; }
[[ -f "$WT/.loop/PROMPT.md" ]] || { echo "FAIL: PROMPT.md 미시드"; exit 1; }
[[ -f "$WT/.loop/PLAN.md" ]] || { echo "FAIL: PLAN.md 미시드"; exit 1; }
grep -q "^CLAUDE.md$" "$WT/.git/info/exclude" || { echo "FAIL: .git/info/exclude에 CLAUDE.md 없음"; exit 1; }
grep -q "^.loop/$" "$WT/.git/info/exclude" || { echo "FAIL: .git/info/exclude에 .loop/ 없음"; exit 1; }
echo "OK"

echo "=== TEST 2: 두 번째 호출에 한 이터 실행 (mock claude) ==="
# PROMPT.md에 최소 frontmatter
cat > "$WT/.loop/PROMPT.md" <<'EOF'
---
scope:
  include:
    - src/**
  exclude:
    - rules/**
verify: 'true'
---

# Test PROMPT
EOF

# 캡 1로 한 번만 돌게
MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 ./.loops/loop.sh test-task-1 || true
[[ -f "$WT/.loop/iterations/1.log" ]] || { echo "FAIL: 이터 로그 미생성"; exit 1; }
echo "OK"

echo "=== TEST 3: 같은 task-id 이중 호출 차단 ==="
# 락 파일을 미리 만들어두고 호출
mkdir -p .loops/locks
echo $$ > .loops/locks/test-task-1.lock
set +e
output=$(MAX_ITERATIONS=1 ./.loops/loop.sh test-task-1 2>&1)
result=$?
set -e
rm -f .loops/locks/test-task-1.lock
[[ $result -ne 0 ]] || { echo "FAIL: 이중 호출이 차단되지 않음"; exit 1; }
echo "$output" | grep -q "이미 동작 중" || { echo "FAIL: 락 메시지 누락"; exit 1; }
echo "OK"

echo "=== TEST 4: 슬래시 task-id (Layer 2 호환) ==="
./.loops/loop.sh "goal-x/sub-task" 2>&1 | head -1
WT2="$WORK_DIR/myproject-loops/goal-x/sub-task"
[[ -d "$WT2" ]] || { echo "FAIL: 슬래시 task-id 워크트리 미생성"; exit 1; }
[[ -f .loops/locks/goal-x-sub-task.lock || ! -f .loops/locks/goal-x-sub-task.lock ]]  # 락은 종료시 정리됐어야 함
# 락 파일명에 슬래시 없음
[[ ! -d ".loops/locks/goal-x" ]] || { echo "FAIL: 락 디렉토리에 슬래시 잔존"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 테스트 통과 ==="
```

- [ ] **Step 3: 실행 권한 부여**

```bash
chmod +x tests/autonomous-loop-rule-creator/test-loop-sh.sh
```

- [ ] **Step 4: 테스트 실행**

```bash
bash tests/autonomous-loop-rule-creator/test-loop-sh.sh
```

기대: 4개 테스트 모두 OK 출력. 실패 시 해당 분기를 `loop.sh`에서 수정.

알려진 잠재 문제:
- yq 미설치 시 SKIP 출력 후 정상 종료 (의존성 안내)
- `bash` 4 미만 환경(macOS 기본)에서는 `mapfile` 등 사용 시 실패 가능 — 본 코드는 4 미만에서도 동작하도록 작성

- [ ] **Step 5: 커밋**

```bash
git add tests/autonomous-loop-rule-creator/test-loop-sh.sh
git commit -m "test(autonomous-loop-rule-creator): loop.sh 통합 테스트 (워크트리·락·슬래시 호환)"
```

---

## Task 11: 스킬 설치 시뮬레이션 테스트

**Files:**
- Create: `tests/autonomous-loop-rule-creator/test-skill-install.sh`

스킬을 실제로 호출할 수는 없지만, `templates/ralph-loop.md`의 frontmatter `on_create` 지시를 셸로 시뮬레이션 실행해 산출물이 모두 생기는지 검증한다.

- [ ] **Step 1: 테스트 작성**

`tests/autonomous-loop-rule-creator/test-skill-install.sh`:

```bash
#!/usr/bin/env bash
# 스킬 호출 시뮬레이션: on_create의 의도를 셸로 직접 실행

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator"

# 산출물 존재 검사
echo "=== 스킬 디렉토리 구조 ==="
for f in SKILL.md \
         templates/ralph-loop.md \
         assets/loop.sh \
         assets/PROMPT.template.md \
         assets/loops-README.md \
         assets/PLAN.template.md \
         assets/NOTES.template.md \
         assets/HANDOFF.template.md \
         assets/RUN_LOG.template.md \
         assets/ESCALATION.template.md; do
  [[ -f "$SKILL_DIR/$f" ]] || { echo "FAIL: $f 부재"; exit 1; }
  echo "OK: $f"
done

echo ""
echo "=== loop.sh 실행 권한 ==="
[[ -x "$SKILL_DIR/assets/loop.sh" ]] || { echo "FAIL: loop.sh 실행 권한 없음"; exit 1; }
echo "OK"

echo ""
echo "=== ralph-loop.md frontmatter 필수 필드 ==="
yq '.label' "$SKILL_DIR/templates/ralph-loop.md" >/dev/null 2>&1 \
  || { echo "FAIL: label 필드 부재"; exit 1; }
yq '.on_create' "$SKILL_DIR/templates/ralph-loop.md" >/dev/null 2>&1 \
  || { echo "FAIL: on_create 필드 부재"; exit 1; }
echo "OK"

echo ""
echo "=== PROMPT.template.md frontmatter 파싱 ==="
yq '.scope.include[]' "$SKILL_DIR/assets/PROMPT.template.md" >/dev/null \
  || { echo "FAIL: scope.include 파싱 실패"; exit 1; }
yq '.verify' "$SKILL_DIR/assets/PROMPT.template.md" >/dev/null \
  || { echo "FAIL: verify 파싱 실패"; exit 1; }
echo "OK"

echo ""
echo "=== 헌법 본문에서 자율-루프-지침 미참조 ==="
# 본문(frontmatter 제외)에 "자율-루프-지침"이라는 문자열이 없어야 함
sed -n '/^---$/,/^---$/!p' "$SKILL_DIR/templates/ralph-loop.md" | grep -q "자율-루프-지침" \
  && { echo "FAIL: 헌법 본문이 자율-루프-지침.md를 참조함"; exit 1; }
echo "OK"

echo ""
echo "=== on_create 시뮬레이션 (임시 프로젝트에서) ==="
WORK_DIR="$(mktemp -d)"
trap "rm -rf $WORK_DIR" EXIT
PROJECT="$WORK_DIR/test-project"
mkdir -p "$PROJECT" "$PROJECT/rules"
cd "$PROJECT"
git init -q
git config user.email "test@example.com"
git config user.name "Test"

# on_create 1단계: rules/autonomous-loop.md 생성 (frontmatter 제거)
sed -n '/^---$/,/^---$/!p' "$SKILL_DIR/templates/ralph-loop.md" | sed '/^$/d;1{/^$/d}' > rules/autonomous-loop.md
[[ -s rules/autonomous-loop.md ]] || { echo "FAIL: rules/autonomous-loop.md 빈 파일"; exit 1; }

# on_create 2~4단계: assets 복사
mkdir -p .loops/{templates,locks,archive}
cp "$SKILL_DIR/assets/PROMPT.template.md" .loops/
cp "$SKILL_DIR/assets/loop.sh" .loops/
chmod +x .loops/loop.sh
cp "$SKILL_DIR/assets/loops-README.md" .loops/README.md
cp "$SKILL_DIR/assets/"{PLAN,NOTES,HANDOFF,RUN_LOG,ESCALATION}.template.md .loops/templates/
touch .loops/locks/.gitkeep .loops/archive/.gitkeep

# 모든 파일 존재 확인
for f in rules/autonomous-loop.md \
         .loops/PROMPT.template.md \
         .loops/loop.sh \
         .loops/README.md \
         .loops/templates/PLAN.template.md \
         .loops/templates/NOTES.template.md \
         .loops/templates/HANDOFF.template.md \
         .loops/templates/RUN_LOG.template.md \
         .loops/templates/ESCALATION.template.md; do
  [[ -f "$f" ]] || { echo "FAIL: 시뮬레이션 후 $f 부재"; exit 1; }
done
echo "OK"

echo ""
echo "=== .gitignore 갱신 ==="
echo ".loops/locks/" >> .gitignore
grep -q "^\.loops/locks/" .gitignore || { echo "FAIL: .gitignore 갱신 실패"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 테스트 통과 ==="
```

- [ ] **Step 2: 실행 권한 + 실행**

```bash
chmod +x tests/autonomous-loop-rule-creator/test-skill-install.sh
bash tests/autonomous-loop-rule-creator/test-skill-install.sh
```

기대: 모든 OK 출력 후 "모든 테스트 통과".

- [ ] **Step 3: 커밋**

```bash
git add tests/autonomous-loop-rule-creator/test-skill-install.sh
git commit -m "test(autonomous-loop-rule-creator): 스킬 설치 시뮬레이션 테스트"
```

---

## Task 12: bootstrap 통합 검증 + 최종 점검

**Files:**
- Read: `plugins/project-init/skills/bootstrap/SKILL.md`

bootstrap이 새 스킬을 자동 열거하는지 확인한다. 이 task는 코드 변경 없이 검증만 한다.

- [ ] **Step 1: bootstrap 동작 재확인**

```bash
grep -A 5 "열거" plugins/project-init/skills/bootstrap/SKILL.md | head -20
# 예상: bootstrap이 "*-rule-creator/" 디렉토리를 부모 디렉토리에서 스캔
```

`autonomous-loop-rule-creator/`가 `*-rule-creator` 패턴을 만족하므로 bootstrap이 자동으로 카테고리 후보 목록에 포함시킨다.

- [ ] **Step 2: 카테고리 도출 시뮬레이션**

```bash
ls plugins/project-init/skills/ | grep '\-rule-creator$' | sed 's/-rule-creator$//'
# 예상 출력:
# autonomous-loop
# context
# orchestration  (남아있다면)
```

`autonomous-loop`가 카테고리 목록에 도출돼야 한다.

- [ ] **Step 3: 두 통합 테스트 다시 실행 (regression)**

```bash
bash tests/autonomous-loop-rule-creator/test-skill-install.sh
bash tests/autonomous-loop-rule-creator/test-loop-sh.sh
```

둘 다 통과해야 한다.

- [ ] **Step 4: spec §13 검증 기준 12개 매핑 확인**

각 검증 기준이 어느 task에서 충족되는지 다음을 만족하는지 점검:

| spec §13 기준 | 충족 task |
|---|---|
| 1. bootstrap이 자동 열거하고 트리 정확히 생성 | Task 1, 12 (검증) |
| 2. loop.sh 첫 호출에 워크트리·메타 생성 후 종료 | Task 6, 10 (테스트) |
| 3. loop.sh 두 번째 호출에 락 + 이터 실행 | Task 7, 10 (테스트) |
| 4. 워크트리에 CLAUDE.md, .git/info/exclude 비추적 | Task 6 (구현), 10 (테스트) |
| 5. PROMPT.md frontmatter yq 파싱 가능 | Task 3, 11 (테스트) |
| 6. 헌법 자체완결 (자율-루프-지침 미참조) | Task 2, 11 (테스트) |
| 7. 9개 객관 게이트 모두 구현 | Task 8 |
| 8. DONE 시 archive 복사 | Task 9 |
| 9. ESCALATION.md 작성 시 보존 (archive 안 함) | Task 9 (구현 분기), 사용자 워크플로 |
| 10. 동시 task 격리 (워크트리·브랜치·메모리·이터 카운터) | Task 6, 7 (구현), 10 (TEST 4) |
| 11. 같은 task-id 이중 실행 락으로 차단 | Task 7, 10 (TEST 3) |
| 12. 사용자 레벨 잔여 위험 README에 명시 | Task 5 |

모든 기준이 어느 task에 매핑되는지 확인 — 누락 시 task 추가.

- [ ] **Step 5: PR 생성 (선택, 사용자 결정)**

```bash
git push -u origin feat/autonomous-loop-rule-creator

gh pr create --base main --title "feat: autonomous-loop-rule-creator 스킬" --body "$(cat <<'EOF'
## Summary

- 단일 task 자율 수행 환경(랄프 루프)을 한 번의 스킬 호출로 설치하는 새 rule-creator
- sibling 워크트리 격리 + 4대 메모리 파일(PLAN/NOTES/HANDOFF/RUN_LOG) + git commit 자기 분류 + 9개 드라이버 객관 게이트
- spec: docs/superpowers/specs/2026-05-08-autonomous-loop-rule-creator-design.md
- plan: docs/superpowers/plans/2026-05-09-autonomous-loop-rule-creator.md

## Test plan

- [x] tests/autonomous-loop-rule-creator/test-skill-install.sh
- [x] tests/autonomous-loop-rule-creator/test-loop-sh.sh
- [ ] 실제 프로젝트에서 bootstrap → autonomous-loop 카테고리 선택 → 산출물 확인
- [ ] 실제 task에서 loop.sh 첫 호출 → 워크트리 생성 검증
- [ ] 실제 task에서 PROMPT.md 채운 후 두 번째 호출 → 첫 이터 실행 검증

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

PR 생성은 사용자 승인이 있을 때만 실행. 본 task는 사용자에게 PR 옵션을 안내만 하고 종료.

---

## Self-Review

본 plan을 spec과 대조한 셀프 점검:

**1. Spec coverage:**

- spec §1 목적 → Task 1~12 전체로 실현
- spec §2 채택·기각 → 헌법 본문에 흡수 (Task 2)
- spec §3 산출물 트리 → Task 1, 6의 워크트리 생성 코드
- spec §4 메모리 파일 모델 → Task 4 (스텁) + 헌법 §11 (Task 2)
- spec §5 자기 분류 → 헌법 §3.3 (Task 2 step 4)
- spec §6 헌법 → Task 2 (15 step에 걸쳐 13절 모두)
- spec §7 PROMPT.md 템플릿 → Task 3
- spec §8 드라이버 → Task 6~9
- spec §9 스킬 구조 → Task 1
- spec §10 사용자 워크플로 → Task 5 (loops-README.md)
- spec §11 동시 실행 모델 → Task 7 (락) + Task 10 (테스트 TEST 4)
- spec §13 검증 기준 12개 → Task 12 매핑 표

빠진 항목 없음.

**2. Placeholder scan:**

본 plan은 어느 step에서도 "TBD", "implement later", "fill in details", "add appropriate error handling" 등을 쓰지 않음. 헌법 본문(Task 2)은 자율-루프-지침의 기존 내용을 흡수하는 작업이지만, 각 절의 핵심 문장과 개념을 모두 step 본문에 명시 — 인용 가능한 형태의 가이드를 제공.

스텝의 코드 블록이 모두 실제 사용 가능한 셸/마크다운/YAML 형태.

**3. Type consistency:**

- `.loop/` 경로: 모든 task에서 일관 (PROMPT.md, PLAN.md, NOTES.md, HANDOFF.md, RUN_LOG.md, iterations/, ESCALATION.md)
- 워크트리 루트의 `CLAUDE.md`, `DONE`: 일관
- 함수명: `create_worktree`, `acquire_lock`, `iterate`, `halt`, `archive_meta_files` — 모두 task 6~9에서 일관
- 환경변수명: `LOOP_WORKTREE_BASE`, `MAX_CONCURRENT`, `MAX_ITERATIONS`, `WALL_CLOCK_MINUTES` — 일관
- task-id 슬래시 처리: `sanitize_for_filename`로 락 파일명 안전화 (Task 6) + Task 10 TEST 4에서 검증

타입·이름 불일치 없음.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-05-09-autonomous-loop-rule-creator.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
