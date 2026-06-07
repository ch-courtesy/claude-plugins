# Codex PR Review Workflow

이 문서는 `codex review` 자연어 출력 대신 직접 프롬프팅한 structured JSON을 사용해 PR 리뷰를 자동화하는 계획과 경계를 정의한다.

모델 호출은 셸에서 `codex exec`를 직접 실행하지 않고 공식 GitHub Action `openai/codex-action`(SHA 고정, codex CLI 버전은 action의 `codex-version` 입력으로 고정)을 통해 이뤄진다. 인증은 ChatGPT 계정 `auth.json`을 codex-home 디렉터리로 부트스트랩하는 방식을 쓰며 API 키 입력은 사용하지 않는다. 리뷰 결과 게시는 자매 워크플로(Claude PR 리뷰, `claude-review.yml`)와 **동일한 구조**다 — 발견사항(findings)을 코드 라인에 anchor된 inline review thread로 담은 **단일 inline 리뷰** 제출(리뷰 요약은 작성하지 않고, 본문은 approve일 때만 승인 사실 한 줄을 담는다) + 모델이 해소로 판정한 자기 소유 thread의 **fingerprint 기준 자동 resolve**. 별도의 마커 관리형 이슈 레벨 코멘트 게시 경로는 없다. 게시·resolve·정식 APPROVE는 `REVIEW_APP_ID`가 설정된 환경에서 발급한 GitHub App 설치 토큰으로 단일 봇 신원 아래 수행한다 — App 토큰만이 자기 소유 inline thread를 resolve하고 자기 PR을 정식 APPROVE할 수 있기 때문이다(자세한 권한은 메모리/운영 노트 참조). App 시크릿이 없는 fork·미설정 저장소에서는 토큰 발급 스텝이 건너뛰어지고 워크플로 기본 토큰(`github.token`)으로 graceful degradation한다(기본 토큰은 thread resolve·자기 PR 정식 APPROVE 불가). 봇 신원은 실제로 게시에 쓰인 토큰에 따라 동적으로 결정된다 — App 토큰이면 `<app-slug>[bot]`, 기본 토큰이면 `github-actions[bot]`.

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
7. 게시는 자매 Claude 워크플로와 **동일한 구조**인 단일 `Submit … inline review` 스텝(codex 라벨·마커로 치환)에서 이뤄진다.
   - **inline comment 조립**: 발견사항마다 파일과 변경 라인에 anchor된 inline comment(`side: 'RIGHT'`, multi-line이면 `start_line`/`start_side` 추가)를 만들고 본문 끝에 숨김 마커 `<!-- codex-review-inline fingerprint=<fp> -->`를 붙인다. `fingerprint`는 발견사항의 안정 속성(파일 경로 + 리뷰 관점 + 정규화한 제목)만으로 결정론적으로 계산되며 줄 번호에 의존하지 않는다(정규화·해시 규칙은 Claude 워크플로와 byte-identical).
   - **diff-only anchor 검증**: 제출 배치를 만들기 **전에** 공유 단위 `.github/scripts/diff-anchor-filter.js`로 각 finding의 anchor(파일 + `line`, 범위면 `start_line` 양끝)가 PR diff의 RIGHT side(추가 `+`·context ` ` 라인)에 실제로 존재하는지 검증한다. off-diff anchor는 GitHub이 `createReview` 배치 **전체**를 422(`Path could not be resolved`)로 거부해 유효한 finding까지 함께 떨어뜨리므로, 벗어난 finding은 배치에 넣지 않고 제외·로그만 남긴다(가장 가까운 hunk로 relocate하거나 force-post하지 않는다). 이 검증기는 trusted base 체크아웃에서 require하므로, 검증기를 도입·수정하는 바로 그 PR에선 base에 모듈이 없어 require가 실패할 수 있다 — 이때는 명시적 경고와 함께 미필터 제출로 loud degrade하며(검증은 머지 후부터 효력), 아래 false-green 가드가 실제 제출 오류는 여전히 잡는다. (정규화·검증 규칙은 Claude 워크플로와 공유하는 동일 단위다.)
   - **단일 리뷰 제출**: 위에서 걸러진 in-diff inline comment 배열과 함께 단일 `github.rest.pulls.createReview` 호출로 제출한다. review event는 findings가 없고 `automation_safety.may_approve=true`이며 diff가 truncate되지 않은 `approve`일 때 `APPROVE`, 그 외 `COMMENT`다(REQUEST_CHANGES는 폐지). **리뷰 본문은 실제 `APPROVE` 이벤트일 때만 `## Codex PR 리뷰` 헤더 + `승인되었습니다.` 한 줄을 담고, 그 외(비-approve)에는 숨김 멱등 마커만 담는다 — 리뷰 요약(summary)은 작성하지 않는다.** 숨김 멱등 마커는 `codex-formal-review head_sha=… verdict=…`이며, 같은 마커의 봇 리뷰가 이미 있으면 제출만 건너뛴다(resolve 후처리는 계속). App 토큰이면 `APPROVE`가 정식 승인으로 제출되지만, 기본 토큰으로 degrade된 환경에서는 자기 PR을 정식 APPROVE하지 못하므로 `APPROVE`가 실패한다 — 이때 같은 inline 코멘트와 본문을 담은 `COMMENT` 리뷰로 강등 제출하고 `.codex-review/approval-failed`로 기록한다(강등된 `COMMENT` 본문에는 승인 문구를 재사용하지 않고 숨김 마커만 담는다).
   - **fingerprint 기준 self thread resolve**: 제출(또는 중복 skip) 후 verdict와 무관하게, GraphQL `reviewThreads`로 조회해 자기 소유 + fingerprint 추출 가능 + 미해결인 inline thread를 자동 resolve한다 — 모델이 `resolved_threads`에 올린 fingerprint(1차)이거나 이번 회차 findings의 fingerprint 집합에서 사라진 thread(2차 fallback)를 `resolveReviewThread`로 닫는다. 다른 리뷰어 thread나 fingerprint를 추출할 수 없는 thread는 건드리지 않는다.

   별도의 마커 관리형 이슈 레벨 코멘트 게시 경로는 없다(발견사항은 inline 전용; 리뷰 요약은 작성하지 않고, 본문은 approve일 때만 승인 사실 한 줄을 담는다). createReview가 라인 매핑 등으로 실패하면 그 회차 inline은 게시되지 않고 로그로만 남으며, 발견사항을 이슈 코멘트로 덤프하지 않는다. 단 제출할 in-diff finding이 있었는데도 제출이 최종 실패한 경우엔 조용히 green으로 끝내지 않고 job을 실패시킨다(**false-green 가드**) — off-diff 제외로 제출할 게 없어진 경우나 zero-finding `APPROVE`→`COMMENT` 강등은 정상이라 실패로 취급하지 않는다.

## 단계적 고도화 계획

> 진행 상황: Phase 1~4는 구현 완료, Phase 5·플랫폼 공통화는 계획이다(각 헤더 표기 참조). Phase 4는 두 워크플로(codex·claude)를 `prep → review(matrix) → merge` 3-잡 파이프라인으로 재구성해 구현했다.

### Phase 1: Structured Review MVP — ✅ 구현됨

- `codex review` 대신 structured `codex exec`(JSON schema 강제)를 사용한다. 단, codex는 셸에서 직접 실행하지 않고 공식 action `openai/codex-action`을 통해 호출한다(action 내부에서 `codex exec`가 실행됨).
- 프롬프트는 `prompt-file` 입력으로 전달해 shell `ARG_MAX` 한계를 피한다.
- JSON schema로 최종 응답을 강제하고 저장 직후 `jq empty`로 검증한다.
- confidence score 80 미만 finding은 게시하지 않는다. 단 이는 프롬프트(`codex-pr-review.ko.md`)가 모델에 지시하는 soft 보장이며, 워크플로 코드에는 confidence 필터가 없다(모델이 지시를 어기면 새어나갈 수 있음 — 워크플로 하드 게이트화는 별도 후속).

완료 기준:
- JSON schema 검증이 실패하면 approve하지 않는다.
- `approve` verdict는 findings가 비어 있고 `automation_safety.may_approve=true`일 때만 제출된다.
- `request_changes` verdict는 별도의 REQUEST_CHANGES 리뷰 이벤트로 제출되지 않는다(폐지). blocking finding은 inline comment로 게시되고 리뷰 이벤트는 `COMMENT`로 남는다.

### Phase 2: Inline Comment Adapter — ✅ 구현됨 (off-diff는 relocate 아닌 exclude)

게시는 모든 finding을 코드 라인에 anchor된 GitHub inline review comment로 올린다("현재 1차 워크플로" 7번 참조).

- 모든 finding을 GitHub inline review comment로 게시한다(inline-only 정책).
- changed line에 직접 매핑되지 않는(off-diff) finding은 issue comment로 떨어뜨리지도, 가장 가까운 hunk로 relocate하지도 않는다 — 공유 `diff-anchor-filter.js`로 제출 **전에** 제외하고 로그만 남긴다(off-diff anchor가 `createReview` 배치 전체를 422로 떨어뜨리는 것을 막기 위함; "현재 1차 워크플로" 7번의 diff-only anchor 검증 참조).
- inline comment 본문 끝 숨김 마커에 결정론적 `fingerprint`를 저장한다(마커 base substring을 보존해 self-식별을 유지).
- `fingerprint`는 파일 경로 + 리뷰 관점 + 정규화한 제목만으로 계산되어 줄 이동에도 실행 간 동일하다.

### Phase 3: Thread Lifecycle — ✅ 구현됨

자기 소유 inline thread는 fingerprint 단위로 자동 resolve한다("현재 1차 워크플로" 7번 참조).

- GraphQL `reviewThreads`를 읽어 `isResolved`, root comment author, marker(fingerprint)를 수집한다.
- 자기 소유(게시에 쓰인 토큰에 따라 App 토큰이면 `<app-slug>[bot]`, 기본 토큰이면 `github-actions[bot]`; GraphQL Actor.login은 `[bot]` 접미사 생략형이라 두 형태 모두 허용) + fingerprint 추출 가능 + 미해결 thread만 resolve 대상으로 삼는다.
- 모델이 `resolved_threads`에 올린 fingerprint(1차)이거나 이번 회차 findings의 fingerprint 집합에서 사라진 thread(2차 fallback)를 `resolveReviewThread`로 닫는다.
- 아직 보고되는(findings에 남은) fingerprint의 thread는 건드리지 않는다.

완료 기준:
- 봇이 만들지 않은 thread는 절대 resolve하지 않는다.
- fingerprint를 추출할 수 없는 thread는 건드리지 않는다.
- resolve는 verdict와 무관하게, 중복으로 제출을 건너뛴 경우에도 실행된다.

### Phase 4: Token Optimized Review — ✅ 구현됨 (3-잡 matrix 파이프라인, codex·claude 대칭)

GHA `uses:` 스텝은 루프할 수 없어 가변 횟수 모델 호출이 불가능하므로, 두 워크플로를 **`prep → review(matrix) → merge` 3-잡 파이프라인**으로 재구성해 청크링을 구현한다. 모델 action `uses:` 소스 라인 수는 런타임 matrix 확장과 무관하게 불변이라 모델-호출 카운트 계약(`codex_action_count` 등)을 깨지 않는다.

- **diff token budget 초과 시 청크링**: `prep` 잡이 diff를 파일 단위로 쪼개 토큰 예산(기본 80k) 이하의 청크로 묶고, 청크 인덱스를 `strategy.matrix`로 내보낸다. `review` 잡이 청크별로 모델 action을 호출(청크당 `needs_context` follow-up 1회 포함)하고 결과를 아티팩트로 올린다. `merge` 잡이 전 청크 결과를 합쳐 단일 리뷰로 제출한다. diff가 임계 이하면 단일 청크(matrix-of-1)로 기존 단일 패스와 동치다(회귀 없음).
- **저우선 강등**: docs-only·lockfile-only·generated-only 변경은 낮은 우선순위로 분류해, 추정 총 입력이 총 예산(기본 250k)을 넘을 때 리뷰 대상에서 먼저 제외하고 제외 사실·파일 목록을 로그로 남긴다.
- **needs_context 재시도**: 각 청크가 `needs_context`를 반환하면 그 청크에 한해 요청 파일(최대 5개)을 붙여 follow-up 패스를 한 번 수행한다.
- **partial findings 병합**: 청크별 findings를 fingerprint 기준으로 중복 제거·병합해 단일 `createReview`로 제출한다. self thread-resolve의 fallback은 청크별이 아니라 **병합된 findings 집합** 기준으로 판정한다.
- **공유 단위**: 청크링·분류·병합 순수 로직은 `.github/scripts/pr-review-chunking.js` 단일 공유 모듈에 두고 두 워크플로가 `require`로 소비한다(`diff-anchor-filter.js`와 동일 패턴; 인라인 복제 없음). 토큰 추정은 토크나이저 부재로 **문자수/4** 휴리스틱을 쓴다. 청크 간 데이터는 잡이 파일시스템을 공유하지 않으므로 아티팩트로 전달한다.
- **App 토큰·anchor 검증·false-green 가드·thread-resolve**는 동작·권한을 보존한 채 `merge` 잡으로 이전했다(잡 경계만 이동).
- **자기 검증 부트스트랩**: 공유 모듈은 trusted base 체크아웃에서 `require`하므로, 모듈을 도입·수정하는 PR에선 base에 아직 없어 단일 패스로 loud degrade한다(청크링은 머지 후부터 효력).

권장 기본값(공유 모듈 `LIMITS` 상수):
- max total input: 250k tokens
- max diff input before chunking: 80k tokens
- max single file content: 30k tokens
- max related files per changed file: 5
- max unchanged context expansion depth: 2
- max output: 16k tokens

### Phase 5: Multi-Perspective Parallel Review — ❌ 미구현 (계획)

Claude 공식 code-review 플러그인의 장점을 Codex runner 정책으로 가져온다.

- eligibility check
- guideline compliance review
- shallow bug scan
- history/context review
- previous PR/comment duplicate scan
- code comment contract review
- confidence scoring

모델명과 병렬 개수는 prompt가 아니라 runner config에서 관리한다.

## 플랫폼 공통화 검토 — ❌ 미구현 (계획)

### Review Core

GitHub, GitLab, Bitbucket에 공통으로 재사용 가능한 영역:

- diff-first review prompt
- JSON schema
- confidence scoring
- fingerprint 생성 규칙
- duplicate detection policy
- token budget policy
- findings merge policy
- `approve | comment | needs_context | unavailable` verdict model (REQUEST_CHANGES는 폐지)

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
- `incremental`: synchronize event. Diffs from the commit **this reviewer last successfully reviewed** — the head SHA carried by its most recent formal-review marker (`<!-- <reviewer>-formal-review head_sha=… -->`), trusted only when the marker's review author is a recognized review bot — up to the current head. Falls back to `full` when no such marker exists or it is not an ancestor of the current head (first review, all prior reviews failed/unavailable, or force-push/rebase). This base is **not** the webhook `event.before` (previous push head): see "Incremental base 현행화" below for why.
- `thread`: review-comment reply. Sends target thread metadata and the target file patch.

If the model returns `needs_context`, the workflow fetches up to 5 requested files from the PR head and runs one follow-up pass.

## Incremental base 현행화 — 커버리지 공백 차단 + 마커 위조 방지 — ✅ 구현됨

> 적용: 2026-06-06. `incremental` 모드의 base 계산을 웹훅 `event.before` → "마지막 성공 리뷰 SHA"로 바꾸고, 그 마커의 신뢰를 리뷰 봇 작성자로 한정했다. 두 리뷰 워크플로(codex·claude) 대칭.

**문제 — 리뷰 커버리지 공백.** 과거 `incremental` 모드는 base를 GitHub 웹훅의 `event.before`(직전 push의 head)로 잡았다. `event.before`는 직전 리뷰의 성공 여부와 무관하게 GitHub가 매 push마다 갱신하므로, 어떤 push의 리뷰가 실패하면(예: 사용량 한도로 리뷰 미게시) 다음 push의 증분 diff가 그 **미검토 커밋들을 건너뛰어 영구히 리뷰되지 않는데도 체크는 통과**했다.

**해결 — 마지막 성공 리뷰 SHA 기준.** 각 워크플로는 실제로 리뷰를 제출할 때만(approve/comment) per-reviewer 마커 `<!-- <reviewer>-formal-review head_sha=<sha> … -->`를 남긴다(실패·unavailable·skipped 시엔 남기지 않음 = 성공 게이트). 이제 `incremental` base는 **그 리뷰어의 가장 최근 마커 head_sha 중 현재 head의 조상인 것**으로 잡는다 → 직전 리뷰가 실패했더라도 그 이후 모든 커밋이 다음 증분에 포함되어 공백이 메워진다. 적격 마커가 없으면(첫 리뷰·전부 실패·force-push) `full`로 떨어진다.

**위조 방지 강화.** 마커는 리뷰 본문에 들어가므로 작성자 검증이 없으면 사람(예: PR 작성자)이나 다른 봇이 가짜 마커를 단 리뷰를 올려 미검토 head를 "마지막 성공 리뷰"로 위조해 base를 조작할 수 있다(자기 변경 리뷰 회피). 그래서 마커는 **신뢰된 리뷰 봇 작성자가 단 것만** 인정한다 — prep 단계에서 GitHub App 토큰 스텝으로 봇 신원(`<app-slug>[bot]`, 미구성 시 `github-actions[bot]`)을 동적으로 얻어 허용 작성자 목록으로 넘기고, 마커 추출이 그 목록의 작성자만 신뢰한다.

**구현 위치.** 마커 파싱·정렬·작성자 검증은 공유 순수 모듈 `.github/scripts/pr-review-incremental-base.js`(hermetic 테스트 동봉)에 있고, base 계산을 수행하는 공유 스크립트 `.github/scripts/pr-review-context.sh`가 이를 호출한다. 신뢰 봇 신원은 prep의 GitHub App 토큰 스텝에서 동적으로 얻는다. 앵커 검증용 정본 diff(`gh pr diff`)는 모드와 무관하게 그대로다 — 모델용 `diff.patch`의 base만 바뀐다.
