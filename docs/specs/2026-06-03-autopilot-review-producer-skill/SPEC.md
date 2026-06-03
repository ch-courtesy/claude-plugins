---
scope:
  include:
    - plugins/autopilot/skills/review/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# depends_on: optional list of sibling SPEC slugs this unit depends on.
# ears_language: ko
---

# autopilot:review 생산자 스킬

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
autopilot 플러그인에 `autopilot:review` 스킬을 신설한다. 이 스킬은 **원샷 리뷰 생산자**다 — 한 작업의 변경(diff)을 받아 여러 독립 관점으로 리뷰하고, 단 하나의 머신리더블 판정(verdict)과 근거 있는 지적 목록(findings)을, 그리고 차단성 지적이 있을 때는 분류된 재작업 브리프를 산출한다. 스킬은 리뷰를 **생산**하기만 하며, 재구현·재푸시·승인까지의 반복(iterate-until-approved)은 소유하지 않는다.

공개 표면은 세 서브커맨드다:
- `run` — 한 작업의 변경을 리뷰해 판정·지적·(차단 시)재작업 브리프를 머신리더블로 출력한다.
- `status` — 한 작업의 마지막 리뷰 상태(판정·라운드·지적 fingerprint)를 조회한다.
- `list` — 리뷰 상태가 있는 작업들을 요약한다.

리뷰 관점(lens)은 최소 네 가지다: ① SPEC 수용기준 준수, ② 정확성·보안, ③ 회귀·역사적 맥락, ④ 저장소 가이드라인 준수. 각 관점은 서로의 결론을 보지 못하는 독립 판단으로 수행되고(합의 투표 아님), 중재 게이트가 관점들의 지적을 합쳐 중복 제거·근거 검증·신뢰도 게이팅한다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->
자율 파이프라인(SPEC → 구현 → 리뷰 → 머지)에는 사람이 지켜보지 않는 리뷰 단계가 필요하고, 그 판정이 머지 게이트를 좌우한다. 현재 리뷰 능력은 CI 봇 워크플로(.github)와 fsd 안의 미배선 채택 루프에 흩어져 있어 파이프라인이 로컬에서 자기완결적으로 리뷰를 생산할 수 없다. 리뷰 생산을 독립 스킬로 떼어 PR 유무와 무관하게 로컬에서 판정을 만들 수 있게 한다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- 항상 `review run`은 `approve`·`request_changes`·`unavailable` 중 정확히 하나의 판정을 머신리더블(구조화된 JSON) 한 건으로 출력한다.
- 작업 식별자(또는 PR·diff 참조)로 `review run`이 호출될 때, 해당 작업의 SPEC 수용기준·변경 diff·기존 리뷰 스레드를 입력으로 모아 네 관점(SPEC 준수·정확성/보안·회귀/역사·가이드라인) 각각의 독립 리뷰를 수행한다.
- 출력 findings에 포함되는 동안, 각 finding은 네 가지 증거(변경 위치 링크·실패 경로 설명·파일과 라인 인용·실행 가능한 제안)를 모두 갖추고 신뢰도 점수 80 이상이며, 네 증거 중 하나라도 빠지거나 신뢰도 80 미만이면 출력에서 제외된다.
- 변경 diff가 잘렸거나 필수 컨텍스트를 읽지 못해 판단 근거가 불완전하면(오류), 판정은 `unavailable`이 되고 어떤 경우에도 `approve`를 내지 않는다.
- 동일한 지적은 파일·관점·정규화된 제목으로 만든 안정적 fingerprint로 식별되어(라인 번호에 의존하지 않음), 같은 작업의 이전 리뷰에 이미 게시된 지적은 중복 출력되지 않는다.
- 차단성(blocking) 지적이 하나라도 있으면, 출력은 그 지적들을 반드시 반영·후속으로 미룸·반영 불필요 세 갈래(`rules/change-adoption.md`)로 분류한 재작업 브리프를 함께 싣고, 안전 경계(보안·데이터 손실·계약·범위·권한) 지적은 반드시 반영으로 고정되어 강등되지 않는다.
- SPEC 수용기준 커버리지(전체 기준 수·검증된 기준 수·미검증 기준)가 출력에 포함되며, 미검증 수용기준이 남으면 판정은 `approve`가 되지 않는다.
- 스킬의 결정적 동작(diff 수집·fingerprint·신뢰도 게이트·판정 산출·스레드 라이프사이클)은 외부 인터페이스(리뷰 조회·구현·forge·backend)를 주입 가능한 명령 변수로 둔 self-test로, 실제 PR·브랜치 아티팩트를 검사하지 않고 mock만으로 통과한다.

## 범위
포함:
- `plugins/autopilot/skills/review/SKILL.md` — 기존 autopilot SKILL.md 컨벤션(frontmatter, 호출, 모델, Subcommands, references 테이블, 의존성, 불변식) 준수.
- `plugins/autopilot/skills/review/references/` — 서브커맨드 라우터 스크립트(bash 3.2+), 결정적 하니스(diff 수집·fingerprint·신뢰도 게이트·판정·스레드 라이프사이클·selftest), lens 서브에이전트 dispatch 양식(agent-prompts), 출력 스키마.
- 다관점 lens 리뷰는 로컬 서브에이전트를 병렬로 돌려 수행한다.

비-목표 / 제외:
- 반복(iterate-until-approved) 루프·재구현 위임·review-round 증가·수렴 가드는 이 스킬이 소유하지 않는다(오케스트레이터 책임 — 형제 SPEC).
- fsd.sh `cmd_review`/`cmd_poll` 배선·poll.sh 재지정은 이 스킬에 포함하지 않는다(형제 SPEC).
- 새 적대 렌즈 정의를 만들지 않는다 — `plugins/autopilot/skills/spec/references/personas.md`(contrarian·minimalist·constraint-auditor)를 참조한다.
- GitHub로의 자동 승인(approve) API 호출·머지 차단은 하지 않는다 — 판정은 머신리더블 산출물일 뿐 게이트 결정은 오케스트레이터·머지 규칙이 한다.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 라우터·하니스는 bash 3.2+ 호환(연관 배열 미사용)으로 작성한다.
- 리뷰 생산의 프롬프트·출력 스키마는 기존 `.github/prompts`의 PR 리뷰 계약(5관점·4점 증거요건·신뢰도≥80·fingerprint)과 `.github/prompts/codex-pr-review.schema.json`을 재사용·확장하되, SPEC 수용기준 재검증 필드와 파이프라인 판정(approve/request_changes/unavailable) 분기를 가산한다 — 계약을 새로 지어내 분기시키지 않는다.
- 리뷰 9원칙(`rules/review.md`)과 채택 분류 프레임(`rules/change-adoption.md`)을 재정의하지 않고 실행자로서 따른다.
- 스킬은 자기 상태·자기 정의 파일 밖 경로를 만들지 않는다.
- 적대 렌즈는 규모 임계가 충족될 때만 가산 발동하며 정의는 `personas.md`를 참조한다(복제 금지).

## 위험 (있을 때만)
- 로컬 서브에이전트 다관점 리뷰는 LLM 산출이라 결정적 self-test로 직접 검증 불가하다 — self-test는 하니스의 결정적 부분(fingerprint·신뢰도 게이트·판정 산출·스레드 라이프사이클)을 mock 인터페이스로만 검증하고, lens 판단 품질은 검증 범위 밖임을 명시한다.
- 기존 `.github` 계약을 로컬 파이프라인 모드로 확장할 때 CI 봇 경로와 계약이 갈리면 표류 위험이 있다 — 공유 스키마 한 곳을 단일 출처로 두고 파이프라인 필드를 가산하는 형태로 묶는다.
