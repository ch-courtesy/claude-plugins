---
scope:
  include: ["plugins/autopilot/skills/loop/references/review-fix-phase.sh", "plugins/autopilot/skills/loop/SKILL.md", "tests/autopilot/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-review-fix-silent-fail.sh"
ears_language: ko
request_review: true
---

# review-fix-phase silent-fail false-positive: statusCheckRollup 빈 상태 오판

## 무엇을 만들 것인가
`autopilot:loop`의 review-fix-phase silent-fail 검출기가 `statusCheckRollup`이 빈 상태일 때를 "체크 모두 완료"로 오판해 PR 생성 직후 조기 ESCALATION을 트리거하는 false-positive를 제거한다. `0 pending of 0 total`(정보 없음)과 `0 pending of N total`(진짜 완료)을 구분하고, PR 생성 직후 grace 기간 도입으로 GitHub Actions check가 등록되기 전까지의 일시적 빈 rollup을 흡수한다.

## 수용 기준 (EARS)
- **AC1**: 시스템은 PR 생성 직후 grace 기간 내에는 review-fix-phase의 silent-fail 검출기를 실행하지 않는다. grace 기간은 환경변수로 조절된다 (기본 5분).
- **AC2**: 시스템이 silent-fail 검출기를 실행할 때, `statusCheckRollup`의 전체 check 수가 0이면 그 폴링 회차에 한해 ESCALATION을 발동하지 않고 카운터만 리셋한다.
- **AC3**: 전체 check 수가 0보다 크고 pending 수가 0이며 다른 활동 지표(reviews·comments·inline·owner cmd) 모두 0일 때는 기존 동일하게 ESCALATION을 발동한다 (회귀 보존).
- **AC4**: 시스템은 grace 기간 조절용 환경변수의 이름·기본값·floor를 모두 명시한다.
- **AC5**: 본 SPEC의 verify 명령이 0 exit으로 통과한다.

## 범위
포함:
- `plugins/autopilot/skills/loop/references/review-fix-phase.sh` silent-fail 검출기 수정 (total_checks 산출 + grace 기간 도입)
- `plugins/autopilot/skills/loop/SKILL.md` 새 환경변수(grace 기간) 문서화
- `tests/autopilot/test-review-fix-silent-fail.sh`(또는 동등 명칭) 검증 스크립트 추가

비-목표 / 제외:
- `pr-phase.sh`·`rebase-phase.sh`·`cleanup-phase.sh` 수정
- review-fix-phase의 다른 로직(merge 경로, owner cmd, auto-merge) 재설계
- GitHub Actions 시점 시뮬레이션 하니스 자체 구축
- `LOOP_REVIEW_IDLE_THRESHOLD` 기본값 변경 (grace로 해결)

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash tests/autopilot/test-review-fix-silent-fail.sh
```

스크립트는 4가지 statusCheckRollup mock 시나리오에서 silent-fail 평가 결과·grace 기간 동작·회귀 시나리오를 검사한다:
- (a) **빈 배열** — grace 기간 내·외 모두 ESCALATION 미발동 (AC1·AC2)
- (b) **`[COMPLETED]` + 활동 0건** — grace 후 ESCALATION 발동 (AC3 회귀 보존)
- (c) **`[IN_PROGRESS]`** — pending=1로 ESCALATION 미발동 (기존 동작 회귀)
- (d) **`[COMPLETED, IN_PROGRESS]`** — pending=1로 ESCALATION 미발동 (기존 동작 회귀)

추가로 grace 기간 환경변수의 이름·기본값·floor가 SKILL.md 또는 스크립트 내 명시되어 있음을 정적 검사 (AC4).

## 제약 (있을 때만)
- 본 repo는 plugin source repo이며 실제 효과는 사용자 plugin cache가 새 review-fix-phase.sh를 동기화한 뒤에만 관측된다.
- `request_review: true`로 설정된 본 SPEC 자체의 loop 실행이 해결 이전 버그 가진 코드로 감지되므로 첫 PR 실행 시 독자적 좌절 가능 — 사용자 개입으로 머지 신호 또는 수동 cleanup 처리.

## 위험 (있을 때만)
- grace 기간을 너무 길게 설정하면 진짜 stuck 상황 감지가 늦어지고, 너무 짧게 설정하면 본 버그 재현. 기본값 5분이 GitHub Actions 등록 지연·큐 지연 폭을 얼마나 잘 흡수하는지 실측 검증 필요.
- `total_checks` 관측은 PR 생성 직후 조기 폴링에서 일시적으로 0에 머문 가능 (action job queue delay). grace 기간으로 이는 안전하게 명시 처리되어야 함.
