---
scope:
  include:
    - plugins/autopilot/**
    - milestones/2026-06-conductor-pipeline/**
    - docs/specs/2026-06-03-autopilot-review-producer-skill/**
    - docs/specs/2026-06-03-fsd-review-orchestration-wiring/**
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - CLAUDE.md
ears_language: ko
---

# Remove fsd internal review and review skill

## 무엇을 만들 것인가

autopilot 플러그인에서 **fsd 차원의 내부 리뷰**(자동 리뷰·재구현 고리)와 **`autopilot:review` 스킬**을 완전히 제거한다. 리뷰는 외부 CI(GitHub PR 워크플로)와 사람에게 위임하고, fsd 파이프라인은 `intake → start → 통합(PR) → [외부 승인] → merge` 로 닫는다.

제거 후 `poll` 드레인은 열린 PR이 미승인 상태이면 어떤 자동 재구현도 하지 않고 "외부 승인 대기"로 전진을 멈춘다. 외부(CI 봇 또는 사람)가 PR에 승인을 달면 기존 머지 경로로 닫힌다.

## 목적 (왜)

내부 리뷰의 재구현 스텝이 프로덕션 경로에서 끊겨 있고(자율 실행기 미연결·미지원 인자·워크트리→브랜치 이식 부재), 외부 CI 리뷰가 이미 같은 역할을 독립적으로 수행한다. 이중 리뷰 레이어를 한 겹으로 줄여 깨진 내부 고리를 들어내고 파이프라인을 단순화한다.

## 완료 조건

1. 항상 `plugins/autopilot/skills/review/` 디렉터리와 `plugins/autopilot/skills/fsd/references/review-loop.sh` 파일이 존재하지 않는다.
2. 항상 `docs/specs/2026-06-03-autopilot-review-producer-skill/` 와 `docs/specs/2026-06-03-fsd-review-orchestration-wiring/` 디렉터리가 존재하지 않는다.
3. 항상 `plugins/` 아래 어떤 파일에도 `review-loop`, `FSD_REVIEW_CMD`, `POLL_REVIEW_CMD`, `REVIEW_PRODUCE_CMD`, `autopilot:review`, `skills/review`, `review_round`, `bump_review_round` 문자열이 남지 않는다(외부 CI `claude-review`·`codex-review` 워크플로 파일은 이 조건의 대상이 아니다).
4. `fsd.sh` 에 `review` 서브커맨드 라우팅·`cmd_review` 함수·usage의 `review` 줄·`FSD_REVIEW_CMD` 선언과 환경변수 안내·`cmd_status` 의 `review:` 출력 줄·selftest의 리뷰 위임 검증이 없다.
5. `bash plugins/autopilot/skills/fsd/references/fsd.sh selftest` 가 ALL PASS 한다.
6. `poll.sh` 의 `poll_task` 는 열린 PR이 미승인일 때 리뷰를 호출하지 않고 "외부 승인 대기" 취지의 no-op 로그만 남기며 상태를 바꾸지 않는다. 같은 상태를 재드레인해도 결과가 같다(멱등).
7. `bash plugins/autopilot/skills/fsd/references/poll.sh selftest` 가 ALL PASS 하고, 그 안에 "PR 미승인 → 전진 없음·상태 불변" 을 확인하는 케이스가 포함된다(기존 리뷰 경로 검증 케이스는 대체된다).
8. `lib-state.sh` 에 `review_round`·`bump_review_round` 함수가 없다.
9. `bash plugins/autopilot/skills/fsd/references/merge.sh selftest` 가 ALL PASS 한다(승인→머지 경로 무손상). `forge.sh` 는 본 task 에서 수정하지 않으므로(조건 13) 통합 경로는 구조적으로 무손상이며, `bash -n plugins/autopilot/skills/fsd/references/forge.sh` 문법 검사가 통과한다(forge.sh 에는 selftest 서브커맨드가 없다 — 신규 추가하지 않는다).
10. `plugins/autopilot/.claude-plugin/plugin.json` 과 `.claude-plugin/marketplace.json` 의 autopilot 설명이 "4-skill family" 이고 review 스킬을 가리키는 절이 없으며, 두 파일의 autopilot version 이 `0.19.0` 이다. 두 파일 모두 `jq .` 로 유효하게 파싱된다.
11. `plugins/autopilot/skills/fsd/SKILL.md`, `plugins/autopilot/skills/using-autopilot/SKILL.md`, `plugins/autopilot/skills/fsd/references/operational-guide.md` 에 내부 리뷰 단계(서브커맨드·파이프라인·상태 필드)를 가리키는 서술이 남지 않는다.
12. `milestones/2026-06-conductor-pipeline` 의 C3 리뷰 피드백 루프가 폐기됨(제거/외부 위임)으로 표시되어 있다.
13. 항상 `rules/review.md`, `rules/change-adoption.md`, `.github/workflows/claude-review.yml`, `.github/workflows/codex-review.yml`, 그리고 `forge.sh` 의 `ST_REVIEW`·`transition_to_review` 는 변경되지 않는다(보존).

## 범위

포함:
- `plugins/autopilot/skills/review/` 및 `review-loop.sh` 삭제
- `fsd.sh`·`poll.sh`·`lib-state.sh` 의 리뷰 배선 제거 및 poll 미승인 분기의 no-op 전환
- `fsd/SKILL.md`·`using-autopilot/SKILL.md`·`operational-guide.md` 서술 갱신
- `plugin.json`·`marketplace.json` 설명·버전 갱신
- 제거 기능을 명세한 docs/specs 2건 삭제
- milestone C3 리뷰 루프 폐기 표시

비-목표 / 제외:
- 외부 CI 리뷰 워크플로(`claude-review.yml`·`codex-review.yml`)와 관련 테스트 변경
- `rules/review.md`·`rules/change-adoption.md` 등 일반 리뷰 지침 변경
- `forge.sh` 의 통합·`Review` 상태 전이 로직 변경
- 깨진 loop→브랜치 이식 등 다른 미구현 영역의 신규 구현
- `merge.sh` 승인 게이트 로직 변경

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약

- 편집 대상은 작업 트리의 실제 코드(autopilot 0.18.1 계열)다. 세션에 로드된 `fsd`·`spec` 스킬 캐시(0.16.1)의 "review 미구현" 서술에 의존하지 않는다.
- `SKILL.md` 편집은 `superpowers:writing-skills` 관례를 따른다.
- 셸 스크립트는 bash 3.2+ 호환을 유지한다.
- 버전 정합: `plugin.json`(단일 출처)과 루트 `marketplace.json`(미러)의 autopilot 버전·설명을 함께 0.19.0 으로 올린다.
- `rules/**` 와 `CLAUDE.md` 는 수정하지 않는다.
- 버전 범프 규율은 `rules/engineering/versioning.md` 를 따른다.

## 위험

- poll 미승인 no-op 전환으로, 외부 승인이 없으면 task 가 `Review` 상태에서 머지까지 진행하지 않고 대기한다 — 이는 의도된 동작(외부 CI/사람 승인 필요)이며 완료 조건 6 이 이를 고정한다.
- dangling 참조가 한 곳이라도 남으면 스킬 로드·셀프테스트가 깨질 수 있다 — 완료 조건 3 의 전역 grep 게이트가 이를 차단한다.
