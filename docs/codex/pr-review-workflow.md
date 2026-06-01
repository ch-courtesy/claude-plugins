# Codex PR Review Workflow

이 문서는 `codex review` 자연어 출력 대신 직접 프롬프팅한 structured JSON을 사용해 PR 리뷰를 자동화하는 계획과 경계를 정의한다.

모델 호출은 셸에서 `codex exec`를 직접 실행하지 않고 공식 GitHub Action `openai/codex-action`(SHA 고정, codex CLI 버전은 action의 `codex-version` 입력으로 고정)을 통해 이뤄진다. 인증은 ChatGPT 계정 `auth.json`을 codex-home 디렉터리로 부트스트랩하는 방식을 쓰며 API 키 입력은 사용하지 않는다. 리뷰 결과 게시는 자매 워크플로(Claude PR 리뷰, `claude-review.yml`)와 **동일한 구조**다 — 정식 리뷰 verdict 제출 + 마커 기반 관리형 PR 코멘트 1개. codex만의 독자 게시 경로(인라인 코멘트, fingerprint 기반 self thread 자동 resolve, GitHub App 토큰 정식 approve)는 사용하지 않는다.

## 목표

- diff를 먼저 읽고 필요한 문맥만 확장한다.
- 명확하고 실행 가능한 correctness 이슈만 남긴다.
- findings를 JSON으로 받아 GitHub API 동작으로 안정적으로 매핑한다.
- GitHub 전용 동작과 플랫폼 공통 리뷰 코어를 분리해 GitLab 등 다른 플랫폼으로 확장할 수 있게 한다.

## 현재 1차 워크플로

1. PR context를 확인한다.
2. trusted base를 checkout하고 base/head와 diff를 공유 helper(`.github/scripts/pr-review-context.sh`)로 수집한다.
3. `.github/prompts/codex-pr-review.ko.md`를 system prompt처럼 붙이고 untrusted PR context(metadata·comments·diff)와 출력 언어 지시를 더해 프롬프트 파일을 조립한다.
4. 공식 action `openai/codex-action`을 호출한다. 공유 스키마(`.github/prompts/codex-pr-review.schema.json`)는 `output-schema-file` 입력으로, 조립한 프롬프트는 `prompt-file` 입력으로, 샌드박스는 `read-only`, reasoning effort는 `medium`, 결과 JSON은 `output-file` 입력으로 수신하고, auth.json 디렉터리는 `codex-home` 입력으로 전달한다.
   - **server-info 시드(중요)**: action은 API 키가 있을 때만 Responses API 프록시를 띄워 `<codex-home>/<run_id>.json`(server-info)을 쓰지만, 그 파일을 읽는 "Read server info" 스텝은 프롬프트만 있으면 무조건 실행된다. API 키 없이 auth.json만 쓰면 읽을 파일이 없어 `Failed to read server info`로 죽는다. 그래서 부트스트랩 단계에서 codex-home에 `auth.json`과 함께 더미 server-info(`{"port":1}`)를 같은 `<run_id>.json` 이름으로 미리 심는다. 프록시 설정 스텝도 API 키 게이트라 건너뛰므로 더미 port는 실제로 연결되지 않고 codex는 auth.json으로 OpenAI에 직접 인증한다. (이 시드는 고정한 action SHA의 step 게이트 동작에 결합되어 있다 — action 갱신 시 재검증 필요.)
5. 결과 JSON을 저장 직후 `jq empty`로 유효성을 검증한다.
6. 모델이 `needs_context`를 반환하면 요청 파일(최대 5개)을 PR head에서 수집해 2차 호출로 최종 verdict를 받는다(Claude 리뷰와 동일한 2-pass 흐름).
7. 게시는 자매 Claude 워크플로와 **동일한 구조**다(`claude-review.yml`의 'Submit … review verdict' + 'Post … review comment' 스텝을 codex 라벨·마커로 치환).
   - **정식 리뷰 verdict 제출**: `gh pr review`로 `--approve` / `--comment` / `--request-changes` 중 하나를 제출한다. 승인은 findings가 없고 `automation_safety.may_approve=true`이며 diff가 truncate되지 않았을 때만, request-changes는 confidence ≥ 80 blocking finding이 있을 때만. 본문 헤더는 `## Codex PR Review`이며 숨김 멱등 마커 `codex-formal-review head_sha=… verdict=…`를 담는다. 같은 (head_sha, verdict) 리뷰가 이미 있으면 중복 제출을 건너뛴다.
   - **마커 관리형 PR 코멘트 1개**: findings를 담은 issue-level 코멘트를 마커(`<!-- codex-api-pr-review -->`) 기준으로 최대 1개만 생성하거나 갱신한다(clean approve일 때는 게시하지 않음). 기본 토큰 봇(`github-actions[bot]`)이 자기 소유 코멘트를 식별·갱신한다.

   인라인 리뷰 코멘트, fingerprint 기반 self thread 자동 resolve, GitHub App 설치 토큰을 통한 정식 approve는 사용하지 않는다(Claude 리뷰와 동일한 한계: 워크플로 기본 토큰은 자기 PR을 정식 APPROVE하지 못해 COMMENT로 강등될 수 있다).

## 단계적 고도화 계획

### Phase 1: Structured Review MVP

- `codex review` 대신 structured `codex exec`(JSON schema 강제)를 사용한다. 단, codex는 셸에서 직접 실행하지 않고 공식 action `openai/codex-action`을 통해 호출한다(action 내부에서 `codex exec`가 실행됨).
- 프롬프트는 `prompt-file` 입력으로 전달해 shell `ARG_MAX` 한계를 피한다.
- JSON schema로 최종 응답을 강제하고 저장 직후 `jq empty`로 검증한다.
- confidence score 80 미만 finding은 게시하지 않는다.

완료 기준:
- JSON schema 검증이 실패하면 approve하지 않는다.
- `approve` verdict는 findings가 비어 있고 `automation_safety.may_approve=true`일 때만 제출된다.
- `request_changes`는 confidence 80 이상의 blocking finding이 있을 때만 제출된다.

### Phase 2: Inline Comment Adapter (superseded)

> **Superseded.** 게시 구조를 자매 Claude 워크플로와 통일하면서 codex 독자 인라인 코멘트 경로는 제거되었다. findings는 인라인이 아니라 마커 관리형 PR 코멘트 1개에 담겨 게시된다("현재 1차 워크플로" 7번 참조). 아래는 과거 설계 기록이다.

- ~~모든 finding을 GitHub inline review comment로 게시한다(inline-only 정책).~~
- ~~changed line에 직접 매핑되지 않는 finding도 issue comment로 떨어뜨리지 않고, 가장 가까운 변경 hunk 라인에 inline으로 붙이고 본문에 실제 위치를 명시한다.~~
- ~~comment marker에 `fingerprint`, `head_sha`, `severity`, `status`를 저장한다.~~
- ~~같은 fingerprint가 이미 존재하면 중복 게시하지 않는다.~~

### Phase 3: Thread Lifecycle (superseded)

> **Superseded.** Claude 동일 게시 구조에는 self thread lifecycle 관리가 없다. fingerprint 기반 self thread 자동 resolve 경로는 제거되었다. 아래는 과거 설계 기록이다.

- ~~GraphQL `reviewThreads`를 읽어 `isResolved`, `isOutdated`, root comment body, marker를 수집한다.~~
- ~~Codex-owned active thread만 resolve/unresolve/reply 대상으로 삼는다.~~
- ~~최신 push가 기존 finding을 고쳤으면 resolve한다.~~
- ~~아직 고쳐지지 않았으면 같은 thread에 후속 피드백을 단다.~~

완료 기준(과거):
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

## Context Modes

- `full`: initial PR review. Sends full PR patch and existing comments.
- `incremental`: synchronize event. Sends only previous head to current head patch when available.
- `thread`: review-comment reply. Sends target thread metadata and the target file patch.

If the model returns `needs_context`, the workflow fetches up to 5 requested files from the PR head and runs one follow-up pass.
