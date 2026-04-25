# PR 코드 리뷰 에이전트 (계획)

**상태**: Phase 1 완료 · Phase 2/3 미진행 (스코프 동결)
**작성일**: 2026-04-25
**최종 갱신**: 2026-04-26

## 목표

이 플러그인 마켓플레이스 리포에 올라오는 PR을 Claude 기반 에이전트가 자동으로 1차 검토하고, GitHub에 리뷰 코멘트를 게시한다. 사람 리뷰어를 대체하지 않고 **스크리닝·일관성 검사·힌트 제공** 역할.

## 접근 방식 비교

| 옵션 | 설명 | 장점 | 단점 |
|---|---|---|---|
| A. Anthropic 공식 `claude-code-action` | GitHub Marketplace에 공개된 공식 액션. PR 트리거 + `@claude` 멘션 응답 | 구축 비용 최소, 공식 유지보수 | 이 리포 특화 체크 커스터마이즈 제한적 |
| B. 커스텀 GitHub Action + Anthropic SDK | 직접 짜는 액션, 리포 맥락에 맞게 프롬프트/도구 구성 | 완전한 커스터마이즈 | 구축·유지보수 공수, 보안 표면 증가 |
| C. 외부 웹훅 서비스 | GitHub Webhook → 자체 서버 → Anthropic SDK | 긴 문맥·복잡 로직 가능 | 운영 인프라 비용, 오버엔지니어링 |

**추천**: A로 시작 → 공식 액션이 못 커버하는 부분만 B의 보조 액션으로 확장.

## 체크 항목

### 목표 정합성 검증 (모든 PR 공통)

파일 단위 검사 이전에, PR 전체 수준에서 "변경이 선언된 목표에 타당한가"를 먼저 본다:

- **PR 목적 선언 존재**: description에 "무엇을 / 왜" 바꾸는지 명확한지. 없거나 모호하면 지적.
- **목표 달성 충분성**: 변경 내용이 선언된 목표를 **빠짐없이** 구현했는지 (주장만 하고 구현이 누락된 부분 없는지).
- **접근의 타당성**: 선택한 방법이 목표에 비추어 적절한지 (우회·과잉 복잡도·잘못된 추상화·부적절한 위치 변경 아닌지).
- **스코프 준수**: 목표 범위를 **과도하게 초과**하지 않는지 (무관한 리팩토링·곁가지 튜닝 섞임 감지).
- **불필요·저가치 요소 감지**: 변경 안에 신호가 없는 부분이 있는지 — 코드가 이미 말하는 걸 다시 쓴 주석, 미사용 import·변수·함수, 남은 디버그 로그, 당장 필요 없는 추측성 확장, 과잉 스캐폴딩·예시, 중복된 설명. 가능하면 구체 라인을 지목해 제거 제안.
- **문서·테스트 동조**: 행동이 바뀌면 관련 문서(`docs/plans/`, `SKILL.md`, `CLAUDE.md`)와 검증 항목이 같이 갱신됐는지.

이 검증은 diff만으로는 어렵고, PR description · 관련 이슈 · 기존 계획 문서를 함께 읽어야 한다. 에이전트 시스템 프롬프트에 "먼저 PR description과 연결된 docs/plans 문서를 읽고, 변경이 목표에 비추어 타당한지 요약하라"를 초반 지시로 둔다.

### 파일 성격별 검증

PR이 건드린 파일 성격에 따라:

- **`.claude-plugin/marketplace.json`**: 참조하는 `plugins/*` 디렉토리 실제 존재, 중복 `name`, 필수 필드 존재 여부
- **`plugins/*/.claude-plugin/plugin.json`**: 필수 필드(`name`/`version`), semver 형식, 작성자 정보 정합성
- **`SKILL.md`**: frontmatter의 `name`/`description`이 **활성화 트리거로 충분히 명확한지**, 본문이 description과 일치하는지
- **`<category>.md` 템플릿**: 짝을 이루는 `SKILL.md`의 참조 경로 일치, 불필요한 `---` 프론트매터 구분선 없는지
- **`CLAUDE.md` 템플릿**: `AskUserQuestion` 필수 문구가 글자 그대로 보존됐는지
- **`docs/plans/*.md`**: 상태(`계획 중` / `완료`) 마커 적절성, 날짜 정합성
- **일반 품질**: 네이밍 일관성, 주석·문서 정합성, 비밀 노출, 외부 요청 신규 추가

## 단계적 배포

### Phase 1 — 공식 액션 도입 (낮은 리스크)
- `.github/workflows/claude-review.yml` 생성
- `ANTHROPIC_API_KEY` secret 등록
- 트리거: PR `opened` / `synchronize` + `@claude` 멘션
- 기본 리뷰만 — 코드 품질 일반 코멘트

### Phase 2 — 리포 특화 프롬프트 튜닝 (~~미진행, 2026-04-26 결정~~)
~~위 "체크 항목"을 시스템 프롬프트로 주입, 리포 규약에 맞춰 기대 기준 명시 등.~~
**미진행 사유**: Phase 1 카나리(PR #16, #20) 검증에서 기본 프롬프트가 의도한 5개 체크 항목을 충분히 잡고, 합격 신호·스레드 resolve도 정상 동작 확인. 추가 튜닝의 한계 효용이 유지비용을 못 넘는다고 판단.

### Phase 3 — 확장 (~~미진행, 2026-04-26 결정~~)
~~플러그인 매니페스트 validation 분리, `merge-ready` 라벨 자동화, 블로커 표시 등.~~
**미진행 사유**: 현재 PR 트래픽 규모에서 자동화 확장이 과잉. 사람 리뷰어 + Claude 1차 스크리닝의 조합으로 충분.

## 비용 · 리스크

- **API 비용**: PR 크기에 비례. 일반 PR 기준 ¢ 단위, 대형 PR은 $ 단위 가능. 월간 PR 볼륨 예상치가 정해지면 상한 설정.
- **False positive**: AI 리뷰는 틀린다. **인간 최종 승인 필수**, 에이전트 리뷰를 블로커로 두지 않는 것이 안전한 출발점.
- **누설 리스크**: 프롬프트에 리포 컨텍스트가 실리므로, secret/PII가 유입되지 않도록 레포 차원의 게이트 유지.
- **소음**: 모든 라인에 코멘트 달면 피로. "요약 + 주요 이슈" 포맷 + 중요도 threshold 권장.

## 결정 (2026-04-25 확정)

- [x] **공식 `anthropics/claude-code-action@v1`** 사용 (커스텀 미선택)
- [x] **모든 PR, 드래프트 제외** (`opened` / `synchronize` / `ready_for_review`)
- [x] `@claude` 멘션으로 수동 재리뷰 **허용** — 세 가지 코멘트 이벤트 모두에서 (PR 메인 대화 `issue_comment` / 인라인 `pull_request_review_comment` / 리뷰 본문 `pull_request_review`)
- [x] **`CLAUDE_CODE_OAUTH_TOKEN` 사용** (Pro/Max 구독 사용량에 포함) — `ANTHROPIC_API_KEY` 별도 과금 회피. 사용량은 본인 Claude 한도와 공유됨
- [x] **참고 의견만** — 리뷰는 코멘트로만 게시, merge 차단 없음

## 후속 작업 (모두 완료, 2026-04-26)

1. ✅ Phase 1 워크플로 작성 — `.github/workflows/claude-review.yml` (PR #15)
2. ✅ OAuth 토큰 등록 + Claude GitHub App 설치 + 머지
3. ✅ 카나리 시운전:
   - PR #16 (canary v1): 5개 체크 항목 동작 확인. 중복 코멘트·심각도 불일치 발견 → PR #19에서 보정 (스레드 resolve + 합격 신호 + 워크플로 변경 PR 자동 스킵)
   - PR #20 (canary v2): inline 코멘트 깔끔(중복 0, 심각도 일관). Phase 1 합격
4. ❌ Phase 2 진입 — 미진행 결정 (위 Phase 2 항목 참조)

## 검증된 전제 (2026-04-25)

- Anthropic 공식 액션: `anthropics/claude-code-action@v1` (GitHub Marketplace 등록명: "Claude Code Action Official")
- 인증 = **두 단계 모두 필요**:
  - (1) Anthropic API 인증: `CLAUDE_CODE_OAUTH_TOKEN` (Pro/Max 전용, `claude setup-token`). `anthropic_api_key` input에 그대로 전달
  - (2) GitHub 리포 권한: Claude GitHub App (https://github.com/apps/claude) 설치. 미설치 시 워크플로가 401 "Claude Code is not installed on this repository"로 실패
- 대안 인증: `ANTHROPIC_API_KEY` (별도 과금) / Bedrock / Vertex / Foundry — 이 경우에도 GitHub App 설치는 동일하게 필요
- 커스텀 프롬프트는 `with.prompt` 입력으로 주입
- 사용량 한도: 본인 Pro/Max 구독 한도와 공유됨 (별도 spend cap 없음). 트래픽이 본인 일반 Claude 사용에 영향
- 보안 주의: 외부 컨트리뷰터 PR도 본인 OAuth 토큰으로 실행됨. 공식 액션의 sandbox에 의존하므로 신뢰 못 할 PR 트래픽이 늘어나면 `ANTHROPIC_API_KEY`로 분리 검토
