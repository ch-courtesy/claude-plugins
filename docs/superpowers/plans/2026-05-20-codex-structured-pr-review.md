# Codex 구조화 PR 리뷰 구현 계획

> **에이전트 작업자용:** 이 계획을 단계별로 실행할 때는 `superpowers:subagent-driven-development`(권장) 또는 `superpowers:executing-plans`를 사용한다. 각 단계는 진행 추적을 위해 체크박스(`- [ ]`) 형식을 쓴다.

**목표:** 자유 형식의 `codex review` 출력 대신 GitHub 리뷰 동작을 안정적으로 구동할 수 있는 structured JSON 리뷰 출력을 도입하고, 이후 다른 코드 리뷰 플랫폼에도 확장할 수 있게 한다.

**아키텍처:** 한국어 프롬프트와 JSON schema로 리뷰 판단 코어를 플랫폼 중립으로 유지한다. 댓글 게시, thread resolve, approve 제출은 플랫폼 adapter가 담당한다. 1단계에서는 GitHub Actions adapter가 schema 검증과 verdict 기반 리뷰 제출을 수행한다.

**기술 스택:** GitHub Actions, GitHub CLI, Codex CLI, JSON Schema, `jq`, Bash.

---

### 작업 1: 리뷰 코어 프롬프트와 schema 추가

**파일:**
- 생성: `.github/prompts/codex-pr-review.ko.md`
- 생성: `.github/prompts/codex-pr-review.schema.json`

- [x] **단계 1: 한국어 프롬프트 작성**

diff 우선 리뷰, 토큰 예산, 다중 관점 리뷰, confidence scoring, 중복 처리, 승인 정책, JSON-only 출력을 포함하는 프롬프트를 작성한다.

- [x] **단계 2: JSON schema 작성**

`eligibility`, `verdict`, `reviewed_context`, `automation_safety`, `findings`, thread 상태 배열, 중복 상태, context 요청을 요구하는 strict schema를 작성한다.

- [x] **단계 3: schema 검증**

실행:

```bash
jq empty .github/prompts/codex-pr-review.schema.json
```

기대 결과: exit 0.

### 작업 2: 워크플로와 크로스 플랫폼 경계 문서화

**파일:**
- 생성: `docs/codex/pr-review-workflow.md`
- 생성: `docs/superpowers/plans/2026-05-20-codex-structured-pr-review.md`

- [x] **단계 1: 현재 MVP 문서화**

`codex exec --output-schema`, schema 검증, managed comment, verdict 기반 GitHub review 제출 방식을 설명한다.

- [x] **단계 2: 단계적 로드맵 문서화**

inline comment, thread lifecycle, 토큰 최적화 chunking, 다중 관점 병렬 리뷰 단계를 정리한다.

- [x] **단계 3: review core와 platform adapter 분리**

GitLab 등에서 재사용 가능한 부분과 플랫폼별로 남겨야 하는 부분을 구분해 문서화한다.

### 작업 3: GitHub 워크플로 갱신

**파일:**
- 수정: `.github/workflows/codex-review.yml`
- 수정: `tests/codex/test-codex-review-workflow.sh`

- [x] **단계 1: `codex review`를 `codex exec`로 교체**

shell argument limit을 피하기 위해 stdin을 사용하고, `--output-schema`로 structured output을 강제한다.

- [x] **단계 2: 리뷰 context 수집**

base/head SHA, PR metadata, 변경 파일, 기존 comment, 기존 review comment, diff를 수집한다. PR 사용자 텍스트는 untrusted context로 취급한다.

- [x] **단계 3: verdict 게시**

검증된 JSON과 automation safety에 따라 `gh pr review --approve`, `--request-changes`, `--comment` 중 하나를 사용한다.

- [x] **단계 4: managed issue comment 유지**

review event가 제출된 경우에도 사람이 structured result를 볼 수 있도록 marker 기반 issue comment를 갱신한다.

- [x] **단계 5: 정적 테스트 추가**

워크플로가 prompt 파일, schema 파일, `codex exec`, stdin, `jq`, `gh pr review`를 사용하고 trusted `@codex` trigger guard를 유지하는지 확인한다.

### 작업 4: 검증

**파일:**
- 테스트: `tests/codex/test-codex-review-workflow.sh`
- 테스트: `.github/workflows/codex-review.yml`
- 테스트: `.github/prompts/codex-pr-review.schema.json`

- [x] **단계 1: 워크플로 계약 테스트 실행**

```bash
bash tests/codex/test-codex-review-workflow.sh
```

기대 결과: 모든 check 통과.

- [x] **단계 2: workflow YAML 파싱**

```bash
yq e '.' .github/workflows/codex-review.yml >/dev/null
```

기대 결과: exit 0.

- [x] **단계 3: JSON schema 파싱**

```bash
jq empty .github/prompts/codex-pr-review.schema.json
```

기대 결과: exit 0.
