---
scope:
  include:
    - plugins/autopilot/skills/dispatch/**
    - plugins/autopilot/agents/**
    - plugins/autopilot/.claude-plugin/plugin.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko (default)
---

# dispatch worker contract enforcement and forge review gating

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 파일·스크립트·도구명은 제약으로. -->
dispatch가 준비된 SPEC마다 띄우는 per-SPEC 워커가 **안전 절차를 구조적으로 강제**받도록 만든다.

1. 워커는 **전용 서브에이전트 타입**으로 띄워지며, 그 타입의 정의 자체가 절차 계약을 담는다 — 워커는 구현을
   **반드시 격리 구현 스킬(loop)을 통해서만** 수행하고(직접 파일 편집·임의 git 분기/커밋·구현 스크립트 직접
   구동 금지), 통합·리뷰·머지는 **반드시 제공된 결정적 헬퍼를 구동**해 수행한다(원격 PR 생성/머지·푸시·force
   조작을 직접 raw 명령으로 하지 않는다).
2. **리뷰·승인 경로가 백엔드 가용성으로 갈린다**: forge 백엔드(원격 호스팅 CLI)가 있으면 **로컬 리뷰 스킬을
   호출하지 않고** 변경 제안(PR)에 대한 **호스팅측 리뷰의 승인(approved) 판정을 머지 게이트**로 삼는다.
   forge 백엔드가 없으면(direct) 종전대로 로컬 리뷰 스킬의 판정을 게이트로 삼는다.
3. 두 경로 모두 **승인 이후에만** 대상 브랜치로 fast-forward 머지하고, 어떤 경로에서도 force(push·merge·
   rebase)를 쓰지 않는다(안전 불변식 보존·강화).

## 목적 (왜)
재현 실험에서 워커가 격리 구현 스킬과 결정적 헬퍼를 모두 우회하고 raw git/원격 명령으로 직접 처리해,
격리 워크트리 미생성·승인 전 머지·force push가 동시에 발생했다. 절차를 **프로즈 권고가 아니라 워커 정의로
강제**하고 리뷰 게이트를 백엔드에 맞게 정렬해, 이런 위반이 구조적으로 일어나지 않게 하는 것이 목적이다.

## 완료 조건
<!-- 5문장 패턴. 각 조건 관찰 가능·독립 검증 가능. -->
- **항상**: dispatch는 준비된 SPEC마다 워커를 **전용 워커 서브에이전트 타입**으로 띄워야 한다(범용 에이전트로 띄우지 않는다).
- **항상**: 워커의 구현 단계는 **격리 구현 스킬(loop) 호출로만** 이뤄져야 한다 — 워커가 대상 파일을 직접 편집하거나
  임의 작업 브랜치를 직접 만들어 구현하면 안 된다(구현 산출물은 격리 워크트리 안에서 생성된다).
- **항상**: 워커의 통합·리뷰·머지 단계는 **제공된 결정적 헬퍼를 구동**해 수행돼야 한다 — 워커가 원격 PR 생성/머지·
  브랜치 푸시를 raw 명령으로 직접 수행하면 안 된다.
- **forge 백엔드가 있으면**: 워커는 **로컬 리뷰 스킬을 호출하지 않아야** 하고, 머지는 변경 제안(PR)에 대한
  **호스팅측 리뷰가 승인(approved)된 뒤에만** 일어나야 한다.
- **forge 백엔드가 없으면(direct)**: 워커는 로컬 리뷰 스킬의 판정으로 리뷰하고, 그 판정이 승인일 때만 머지해야 한다.
- **머지할 때**: 승인 **이후에만** 대상 브랜치로 fast-forward 전용 머지를 하고, 어떤 경로에서도 force
  (push·merge·rebase)를 쓰지 않아야 한다.
- **워커가 끝날 때**: 자기 SPEC을 식별 가능한 형태로 구조화 결과(머지됨/비완료)를 보고해야 한다.
- **승인이 없으면(오류)**: 머지하지 않고 비완료로 에스컬레이션해야 한다(거짓 green 금지).
- **항상**: 위 동작이 결정적 헬퍼의 self-test로 검증돼야 한다 — forge 경로가 호스팅 승인 없이는 머지하지 않음,
  forge 경로가 로컬 리뷰 스킬을 호출하지 않음을 포함한다.

## 범위
포함:
- per-SPEC 워커를 강제하는 **전용 워커 서브에이전트 타입 정의** 신설.
- dispatch가 워커를 그 타입으로 띄우도록 위임 절차 명시(전달 보장).
- 워커 절차 계약 문서를 위 강제·게이트에 맞게 갱신.
- forge 리뷰 게이트(호스팅 승인) 도입 — 리뷰 반복·머지 결정적 헬퍼 수정.
- 관련 self-test 추가·갱신, 버전 범프.

비-목표 / 제외:
- 되돌린 fan-out 백그라운드 드라이버 기능(#350)의 재구현 — 별도 후속.
- direct(no-forge) 리뷰 경로의 동작 변경(현행 유지).
- `loop`·`review` 스킬 내부 구현 변경.
- `rules/`·`milestones/`·`CLAUDE.md` 변경.

## 검증
<!-- 검증 기준 단일 출처 = 위 완료 조건. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을
실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 변경 범위는 autopilot **dispatch 스킬**(`plugins/autopilot/skills/dispatch/**`), 신규 **에이전트 정의**
  (`plugins/autopilot/agents/**`), 플러그인 매니페스트(`plugins/autopilot/.claude-plugin/plugin.json`)에 한정.
- 전용 워커 타입은 플러그인 agent 규약(`<plugin>/agents/<name>.md`, frontmatter `name/description/model`
  + 시스템 프롬프트 본문)으로 신설하고, dispatch는 Agent 도구의 `agentType`으로 이 타입을 지정해 spawn한다.
- 격리 구현 스킬 = `autopilot:loop`(전용 `<spec_dir>/.worktree` 소유). 결정적 헬퍼 =
  `references/integration.sh`(`integrate`/`integrate-direct`)·`references/review-loop.sh`(`run`/`run-direct`)·
  `references/merge.sh`(`finish`). 워커는 이들을 구동하고 raw `gh pr create/merge`·`git push`·force를 쓰지 않는다.
- forge 게이트: `review-loop.sh` forge 경로에서 로컬 리뷰 생산(`REVIEW_PRODUCE_CMD`) 호출을 제거하고,
  PR 리뷰 조회(`REVIEW_FETCH_CMD`)의 승인(approved) 판정으로 승인 phase 전이. `merge.sh` forge 경로는 머지
  직전 PR 승인(`reviewDecision==APPROVED`)을 재확인하는 게이트를 둔다. 결정적 헬퍼는 주입 가능 인터페이스로
  mock self-test 가능해야 한다(실제 PR·머지 미수행).
- 워커 계약 단일 출처는 `references/spec-subagent.md`이며, 신설 워커 타입 정의와 일관되게 갱신한다.
- 기존 헬퍼 self-test(force 거부 가드 포함)는 계속 통과해야 한다.

## 위험
- **타입 강제의 실효성**: 워커 타입 시스템 프롬프트가 강제력을 가지려면 dispatch가 실제로 그 `agentType`으로
  띄워야 한다 — 위임 절차 누락 시 강제가 무력화. 위임 명시 + self-test로 완화.
- **forge 승인 주체**: forge 경로가 로컬 리뷰를 제거하므로, PR의 호스팅측 적대 리뷰(봇/외부 리뷰어)가 실제로
  승인을 생산해야 머지가 진행된다 — 승인 소스 부재 시 머지 불가(에스컬레이션). 환경 가정 명시 필요.
- **direct/forge 일관성**: 두 경로의 안전 불변식(승인 후 머지·force 금지·ff-only)이 동일하게 성립해야 함.
