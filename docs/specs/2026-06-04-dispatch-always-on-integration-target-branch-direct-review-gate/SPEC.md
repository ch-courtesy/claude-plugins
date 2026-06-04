---
scope:
  include:
    - plugins/autopilot/skills/dispatch/**
    - plugins/autopilot/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# dispatch always-on integration, target branch, direct review gate

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

`autopilot:dispatch`의 통합(리뷰·머지) 모드에 세 가지 변경을 가한다.

1. **통합 상시화** — 통합 모드를 켜고 끄는 토글을 없애고 통합을 항상 적용한다. `dispatch start`는 별도 플래그 없이 항상 통합(리뷰·머지) 모드로 시작하며, "구현만 하고 머지하지 않는" 비통합(레거시) 동작 경로를 제거한다. 기존에 받던 `--no-integrate`·`--integrate` 플래그는 하위 호환을 위해 받아들이되 아무 효과 없이 조용히 무시한다.

2. **머지 타겟 브랜치 일반화** — 머지·동기화 대상 브랜치가 `main`에 고정되지 않고 호출 시 지정할 수 있게 한다. `dispatch start`에 대상 브랜치를 지정하는 새 옵션을 추가하고, 지정하지 않으면 기본 브랜치를 대상으로 삼는다. 지정한 대상 브랜치는 그 run의 모든 base 동기화·승인 요청 base·fast-forward 머지·base push에 일관되게 적용되며, run 동안(재개 포함) 유지된다.

3. **direct 서브모드 적대적 리뷰 게이트** — forge가 구성되지 않은 환경(direct 서브모드)에서도 머지 직전에 적대적 리뷰를 한 단계 거치게 한다. 지금까지 direct 경로는 리뷰 없이 곧바로 직접 머지했으나, 변경 후에는 구현 완료(loop DONE) 결과를 머지하기 전에 리뷰 생산자(`autopilot:review`)로 적대적 리뷰를 받고, 그 판정이 통과(approve)일 때만 머지한다. 리뷰가 변경 요구(request_changes)를 내면 forge 서브모드와 동일한 리뷰 루프(변경 요구분 재구현 → 재리뷰)를 거친다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->

머지 대상이 항상 `main`은 아니므로 대상 브랜치를 일반화해 release 브랜치·통합 브랜치 등 다른 베이스로도 dispatch를 운용할 수 있게 한다. 통합은 이제 dispatch의 단일 동작이므로 토글을 없애 분기와 레거시 경로의 유지 비용을 제거한다. direct 서브모드에 적대적 리뷰를 넣어, forge가 없는 환경에서도 "리뷰 없이 머지"의 품질 공백을 메운다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. 항상 `dispatch start`는 별도 플래그 없이 통합(리뷰·머지) 모드로 시작한다.
2. `--no-integrate` 또는 `--integrate` 플래그를 받을 때, dispatch는 그 플래그를 아무 효과 없이 받아들이고(오류 없이) 통합 모드로 동작한다.
3. 비통합(레거시) 경로 — loop DONE을 곧바로 `done`으로 전이시키고 `NO_INTEGRATE` 마커로 통합을 끄는 분기 — 는 코드·self-test에서 더 이상 존재하지 않는다.
4. `dispatch start`에 대상 브랜치 지정 옵션을 줄 때, 그 run의 모든 base 동기화·승인 요청(PR) base·fast-forward 머지·base push가 지정한 브랜치를 대상으로 수행된다.
5. 대상 브랜치 지정 옵션을 주지 않을 때, 대상은 기본 브랜치(`main`, 또는 주입된 기본 브랜치 값)이며 기존과 동일하게 동작한다.
6. `--resume`로 재개하는 동안, 최초 시작 때 결정된 대상 브랜치와 서브모드(forge/direct)가 보존되어 현재 환경·플래그 값보다 우선 적용된다.
7. forge가 구성되지 않은(direct) 환경에서 한 SPEC의 구현이 완료(loop DONE)될 때, 머지 직전에 적대적 리뷰(`autopilot:review`)를 거치며, 리뷰가 approve를 낼 때만 그 SPEC을 fast-forward 머지하고 `done`(=머지됨)으로 전이한다.
8. direct 서브모드 리뷰가 변경 요구(request_changes)를 낼 때, forge 서브모드와 동일한 리뷰 루프(변경 요구분을 SPEC 델타로 재구현 → 같은 작업 브랜치 위 재리뷰)를 수행하고, 동일한 세 가드(라운드 상한·무진전·핑퐁) 안에서만 반복한다.
9. direct 서브모드 리뷰·재구현이 진행되는 동안, 승인 요청(PR) 생성이나 원격 push 없이 로컬 작업 브랜치의 diff만으로 리뷰가 수행된다.
10. direct 서브모드 리뷰 루프가 세 가드 중 하나에 걸려 approve 없이 종료되면(오류 조건), 그 SPEC을 머지하지 않고 비완료(blocked/escalated)로 기록하며 그 **이행적 의존자만** `skipped` 처리한다.
11. 머지될 변경이 버전 워치 디렉토리(`plugins/**`)를 건드리는데 패키지 매니페스트 버전 범프가 없으면(오류 조건), forge·direct 어느 경로에서도 머지를 차단하고 차단 사실을 기록한다.
12. 항상 모든 머지·동기화 경로는 fast-forward 전용 머지만 사용하고 force(강제) push·history 재작성 rebase push를 어떤 경로(forge·direct)에서도 쓰지 않는다.
13. dispatch 스킬의 단위 self-test(스케줄러·통합·리뷰·머지 모듈)가 모두 통과(exit 0)하며, 위 분기(통합 상시 켜짐·플래그 no-op, 대상 브랜치 일반화·기본값, 재개 sticky, direct 리뷰 게이트의 approve/request_changes/가드-소진, 버전 게이트 차단, force 미사용)를 mock 인터페이스로 검증한다.
14. dispatch `SKILL.md`가 위 동작(통합 상시화, 대상 브랜치 지정 옵션, direct 리뷰 게이트)을 반영하고, `--no-integrate` 레거시 모드 서술과 "direct 서브모드는 리뷰를 우회한다 / 적대적 리뷰는 후속 작업" 서술을 제거한다.

## 범위
포함:
- `plugins/autopilot/skills/dispatch` 전체 — 스킬 정의(`SKILL.md`)와 `references/`의 셸 모듈(`dispatch.sh`, `integration.sh`, `review-loop.sh`, `merge.sh`, `lib-integration.sh`).
- 패키지 매니페스트(`plugins/autopilot/.claude-plugin/plugin.json`)와 루트 `.claude-plugin/marketplace.json` 미러의 버전 범프.

비-목표 / 제외:
- forge 서브모드의 기존 리뷰 루프·통합·머지 로직 변경(direct 경로가 재사용할 뿐 forge 동작 자체는 불변).
- 리뷰 생산자(`autopilot:review`) 스킬 자체의 판정 로직 변경.
- `fsd`·`loop`·`spec` 등 dispatch 외 다른 스킬 수정.
- `rules/`·`CLAUDE.md`·`milestones/` 변경.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 대상 브랜치 지정은 run-dir 마커로 영속화해 재개 시 sticky하게 유지하며, 기존 `DEFAULT_BRANCH` 주입 경로와 양립한다(재개 시 마커가 환경·플래그보다 우선). 현재 `main`을 하드코딩한 모든 사용처(usage 문자열 포함)를 대상 브랜치 값으로 일원화한다.
- direct 서브모드 리뷰는 forge 의존성(forge CLI·PR) 없이 동작해야 한다 — 기존 forge 리뷰 루프 기계(리뷰 생산자 호출·변경 요구분 재구현·세 가드)를 PR 없는 로컬 작업 브랜치 리뷰로 재사용하되, PR 상태 조회·원격 push를 전제하지 않는다.
- 모든 외부 인터페이스(`LOOP_CMD`·`GIT_CMD`·`FORGE_CMD`·`FORGE_BIN`·`DEFAULT_BRANCH`·`APPROVER`·`REVIEW_BOT`·`APPROVE_CMD`·`REVIEW_ROUNDS_MAX`·`WATCH_DIRS`·`REVIEW_PRODUCE_CMD`·`INTEGRATION_CMD`·`REVIEW_CMD`·`MERGE_CMD` 등)는 주입 가능하게 유지해 각 모듈을 mock으로 독립 검증한다(실제 PR·머지·push 미수행).
- 머지는 `git merge --ff-only`만 사용하고, 어떤 경로에서도 force push·history 재작성을 쓰지 않는다. 기본 브랜치 체크아웃+머지 구간은 run-dir 락으로 직렬화한다.
- 셸 모듈은 bash 3.2+ 호환으로 유지한다.
- 버전 범프: 현재 `0.23.0` 기준 다음 MINOR(`0.24.0`). 레거시 비통합 동작 제거는 동작 변경(호환 깨짐)이나 pre-1.0(`0.y.z`)이므로 MINOR 증가로 수용한다. `plugin.json`(SoT)과 루트 `marketplace.json` 미러를 함께 올린다. 동시 변경과 버전 충돌 시 최종 번호는 통합자가 조정한다.

## 위험 (있을 때만)
- direct 리뷰에서 PR이 없으므로, 기존 리뷰 루프가 가정하던 PR 리뷰 상태 조회·브랜치 원격 push가 그대로 동작하지 않을 수 있다 → 로컬 diff 리뷰·push 생략 경로로 분리해 흡수한다.
- 통합 상시화로 `--no-integrate`에 의존하던 기존 호출·self-test가 깨질 수 있다 → 해당 분기·검증·문서를 같은 변경에서 함께 정리한다.
- 대상 브랜치 일반화가 일부 사용처만 덮으면 `main`이 잔존해 경로마다 대상이 갈리는 누수가 생긴다 → 모든 사용처를 대상 브랜치 단일 출처로 모은다.
