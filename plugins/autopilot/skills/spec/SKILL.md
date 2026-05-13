---
name: spec
description: "autopilot loop이 입력으로 받는 SPEC.md를 대화형으로 생성. 한 질문씩 명확화·섹션별 승인·EARS 포맷·[NEEDS CLARIFICATION] 마커로 자율 loop이 도중 질문 없이 완수 가능한 자기완결적 SPEC을 만듭니다. SPEC.md 작성 후 결정적 슬러그화 규칙(ASCII 영숫자·하이픈만)으로 `feat/<task-id>-<slug>` 브랜치를 main에서 분기·SPEC.md를 commit해 loop·PR 흐름이 단일 feature 브랜치로 통합되게 합니다. 호출 'Skill(skill=\"spec\", args=\"<task-id> [--milestone <m>] [--resume]\")'. milestone 미지정 시 `regular`(catch-all)을 default로 적용."
allowed-tools: AskUserQuestion, Read, Write, Skill, Bash(git log:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git checkout:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*), Bash(git show-ref:*), Bash(git for-each-ref:*), Bash(ls:*), Bash(cat:*), Bash(find:*), Bash(mkdir:*), Bash(grep:*), Bash(echo:*), Bash(head:*), Bash(tr:*), Bash(sed:*), Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh issue create:*), Bash(gh issue edit:*), Bash(gh project item-list:*), Bash(gh project item-edit:*), Bash(gh project item-add:*), Bash(gh api:*)
---

# spec

`autopilot:loop` 스킬이 입력으로 받는 `milestones/<m>/loops/<c>/SPEC.md`를 대화형으로 생성. 자율 loop이 도중 질문 없이 완수할 수 있는 자기완결적 SPEC이 목표.

## 호출 방법

- 새 SPEC: `Skill(skill: "spec", args: "<task-id> [--milestone <m>]")`
- 마커 해결 모드: `Skill(skill: "spec", args: "<task-id> [--milestone <m>] --resume")`

milestone 미지정 시 `regular`(catch-all)을 default로 적용 — sibling `autopilot:loop`이 단일 컴포넌트 task-id를 `regular/<task-id>`로 정규화하는 컨벤션과 일치. `autopilot:dispatch` 등 milestone 분해 컨텍스트에서 호출할 때는 `--milestone <m>`을 명시.

또는 사용자가 자연어로 의도 전달 시 모델이 자동 호출.

## 10단계 워크플로

호출 시 다음 10단계를 TodoWrite로 등록·실행. 각 단계는 사용자 결정·승인을 `AskUserQuestion`으로 받습니다.

### 1. 사전 검사

- task-id 형식 검증 (loop.sh의 `validate_task_id`와 동일 규칙): 비어 있거나, `..` 포함, `.` 단독 컴포넌트(`.`·`./foo`·`foo/.`·`a/./b`), `__` 포함, 공백 포함 시 검증 실패. 슬래시(`/`)는 `--milestone <m>`이 명시된 경우에만 허용 — milestone이 별도 인자로 분리된 뒤의 nested task-id(`sub-area/child` 등)가 정상 사용 사례. `--milestone` 미지정 + 슬래시 포함 task-id는 검증 실패 — loop.sh의 `normalize_task_id`가 슬래시 있는 task-id의 첫 컴포넌트를 milestone으로 해석하므로 spec의 default(`regular`)와 어긋나 `--resume` 라운드트립이 깨짐. 슬래시 포함 task-id를 쓰려면 `--milestone <m>`을 명시. spec 스킬과 loop이 같은 (milestone, task-id) 쌍을 받아들여야 `--resume` 라운드트립이 성립.
- milestone 인자 파싱: `--milestone <m>` 명시 시 `<m>`을 milestone으로 사용. 미지정 시 `regular`(catch-all)을 default로 적용. milestone 자체에도 task-id와 동일한 형식 검증을 적용 (단, milestone은 단일 컴포넌트 — `/` 미허용).
- 자연어 입력 감지: 인자가 task-id 패턴이 아닌 자연어 문장으로 보이는 경우(물음표·따옴표·문장 부호 다중, 길이 ≥ 40자 등 휴리스틱)도 검증 실패로 분류 — 즉시 abort 대신 아래 **검증 실패 라우팅**으로 진입.
- 검증이 통과되면 아래 일반/--resume 모드 분기로 진행. 어떤 형태의 검증 실패든 직접 abort/die 하지 않고 라우팅으로 분기한다.
- **일반 모드**: `milestones/<m>/loops/<c>/` 존재 시 abort + `AskUserQuestion`으로 3옵션 (다른 task-id / `--resume` / 백업 후 새로). 본 절 이후 `<c>`는 task-id를 지칭.
- **--resume 모드**: `milestones/<m>/loops/<c>/SPEC.md` 부재 시 abort. 잔존 `[NEEDS CLARIFICATION` 마커 0개 시 "해결할 마커 없음" 안내 후 종료

#### 1.1 검증 실패 라우팅

task-id 형식 검증 실패 또는 자연어 입력 감지 시, 즉시 종료하지 않고 `AskUserQuestion`으로 사용자 의도를 분류하는 3옵션을 제시한다 (프로젝트 CLAUDE.md의 "사용자에게 결정·승인·선택·해명을 요청할 때는 예외 없이 AskUserQuestion 도구를 사용" 규칙과 동일 정신):

- **(a) 올바른 task-id 재입력 후 검증 재시도** — 사용자가 새 task-id를 입력하면 step 1 검증을 재실행. 통과 시 정상 spec 흐름(일반/--resume 분기)으로 복귀.
- **(b) 사전 명확화 라운드 진입** — 아직 task-id가 확보되지 않은 상태로 step 5 명확화 라운드 메커니즘을 *앞당겨* 적용 (별도 phase 신설 없음, 동일 메커니즘 재사용). 자세한 흐름은 §1.2.
- **(c) 종료** — SPEC.md를 작성하지 않고 종료. 어떠한 산출물도 남기지 않는다. 라우팅 AskUserQuestion에 응답 없이 종결될 경우도 동일.

옵션 표기는 본문에서 `(a)`/`(b)`/`(c)` 형식을 유지한다. "다음 단계: Skill(...)" 형식의 자유 텍스트 안내는 출력하지 않는다 — 후속 스킬 호출은 항상 AskUserQuestion 확인 후 invoke한다.

#### 1.2 사전 명확화 라운드 (step 5 앞당김)

(b) 선택 시 진입. 핵심 원칙: spec의 기존 step 5 명확화 라운드를 task-id 확보 *전* 단계로 앞당긴 것이다. 별도 phase·신규 모듈을 만들지 않고 같은 인터랙션 규칙을 그대로 적용한다.

- 한 번에 한 질문(`AskUserQuestion`, 가능하면 멀티초이스). 답변이 다음 질문 형태를 결정. 한 호출에 관련 소문항 최대 4개.
- 수집 항목:
  - 문제: 사용자가 해결하려는 것 (한 줄)
  - 목표: 완료 시 어떤 상태가 되는가
  - 범위: 포함 영역과 비-목표
  - 제약: 환경·도구·호환성·이미 시도한 dead-end

  (step 5는 task가 이미 정의된 상태에서 `핵심 목적·성공 기준·알려진 제약·알려진 위험`을 묻지만, §1.2는 task 자체를 아직 정의하지 않은 상태이므로 `문제·목표·범위·제약`으로 폭을 넓힌다. 메커니즘은 동일하지만 수집 항목은 단계 목적에 맞춰 달리한다.)
- 매 라운드 사용자 측 "충분" 종결 옵션을 `AskUserQuestion`에 포함해 무한 Q&A를 방지한다.
- 사용자가 라운드 중 명시적으로 **취소**를 선택하면 task를 생성하지 않고 어떠한 산출물도 남기지 않고 종료한다 (§1.1 (c)와 동일 안전 종료).

라운드가 수렴하면 규모에 따라 분기:

##### 1.2.1 단일 task 규모 수렴 → 프로젝트 태스크 관련 지침

수집된 문제·목표·범위·제약이 단일 task 규모로 정리되면, **프로젝트의 태스크 관련 지침**(예: `CLAUDE.md`·`rules/`의 issue 생성 컨벤션, GitHub project 운영 규칙 등)에 따라 task를 생성해 task-id를 확보한다. 본 스킬은 그 구조를 재정의하지 않고 프로젝트 지침의 issue body 구조(목표·배경·제안·검증 계획·DoD 등)를 그대로 따른다.

task-id 확보 후 spec의 **step 2(task 상태 정합)부터 그 task-id로 재개**한다. 라운드에서 합의된 문제·목표·범위·제약은 step 3 이후 단계의 섹션 초안으로 손실 없이 이어진다 (step 7 섹션별 SPEC 제시 시 사전 합의 내용을 초안으로 사용).

task 생성 자체는 외부 도구(`gh` CLI, GitHub project 접근 등 프로젝트 지침이 정한 경로)에 의존한다. 실패 시 사용자에게 명시적으로 알리고 부분 산출물을 남기지 않고 안전하게 종료한다 — `milestones/<m>/loops/<c>/` 디렉터리도 생성하지 않는다.

##### 1.2.2 마일스톤 규모 수렴 → PRD 라우팅 (AskUserQuestion 승인 필수)

수집된 내용이 다수 task로 분해될 마일스톤 규모로 판명되면, **PRD 스킬 호출 여부를 AskUserQuestion으로 묻는다**. 사용자의 명시적 승인이 있을 때만 PRD 스킬을 invoke한다 — "다음 단계: Skill(...)" 자유 텍스트 안내로 대체하지 않는다.

PRD 스킬은 `milestone-id`를 요구하므로, spec은 PRD 스킬을 invoke하기 전 사용자에게 milestone-id를 받아 `Skill(skill: "prd", args: "<milestone-id>")` 인자로 전달할 책임이 있다. milestone-id 형식 검증은 prd 스킬 step 1이 다시 수행하므로 spec은 받아 넘기기만 한다.

승인이 없으면 PRD를 invoke하지 않고 종료. SPEC.md도 작성하지 않는다 — 산출은 단일 경로의 SPEC.md 또는 마일스톤 경로의 PRD.md 하나뿐이다.

### 2. task 상태 정합 (일반·--resume 두 모드 공통)

**사전 검사 통과 직후** 실행. task-id로 식별되는 외부 task를 조회하고 4갈래 분기로 상태를 설계 상태(`In Design`)로 정합한다. 본 단계는 일반 모드와 `--resume` 모드 모두에 동일하게 적용된다.

**백킹 시스템 매핑**: 본 프로젝트는 `rules/context.md`에 따라 **GitHub Project + Issue** 백엔드를 사용한다. 추상 상태 → 구체 매핑:

| 추상 상태 (SPEC) | GitHub Project Status field |
|---|---|
| 설계 상태 | `In Design` |
| 설계 이전 상태 | `Backlog` |
| 설계 이후 상태 | `In Progress`, `Review`, `Done`, `Blocked`, `Cancelled` 등 그 외 |

task-id ↔ Issue 매핑은 task-id 자체가 issue number(`#42` 또는 `42` 형식)이거나, task-id를 검색 키로 `gh issue list --search`로 단일 매칭을 찾는다. 본 프로젝트 컨벤션 외 다른 프로젝트에서 호출 시 `rules/context.md` 매핑을 재확인.

**조회 절차**:
- `gh issue view <task-id>` 또는 `gh issue list --search "<task-id>"`로 task 존재 확인.
- 존재 시 `gh project item-list <project>`로 해당 issue의 Status field 값 읽기.

**4갈래 분기**:

1. **(a) task 부재** (issue 조회 결과 없음): 새 issue를 `gh issue create`로 생성하고 `gh project item-add`로 Project에 추가 + Status를 `In Design`으로 설정. 새 issue number를 새 task-id로 사용하며 — 이후 워크플로의 `<c>`는 새 task-id로 **교체**한다. `AskUserQuestion`으로 사용자에게 새 task-id를 명시적으로 안내한 후 진행. 새 task-id에 대해 사전 검사(단계 1)의 폴더 존재 검사·형식 검증을 다시 적용한다 (위험: 새 task-id의 `milestones/<m>/loops/<c>/` 폴더가 이미 있을 수 있음).
2. **(b) 기존 task가 설계 상태(`In Design`)**: 상태를 변경하지 않고 다음 단계로 진행 (resume 케이스).
3. **(c) 기존 task가 설계 이전 상태(`Backlog`)**: `gh project item-edit`로 Status field를 `In Design`으로 전이한 뒤 다음 단계로 진행.
4. **(d) 기존 task가 설계 이후 상태(`In Progress`·`Review`·`Done` 등)**: 새 issue를 `gh issue create`로 생성·Project 추가·Status를 `In Design`으로 설정. 새 issue number로 task-id를 **교체**하고 `AskUserQuestion`으로 사용자에게 새 task-id를 명시적으로 안내한 후 진행. (a)와 동일하게 새 task-id에 대해 사전 검사를 재적용.

**(a)·(d) 새 issue 생성 시 title/body 수집**: step 2 시점에는 아직 명확화 라운드(step 5) 전이라 issue 본문에 쓸 문제·목표·범위가 수집되지 않은 상태다. 임의 값으로 채우면 실행 일관성이 깨지므로 다음 절차로 최소 정보를 명시적으로 확보한다:

- **Title**: `AskUserQuestion`으로 한 줄 제목을 수집 (1문항, 자유 입력 옵션 포함). 사용자가 "그대로 task-id 사용"을 선택하거나 입력이 비어 있으면 원래 task-id 문자열을 fallback 제목으로 사용한다.
- **Body**: 최소 본문은 다음 두 줄로 고정 — 임의 확장 금지:
  ```
  spec 워크플로우 step 2에서 자동 생성. 본문은 SPEC.md 작성·승인 후 갱신될 예정.
  SPEC: milestones/<m>/loops/<new-task-id>/SPEC.md
  ```
  `<new-task-id>` 플레이스홀더는 `gh issue create` 호출 시점엔 새 issue 번호를 모르므로 다음 절차로 처리한다 — `gh issue create`로 임시 body(`<new-task-id>` 리터럴 포함)를 올리고, 반환된 issue number(`N`)로 즉시 `gh issue edit N --body <substituted-body>`를 호출해 리터럴을 실제 번호로 치환한다. edit 실패 시 abort 규칙은 다른 `gh` 호출과 동일하다.

  명확화 라운드(step 5) 완료 시점에 본 issue 본문을 update할지 여부는 본 SPEC 범위 밖이며, 필요하면 사용자가 수동으로 보강한다.

본 절차로 입력이 결정된 뒤에만 `gh issue create --title <title> --body <body>`를 호출한다. 사용자가 title 수집 단계에서 명시적 취소를 선택하면 (a)·(d) 분기는 abort로 처리한다 — `milestones/` 디렉터리도 생성하지 않는다.

**호출 실패 시 abort**: task 조회·생성·편집·상태 전이 호출(`gh issue view`·`gh issue create`·`gh issue edit`·`gh project item-list`·`gh project item-edit`·`gh project item-add`) 중 어느 하나라도 0이 아닌 exit으로 실패하면 명확한 에러 메시지와 함께 abort. 자동 roll-back은 수행하지 않으며 부분 실패 상태로 다음 단계로 진행하지 않는다.

**범위 외 (비-목표)**: loop `start` 시점의 `In Design → In Progress` 전이, SPEC 승인 후 자동 후속 전이는 본 단계의 책임이 아니다 (다른 스킬·이벤트가 담당).

### 3. 컨텍스트 탐색

다음 명령으로 프로젝트 컨텍스트 자동 수집 (사용자에게 요약만):
```
git log --oneline -5
ls -A          # 최상위 트리만 (재귀 없음)
cat CLAUDE.md  # 있으면
ls rules/      # 있으면
find . -maxdepth 3 -type d \( -name 'tests' -o -name 'test' -o -name '__tests__' -o -name 'spec' \) 2>/dev/null | head -5
```

목적: 테스트 컨벤션·CLAUDE.md 룰·디렉터리 구조 파악. 모노레포여도 단계 5에서 좁힐 것이므로 깊이 탐색 안 함.

### 4. 범위 분해 게이트

`references/decomposition-gate.md` 휴리스틱으로 다중 서브시스템 검사. 감지 시 사용자에게 분해 제안.

`--resume` 모드: 이 단계 생략 (이미 SPEC 존재).

### 5. 명확화 라운드

한 번에 한 질문 (`AskUserQuestion`, 가능하면 멀티초이스). 답변이 다음 질문 형태를 결정.

수집할 정보:
- task의 핵심 목적 (한 줄)
- 성공 기준 (어떻게 "완료"를 판정하는가)
- 알려진 제약 (환경·도구·호환성)
- 알려진 위험 (이미 시도한 dead-end·금지 영역)

`--resume` 모드: 마커가 박힌 섹션 관련 질문만.

### 6. 접근법 비교 (조건부)

명확화에서 task가 비-자명한 설계 결정을 포함한다고 판단되면 2-3 접근법 + 트레이드오프 + 추천 제시. 자명하면 생략.

판단 기준 (하나라도 해당):
- 사용자가 "어떻게 할까?" 묻거나 모호한 요구를 표현
- 영향 받는 코드 영역이 둘 이상의 명확히 다른 패턴 사이에서 선택을 요구
- 외부 의존성·라이브러리 선택이 task 결과에 큰 영향

### 7. 섹션별 SPEC 제시·승인

다음 순서로 한 섹션씩 사용자에게 제시 → `AskUserQuestion`으로 "이 섹션 OK?" 확인:
1. 제목
2. 무엇을 만들 것인가 (WHAT/HOW 방어선 적용 — 기술 스택·파일 경로·라이브러리·클래스명 금지)
3. 수용 기준 (EARS, `references/ears-patterns.md` 참조)
4. 범위 (포함·비-목표)
5. 검증 (실행 가능한 명령)
6. 제약 (있을 때만)
7. 위험 (있을 때만)

승인 안 받은 섹션은 다시 제시·수정. 한 번에 통째로 보여주지 않음.

**EARS 작성 언어 해석 (`ears_language` frontmatter override).** 수용 기준(섹션 3) 산출
시점에 SPEC frontmatter의 `ears_language` 키를 읽어 디폴트와 override를 일관 적용한다:
- 값이 `en`·`ko`·`hybrid` 중 하나면 그 모드로 AC를 산출한다.
- 키가 미명시이면 **디폴트 `ko`**(프로젝트 기본 언어)로 산출한다.
- 사용자에게 작성 언어를 다시 묻지 않는다 — frontmatter 값 또는 default만으로 결정.
- 3모드 형식 정의·5패턴 예시·자유 텍스트→EARS 변환 규칙은 `references/ears-patterns.md`의
  "EARS 작성 언어" 절을 단일 출처(single source of truth)로 사용한다.

`--resume` 모드: 마커가 박힌 섹션만.

### 8. SPEC.md 작성

`references/spec-template.md` 읽어 placeholder 치환:
- `{{task_title}}` → 단계 7에서 합의된 제목 (없으면 task-id 그대로)
- `{{task_description}}` → 섹션 2 합의 내용
- `{{acceptance_criteria}}` → 섹션 3 합의 내용 (EARS 포맷)
- `{{scope_in}}` / `{{scope_out}}` → 본문 섹션 4 (사람이 읽는 형식)
- `{{scope_include}}` → frontmatter `scope.include` (YAML inline flow list 형식, 예: `["src/**", "tests/**"]`. 본문 `{{scope_in}}`과 같은 내용을 YAML 문법으로)
- `{{verify_command}}` → 본문 섹션 5 + frontmatter `verify` (둘 다 같은 placeholder)
- `{{constraints}}` / `{{risks}}` → 섹션 6/7. 빈 값이면 빈 줄 한 줄로 치환 (헤더는 남김)
- frontmatter `scope.exclude`는 고정 default(`rules/**`, `milestones/**`, `CLAUDE.md`) — 치환 대상 아님

미해결 항목은 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 박은 채 작성.

`mkdir -p milestones/<m>/loops/<c>` 후 `milestones/<m>/loops/<c>/SPEC.md`에 기록.

### 9. 자체 검토

`references/self-review.md` 5항목 체크 (placeholder · 모순 · 범위 · 모호성 · EARS fail-가능성). 발견 시 인라인 수정 또는 `[NEEDS CLARIFICATION]` 마커만 — 사용자 Q&A 없음(단계 10에서 일괄 해결). 재루프 없음. 수정·마커 후 SPEC.md 재기록.

### 9.5. feat 브랜치 + SPEC.md commit (자동, main 작업트리 무손상)

SPEC.md 작성과 자체 검토가 끝나면, sibling `autopilot:loop`이 worktree base로 사용할 `feat/<task-id>-<slug>` 브랜치를 main에서 분기·생성하고 SPEC.md를 그 브랜치에 commit한다. main 작업트리 상태(staged/unstaged/untracked)는 변경되지 않아야 한다.

이 단계를 단계 10의 사용자 최종 검토 *전*에 수행해 SPEC.md가 이미 git history에 반영된 상태에서 사용자가 결정을 내리도록 한다. 사용자가 단계 10에서 "변경" 옵션을 선택하면 단계 7/8 재진입 후 본 단계의 commit을 amend하거나 새 commit을 쌓는다 (자동 처리).

#### 9.5.1 슬러그화 규칙 (결정적)

SPEC §1 제목(첫 H1, `# ` 다음 텍스트)에서 `<slug>`를 도출:

1. ASCII 소문자로 변환
2. `[a-z0-9-]`가 아닌 모든 문자를 `-`로 치환 (UTF-8 멀티바이트는 바이트별 치환)
3. 연속된 `-`를 단일 `-`로 압축
4. 시작·끝의 `-` 제거

결과가 빈 문자열이면 `<slug>` 없이 `feat/<task-id>` 단독으로 fallback. 같은 SPEC 제목은 항상 같은 slug를 만든다.

구현 예 (bash):

```bash
title=$(sed -n '/^---$/,/^---$/!{/^# /{s/^# //p; q;}}' "milestones/<m>/loops/<c>/SPEC.md")
slug=$(printf '%s' "$title" \
  | LC_ALL=C tr '[:upper:]' '[:lower:]' \
  | LC_ALL=C tr -c 'a-z0-9-' '-' \
  | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')
```

#### 9.5.2 브랜치 생성·commit 절차

1. `git status --porcelain`으로 main 작업트리 상태 스냅샷 캡처. unstaged·untracked가 있으면 그 사실을 인지 (다음 단계의 git 동작이 영향 안 주도록 명시적 경로 사용).
2. 현재 브랜치 이름 보존: `orig_branch=$(git rev-parse --abbrev-ref HEAD)`.
3. 브랜치 이름 결정:
   - `branch="feat/<task-id>-<slug>"` (slug 비-empty 시)
   - `branch="feat/<task-id>"` (slug fallback)
4. `git show-ref --verify --quiet "refs/heads/$branch"`로 충돌 확인. 이미 존재하면 사용자에게 알리고 `AskUserQuestion`으로 (덮어쓰기 / 새 이름 / 종료) 선택.
5. `git checkout -b "$branch" main`으로 main에서 명시적으로 분기. base를 명시하지 않으면 호출 시점 HEAD에서 분기되어 비-main 브랜치에서 호출 시 엉뚱한 base로 feat 브랜치가 만들어진다. main 작업트리의 다른 변경은 그대로 따라옴 (이를 의도). SPEC.md만 add·commit하므로 다른 파일은 새 commit에 들어가지 않는다.
6. `git add "milestones/<m>/loops/<c>/SPEC.md"`로 명시적으로 SPEC.md만 staging (`git add .` 절대 금지).
7. `git commit -m "feat(spec): <task-id> — <title>" -- "milestones/<m>/loops/<c>/SPEC.md"`로 SPEC만 commit. `-- <pathspec>` 형식이 다른 staged 파일을 commit에서 격리.
8. `git checkout "$orig_branch"`로 원래 브랜치 복귀.
9. 복귀 후 `git status --porcelain` 결과가 step 1과 동일한지 검증. 다르면 사용자에게 경고.

#### 9.5.3 실패 처리

위 절차 중 어떤 단계라도 실패하면:
- 부분 결과 정리: 생성된 feat 브랜치가 있으면 `git branch -D "$branch"`로 삭제 (단, 그 브랜치에 다른 commit이 없을 때만; 의심스러우면 사용자에게 알리고 수동 정리 안내).
- 원래 브랜치 복귀: `git checkout "$orig_branch"`.
- 사용자에게 명시적으로 실패 사유와 복구 방법 안내. SPEC.md는 `milestones/<m>/loops/<c>/SPEC.md`에 그대로 남기되, loop 진행은 다음 단계에서 사용자가 결정.

### 10. 사용자 최종 검토

SPEC.md 경로(`milestones/<m>/loops/<c>/SPEC.md`)와 요약을 먼저 안내한 뒤, `AskUserQuestion`으로 **명시적 결정 입력**을 받는다 (자유 텍스트 안내·자유 텍스트 끝 질문 종결구 금지 — CLAUDE.md 규칙). 옵션은 다음 3개:

- **지금 loop start 호출** (Recommended) — 동일 task-id로 sibling 스킬을 자동 연계 호출: `Skill(skill: "loop", args: "start <m>/<c>")`. 사용자가 이 옵션을 선택하면 모델은 즉시 본 Skill 호출을 발행하며, 추가 모니터 결정 질문은 묻지 않고 loop 기본 동작(자동 Monitor 가설 포함, `plugins/autopilot/skills/loop/SKILL.md` 참조)을 그대로 적용한다. milestone이 default `regular`인 경우 `start <c>` 단축형도 동등 (loop.sh가 자동 정규화).
- **SPEC만 확정** — 경로만 안내하고 종료. 사용자가 이후 별도 시점에 `Skill(skill: "loop", args: "start <m>/<c>")`를 직접 호출.
- **변경** — 어느 섹션을 변경할지 묻고 단계 7/8 재진입.

세 옵션은 상호배타. "지금 loop start 호출"이라는 옵션 라벨에서 본 결정의 효과가 곧 sibling loop 스킬 호출임이 명확해야 한다.

## --resume 모드 요약

위 10단계 중:
- 1: 마커 0개 시 즉시 종료
- 2: 일반 모드와 동일하게 적용 — 사전 검사 통과 직후 task 상태 정합(4갈래 분기·abort) 수행. `--resume`은 보통 (b) 설계 상태 분기로 떨어져 상태 변경 없이 통과한다.
- 4: 생략 (이미 SPEC 존재)
- 5, 6: 마커 위치 기준으로 좁힘
- 7: 마커 박힌 섹션만
- 나머지 동일

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `spec-template.md` | SPEC.md placeholder 템플릿 (EARS 가이드·WHAT/HOW 방어선 주석 포함) |
| `ears-patterns.md` | 5개 EARS 패턴 사례·자유 텍스트→EARS 변환 가이드·Independent-Test 규칙 |
| `self-review.md` | 자체 검토 5항목 체크리스트 |
| `decomposition-gate.md` | 다중 서브시스템 감지 휴리스틱·분해 제안 흐름 |

## 규칙

- 본 스킬은 target 프로젝트의 `milestones/<m>/loops/<c>/SPEC.md`만 작성한다. 다른 파일 생성·수정 안 함.
- 모든 결정·선택·확인은 `AskUserQuestion`으로. 자유 텍스트 끝에 질문 종결구 다는 방식 금지 (CLAUDE.md 규칙).
- 한 주제씩 (한 `AskUserQuestion` 호출에 관련 소문항 최대 4개 허용).
- `[NEEDS CLARIFICATION` 마커는 `loop start`에서 차단됨. 사용자에게 명시적으로 마커가 박혔음을 알리고 `--resume`으로 해결하도록 안내.
