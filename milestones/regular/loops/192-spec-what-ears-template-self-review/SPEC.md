---
scope:
  include:
    - "plugins/autopilot/skills/spec/references/spec-template.md"
    - "plugins/autopilot/skills/spec/references/self-review.md"
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "grep -qE 'literal.*패턴.*WHAT.*적지 않|EARS.*단일 출처' plugins/autopilot/skills/spec/references/spec-template.md && grep -qE 'WHAT.?EARS.?결합|WHAT-EARS' plugins/autopilot/skills/spec/references/self-review.md && grep -qE 'Bash\\(.*\\).*literal|exclusion 문구|\\[NEEDS CLARIFICATION\\]' plugins/autopilot/skills/spec/references/self-review.md"
ears_language: ko
---

# spec 스킬 — WHAT/EARS 결합 차단 (template 강화 + self-review 게이트)

## 무엇을 만들 것인가

spec 스킬의 SPEC 작성 표준 파일 2종 — `references/spec-template.md` (작성 템플릿) 와 `references/self-review.md` (자체 검토 5항목) — 를 갱신해 WHAT 섹션이 literal 패턴·exclusion 목록·예외 사유 같은 구체 세부사항을 보유하지 않도록 구조적으로 강제한다. EARS 섹션이 literal·exclusion 의 단일 출처가 되고, WHAT 은 카테고리 라벨·의도만 보유. step 9 자체 검토 단계에서 본 분리 위반을 검출해 `[NEEDS CLARIFICATION]` 마커를 박는 새 게이트 항목을 추가한다.

배경: 본 세션의 PR #187 가 AC4 split (positive AC4 + negative AC4-neg) 시 WHAT 항목 (4) 가 동반 갱신되지 않아 reviewer NIT 가 발생했다. worker 가 cosmetic NIT 응대 chase 에 빠지고 결국 사용자가 수동 보완으로 마무리. 근본 원인은 WHAT 과 EARS 가 같은 정보(literal 패턴·exclusion 목록)를 중복 보유하는 구조적 결합 — AC 변경 시 WHAT 동기 누락이 자명한 일관성 NIT 를 만든다. 처방은 WHAT 의 정보 범위를 좁혀 (카테고리 라벨·의도만) 결합 자체를 차단하는 것이며, 본 SPEC 는 template 강화 + self-review 게이트 두 트랙으로 이를 강제한다.

## 수용 기준 (EARS)

- **AC1** (Ubiquitous): `plugins/autopilot/skills/spec/references/spec-template.md` 의 "## 무엇을 만들 것인가" 섹션 주석에 literal 패턴 (`Bash(...)` 같은) 과 exclusion 문구 ("…는 제외", "…는 추가되지 않는다") 를 WHAT 에 적지 않고 수용 기준 (EARS) 가 단일 출처라는 명시 지침이 포함된다.
- **AC2** (Ubiquitous): `plugins/autopilot/skills/spec/references/self-review.md` 의 자체 검토 항목 리스트에 "WHAT-EARS 결합 검사" 라는 신규 항목이 추가된다.
- **AC3** (Ubiquitous): self-review.md 의 신규 항목 본문은 WHAT 본문에 `Bash(...)` literal 패턴 또는 exclusion 문구 ("…는 제외", "…는 추가되지 않는다", "…는 포함되지 않는다") 가 검출되면 `[NEEDS CLARIFICATION]` 마커를 박도록 명시한다.
- **AC4** (Unwanted): 본 변경은 `spec-template.md` 와 `self-review.md` 외 다른 어떤 spec 스킬 파일 (SKILL.md, ears-patterns.md, pre-clarification.md 등) · 자매 스킬 (loop, dispatch, prd) · target 프로젝트 파일도 수정하지 않는다.
- **AC5** (State-driven): 본 SPEC 호출 자체는 옛 규칙으로 마치고 (메모리 노트 `feedback_no_self_apply_during_spec` 정합), 새 룰은 본 SPEC 이 default 브랜치에 merge 된 후의 다음 spec 호출부터 효력을 가진다.

## 범위

포함:

- `plugins/autopilot/skills/spec/references/spec-template.md` — "## 무엇을 만들 것인가" 섹션 주석 보강 (literal·exclusion 금지 + EARS 단일 출처 명시)
- `plugins/autopilot/skills/spec/references/self-review.md` — 기존 5항목 (placeholder · 모순 · 범위 · 모호성 · EARS fail-가능성) 보존, "WHAT-EARS 결합 검사" 신규 항목 추가

비-목표 / 제외:

- 다른 spec 스킬 파일 (SKILL.md · ears-patterns.md · pre-clarification.md · task-state-alignment.md · feat-branch-commit.md 등) — 별개 SPEC 으로 분리
- 자매 스킬 (`loop`·`dispatch`·`prd`) — 영향 없음
- 기존 SPEC 들의 retroactive WHAT 리팩토링 — 본 SPEC 머지 후의 새 SPEC 부터 새 룰 적용 (점진 적용)
- target 프로젝트 코드·문서 — spec 스킬 자체의 표준만 갱신

## 검증

frontmatter `verify` 명령이 0 exit 으로 끝나야 합니다 (3개 grep -qE 체인 — AC1·AC2·AC3 표현 검출):

```bash
grep -qE 'literal.*패턴.*WHAT.*적지 않|EARS.*단일 출처' plugins/autopilot/skills/spec/references/spec-template.md && \
grep -qE 'WHAT.?EARS.?결합|WHAT-EARS' plugins/autopilot/skills/spec/references/self-review.md && \
grep -qE 'Bash\(.*\).*literal|exclusion 문구|\[NEEDS CLARIFICATION\]' plugins/autopilot/skills/spec/references/self-review.md
```

PR 리뷰 시점 보조 검사:

- `spec-template.md` 의 WHAT 주석에 "literal 패턴 금지", "exclusion EARS 단일 출처" 같은 의도가 자연어로 명확히 표현됐는지 사람이 직접 확인 (verify grep 은 표현 형태만 검증, 의미는 휴리스틱)
- `self-review.md` 의 신규 항목이 기존 5항목과 같은 형식·톤으로 추가됐는지 확인
- 기존 5항목 (placeholder · 모순 · 범위 · 모호성 · EARS fail-가능성) 이 본 변경으로 누락·변형되지 않았는지 확인

## 제약

- self-referential: `feedback_no_self_apply_during_spec` 메모리 노트에 따라 본 SPEC 호출 자체는 옛 규칙으로 마치고, 새 룰은 본 SPEC 머지 후의 다음 spec 호출부터 효력.
- `spec-template.md` 의 기존 WHAT 주석 ("WHAT/HOW 방어선 — 이 섹션은 무엇을 만드는지만 적습니다. ... loop이 자율적으로 접근법을 조정할 수 있도록 의도를 기술-중립적으로.") 은 유지·보강이며 제거가 아니다.
- `self-review.md` 의 기존 5항목은 보존, 신규 1항목 추가만 (총 6항목).
- WHAT-EARS 결합 검사는 step 9 자체 검토 단계의 모델 self-check 게이트 (runtime verify 가 아님) — 텍스트 휴리스틱 (`Bash(...)` 패턴·exclusion 문구) 기반.

## 위험

- 주석 강화·게이트 룰이 너무 강해 정당한 WHAT 표현 (간단한 카테고리 내 nested clarification, 예: "(1) JSON parser") 까지 차단할 수 있음 — 검출 기준 ("Bash(...) literal 패턴" · 명시적 exclusion 문구) 을 정확히 정의해 false-positive 최소화.
- 기존 SPEC 들이 본 룰 위반 상태로 남음 — retroactive 강제 안 함이 본 SPEC 의 명시 선택. 실무적으로 새 SPEC 부터 점진 적용 (위반 SPEC 들이 다시 손대질 때 자연 정리).
- WHAT-EARS 결합 검사 자체가 runtime verify 로 자동화하기 어려움 (텍스트 휴리스틱·자연어 의미 의존) — self-review 단계의 모델 self-check 로 처리, frontmatter `verify` 는 표현 grep 만 검증.
- 검출 패턴 (`Bash(...)`, "…는 제외", "…는 추가되지 않는다", "…는 포함되지 않는다") 가 도메인 변화에 따라 더 추가될 수 있음 — 본 SPEC 는 최소 휴리스틱 셋만 도입, 향후 SPEC 으로 보강 가능.
