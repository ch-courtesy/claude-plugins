---
scope:
  include:
    - plugins/autopilot/skills/conductor/references/merge.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
depends_on: ["conductor-done-to-push-pr-integration"]
verify: "bash -c 'set -e; F=plugins/autopilot/skills/conductor/references/merge.sh; test -f \"$F\"; bash -n \"$F\"; grep -qiE \"approv\" \"$F\"; grep -qE \"plugins/|plugin.json\" \"$F\"; grep -qiE \"version|범프|bump\" \"$F\"; grep -qE -- \"--ff-only|ff-only|fast-forward\" \"$F\"; grep -q \"Done\" \"$F\"; grep -q \"cleanup\" \"$F\"; ! grep -q -- \"--force\" \"$F\"'"
ears_language: ko
---

# conductor 머지 + Done + cleanup

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

승인된 승인 요청을 검증 게이트를 거쳐 머지하고, task를 완료 상태로 전이하며, 자율 실행기의 작업 공간을 정리하는 모듈을 만든다. 이 모듈이 파이프라인의 종착("승인되면 머지되고 task는 완료 상태가 된다")을 닫는다.

본 모듈이 수행하는 것:

- **승인 확인**: 승인 요청에 승인 권한 신원(별도 approver 봇/PAT)의 "승인됨" 정식 리뷰가 있는지 확인한다. 이 승인됨이 완료 전이의 명시적 신호 역할을 한다. (자동 리뷰 봇 토큰은 자기 PR을 스스로 승인하지 못하므로, 승인은 분리된 승인 권한 신원이 수행한다.)
- **버전 범프 게이트(필수)**: 머지 직전, 머지될 변경이 버전 관리 워치 디렉토리(`plugins/**`)를 건드리는지 확인한다. 건드린다면 같은 승인 요청 안에서 해당 패키지 매니페스트(`plugin.json`)의 버전이 올랐는지 단언한다. 오르지 않았으면 머지를 차단하고 차단 기록을 남긴다. 무인 자동 머지가 가장 무거운 규칙(버전 관리)을 조용히 위반하지 않도록 한다.
- **머지**: 기본 브랜치에 fast-forward 전용(ff-only)으로 머지한다. 머지 커밋을 만들지 않으며 force는 쓰지 않는다.
- **완료·정리**: 머지가 확인되면 task를 완료(`Done`) 상태로 전이하고, 자율 실행기의 작업 공간 정리를 그 공개 정리 인터페이스로 위임하며, 완료 기록을 남긴다.

이 모듈은 C2의 forge 통합(승인 요청 조회·브랜치)을 차용하고, task 상태 전이는 공개 함수 계약으로 호출한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

1. 시스템은 `plugins/autopilot/skills/conductor/references/merge.sh`를 제공하며, 그 파일은 `bash -n` 문법 검사를 통과한다.
2. If 승인 요청에 승인 권한 신원의 "승인됨" 정식 리뷰가 없으면, 시스템은 머지하지 않는다.
3. While 머지될 변경이 버전 워치 디렉토리(`plugins/**`)를 건드리는 동안, 시스템은 같은 승인 요청에서 패키지 매니페스트 버전이 오르지 않았으면 머지를 차단한다.
4. When 승인·버전 게이트를 통과해 머지하면, 시스템은 fast-forward 전용으로 머지하고 머지 커밋을 만들지 않는다.
5. When 머지가 확인되면, 시스템은 해당 task를 완료(`Done`) 상태로 전이한다.
6. When 머지가 확인되면, 시스템은 자율 실행기의 작업 공간 정리를 그 공개 정리 인터페이스로 위임한다.
7. 시스템은 어떤 머지·push에서도 force(강제) 옵션을 사용하지 않는다.

## 범위
포함:
- `plugins/autopilot/skills/conductor/references/merge.sh` — 승인 권한 신원 승인 확인 + 버전 범프 게이트(`plugins/**`→`plugin.json` 범프 강제) + ff-only 머지 + Done 전이 + 작업 공간 정리 위임

비-목표 / 제외:
- conductor SKILL.md 수정 — C0 단독 소유
- task 상태 전이 정의 — C1 제공(호출만)
- 승인 요청 조회·브랜치 헬퍼 정의 — C2 제공(호출만)
- 리뷰 피드백 루프 — C3 담당
- poll 드레인 — C5 담당
- `plugin.json` 실제 버전 범프 수행 — 본 단위는 범프 여부를 **게이트로 검사**할 뿐, 매니페스트 자체를 수정하지 않는다(범프 수행은 머지 오케스트레이션/사람 책임)
- `rules/` 변경 — `versioning.md`·`branch-and-slug.md`의 실행자
- 자율 실행기·dispatch 코드 변경 — 공개 인터페이스만 소비

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 사용자 확정 결정: **머지 전면 무인.** 자동 리뷰 봇의 self-approve 제약은 별도 approver 봇/PAT로 우회하고, 그 "승인됨"을 완료 전이의 명시적 신호로 본다.
- 머지·버전 게이트는 단일 출처 규칙의 실행자로서 따른다: `rules/engineering/versioning.md`(워치 디렉토리·머지 시 범프 강제), `rules/engineering/branch-and-slug.md`(ff-only 머지·원격 동기화·force 금지).
- 머지는 ff-only, force 금지. 작업 공간 정리는 자율 실행기의 공개 정리 인터페이스(`loop.sh cleanup`)로 위임한다.
- 본 단위는 C2에 의존한다(`depends_on`). task 전이는 C1의 공개 함수 계약으로 호출한다(런타임 의존, 같은 스킬 모듈군).
- `feedback_no_self_apply_during_spec`: 본 SPEC 구현 호출 중 contract 선행 적용 금지.

## 위험
- **무인 머지의 규칙 위반**: 버전 범프 누락이 가장 무거운 규칙을 위반할 위험. 범프 게이트가 `plugins/**` 변경 시 매니페스트 범프를 강제하고 없으면 머지를 차단한다.
- **self-approve 신원 혼동**: 승인이 자동 리뷰 봇 자신이면 무효다. 승인 확인은 분리된 승인 권한 신원의 "승인됨"만 인정한다.
- **self-referential**: `feedback_self_referential_verification`에 따라 검증은 verify·worktree source만 보고 runtime artifact(실제 머지·PR)를 직접 검사하지 않는다. 머지·게이트 동작은 mock으로 검증한다.
