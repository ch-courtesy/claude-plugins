# prepare 인터랙티브 절차 상세

`Skill(skill: "loop", args: "prepare <task-id>")` 호출 시 다음 절차로 PROMPT.md 생성.

## 1. 사전 검사

- `.loops/<task-id>/` 디렉토리 이미 존재? → abort + 안내
- `task-id` 비어 있거나 path traversal 문자(`..`/`/`이외) 포함? → abort

## 2. 사용자에게 task 정보 수집 (`AskUserQuestion` 4문항)

다음 4개를 한 번의 AskUserQuestion 호출로 묶어 수집 (각 단일 선택, "Other"로 자유 입력):

### Q1. task_description (무엇을 만들 것인가)
- "한 줄 설명을 입력하세요"
- "Other"로 자유 텍스트 받음

### Q2. acceptance_criteria (수용 기준)
- "수용 기준을 줄바꿈 구분으로 나열해 주세요. 예: '- 로그인 폼 검증\n- 비밀번호 해시 검사'"
- "Other"로 자유 텍스트 받음

### Q3. scope_include (수정 허용 경로 패턴)
- 옵션:
  - `src/**, tests/**` (일반)
  - `src/**` (구현만)
  - `tests/**` (테스트만)
- "Other"로 직접 입력

### Q4. verify_command (검증 명령)
- 옵션:
  - `pnpm test` / `npm test` / `pytest` / `cargo test` / `go test ./...`
- "Other"로 직접 입력

## 3. PROMPT.md 작성

`references/prompt-template.md`를 읽어 placeholder 치환:
- `{{task_description}}` → Q1 값
- `{{acceptance_criteria}}` → Q2 값
- `{{scope_in}}` → Q3 값 (frontmatter scope.include에도 동일 적용)
- `{{scope_out}}` → 기본 `["rules/**", ".loops/**", "CLAUDE.md"]`
- `{{verify_command}}` → Q4 값

frontmatter도 동일 치환 (scope.include·verify).

치환된 본문을 `.loops/<task-id>/PROMPT.md`로 작성.

## 4. 안내

```
prepared: .loops/<task-id>/PROMPT.md
다음 단계: Skill(skill: "loop", args: "start <task-id>")
```
