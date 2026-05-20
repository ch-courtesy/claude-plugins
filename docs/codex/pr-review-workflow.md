# Codex PR Review Workflow

이 문서는 `codex review` 자연어 출력 대신 직접 프롬프팅한 structured JSON을 사용해 PR 리뷰를 자동화하는 계획과 경계를 정의한다.

## 목표

- diff를 먼저 읽고 필요한 문맥만 확장한다.
- 명확하고 실행 가능한 correctness 이슈만 남긴다.
- findings를 JSON으로 받아 GitHub API 동작으로 안정적으로 매핑한다.
- GitHub 전용 동작과 플랫폼 공통 리뷰 코어를 분리해 GitLab 등 다른 플랫폼으로 확장할 수 있게 한다.

## 현재 1차 워크플로

1. PR context를 확인한다.
2. base/head와 diff를 수집한다.
3. `.github/prompts/codex-pr-review.ko.md`를 system prompt처럼 붙인다.
4. `codex exec --output-schema .github/prompts/codex-pr-review.schema.json`을 stdin 기반으로 실행한다.
5. JSON schema를 검증한다.
6. reviewer GitHub App installation token을 발급해 `GH_TOKEN`과 `github-script` token으로 사용한다.
7. `verdict`에 따라 GitHub review를 제출한다.
   - `approve`: `gh pr review --approve`
   - `request_changes`: `gh pr review --request-changes`
   - `comment`, `needs_context`, `unavailable`: `gh pr review --comment`
8. managed issue comment를 marker 기반으로 create/update한다.

필수 secrets:

- `CODEX_AUTH_JSON`: Codex CLI 인증용 `auth.json` 내용.
- `CODEX_REVIEW_APP_ID`: 리뷰어 GitHub App ID.
- `CODEX_REVIEW_APP_PRIVATE_KEY`: 리뷰어 GitHub App private key.
- `CODEX_REVIEW_APP_INSTALLATION_ID`: 선택 값. 비워두면 repository installation endpoint에서 자동 조회한다.

리뷰어 GitHub App 권한:

- Contents: Read
- Issues: Write
- Pull requests: Write

## 단계적 고도화 계획

### Phase 1: Structured Review MVP

- `codex review` 대신 `codex exec`를 사용한다.
- stdin으로 prompt를 전달해 shell `ARG_MAX` 한계를 피한다.
- JSON schema로 최종 응답을 강제한다.
- confidence score 80 미만 finding은 게시하지 않는다.
- inline comment는 아직 생성하지 않고 summary review body에 묶는다.

완료 기준:
- JSON schema 검증이 실패하면 approve하지 않는다.
- `approve` verdict는 findings가 비어 있고 `automation_safety.may_approve=true`일 때만 제출된다.
- `request_changes`는 confidence 80 이상의 blocking finding이 있을 때만 제출된다.

### Phase 2: Inline Comment Adapter

- changed diff line에 매핑 가능한 finding만 GitHub inline review comment로 게시한다.
- changed line에 매핑되지 않는 finding은 managed issue comment로 유지한다.
- comment marker에 `fingerprint`, `head_sha`, `severity`, `status`를 저장한다.
- 같은 fingerprint가 이미 존재하면 중복 게시하지 않는다.

완료 기준:
- diff line 매핑 실패 시 inline 대신 issue-level finding으로 degrade한다.
- 기존 다른 reviewer가 같은 이슈를 남겼으면 `skipped_duplicates`로 기록하고 게시하지 않는다.

### Phase 3: Thread Lifecycle

- GraphQL `reviewThreads`를 읽어 `isResolved`, `isOutdated`, root comment body, marker를 수집한다.
- Codex-owned active thread만 resolve/unresolve/reply 대상으로 삼는다.
- 최신 push가 기존 finding을 고쳤으면 resolve한다.
- 아직 고쳐지지 않았으면 같은 thread에 후속 피드백을 단다.

완료 기준:
- Codex가 만들지 않은 thread는 절대 resolve하지 않는다.
- outdated thread는 fingerprint로 최신 diff에 남아 있는지 재확인한다.

### Phase 4: Token Optimized Review

- diff token budget을 넘으면 파일 그룹별로 나눠 리뷰한다.
- docs-only, lockfile-only, generated-only 변경은 낮은 우선순위로 처리한다.
- `needs_context`가 반환되면 요청된 파일/symbol만 추가해 재시도한다.
- partial findings를 fingerprint 기준으로 병합한다.

권장 기본값:
- max total input: 250k tokens
- max diff input before chunking: 80k tokens
- max single file content: 30k tokens
- max related files per changed file: 5
- max unchanged context expansion depth: 2
- max output: 16k tokens

### Phase 5: Multi-Perspective Parallel Review

Claude 공식 code-review 플러그인의 장점을 Codex runner 정책으로 가져온다.

- eligibility check
- guideline compliance review
- shallow bug scan
- history/context review
- previous PR/comment duplicate scan
- code comment contract review
- confidence scoring

모델명과 병렬 개수는 prompt가 아니라 runner config에서 관리한다.

## 플랫폼 공통화 검토

### Review Core

GitHub, GitLab, Bitbucket에 공통으로 재사용 가능한 영역:

- diff-first review prompt
- JSON schema
- confidence scoring
- fingerprint 생성 규칙
- duplicate detection policy
- token budget policy
- findings merge policy
- `approve | request_changes | comment | needs_context | unavailable` verdict model

공통 입력 모델:

```json
{
  "platform": "github|gitlab|bitbucket",
  "review_id": "string",
  "base_sha": "string",
  "head_sha": "string",
  "metadata": {},
  "changed_files": [],
  "diff": "unified diff",
  "existing_discussions": []
}
```

### Platform Adapter

플랫폼별로 분리해야 하는 영역:

- PR/MR metadata fetch
- changed file/diff fetch
- inline comment line mapping
- discussion/thread resolve API
- approve/request changes API
- author association/trust policy
- bot identity and marker lookup

GitHub adapter:
- PR, review, review thread, issue comment 개념을 사용한다.
- `gh pr review`, REST review comments, GraphQL review thread resolve가 필요하다.

GitLab adapter:
- Merge Request, discussions, notes, approval 개념을 사용한다.
- GitLab은 discussion resolve와 MR approval API가 별도로 존재하므로 thread lifecycle은 GitHub adapter와 분리해야 한다.

권장 구조:

```text
review-core/
  prompt.ko.md
  schema.json
  fingerprint policy
  token budget policy

adapters/
  github/
    collect context
    publish review
    resolve threads
  gitlab/
    collect context
    publish discussions
    resolve discussions
    approve merge request
```

## 운영 원칙

- prompt는 모델명과 병렬 처리 방식을 알지 않는다.
- workflow/runner가 모델, chunking, retry, publish 정책을 소유한다.
- user-provided PR body/title/comments는 untrusted context로만 다룬다.
- approval은 JSON verdict와 automation safety가 모두 통과할 때만 수행한다.
- schema validation 실패, context truncation, diff fetch 실패 시 approve하지 않는다.
