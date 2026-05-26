---
name: spec
description: "기능 추가·동작 수정·지침 작성·새로 만들기 등 새 코드 변경을 정의하는 자연어 신호에 대응. autopilot loop이 입력으로 받는, 도중 질문 없이 완수 가능한 자기완결적 SPEC.md를 대화형으로 작성하고 `feat/<task-id>-<slug>` 브랜치로 commit합니다. 호출 'Skill(skill=\"spec\", args=\"<task-id> [--milestone <m>] [--resume]\")'. milestone 미지정 시 `regular` default."
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Skill
  - Agent
  - Bash(git log:*)
  - Bash(git status:*)
  - Bash(git rev-parse:*)
  - Bash(git checkout:*)
  - Bash(git branch:*)
  - Bash(git add:*)
  - Bash(git commit:*)
  - Bash(git show-ref:*)
  - Bash(git for-each-ref:*)
  - Bash(ls:*)
  - Bash(cat:*)
  - Bash(find:*)
  - Bash(mkdir:*)
  - Bash(grep:*)
  - Bash(echo:*)
  - Bash(head:*)
  - Bash(git -C * rev-parse:*)
  - Bash(git -C * status --porcelain)
  - Bash(git -C * log:*)
  - Bash(git -C * branch:*)
  - Bash(git -C * show-ref:*)
  - Bash(git -C * for-each-ref:*)
  - Bash(git -C * ls-files:*)
  - Bash(git -C * diff:*)
  - Bash(git -C * checkout:*)
  - Bash(git -C * checkout -b:*)
  - Bash(git -C * add:*)
  - Bash(git -C * commit:*)
  - Bash(git update-ref:*)
  - Bash(git -C * hash-object -w:*)
  - Bash(GIT_INDEX_FILE=* git -C * read-tree:*)
  - Bash(GIT_INDEX_FILE=* git -C * update-index --add --cacheinfo:*)
  - Bash(GIT_INDEX_FILE=* git -C * write-tree)
  - Bash(git -C * commit-tree * -p:*)
  - Bash(mkdir -p milestones/**)
  - Bash(awk:*)
  - Bash(sed:*)
  - Bash(tr:*)
  - Bash(grep -rE * plugins/autopilot/**)
  - Bash(grep -rln * plugins/autopilot/**)
  - Bash(git -C * stash list)
  - Bash(git -C * stash pop:*)
  - Bash(git -C * stash show:*)
  - Bash(ps -p:*)
  - Bash(cat */*.lock)
  - Bash(printf:*)
  - Bash(pwd:*)
  - Bash(mktemp:*)
  - ToolSearch
  - EnterWorktree
  - ExitWorktree
  - TaskCreate
  - TaskUpdate
---

# spec

`autopilot:loop` 입력인 `milestones/<m>/loops/<c>-<slug>/SPEC.md`를 대화형으로 작성한다. 목표는 loop이 중간 질문 없이 수행 가능한 자기완결 SPEC이다.

## 호출

- 새 SPEC: `Skill(skill: "spec", args: "<task-id> [--milestone <m>]")`
- 마커 해결: `Skill(skill: "spec", args: "<task-id> [--milestone <m>] --resume")`
- dispatch 위임: `Skill(skill: "spec", args: "--milestone <m> <자연어 task 설명>")`

`--milestone` 기본값은 `regular`. args 본문에는 task-id 또는 자연어 설명 하나만 둔다. dispatch 위임 모드는 현재 호출의 직접 부모가 `autopilot:dispatch`이고 본문이 자연어일 때만 인정한다. 이때 step 10의 사용자 질문 없이 `Skill(skill: "loop", args: "start <m>/<c>")`까지 자동 연계한다. 모호하면 사용자 직접 호출로 처리한다.

## 10단계 워크플로

호출 시 10단계를 TodoWrite로 등록한다. 모든 결정·승인은 `AskUserQuestion`으로 받고, 후속 스킬 호출도 AskUserQuestion 확인 후 invoke한다.

### 1. 사전 검사

- task-id 검증: `validate_task_id` 기본 규칙(빈 값, `..`, `.` 단독 컴포넌트, `__`, 공백 금지)에 더해 args 본문 `/` 금지. milestone도 단일 컴포넌트로 검증한다.
- 자연어 문장으로 보이면 task 생성 입력이다. 직접 호출에서는 검증 실패 라우팅으로, dispatch 위임에서는 정상 입력으로 step 2에 진입한다.
- 일반 모드: 기존 `milestones/<m>/loops/<c>/`가 있으면 abort 후 다른 task-id / `--resume` / 백업 후 새로 중 하나를 묻는다.
- `--resume`: SPEC.md가 없으면 abort. `[NEEDS CLARIFICATION` 마커가 없으면 종료.

#### 1.1 검증 실패 라우팅

검증 실패·자연어 직접 입력은 즉시 종료하지 않고 `(a)` task-id 재입력 후 재시도, `(b)` 사전 명확화 라운드, `(c)` 종료를 묻는다. `(c)` 또는 취소 시 어떤 산출물도 작성하지 않는다. "다음 단계: Skill(...)" 같은 자유 텍스트 안내는 금지. 상세는 `references/pre-clarification.md`.

#### 1.2 사전 명확화 라운드

`(b)` 선택 시 step 5 메커니즘을 task-id 확보 전으로 앞당겨 재사용한다. 별도 phase를 만들지 말고 한 번에 한 질문으로 `문제·목표·범위·제약`을 수집한다. 단일 task로 수렴하면 프로젝트 태스크 관련 지침에 따라 task를 생성하고 반환된 task-id로 step 2부터 재개한다. 마일스톤 규모면 `AskUserQuestion` 명시적 승인 후 milestone-id를 인자로 PRD 스킬을 invoke한다.

### 2. task 상태 정합 (일반·--resume 두 모드)

사전 검사 통과 직후 실행한다. GitHub Issue/Project 같은 백킹 시스템 매핑은 `rules/context.md`, 상세 절차는 `references/task-state-alignment.md`가 단일 출처다.

4갈래 분기: (a) task 부재/없으면 새 task 생성, 설계 상태로 설정, task-id 교체 후 안내. (b) 설계 상태/In Design이면 그대로 진행. (c) 설계 이전/Backlog이면 설계 상태로 전이. (d) 설계 이후/In Progress/Review/Done이면 새 task를 만들고 새 task-id로 교체한다. (a)/(d)의 title은 AskUserQuestion으로 한 줄 제목 수집, 없으면 task-id 문자열 fallback. body는 최소 고정 placeholder 2줄이며 `<m>`은 create 호출 전 치환하고, 반환된 issue number로 `<new-task-id>`를 gh issue edit body 치환한다. 조회·생성·전이·edit 호출 실패 시 abort.

### 3. 컨텍스트 탐색

`git log --oneline -5`, `ls -A`, 선택적 `cat CLAUDE.md`, `ls rules/`, 얕은 테스트 디렉터리 탐색으로 테스트 컨벤션·룰·구조만 요약한다. 부족하면 `references/agent-prompts.md`의 `spec-context-explorer`를 Agent로 위임한다. 권장 도입 휴리스틱: 적용 룰이 많음, 기존 SPEC 선례가 많음, multi-file 영향, 자연어 의도만 있음. subagent는 사실 수집만 하며 결정·합성은 메인 책임이다(헌법 §11.6, 이터 내 서브 도구 위임).

### 4. 범위 분해 게이트

`references/decomposition-gate.md`로 다중 서브시스템 여부를 확인하고, 감지 시 사용자에게 분해를 제안한다. `--resume`에서는 생략한다.

### 5. 명확화 라운드

목적·성공기준·제약·위험을 결정 트리 기반 적응적 인터뷰로 수집한다. 인터뷰 방법(집요함·결정 트리·추천 답·코드 우선 네 원칙, "충분" 종결 조건, step 3과의 역할 경계)은 `references/clarification.md`가 단일 출처다. 전달 매체는 `AskUserQuestion`(한 번에 한 질문, 추천 답을 첫 선택지로) — 자유 텍스트 질문 금지. `--resume`에서는 마커 섹션만 묻는다.

#### 5.1 test 코드 변경 sweep

라운드 마지막에 test 코드 변경(rename·cleanup·삭제·내용 수정 등) 포함 여부를 자동 판단한다. 포함 신호가 있으면 sweep 화이트리스트 후보 경로를 추출하고 단발 yes/no 확인으로 SPEC frontmatter `test_sweep_paths` 등록 여부를 묻는다. yes면 `test_sweep_paths` 키와 경로 목록을 기록한다. no 또는 test 변경 없음이면 `test_sweep_paths` 키 부재 상태로 두고 `# test_sweep_paths: reviewed-no-sweep` 주석만 치환한다. 후보가 0개면 사용자에게 빈 목록을 보이지 않는다.

### 6. 접근법 비교

비자명한 결정(모호 요구, 둘 이상의 패턴, 외부 의존성 선택)이 있으면 2-3 접근법, trade-off, 추천을 제시한다. 자명하면 생략한다.

### 7. 섹션별 SPEC 승인

제목, 무엇을 만들 것인가(WHAT/HOW 방어선: 기술 스택·파일 경로·라이브러리·클래스명 금지), 수용 기준(EARS), 범위, 검증, 제약, 위험을 한 섹션씩 제시하고 승인받는다. EARS 언어(`en`/`ko`/`hybrid`, 기본 `ko`)와 5패턴은 `references/ears-patterns.md`를 따른다.

### 8. SPEC.md 작성

`references/spec-template.md` placeholder를 치환한다: `{{task_title}}`, `{{task_description}}`, `{{acceptance_criteria}}`, `{{scope_in}}`, `{{scope_out}}`, `{{scope_include}}`, `{{verify_command}}`, `{{test_sweep_paths}}`, `{{constraints}}`, `{{risks}}`. 미해결 항목은 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 남긴다. 저장 경로는 `milestones/<m>/loops/<c>-<slug>/SPEC.md`; slug는 `references/feat-branch-commit.md` §9.5.1 규칙으로 만든다. 빈 slug는 fallback 없이 abort하고 제목 수정을 요청한다.

### 8.2 SPEC.md write -> Issue body sync (단일 trigger)

SPEC.md 최초 작성, 자체 검토 재작성, 변경 재진입, `--resume` 재작성마다 단일 trigger로 GitHub Issue body를 sync한다. 첫 두 줄 placeholder는 `references/task-state-alignment.md` 표준과 일치해야 하며 불일치 시 abort.

Issue body 동기화 블록 구조:

```text
<step 2 placeholder line 1>
<step 2 placeholder line 2: SPEC: milestones/<m>/loops/<task-id>/SPEC.md>

<!-- autopilot:spec-sync:begin -->
## SPEC.md (auto-synced)

<SPEC.md 전문 그대로>
<!-- autopilot:spec-sync:end -->
```

sync 영역은 `<!-- autopilot:spec-sync:begin -->` / `<!-- autopilot:spec-sync:end -->` fence로만 식별한다. first-sync는 placeholder 아래 append, re-sync는 fence 사이(`## SPEC.md (auto-synced)` + SPEC 전문)만 replace하고 바깥 사용자 내용은 보존한다. `gh issue view <task-id> --json body --jq .body`, SPEC 전문 읽기, tempfile 경유 `gh issue edit <task-id> --body-file <tempfile>` 순서로 수행한다. GitHub 한도 초과, 비표준 body, 호출 실패는 abort하며 역방향 sync와 metadata 변경은 범위 외다.

### 9. 자체 검토

`references/self-review.md` 5축(placeholder, 모순, 범위, 모호성, EARS fail-가능성)을 검사한다. 수정 또는 `[NEEDS CLARIFICATION]` 마커만 남기고 사용자 Q&A와 재루프는 하지 않는다. 초안이 100줄 이상이거나 마커 2개 이상이면 `references/agent-prompts.md`의 `spec-self-reviewer`를 권장 도입한다. subagent는 발견만 보고하고 수정·마커 박기는 메인이 한다.

### 9.5 feat 브랜치 + SPEC.md commit

step 10 전, `feat/<task-id>-<slug>` 브랜치를 만들고 SPEC.md만 commit한다. main 작업트리(staged/unstaged/untracked)는 호출 전 상태로 보존한다. 슬러그화, 브랜치 생성, commit, 실패 처리, default 브랜치 자동 fast-forward merge, `push origin main`, `push origin feat/<c>-<slug>`, force push 금지는 모두 `references/feat-branch-commit.md`가 단일 출처다.

### 10. 사용자 최종 검토

dispatch 위임 모드는 질문 없이 loop start까지 자동 연계한다. 직접 호출은 SPEC 경로·요약을 제시하고 세 옵션을 묻는다: 지금 loop start 호출(Recommended), SPEC만 확정, 변경. loop start 선택 시 `--events-only` opt-out 여부를 한 번 더 묻고 yes면 `Skill(skill: "loop", args: "start <m>/<c> --events-only")`, no면 raw Monitor 기본 동작을 쓴다.

## --resume 요약

1은 마커 없으면 종료, 2는 동일, 4는 생략, 5-7은 마커 섹션만, 8/8.2는 재작성·sync, 나머지는 동일.

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `spec-template.md` | SPEC.md placeholder 템플릿 |
| `ears-patterns.md` | EARS 5패턴·언어 규칙 |
| `self-review.md` | 자체 검토 5항목 |
| `decomposition-gate.md` | 다중 서브시스템 감지 |
| `agent-prompts.md` | step 3·9 subagent dispatch 양식 (헌법 §11.6) |
| `clarification.md` | 명확화 인터뷰 방법론(집요함·결정 트리·추천 답·코드 우선) 단일 출처 |
| `pre-clarification.md` | 검증 실패 라우팅·사전 명확화 |
| `task-state-alignment.md` | task 상태 정합 4갈래 분기 |
| `feat-branch-commit.md` | feat 브랜치·commit·slug 단일 출처 |
| `test-spec-loop-contract.sh` | spec↔loop contract verifier |

## 규칙

- 본 스킬은 target 프로젝트의 SPEC.md만 작성한다.
- 자유 텍스트 질문 종결구 금지. 모든 선택은 `AskUserQuestion`.
- 한 주제씩 묻고, 한 호출의 관련 소문항은 최대 4개.
- `[NEEDS CLARIFICATION` 마커가 있으면 loop start가 차단된다. 사용자에게 `--resume` 해결을 안내한다.
