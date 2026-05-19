---
scope:
  include: ["plugins/autopilot/skills/spec/**", "tests/autopilot/test-spec-skill.sh"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-spec-skill.sh"
request_review: true
test_sweep_paths:
  - "tests/autopilot/test-spec-skill.sh"
---

# spec 워크플로 엄격 강화 — §5.1 누락 면제 차단 + self-review 통과 흔적 외부 검증

## 무엇을 만들 것인가
spec 워크플로의 자체 검증 절차를 LLM 휴리스틱 의존에서 분리된 강제 단계·외부 검증가능한 흔적으로 전환한다.

(1) **§5.1 sweep 자동 판단 단계 승격**: 기존 step 5 내부 sub-section이던 §5.1을 독립 단계로 승격해 step 5 명확화 라운드가 생략되더라도 §5.1은 항상 실행되도록 한다. 자체 검토(step 9) sweep 축 검사가 "§5.1 실행 흔적(SPEC.md frontmatter의 `test_sweep_paths` 키 또는 `# test_sweep_paths: reviewed-no-sweep` 주석)" 부재 시 fail 조건으로 명시된다.

(2) **self-review 통과 라벨 기록**: step 9 5+1축 체크를 모두 통과하면 task issue에 `self-review-passed` 라벨을 추가한다. 라벨 부여는 spec 워크플로 내부에서 step 9 종료 직후 수행한다. 라벨 명시·제거 lifecycle은 본 SPEC 범위 외.

(3) **정적 검증**: tests/autopilot/test-spec-skill.sh에 self-referential 검사 케이스 추가 — 본 SPEC 자체 issue의 `gh issue view --json labels` 결과에 `self-review-passed` 라벨이 포함되었는지 검사. 본 SPEC issue ID는 SPEC.md frontmatter 또는 test 자체에서 참조 가능하게 한다.

## 수용 기준 (EARS)
- **AC1 (Ubiquitous)**: plugins/autopilot/skills/spec/SKILL.md의 §5.1 sweep 자동 판단 절차가 step 5 내부 sub-section에서 **독립된 단계(step 5.1)로 승격**되어, step 5 생략 여부와 무관하게 항상 실행됨이 워크플로 본문에 명시된다.
- **AC2 (Ubiquitous)**: plugins/autopilot/skills/spec/references/self-review.md의 sweep 축 검사 항목이 "§5.1 실행 흔적 부재 시 fail" 조건을 명시한다 — `test_sweep_paths` 키와 `# test_sweep_paths: reviewed-no-sweep` 주석 둘 다 부재일 때 `[NEEDS CLARIFICATION]` 마커를 박는다.
- **AC3 (Event-driven)**: spec 워크플로 step 9 자체 검토가 완료되고 5+1축 모두 통과했을 때, 시스템은 task issue에 `self-review-passed` 라벨을 추가한다.
- **AC4 (Unwanted/조건)**: step 9 자체 검토에서 한 개라도 `[NEEDS CLARIFICATION]` 마커가 박힌 경우, 시스템은 task issue에 `self-review-passed` 라벨을 추가하지 않는다.
- **AC5 (Ubiquitous)**: tests/autopilot/test-spec-skill.sh가 self-referential 라벨 검사 케이스를 포함 — 본 SPEC 자체 issue ID(SPEC.md frontmatter 또는 test 내부 참조)의 `gh issue view --json labels` 결과에 `self-review-passed` 라벨 포함을 검사한다.
- **AC6 (Ubiquitous)**: `bash tests/autopilot/test-spec-skill.sh`가 0 exit으로 끝난다 (기존 TEST 1–16 + AC5 새 케이스 결합).

## 범위
포함:
- `plugins/autopilot/skills/spec/SKILL.md` — §5.1 독립 단계(step 5.1) 승격 + step 9 자체 검토 종료 직후 자동 라벨 추가 절차 명세.
- `plugins/autopilot/skills/spec/references/self-review.md` — sweep 축 검사의 "§5.1 실행 흔적 부재 시 fail" 조건 명시.
- `tests/autopilot/test-spec-skill.sh` — self-referential 라벨 검사 새 케이스 추가.

비-목표 / 제외:
- loop 스킬·pr-phase·review-fix·cleanup-phase 등 loop 측 로직 변경 (라벨 확인은 spec 스킬 내부와 test 내부에서만).
- 다른 스킬 frontmatter 수정 (autopilot:dispatch, autopilot:loop, autopilot:prd 변경 안 함).
- 기존 SPEC들의 retroactive 라벨 부여 (라벨 부재 issue도 정상 처리).
- 라벨 제거·재부여 lifecycle 로직 (Done 전이 이후 처리 등).
- 라벨명 변경 시 마이그레이션 (현 SPEC은 `self-review-passed` 고정).

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash tests/autopilot/test-spec-skill.sh
```

## 제약 (있을 때만)
- 라벨명 `self-review-passed` 고정 — 테스트도 동일 문자열로 hardcoded.
- AC5 self-referential 테스트는 본 SPEC 자체 issue ID 필요 — SPEC.md frontmatter에 issue ID 명시 또는 test 자체에 hardcode (구현 단계 결정).
- 자체-재귀 (`feedback_no_self_apply_during_spec`): 본 SPEC를 작성·수행하는 *현 호출*은 아직 라벨 추가 절차 미적용 상태이므로 라벨은 수동으로 부여돼야 한다 — 새 동작은 본 SPEC이 merge된 이후의 다음 spec 호출부터 자동 적용된다.
- gh CLI OAuth 인증 의존 — 테스트 실행 환경에 `gh` 설치 + 인증 필수. 미설치·미인증 환경에서는 테스트가 fail한다.

## 위험 (있을 때만)
- **라벨 수동 제거 시 테스트 fail**: PR merge 이후 누군가가 라벨을 수동 제거하면 self-referential 테스트가 fail. PR merge 이후 lifecycle 처리는 본 SPEC 범위 외 — 사후 SPEC으로 보강.
- **gh CLI 의존으로 테스트 brittle**: offline·CI 환경에서 gh 인증이 없으면 skip이 아닌 fail. 향후 fallback (skip with warning) 로직 추가 검토 가능.
- **self-referential 순서 제약**: 본 SPEC PR이 merge되기 전에는 본 SPEC issue에도 라벨이 수동 부여돼야 테스트가 통과. 자동화 도입 후 다음 spec 호출부터 자연스럽게 정합.
- **사용자 마찰 증가**: step 5 생략 시에도 §5.1이 항상 실행되므로 사용자에게 노출되는 프롬프트 수가 미소 증가. 의도된 trade-off — 누락 위험 감소가 우선.
