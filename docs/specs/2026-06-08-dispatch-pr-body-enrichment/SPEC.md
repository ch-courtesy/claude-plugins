---
scope:
  include:
    - plugins/autopilot/skills/dispatch/references/integration.sh
    - plugins/autopilot/.claude-plugin/plugin.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "grep -q 'in_pr_body' plugins/autopilot/skills/dispatch/references/integration.sh && ! grep -q 'dispatch 통합: 구현 완료, 승인 요청.' plugins/autopilot/skills/dispatch/references/integration.sh && grep -q 'body-file' plugins/autopilot/skills/dispatch/references/integration.sh && bash plugins/autopilot/skills/dispatch/references/integration.sh selftest"
ears_language: ko
---

# dispatch PR 본문 구조화

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
dispatch 가 forge 서브모드에서 새 PR 을 생성할 때 채우는 **PR 본문**을, 모든 PR 에 동일하게 들어가던
정적 한 줄에서 그 SPEC 을 식별·추적할 수 있는 **구조화된 본문**으로 바꾼다. 구조화 본문은 어떤 SPEC 에서
나온 PR 인지(추적성), 그 SPEC 이 무엇을 만드는지(요약), 어느 dispatch 실행에서 통합되는지(실행 컨텍스트)를
담는다. SPEC 에 이슈 식별 정보가 있으면 그 이슈로의 cross-reference 도 본문에 포함한다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->
정적 한 줄 본문은 PR 마다 동일해 어떤 SPEC·실행에서 나왔는지 식별할 수 없고, 통합 이력을 훑을 때
변별력이 없으며, "PR description 에 이슈 cross-reference 를 포함한다"는 프로젝트 규칙도 충족하지 못한다.
PR 본문이 SPEC 추적성·요약·실행 컨텍스트를 담으면 사람이 PR·머지 이력만으로 변경의 출처와 내용을
재구성할 수 있다.

## 완료 조건
<!-- 5문장 패턴. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. dispatch 가 새 PR 을 생성할 때, 시스템은 그 PR 본문에 통합 대상 **SPEC 의 경로를 식별 가능한 형태로**
   포함해야 한다.
2. 통합 대상 SPEC 에 "무엇을 만들 것인가" 의도 요약 섹션이 있을 때, 시스템은 그 **섹션 본문 전체를**
   설명용 주석을 제거한 채 PR 본문의 요약으로 포함해야 한다.
3. 통합 대상 SPEC 에 그 요약 섹션이 없는 동안, 시스템은 요약 블록을 **생략하고도** 나머지 본문을
   정상 생성해야 한다.
4. dispatch 가 새 PR 을 생성할 때, 시스템은 그 PR 본문에 해당 **dispatch 실행 식별자(run-id)** 를
   포함해 어느 실행에서 통합되는지 드러내야 한다.
5. 통합 대상 SPEC 에 이슈 식별 정보가 있을 때, 시스템은 PR 본문에 그 이슈로의 **cross-reference 한 줄**을
   포함해야 한다. 이슈 식별 정보가 없는 동안, 시스템은 cross-reference 줄을 **생성하지 않아야** 한다.
6. PR 본문에 여러 줄(요약 섹션 포함)이 들어갈 때, 시스템은 그 본문을 **줄바꿈이 보존되는 방식으로**
   forge 에 전달해야 한다.
7. 같은 작업 브랜치에 이미 열린 PR 이 있으면, 시스템은 새 PR 을 생성하지 않고 기존 PR 을 **재사용**해야
   한다(본문 변경이 재사용 동작을 깨지 않는다).
8. PR 본문 구성 로직이 바뀌면, 시스템의 **selftest 가 본문에 SPEC 경로·요약·실행 식별자가 포함되고
   정적 한 줄 본문이 남아 있지 않음을 검증**해야 한다(실제 PR·머지 미수행, mock 인터페이스로).
9. 이 변경이 `plugins/` 아래 파일을 수정하면, 같은 변경 안에서 **패키지 매니페스트 버전이 SemVer
   PATCH 로 올라가야** 한다.

## 범위
포함:
- forge 서브모드의 PR 생성 본문(생성 경로 한 곳)과 그 본문을 구성하는 결정적 헬퍼.
- 본문 구성 로직을 검증하는 selftest 확장.
- 버전 단일 출처(패키지 매니페스트) PATCH 범프.

비-목표 / 제외:
- direct 서브모드(PR 미생성)는 본문 개념이 없어 무관.
- SPEC frontmatter 에 이슈 필드를 **새로 도입**하거나 spec 작성 스킬에 이슈를 스레딩하는 작업은 제외
  — 이슈 cross-reference 는 이슈 식별 정보가 SPEC 에 존재할 때만 채워지는 forward-compatible 처리로 둔다.
- PR 제목 형식 변경(이미 SPEC 제목에서 파생) 제외.
- 생성 이후 PR 본문을 갱신·재작성하는 동작 제외.

## 검증
이 SPEC 의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다.
검증을 실행하는 진입 명령은 SPEC 이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의하며, 본 변경의
결정적 부분은 해당 헬퍼의 `selftest`(mock forge·git 인터페이스, 실제 PR·머지 미수행)로 독립 검증된다.

## 제약 (있을 때만)
- 본문을 forge 에 넘길 때 셸 인용·줄바꿈 손상이 없어야 한다(멀티라인 안전 전달).
- 기존 PR 재사용 분기·force 미사용 등 기존 통합 불변식을 깨지 않는다.
- 요약 섹션 추출은 SPEC 작성 도구·형식에 과결합하지 않는다 — 섹션 헤더가 없거나 비면 요약을 생략하고
  나머지 본문은 정상 생성한다.
