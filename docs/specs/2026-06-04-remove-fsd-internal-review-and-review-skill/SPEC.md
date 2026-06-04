---
scope:
  include:
    - plugins/autopilot/skills/fsd/**
    - plugins/autopilot/skills/using-autopilot/**
    - plugins/autopilot/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - CLAUDE.md
ears_language: ko
---

# Remove fsd internal review (keep autopilot:review skill)

## 무엇을 만들 것인가

autopilot 플러그인에서 **fsd 차원의 내부 리뷰**(fsd 자체 자동 리뷰·재구현 고리)만 제거한다. `autopilot:review` 스킬과 `dispatch` 통합 모드의 리뷰는 **보존**한다 — 현재 `dispatch --integrate`(기본 활성)의 forge 서브모드가 `autopilot:review` 생산자를 사용하기 때문이다(스킬을 지우면 dispatch가 깨진다).

fsd 파이프라인은 `intake → start → 통합(PR) → [외부 승인] → merge` 로 닫고, fsd가 열린 PR을 미승인 상태로 만나면 자동 재구현 없이 "외부 승인 대기" no-op로 멈춘다(외부 CI/사람이 승인하면 머지 경로로 닫힘).

## 목적 (왜)

fsd의 내부 리뷰 재구현 스텝은 프로덕션 경로에서 끊겨 있었고(loop→브랜치 이식 부재 등), 외부 CI 리뷰가 같은 역할을 독립 수행한다. fsd의 깨진 내부 고리를 들어내 단순화하되, dispatch가 의존하는 리뷰 스킬은 건드리지 않는다(범위 최소화 — main의 dispatch 재설계와 충돌 회피).

## 완료 조건

1. 항상 `plugins/autopilot/skills/fsd/references/review-loop.sh` 파일이 존재하지 않는다(fsd 내부 리뷰 오케스트레이터 제거).
2. 항상 `plugins/autopilot/skills/review/`(autopilot:review 스킬)와 `plugins/autopilot/skills/dispatch/`(dispatch 통합·리뷰)는 **보존**되어 변경되지 않는다.
3. 항상 `plugins/autopilot/skills/fsd/` 와 `plugins/autopilot/skills/using-autopilot/` 아래 어떤 파일에도 `review-loop`, `FSD_REVIEW_CMD`, `POLL_REVIEW_CMD`, `review_round`, `bump_review_round`, `autopilot:review` 문자열이 남지 않는다(dispatch·review 스킬은 이 조건의 대상이 아니다 — 그쪽은 리뷰를 정당하게 사용).
4. `fsd.sh` 에 `review` 서브커맨드 라우팅·`cmd_review` 함수·usage의 `review` 줄·`FSD_REVIEW_CMD` 선언과 환경변수 안내·`cmd_status` 의 `review:` 출력 줄·selftest의 리뷰 위임 검증이 없다.
5. `bash plugins/autopilot/skills/fsd/references/fsd.sh selftest` 가 ALL PASS 한다.
6. `poll.sh` 의 `poll_task` 는 열린 PR이 미승인일 때 리뷰를 호출하지 않고 "외부 승인 대기" 취지의 no-op 로그만 남기며 상태를 바꾸지 않는다(같은 상태 재드레인 멱등).
7. `bash plugins/autopilot/skills/fsd/references/poll.sh selftest` 가 ALL PASS 하고, "PR 미승인 → 전진 없음·상태 불변" 케이스를 포함한다.
8. `fsd/references/lib-state.sh` 에 `review_round`·`bump_review_round` 함수가 없다.
9. `bash plugins/autopilot/skills/fsd/references/merge.sh selftest` 가 ALL PASS 한다. `forge.sh` 는 미수정이며 `bash -n` 문법 검사가 통과한다.
10. `plugins/autopilot/.claude-plugin/plugin.json` 과 `.claude-plugin/marketplace.json` 의 autopilot 설명이 **"5-skill family"**(review 스킬 보존)이고, fsd forge 레이어 괄호에서 `review` 가 빠져 `(intake·start·merge·poll)` 이며, 두 파일의 autopilot version 이 `0.22.0` 이다. 두 파일 모두 `jq .` 로 유효하다.
11. `fsd/SKILL.md`, `using-autopilot/SKILL.md`, `fsd/references/operational-guide.md` 에 fsd 내부 리뷰 단계(서브커맨드·파이프라인·상태 필드)를 가리키는 서술이 남지 않는다.
12. 항상 `dispatch` selftest(`dispatch.sh`·`integration.sh`·`merge.sh`·`lib-integration.sh`)가 ALL PASS 한다(dispatch 무손상 회귀 가드).

## 범위

포함:
- `plugins/autopilot/skills/fsd/references/review-loop.sh` 삭제
- `fsd.sh`·`poll.sh`·`lib-state.sh` 의 리뷰 배선 제거 및 poll 미승인 분기 no-op 전환
- `fsd/SKILL.md`·`using-autopilot/SKILL.md`·`operational-guide.md` 서술 갱신
- `plugin.json`·`marketplace.json` fsd 괄호·버전(0.22.0) 갱신(5-skill 유지)

비-목표 / 제외:
- `autopilot:review` 스킬(`skills/review/`)·`dispatch`(통합·리뷰) 변경 — **보존**
- 외부 CI 리뷰 워크플로·`rules/review.md`·`rules/change-adoption.md` 변경
- `forge.sh` 통합 로직, `merge.sh` 승인 게이트 변경
- 통합 모드 loop→브랜치 이식 등 다른 버그 신규 수정(별도 작업)

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 검증 진입 명령은 프로젝트 규칙(`rules/`)이 단일 출처다.

## 제약

- `SKILL.md` 편집은 `superpowers:writing-skills` 관례를 따른다.
- 셸 스크립트는 bash 3.2+ 호환을 유지한다.
- `plugin.json`(단일 출처)·`marketplace.json`(미러) 버전·설명을 함께 0.22.0 으로 올린다([[dispatch-plugins-version-bump-at-integration]]).
- `rules/**`·`CLAUDE.md` 미수정. 버전 범프는 `rules/engineering/versioning.md` 를 따른다.

## 위험

- poll 미승인 no-op로, 외부 승인이 없으면 task가 대기한다 — 의도된 동작(외부 CI/사람 승인). 완료 조건 6이 고정.
- fsd만 리뷰 제거하고 dispatch는 유지하므로, 리뷰 스킬·dispatch 무손상 회귀 가드(완료 조건 2·12)로 보호한다.
