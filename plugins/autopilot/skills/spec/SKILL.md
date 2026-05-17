---
name: spec
description: "기능 추가·동작 수정·지침 작성·새로 만들 등 새 코드 변경을 정의하는 자연어 신호에 대응. autopilot loop이 입력으로 받는 SPEC.md를 대화형으로 생성. 한 질문씩 명확화·섹션별 승인·EARS 포맷·[NEEDS CLARIFICATION] 마커로 자율 loop이 도중 질문 없이 완수 가능한 자기완결적 SPEC을 만듭니다. 이 레포 표준 워크플로우는 자기완결적 SPEC.md 작성 → feat 브랜치 분기·SPEC commit → autopilot loop 실행 → PR. SPEC.md 작성 후 결정적 슬러그화 규칙(ASCII 영숫자·하이픈만)으로 `feat/<task-id>-<slug>` 브랜치를 main에서 분기·SPEC.md를 commit해 loop·PR 흐름이 단일 feature 브랜치로 통합되게 합니다. 호출 'Skill(skill=\"spec\", args=\"<task-id> [--milestone <m>] [--resume]\")'. milestone 미지정 시 `regular`(catch-all)을 default로 적용."
allowed-tools: AskUserQuestion, Read, Write, Skill, Agent, Bash(git log:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git checkout:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*), Bash(git show-ref:*), Bash(git for-each-ref:*), Bash(ls:*), Bash(cat:*), Bash(find:*), Bash(mkdir:*), Bash(grep:*), Bash(echo:*), Bash(head:*), Bash(tr:*), Bash(sed:*), Bash(gh:*)
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

- task-id 형식 검증 (loop.sh의 `validate_task_id` 동일 규칙): 비어 있거나 `..` 포함, `.` 단독 컴포넌트(`.`·`./foo`·`foo/.`·`a/./b`), `__` 포함, 공백 포함 시 실패. 슬래시(`/`)는 `--milestone <m>` 명시 시에만 허용 — nested task-id(`sub-area/child` 등)가 정상 사용 사례. `--milestone` 미지정 + 슬래시 포함은 실패(loop.sh의 `normalize_task_id`가 첫 컴포넌트를 milestone으로 해석해 spec default `regular`와 어긋남 → `--resume` 라운드트립 깨짐). spec·loop이 같은 (milestone, task-id) 쌍을 받아야 `--resume` 라운드트립이 성립.
- milestone 인자 파싱: `--milestone <m>` 명시 시 `<m>` 사용, 미지정 시 default `regular`. milestone에도 동일 형식 검증 적용 (단일 컴포넌트 — `/` 미허용).
- 자연어 입력 감지: 인자가 task-id 패턴이 아닌 자연어 문장(물음표·따옴표·문장 부호 다중, 길이 ≥ 40자 등 휴리스틱)이면 검증 실패로 분류 — 즉시 abort 대신 아래 **검증 실패 라우팅**.
- 어떤 형태의 검증 실패든 직접 abort/die 하지 않고 라우팅으로 분기. 통과 시 일반/--resume 모드 분기로 진행.
- **일반 모드**: `milestones/<m>/loops/<c>/` 존재 시 abort + `AskUserQuestion` 3옵션 (다른 task-id / `--resume` / 백업 후 새로). 이하 `<c>`는 task-id 지칭.
- **--resume 모드**: `milestones/<m>/loops/<c>/SPEC.md` 부재 시 abort. 잔존 `[NEEDS CLARIFICATION` 마커 0개 시 "해결할 마커 없음" 안내 후 종료

#### 1.1 검증 실패 라우팅 (요약)

검증 실패·자연어 입력 시 즉시 종료 대신 `AskUserQuestion` 3옵션: **(a)** task-id 재입력 후 재시도, **(b)** 사전 명확화 라운드 진입(§1.2), **(c)** 종료(산출물 없음). 옵션 표기 `(a)`/`(b)`/`(c)`. "다음 단계: Skill(...)" 자유 텍스트 금지. 전체 절차는 `references/pre-clarification.md` §1.1 참조.

#### 1.2 사전 명확화 라운드 (요약)

(b) 선택 시 진입. step 5 메커니즘을 task-id 확보 *전*으로 앞당겨 재사용(별도 phase·모듈 없음). 수집은 task 미정의 상태에 맞춰 `문제·목표·범위·제약`으로 확장. 매 라운드 "충분" 종결·명시적 취소 안전 종료 포함. 규모 분기: 단일 task → 프로젝트 태스크 트래커 컨벤션으로 task 생성 후 step 2 재진입, 마일스톤 규모 → `AskUserQuestion` 명시 승인 후 PRD 스킬 invoke. 수집 항목·라운드 규칙·1.2.1/1.2.2 분기 상세는 `references/pre-clarification.md` §1.2 참조.

### 2. task 상태 정합 (일반·--resume 두 모드 공통)

**사전 검사 통과 직후** 실행. task-id로 식별되는 외부 task를 조회해 4갈래 분기로 설계 상태로 정합. 일반·`--resume` 모드 공통.

4갈래 요약: **(a)** task 부재 → 새 task 생성·task 상태를 설계 상태로 설정·task-id 교체·사전 검사 재적용. **(b)** 기존 설계 상태 → 변경 없이 진행(resume). **(c)** 기존 설계 이전 상태 → 설계 상태로 전이. **(d)** 기존 설계 이후 상태 → 새 task 생성·task-id 교체(a와 동일).

백엔드 매핑 위임(추상 ↔ 구체 매핑은 `rules/context.md` 단일 출처), 조회·생성·편집·상태 전이 호출의 추상화, (a)·(d) 새 task title/body 수집(고정 2줄 본문, `<m>`/`<new-task-id>` 2단계 치환), 호출 실패 abort, 범위 외(loop start 설계 상태 → 진행 상태 전이는 본 단계 책임 아님)의 전체 절차는 `references/task-state-alignment.md` 참조.

### 3. 컨텍스트 탐색

다음 명령으로 프로젝트 컨텍스트 자동 수집(사용자에게 요약만):
```
git log --oneline -5
ls -A
cat CLAUDE.md  # 있으면
ls rules/      # 있으면
find . -maxdepth 3 -type d \( -name 'tests' -o -name 'test' -o -name '__tests__' -o -name 'spec' \) 2>/dev/null | head -5
```

목적: 테스트 컨벤션·CLAUDE.md 룰·디렉터리 구조 파악. 모노레포여도 step 5에서 좁힐 것이므로 깊이 탐색 생략.

#### 3.1 subagent 위임 (선택)

자동 수집이 부족하면 `references/agent-prompts.md`의 **`spec-context-explorer`** 양식으로 `Agent` 위임. 권장 휴리스틱(하나라도 해당): `rules/` 다수(≈5개 초과)이고 적용 룰 자명하지 않음, 기존 `milestones/*/loops/*/SPEC.md` 다수 선례, multi-file 영향, 사용자가 자연어 의도만 전달. 그 외엔 위임하지 않는다 — 단순 1~2 query는 메인이 직접 호출(헌법 §11.6). subagent는 사실 수집·인용만, **결정·합성은 메인 책임**.

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

비-자명한 설계 결정 포함 시 2-3 접근법 + 트레이드오프 + 추천 제시. 자명하면 생략. 판단 기준(하나라도 해당): 사용자가 "어떻게 할까?" 묻거나 모호 요구, 둘 이상의 다른 패턴 사이 선택, 외부 의존성·라이브러리 선택이 task 결과에 큰 영향.

### 7. 섹션별 SPEC 제시·승인

순서대로 한 섹션씩 제시 → `AskUserQuestion`으로 "이 섹션 OK?":
1. 제목
2. 무엇을 만들 것인가 (WHAT/HOW 방어선 — 기술 스택·파일 경로·라이브러리·클래스명 금지)
3. 수용 기준 (EARS, `references/ears-patterns.md`)
4. 범위 (포함·비-목표)
5. 검증 (실행 가능한 명령)
6. 제약 (있을 때만)
7. 위험 (있을 때만)

미승인 섹션은 재제시·수정. 통째로 보여주지 않음.

**EARS 작성 언어**: SPEC frontmatter `ears_language`(값 `en`·`ko`·`hybrid`, 미명시 시 default `ko`)에 따라 산출·사용자에 다시 묻지 않음. 3모드 형식·5패턴·변환 규칙은 `references/ears-patterns.md` "EARS 작성 언어" 절(단일 출처) 참조.

`--resume` 모드: 마커 박힌 섹션만.

### 8. SPEC.md 작성

`references/spec-template.md` 읽어 placeholder 치환:
- `{{task_title}}` → 단계 7 합의 제목 (없으면 task-id)
- `{{task_description}}` → 섹션 2 내용
- `{{acceptance_criteria}}` → 섹션 3 (EARS 포맷)
- `{{scope_in}}` / `{{scope_out}}` → 본문 섹션 4
- `{{scope_include}}` → frontmatter `scope.include` (YAML inline flow list, 예: `["src/**", "tests/**"]`)
- `{{verify_command}}` → 본문 섹션 5 + frontmatter `verify` (둘 다 같은 placeholder)
- `{{constraints}}` / `{{risks}}` → 섹션 6/7. 빈 값이면 빈 줄 1개 치환(헤더 유지)
- frontmatter `scope.exclude`는 고정 default(`rules/**`, `milestones/**`, `CLAUDE.md`) — 치환 대상 아님

미해결 항목은 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 박은 채 작성.

#### 8.1 SPEC.md 저장 경로 (slug-bearing 단일 컨벤션)

`<slug>`는 `references/feat-branch-commit.md` §9.5.1 결정적 규칙으로 step 7 §1 H1 제목에서 산출. 단일 컨벤션 경로:

- `milestones/<m>/loops/<c>-<slug>/SPEC.md`

`<slug>` 가 빈 문자열로 환원되면 fallback 경로를 만들지 않는다 — SPEC 116 EARS AC4(단일 컨벤션, 다른 경로 fallback 없음) 위반이고 sibling pr-phase 도 슬러그 없는 브랜치는 abort. 빈 slug 시 `references/feat-branch-commit.md` §9.5.3 실패 처리로 분기·§1 H1 제목 수정(step 7 재진입) 요청.

`<c>` 는 input task-id (단계 1 통과값). 본 디렉토리 이름의 `<slug>` 가 sibling `autopilot:loop` 이 발견하는 feat 브랜치 `feat/<c>-<slug>` 의 `<slug>` 와 동일해 spec→loop 라운드트립이 단일 컨벤션으로 정합. `mkdir -p` 후 `SPEC.md` 기록.

기록 직후 §8.2 «SPEC.md write → Issue body sync» 절차가 단일 trigger로 발동된다.

### 8.2 SPEC.md write → Issue body sync (단일 trigger)

SPEC.md가 `milestones/<m>/loops/<c>/SPEC.md`에 (재)기록되는 모든 시점에서 본 절차가 단일 trigger로 발동된다. 발동 경로:

- step 8 최초 작성 직후
- step 9 자체 검토 인라인 수정으로 SPEC.md를 재기록한 직후
- step 10 "변경" 분기 → step 7/8 재진입 후 재기록한 직후
- `--resume` 모드에서의 마커 해결 후 재기록한 직후

발동 시점에 task-id에 해당하는 GitHub Issue body를 다음 구조로 갱신한다 (`rules/context.md`의 Issue body 구조 규약과 step 2가 박은 자리표시를 모두 유지):

```
<step 2가 박은 자리표시 1줄 — spec 워크플로우 step 2에서 자동 생성. 본문은 SPEC.md 작성·승인 후 갱신될 예정.>
<step 2가 박은 자리표시 2줄 — SPEC: milestones/<m>/loops/<task-id>/SPEC.md>

<!-- autopilot:spec-sync:begin -->
## SPEC.md (auto-synced)

<SPEC.md 전문 그대로>
<!-- autopilot:spec-sync:end -->
```

동기화 블록의 경계는 **고유 HTML 코멘트 fence** — `<!-- autopilot:spec-sync:begin -->` ~ `<!-- autopilot:spec-sync:end -->` — 로만 식별한다. SPEC.md가 YAML frontmatter(`---` … `---`)를 포함해도 본문 안의 `---`를 경계로 오해할 여지가 없다. fence는 GitHub Markdown에 렌더되지 않으므로 사용자 가독성에는 영향이 없다.

#### 8.2.1 절차

1. `gh issue view <task-id> --json body --jq .body`로 현재 Issue body를 읽는다.
2. `milestones/<m>/loops/<c>/SPEC.md`에서 SPEC.md 전문을 읽는다.
3. 새 body를 구성한다 — 다음 두 하위 단계를 순서대로 적용:

   **3-a. 자리표시 2줄 검증 (abort 게이트)**

   `references/task-state-alignment.md`가 정의한 step 2 자리표시 2줄 패턴을 기준으로 Issue body의 첫 두 줄이 다음과 정확히 일치하는지 확인 (placeholder 유지·보존). 두 줄 모두 정규식과 일치해야 한다:

   - **line 1**: `^spec 워크플로우 step 2에서 자동 생성\.` 로 시작
   - **line 2**: `^SPEC: milestones/[^/]+/loops/[^/]+/SPEC\.md$`

   하나라도 불일치 시 비표준 입력으로 즉시 **abort** — 본 SPEC 범위는 step 2가 만든 표준 구조의 issue로 한정.

   **3-b. first-sync vs re-sync 분기**

   기존 body 안에 `<!-- autopilot:spec-sync:begin -->` ~ `<!-- autopilot:spec-sync:end -->` fence 쌍이 존재하는지 검사한 결과로 분기:

   - **first-sync (fence 부재)**: 자리표시 2줄을 그대로 유지한 채, 그 *아래에* 빈 줄 · `<!-- autopilot:spec-sync:begin -->` · `## SPEC.md (auto-synced)` 헤딩 · 빈 줄 · SPEC.md 전문 · `<!-- autopilot:spec-sync:end -->` 를 *append*. 기존 body의 자리표시 2줄 이후 사용자 추가 섹션이 있으면(드문 케이스이나 가능), end fence 이후로 그대로 밀어 보존한다 — 덮어쓰지 않는다.
   - **re-sync (fence 쌍 존재)**: begin/end fence *사이*만 새 헤딩·빈 줄·SPEC.md 전문으로 replace. fence 자체와 fence *바깥* 모든 내용(자리표시 2줄, end fence 이후 사용자 추가 섹션 등)은 그대로 보존한다.

   두 분기 모두 동기화 블록 바깥의 사용자 추가 내용은 보존이 원칙이며, 어느 분기에서도 덮어쓰지 않는다.
4. `gh issue edit <task-id> --body-file <tempfile>`로 update. SPEC.md 전문은 멀티라인·frontmatter·backtick을 포함하므로 인라인 `--body "..."`로 셸 전달하면 파싱이 실패한다. 반드시 임시 파일을 거친다:

   ```bash
   tmp=$(mktemp)
   printf '%s' "$new_body" > "$tmp"
   gh issue edit <task-id> --body-file "$tmp"
   rm -f "$tmp"
   ```

5. 호출이 0이 아닌 exit으로 실패하면 step 2의 기존 `gh` 실패 처리와 동일하게 명확한 에러 메시지와 함께 **abort(중단)**. 자동 roll-back은 수행하지 않으며 disk의 SPEC.md는 그대로 두고 Issue body만 옛 상태로 남는 부분 상태를 사용자에게 명시적으로 알린다. tempfile은 abort 경로에서도 `rm -f`로 정리한다.

#### 8.2.2 한도·경쟁·범위 외

- 큰 SPEC.md가 GitHub Issue body 길이 한도(65536 chars)를 초과하면 step 4와 동일하게 abort + 사용자 안내. 일반 SPEC 규모로는 드문 케이스.
- 동일 task에 spec 호출이 동시 실행되는 경우 Issue body update 순서에 경쟁 조건이 발생할 수 있다 — spec 호출은 일반적으로 대화형으로 직렬화되므로 실무 발생 확률 낮음. 경쟁 탐지·잠금은 본 SPEC 범위 외.
- 기존 비표준 Issue body(수동 생성·구분자 없음)의 retroactive migration은 본 SPEC 범위 외 — abort + 사용자 안내로 처리.
- 역방향 sync(Issue body → SPEC.md), 라벨·assignee 등 다른 metadata 변경은 본 SPEC 범위 외.

#### 8.2.3 Self-referential 규약과 현재 호출 면제

본 스킬은 자기 자신에게도 적용된다 — 본 §8.2 규약을 정의하는 SPEC.md가 이후 `--resume`되거나 다른 task의 spec 호출이 일어나면 그 시점부터는 자기 issue body도 sync 대상이다.

다만 **메모리 노트 `feedback_no_self_apply_during_spec`에 따라**, 본 SPEC.md를 작성하는 *현재 호출*에서는 새 contract를 선행 적용하지 않고 현 스킬 규칙으로 마친다 — 새 동작은 다음 spec 호출부터 적용된다. (self-referential SPEC를 같은 호출의 산출물에 미리 선행 적용하지 않는 규약, 단 현재 호출 면제.)

### 9. 자체 검토

`references/self-review.md` 5항목 체크 (placeholder · 모순 · 범위 · 모호성 · EARS fail-가능성). 발견 시 인라인 수정 또는 `[NEEDS CLARIFICATION]` 마커만 — 사용자 Q&A 없음(단계 10에서 일괄 해결). 재루프 없음. 수정·마커 후 SPEC.md 재기록 — 재기록 직후 §8.2 sync trigger가 다시 발동된다.

#### 9.1 subagent 위임 (선택)

SPEC 초안이 길거나 잔존 마커가 다수면 `references/agent-prompts.md`의 **`spec-self-reviewer`** 양식으로 독립 검토 위임. 휴리스틱(하나라도 해당): 본문 ≈100줄 초과, 잔존 `[NEEDS CLARIFICATION]` 마커 2개 이상, 호출자의 명시적 요청. subagent는 5축 발견만 보고하고 **SPEC.md 수정·마커 박기는 메인이 수행**(헌법 §11.6 — patch 생성은 위임하지 않음). step 9 본문 원칙("사용자 Q&A 없음, 재루프 없음")은 위임 여부와 무관.

### 9.5. feat 브랜치 + SPEC.md commit (자동, main 작업트리 무손상)

SPEC.md 작성·자체 검토 후 sibling `autopilot:loop`의 worktree base가 될 `feat/<task-id>-<slug>` 브랜치를 main에서 분기·생성하고 SPEC.md만 그 브랜치에 commit. main 작업트리 상태(staged/unstaged/untracked) 변경 금지. 단계 10 *전*에 수행 — 이후 단계 10에서 "변경" 선택 시 단계 7/8 재진입 후 본 단계 commit amend·추가(자동).

본 단계가 단일 출처로 삼는 **슬러그 도출 코드 조각은 `references/feat-branch-commit.md` §9.5.1**에 보존되며, 안전장치(`references/test-spec-loop-contract.sh`)는 그 새 위치를 검사한다.

결정적 슬러그화 규칙(§9.5.1), 브랜치 생성·commit 9단계 절차(§9.5.2), 실패 처리·빈-slug abort(§9.5.3)의 전체 절차는 `references/feat-branch-commit.md` 참조.

### 10. 사용자 최종 검토

SPEC.md 경로(§8.1 slug-bearing)·요약 안내 후 `AskUserQuestion`으로 **명시적 결정 입력**(자유 텍스트 종결구 금지 — CLAUDE.md 규칙). 옵션 3개(상호배타):

- **지금 loop start 호출** (Recommended) — `Skill(skill: "loop", args: "start <m>/<c>")` 자동 연계. 모니터 추가 질문 없이 loop 기본 동작(자동 Monitor 가설 포함, `plugins/autopilot/skills/loop/SKILL.md`) 적용. default `regular`이면 `start <c>` 단축형 동등.
- **SPEC만 확정** — 경로 안내·종료. 사용자가 별도 시점에 `Skill(skill: "loop", args: "start <m>/<c>")` 직접 호출.
- **변경** — 변경 섹션을 묻고 단계 7/8 재진입.

## --resume 모드 요약

- 1: 마커 0개 시 즉시 종료
- 2: 일반 모드와 동일(보통 (b) 설계 상태 분기로 변경 없이 통과)
- 4: 생략 (이미 SPEC 존재)
- 5, 6, 7: 마커 박힌 섹션만
- 8 / 8.1: SPEC.md를 재기록하므로 §8.2 sync trigger가 동일하게 발동된다.
- 나머지 동일

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `spec-template.md` | SPEC.md placeholder 템플릿 |
| `ears-patterns.md` | 5 EARS 패턴·변환·Independent-Test |
| `self-review.md` | 자체 검토 5항목 |
| `decomposition-gate.md` | 다중 서브시스템 감지·분해 제안 |
| `agent-prompts.md` | step 3·9 subagent dispatch 양식 (헌법 §11.6) |
| `pre-clarification.md` | step 1.1 라우팅 + 1.2 사전 명확화 라운드 |
| `task-state-alignment.md` | step 2 task 상태 정합 4갈래 분기 |
| `feat-branch-commit.md` | step 9.5 feat 브랜치·commit + 슬러그화 단일 출처 |
| `test-spec-loop-contract.sh` | spec↔loop 단일 규약 contract verifier |

## 규칙

- 본 스킬은 target 프로젝트의 `milestones/<m>/loops/<c>/SPEC.md`만 작성한다. 다른 파일 생성·수정 안 함.
- 모든 결정·선택·확인은 `AskUserQuestion`으로. 자유 텍스트 끝에 질문 종결구 다는 방식 금지 (CLAUDE.md 규칙).
- 한 주제씩 (한 `AskUserQuestion` 호출에 관련 소문항 최대 4개 허용).
- `[NEEDS CLARIFICATION` 마커는 `loop start`에서 차단됨. 사용자에게 명시적으로 마커가 박혔음을 알리고 `--resume`으로 해결하도록 안내.
