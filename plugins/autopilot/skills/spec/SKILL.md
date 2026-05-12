---
name: spec
description: "autopilot loop이 입력으로 받는 SPEC.md를 대화형으로 생성. 한 질문씩 명확화·섹션별 승인·EARS 포맷·[NEEDS CLARIFICATION] 마커로 자율 loop이 도중 질문 없이 완수 가능한 자기완결적 SPEC을 만듭니다. 호출 'Skill(skill=\"spec\", args=\"<task-id> [--milestone <m>] [--resume]\")'. milestone 미지정 시 `regular`(catch-all)을 default로 적용."
allowed-tools: AskUserQuestion, Read, Write, Bash(git log:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git for-each-ref:*), Bash(git worktree:*), Bash(git add:*), Bash(git commit:*), Bash(ls:*), Bash(cat:*), Bash(find:*), Bash(mkdir:*), Bash(grep:*), Bash(sed:*), Bash(gh issue view:*), Bash(bash:*), Bash(mktemp:*), Bash(cp:*), Bash(rm:*)
---

# spec

`autopilot:loop` 스킬이 입력으로 받는 `milestones/<m>/loops/<c>/SPEC.md`를 대화형으로 생성. 자율 loop이 도중 질문 없이 완수할 수 있는 자기완결적 SPEC이 목표.

## 호출 방법

- 새 SPEC: `Skill(skill: "spec", args: "<task-id> [--milestone <m>]")`
- 마커 해결 모드: `Skill(skill: "spec", args: "<task-id> [--milestone <m>] --resume")`

milestone 미지정 시 `regular`(catch-all)을 default로 적용 — sibling `autopilot:loop`이 단일 컴포넌트 task-id를 `regular/<task-id>`로 정규화하는 컨벤션과 일치. `autopilot:dispatch` 등 milestone 분해 컨텍스트에서 호출할 때는 `--milestone <m>`을 명시.

또는 사용자가 자연어로 의도 전달 시 모델이 자동 호출.

## 10단계 워크플로

호출 시 다음 10단계를 TodoWrite로 등록·실행. 각 단계는 사용자 결정·승인을 `AskUserQuestion`으로 받으며, 단계 10(자동 finalize)만 단계 9 승인 직후 자동 실행됩니다.

### 1. 사전 검사

- task-id 형식 검증 (loop.sh의 `validate_task_id`와 동일 규칙): 비어 있거나, `..` 포함, `.` 단독 컴포넌트(`.`·`./foo`·`foo/.`·`a/./b`), `__` 포함, 공백 포함 시 abort. 슬래시(`/`)는 `--milestone <m>`이 명시된 경우에만 허용 — milestone이 별도 인자로 분리된 뒤의 nested task-id(`sub-area/child` 등)가 정상 사용 사례. `--milestone` 미지정 + 슬래시 포함 task-id는 abort — loop.sh의 `normalize_task_id`가 슬래시 있는 task-id의 첫 컴포넌트를 milestone으로 해석하므로 spec의 default(`regular`)와 어긋나 `--resume` 라운드트립이 깨짐. 슬래시 포함 task-id를 쓰려면 `--milestone <m>`을 명시. spec 스킬과 loop이 같은 (milestone, task-id) 쌍을 받아들여야 `--resume` 라운드트립이 성립.
- milestone 인자 파싱: `--milestone <m>` 명시 시 `<m>`을 milestone으로 사용. 미지정 시 `regular`(catch-all)을 default로 적용. milestone 자체에도 task-id와 동일한 형식 검증을 적용 (단, milestone은 단일 컴포넌트 — `/` 미허용).
- **일반 모드**: `milestones/<m>/loops/<c>/` 존재 시 abort + `AskUserQuestion`으로 3옵션 (다른 task-id / `--resume` / 백업 후 새로). 본 절 이후 `<c>`는 task-id를 지칭.
- **--resume 모드**: `milestones/<m>/loops/<c>/SPEC.md` 부재 시 abort. 잔존 `[NEEDS CLARIFICATION` 마커 0개 시 "해결할 마커 없음" 안내 후 종료

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
- `{{scope_in}}` / `{{scope_out}}` → 본문 섹션 4 (사람이 읽는 형식)
- `{{scope_include}}` → frontmatter `scope.include` (YAML inline flow list 형식, 예: `["src/**", "tests/**"]`. 본문 `{{scope_in}}`과 같은 내용을 YAML 문법으로)
- `{{verify_command}}` → 본문 섹션 5 + frontmatter `verify` (둘 다 같은 placeholder)
- `{{constraints}}` / `{{risks}}` → 섹션 6/7. 빈 값이면 빈 줄 한 줄로 치환 (헤더는 남김)
- frontmatter `scope.exclude`는 고정 default(`rules/**`, `milestones/**`, `CLAUDE.md`) — 치환 대상 아님

미해결 항목은 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 박은 채 작성.

`mkdir -p milestones/<m>/loops/<c>` 후 `milestones/<m>/loops/<c>/SPEC.md`에 기록.

### 8. 자체 검토

`references/self-review.md` 5항목 체크 (placeholder · 모순 · 범위 · 모호성 · EARS fail-가능성). 발견 시 인라인 수정 또는 `[NEEDS CLARIFICATION]` 마커만 — 사용자 Q&A 없음(단계 9에서 일괄 해결). 재루프 없음. 수정·마커 후 SPEC.md 재기록.

### 9. 사용자 최종 검토

SPEC.md 경로·요약 안내 + `AskUserQuestion`으로 검토 결과 수집:
- 승인: 단계 10(자동 finalize)으로 진행 — 사용자 추가 입력 없이 즉시 feat 브랜치 분기·SPEC commit 실행.
- 변경: 어느 섹션을 변경할지 묻고 단계 6/7 재진입

### 10. 자동 finalize — feat branch 분기 + SPEC commit

단계 9에서 사용자가 "승인"한 직후 자동 실행. 사용자 입력 없음.

**목표**: SPEC.md를 main에서 분기하는 `feat/<task-id>-<slug>` 브랜치에 commit해 `loop start`가 워크트리에 SPEC을 자연 포함한 채 시작할 수 있게 한다. main 작업트리는 변경 전후 동일 (단계 7에서 작성된 untracked SPEC.md 그대로 보존).

#### 절차

1. **브랜치 이름 도출** (M1의 slugify 헬퍼 사용):
   - `title=$(grep -m1 '^# ' milestones/<m>/loops/<c>/SPEC.md | sed 's/^# *//')`
   - `feat_branch=$(bash plugins/autopilot/skills/spec/references/slugify.sh "<m>/<c>" "$title")`
   - 출력: `feat/<m>/<c>-<slug>` 또는 fallback `feat/<m>/<c>` (slug 빈 경우). milestone이 default `regular`이면 task-id는 `regular/<c>` 형식.
2. **기존 브랜치 충돌 검사**:
   - `git for-each-ref --format='%(refname:short)' "refs/heads/$feat_branch"`이 비어있지 않으면 abort + `AskUserQuestion`으로 처리 선택 (수동 정리 후 재호출 / task-id 변경). 자동 덮어쓰기 금지.
3. **임시 워크트리 생성** (main 격리):
   - `tmp_wt=$(mktemp -d)`
   - `git worktree add "$tmp_wt" -b "$feat_branch" main` — main에서 분기하는 격리된 워크트리. main 작업트리는 그대로.
4. **SPEC.md를 임시 워크트리로 cp + commit**:
   - `mkdir -p "$tmp_wt/milestones/<m>/loops/<c>"`
   - `cp "milestones/<m>/loops/<c>/SPEC.md" "$tmp_wt/milestones/<m>/loops/<c>/SPEC.md"`
   - `git -C "$tmp_wt" add "milestones/<m>/loops/<c>/SPEC.md"`
   - `git -C "$tmp_wt" commit -m "spec(<m>/<c>): SPEC.md 초안"`
5. **임시 워크트리 제거** — feat 브랜치는 main repo에 잔존:
   - `git worktree remove "$tmp_wt"` (실패 시 `--force`)
   - `rm -rf "$tmp_wt"` (mktemp 잔존물 정리)
6. **사용자 안내**:
   - *"SPEC commit됨: `$feat_branch`. main 작업트리의 SPEC.md는 untracked로 보존됩니다 (필요 시 `git clean -f milestones/<m>/loops/<c>/SPEC.md`로 정리).\n다음 단계: Skill(skill: \"loop\", args: \"start <m>/<c>\")"* (milestone이 default `regular`이면 `start <c>` 단축형도 동등 — loop.sh가 자동 정규화)

#### 제약

- 단계 10의 git 동작은 모두 임시 워크트리(`mktemp -d`)에서 일어난다. main 작업트리의 staged/unstaged/untracked 상태는 단계 10 시작·종료 시점 동일해야 한다.
- 슬러그화 결정성: 같은 SPEC §1 제목은 항상 같은 `feat_branch` 이름을 만든다 (`references/slugify.sh`).
- 단계 10 실패(branch 충돌·worktree add 실패 등) 시 명확한 에러 메시지로 abort하고 임시 워크트리·브랜치 잔존물을 정리. 부분 실패 상태로 종료하지 않는다.

## --resume 모드 요약

위 10단계 중:
- 1: 마커 0개 시 즉시 종료
- 3: 생략 (이미 SPEC 존재)
- 4, 5: 마커 위치 기준으로 좁힘
- 6: 마커 박힌 섹션만
- 10: feat 브랜치가 이미 존재할 수 있음 — 충돌 검사 단계에서 사용자에게 처리 선택 (브랜치 덮어쓰기는 자동 금지; 신규 SPEC commit을 기존 브랜치 위에 추가하려면 사용자가 명시적으로 결정)
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
