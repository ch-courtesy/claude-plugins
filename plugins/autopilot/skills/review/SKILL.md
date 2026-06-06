---
name: review
description: "한 작업의 변경(diff)을 여러 독립 관점으로 리뷰해 단일 머신리더블 판정(approve/request_changes/unavailable)·근거 있는 지적·재작업 브리프를 생산하고 싶을 때 사용 — 반복(iterate-until-approved)·승인·머지는 소유하지 않는 원샷 리뷰 생산자. 호출 'Skill(skill=\"review\", args=\"<subcommand> [<args>]\")' (run/status/list)."
allowed-tools:
  - Read
  - Agent
  - Bash(bash * review.sh run:*)
  - Bash(bash * review.sh status:*)
  - Bash(bash * review.sh list:*)
  - Bash(bash * review.sh fingerprint:*)
  - Bash(bash * review.sh selftest:*)
---

# review

`review` 는 **원샷 리뷰 생산자**다. 한 작업의 변경(diff)을 받아 여러 독립 관점으로 리뷰하고, 단 하나의 머신리더블 판정(verdict)과 근거 있는 지적 목록(findings), 그리고 차단성 지적이 있을 때는 분류된 재작업 브리프를 산출한다.

이 스킬은 리뷰를 **생산**하기만 한다 — 재구현·재푸시·승인까지의 반복(iterate-until-approved)·review-round 증가·forge 로의 자동 approve/merge 는 **소유하지 않는다**(오케스트레이터·머지 규칙 책임). 판정은 머신리더블 산출물일 뿐, 머지 게이트 결정은 호출 레이어가 한다.

## 호출

`Skill(skill="review", args="<subcommand> [<args>]")`

또는 직접: `bash plugins/autopilot/skills/review/references/review.sh <subcommand> [<args>]`

## 모델

- **단위**: 한 작업의 변경(diff). 작업 식별자(또는 PR·diff 참조)로 입력한다.
- **역할 분리**: LLM 다관점 lens 리뷰는 워커가 서브에이전트로 수행하고, 결정적 중재(diff 수집·fingerprint·신뢰도 게이트·판정 산출·스레드 라이프사이클)는 `review.sh` 하니스가 수행한다. 하니스는 LLM 을 호출하지 않는다.
- **상태 저장소**: `REVIEW_STATE_DIR`(기본 `<git-root>/.review`) 아래 작업별 디렉토리에 마지막 판정·review-round·지적 fingerprint 를 보관한다. 스킬은 자기 상태·자기 정의 파일 **밖 경로를 만들지 않는다**.

## 리뷰 관점 (4 lens, 독립)

서로의 결론을 보지 못하는 **독립 판단**으로 수행한다(합의 투표 아님). 중재 게이트가 관점들의 지적을 합쳐 중복 제거·근거 검증·신뢰도 게이팅한다.

1. **SPEC 수용기준 준수** (`spec_compliance`) — 각 수용기준 충족 여부를 검증하고 검증된 기준 id 를 보고.
2. **정확성·보안** (`bug`) — 변경 hunk 의 명확한 correctness/security/reliability 버그.
3. **회귀·역사적 맥락** (`history`) — 변경이 기존 의도·이전 결정을 깨는지.
4. **저장소 가이드라인 준수** (`guideline`) — `CLAUDE.md`·`rules/`·워크플로 문서와의 충돌.

각 lens dispatch 양식은 `references/agent-prompts.md`. 규모 임계가 충족될 때만 가산 발동하는 적대 렌즈가 필요하면 그 정의는 `plugins/autopilot/skills/spec/references/personas.md`(단일 출처)를 **참조**한다 — 복제하지 않는다.

## 중재 게이트 (결정적)

워커가 4 lens 출력을 하나의 `{findings, verified_criteria, context_incomplete}` 로 병합해 하니스에 주입하면, 하니스가:

- **fingerprint**: 파일 + 리뷰 관점 + 정규화한 제목으로 결정론적으로 계산(라인 번호 무관). 같은 지적은 라인이 바뀌어도 같은 fingerprint.
- **신뢰도·증거 게이트**: 각 finding 은 4증거(변경 위치 링크·실패 경로 설명·파일·라인 인용·실행 가능한 제안)를 모두 갖추고 `confidence_score` 80 이상이어야 한다. 하나라도 빠지거나 80 미만이면 출력에서 **제외**한다.
- **중복 제거**: 같은 작업의 이전 리뷰에 이미 게시된 fingerprint 와 같으면 `skipped_duplicates` 로 보내고 출력 findings 에서 제외한다.
- **재작업 브리프**: 차단성(blocking) 지적이 하나라도 있으면 `rules/change-adoption.md` 의 3분류(반드시 반영 `must_adopt`·후속 `defer`·반영 불필요 `wont_adopt`)로 분류한다. **안전 경계(보안·데이터 손실·계약·범위·권한) 지적은 반드시 반영(`must_adopt`)으로 고정**되어 강등되지 않는다.
- **수용기준 커버리지**: `acceptance_coverage`(total·verified·unverified)를 산출한다. 미검증 수용기준이 남으면 판정은 approve 가 되지 않는다.
- **판정**: 단일 `pipeline_verdict` 를 산출한다 — `approve` · `request_changes` · `unavailable` 중 정확히 하나.
  - diff 가 잘렸거나 필수 컨텍스트를 읽지 못하면 `unavailable`(어떤 경우에도 approve 안 함).
  - blocking 지적 또는 미검증 수용기준이 있으면 `request_changes`.
  - 그 외(컨텍스트 온전·blocking 없음·전 수용기준 검증)면 `approve`.

출력은 `references/output-schema.json` 을 따르는 단일 JSON 한 건이다.

## Subcommands

### review run --task `<task-id>`

한 작업의 변경을 리뷰해 판정·지적·(차단 시)재작업 브리프를 머신리더블 JSON 으로 stdout 에 출력한다.

- 워커 절차: 작업의 SPEC 수용기준·변경 diff·기존 리뷰 스레드를 입력으로 모아 4 lens 를 병렬 dispatch(`agent-prompts.md`) → 출력 병합 → 하니스 중재 → 단일 판정.
- 외부 인터페이스는 주입 가능 명령 변수로 둔다: `REVIEW_DIFF_CMD`·`REVIEW_SPEC_CMD`·`REVIEW_LENS_CMD`·`REVIEW_THREADS_CMD`.
- 출력: `pipeline_verdict`·`findings`·`acceptance_coverage`·`rework_brief`·`skipped_duplicates` 등 단일 JSON.

### review status --task `<task-id>`

한 작업의 마지막 리뷰 상태(판정·review-round·지적 fingerprint)를 조회한다.

### review list

리뷰 상태가 있는 작업들을 요약한다. **빈 상태에서도 0 exit** 으로 정상 출력한다.

## references

| 파일 | 역할 |
|---|---|
| `references/review.sh` | 서브커맨드 라우터 + 결정적 중재 하니스(diff 수집·fingerprint·신뢰도 게이트·판정·스레드 라이프사이클·selftest). 외부 인터페이스를 주입 가능 명령 변수로 둠. |
| `references/agent-prompts.md` | 4 lens 독립 dispatch brief + 공통 출력 계약(발견만 보고, 판정 금지) |
| `references/output-schema.json` | 출력 스키마. `.github/prompts/codex-pr-review.schema.json` 공유 계약 재사용 + 파이프라인 필드(pipeline_verdict·acceptance_coverage·rework_brief) 가산 |

## 의존성

`git`, `bash` 3.2+, `jq`, `sha256sum` 또는 `shasum`. LLM lens 리뷰는 로컬 서브에이전트(`Agent`)로 수행한다. forge(`gh` 등) 연동은 본 스킬 의존성이 아니다(판정은 머신리더블 산출물일 뿐).

## 불변식 / 규칙

- 스킬은 자기 상태(`REVIEW_STATE_DIR`)·자기 정의 파일 **밖 경로를 만들지 않는다**.
- 반복(iterate-until-approved)·재구현 위임·review-round 증가·수렴 가드를 소유하지 않는다(오케스트레이터 책임).
- forge 로의 자동 approve/merge·머지 차단을 하지 않는다 — 판정은 머신리더블 산출물.
- 리뷰 9원칙(`rules/review.md`)·채택 분류 프레임(`rules/change-adoption.md`)을 재정의하지 않고 실행자로서 따른다.
- 적대 렌즈 정의(`personas.md`)를 복제하지 않고 참조한다.
- 공유 PR 리뷰 계약(`.github/prompts/codex-pr-review.schema.json`: 4증거·신뢰도≥80·fingerprint)을 새로 지어내지 않고 단일 출처로 재사용하며 파이프라인 필드만 가산한다.
- 라우터·하니스는 bash 3.2+ 호환(연관 배열 미사용)으로 작성한다.
- 결정적 동작은 외부 인터페이스를 주입 mock 으로 치환한 `review.sh selftest`·`tests/` 로 실제 PR·브랜치 아티팩트 없이 검증한다.
