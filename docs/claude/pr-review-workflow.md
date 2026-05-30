# Claude PR Review Workflow

PR을 pinned `@anthropic-ai/claude-code` CLI(`claude -p`)로 직접 호출하여 구조화 JSON 리뷰를 생성하고 GitHub review/comment로 게시한다. Codex review workflow와 동일한 review schema·context helper·게시 로직을 공유한다.

## 목표

- Codex PR review workflow와 review schema를 공유한다.
- diff를 먼저 읽고 필요한 문맥만 사용한다.
- 명확하고 실행 가능한 correctness 이슈만 남긴다.
- Claude 출력은 `claude -p` envelope `.result`에서 직접 파싱·검증해 GitHub review 동작으로 매핑한다.
- GitHub 전용 publish 로직과 모델별 review prompt를 분리한다.

## 1차 워크플로 흐름

1. PR context를 확인하고 **trusted base ref**를 checkout(권한 있는 job이 PR-controlled 코드를 실행하지 않도록).
2. base/head/diff/기존 comments를 `.github/scripts/pr-review-context.sh`로 수집(`full`/`incremental`/`thread` 모드 자동 판정).
3. `@anthropic-ai/claude-code` CLI를 pinned 버전으로 설치(`npm install -g @anthropic-ai/claude-code@<pinned>`).
4. 단일 stdin 프롬프트를 조립:
   - `.github/prompts/claude-pr-review.ko.md` (리뷰 지시문)
   - 출력 언어 블록(`CLAUDE_REVIEW_LANG`, 기본 `Korean`)
   - **임베디드 JSON 스키마**(`<schema>` 블록) — 모델이 필드명·구조를 직접 본다
   - raw-only 응답 형식 규칙(마크다운 펜스·prose 금지)
   - untrusted PR 데이터(metadata/comments/diff)
   - 마지막 재강조 라인
5. checkout credential extraheader 제거 + `GH_TOKEN` unset → **scratch cwd**(`mktemp -d`)에서 `claude -p --output-format json --json-schema "$schema" --strict-mcp-config --setting-sources "" --no-session-persistence` 실행.
6. envelope JSON의 `.result` 텍스트에서 첫 `{` ~ 마지막 `}` 추출 → jq 파싱 → 11개 required 필드 검증 → `.claude-review/result.json` 저장.
7. 모델이 `needs_context`를 반환하면 요청한 파일을 PR head에서 fetch(최대 5개, 400줄 절단)해 follow-up 프롬프트로 재호출.
8. `verdict`에 따라 GitHub review event를 `pulls.createReview`로 제출. **모든 finding은 inline 코멘트로만** 게시한다(inline-only 정책):
   - `approve` + safety pass: `APPROVE` (review body는 finding 평가 없이 승인 표현만)
   - `request_changes` + blocking finding(confidence ≥ 80): `REQUEST_CHANGES` (body는 마커만, 평가 없음)
   - `comment`/`needs_context`/기타: `COMMENT` (body는 마커만, 평가 없음)
   - 변경 라인에 직접 anchor할 수 없는 finding도 issue 코멘트로 떨어뜨리지 않고, 모델이 가장 가까운 변경 hunk 라인에 inline으로 붙이고 본문에 실제 위치(파일·라인)를 명시한다.
9. managed issue comment(marker `<!-- claude-api-pr-review -->`)는 **verdict=approve일 때만** 게시하며, 승인 표현만 담고 finding 평가 본문은 포함하지 않는다(AC2~AC4). approve가 아니면 게시하지 않고, 직전 approve 코멘트가 있으면 supersede 표시로 갱신한다.

## 구성

| 항목 | 변수 | 기본 |
|---|---|---|
| OAuth token | `secrets.CLAUDE_CODE_OAUTH_TOKEN` | (required) |
| 모델 | `vars.CLAUDE_REVIEW_MODEL` | `claude-sonnet-4-5-20250929` |
| 출력 언어 | `vars.CLAUDE_REVIEW_LANG` | `Korean` |
| CLI 버전 | 워크플로의 `npm install -g` 라인 | `@anthropic-ai/claude-code@2.1.145` |

## 운영 원칙

- review schema(`.github/prompts/codex-pr-review.schema.json`)는 Codex와 공유한다. Claude 전용 prompt는 모델별 표현만 소유한다.
- user-provided PR title/body/comments는 untrusted context로만 다룬다.
- `@claude` comment trigger는 `OWNER`, `MEMBER`, `COLLABORATOR` author association만 허용한다.
- approval은 JSON verdict와 `automation_safety`가 모두 통과할 때만 수행한다(`may_approve=true`, `diff_truncated=false`, findings=0).
- schema/tool output 실패, context truncation, diff fetch 실패 시 approve하지 않는다.
- 워크플로는 `id-token: write` 권한을 **요구하지 않는다**(OIDC는 claude-code-action 전용; 직접 CLI는 OAuth env var로 충분).

## 격리

리뷰 모델은 다음 경계 안에서 실행된다 — codex의 `--sandbox read-only` 의도와 등가의 격리:

- **scratch cwd**: `mktemp -d`에서 실행하여 이 레포의 `CLAUDE.md`·`.claude/`·skills를 auto-discovery하지 않는다.
- **`--strict-mcp-config`**: ambient MCP 서버 로딩 차단.
- **`--setting-sources ""`**: project/local/user 설정·훅·hooks 로딩 차단.
- **`--no-session-persistence`**: 세션 파일 미저장.
- **credential drop**: `claude -p` 실행 전 `git config --local --unset-all http.https://github.com/.extraheader` + `unset GH_TOKEN` — 모델이 인증된 git remote에 접근하지 못한다.
- **권한 있는 job**: trusted base ref를 checkout하여 helper script·prompt·schema가 PR-controlled 코드로 교체되지 않는다.

## `.result` 파싱·검증·fallback

claude-code의 `--json-schema`는 trivial 스키마에서만 `structured_output` 필드를 채우고, 이 리뷰의 11-top-level-field 스키마에서는 신뢰 가능한 메커니즘이 아니다(client-side validation 한계). 워크플로는 다음 우회로를 쓴다:

- **스키마 임베드**: 모델이 스키마 텍스트를 직접 보고 필드명·구조를 따른다.
- **응답 형식 강제**: raw JSON 객체 한 개만, 펜스·prose 금지. 모델 응답은 `.result`에 들어간다.
- **`.result` 직접 파싱**: 첫 `{` ~ 마지막 `}` 추출 → `jq` 파싱 → required keys 검증.
- **fallback 합성**: 파싱·검증 실패 시 `eligibility=reviewed`, `verdict=comment`, `summary="Claude review parsing failed: <reason>"`, `findings=[]`의 합성 result.json 작성 → Submit 스텝이 정상 comment review로 게시하여 사용자에게 파싱 실패가 가시화된다(워크플로 step은 성공으로 종료).

## Context Modes

- `full`: initial PR review. 전체 PR patch와 기존 comments를 전송.
- `incremental`: `synchronize` 이벤트. 이전 head→현재 head의 patch만 전송.
- `thread`: review-comment 응답. 대상 thread 메타데이터와 대상 파일 patch 전송.

모델이 `needs_context`를 반환하면 워크플로가 요청한 최대 5개 파일을 PR head에서 fetch해 2차 패스를 한 번 실행한다.

## Codex Workflow와의 차이

- **CLI**: Codex는 `@openai/codex` CLI의 `codex exec --output-schema`로 **server-side grammar**로 출력을 강제. Claude는 `@anthropic-ai/claude-code` CLI의 `claude -p --json-schema`(client hint) + **프롬프트 임베드 + `.result` 파싱**으로 우회.
- **권한 모델**: Claude는 trusted base를 checkout하고 untrusted PR 데이터만 데이터로 주입(직접 CLI 도구 도구 권한 차단). Codex는 PR merge ref를 checkout 후 `--sandbox read-only`로 격리.
- **인증**: Claude는 `CLAUDE_CODE_OAUTH_TOKEN` env var. Codex는 `CODEX_AUTH_JSON` secret을 `~/.codex/auth.json`으로 복원. 양쪽 모두 Anthropic/OpenAI API key는 사용하지 않는다.

## 알려진 제약

- claude-code CLI의 `--json-schema`가 복잡한 schema에서 `structured_output`을 신뢰 가능하게 채우지 않아, 워크플로는 `.result` 텍스트 파싱에 의존한다. 모델(sonnet-4-5)이 임베디드 스키마 + raw-only 지시를 따르지 못하면 fallback 합성 result로 강등된다.
- `--bare` 옵션은 OAuth가 아니라 `ANTHROPIC_API_KEY`를 요구하므로 OAuth 인증 환경에서는 사용 불가.
- 기본 에이전트 system prompt가 로드되어 매 실행마다 ~수만 토큰의 cache-creation 비용이 발생한다(claude-code-action도 동일).
