---
scope:
  include:
    - rules/engineering/branch-and-slug.md
    - rules/orchestration/**
  exclude:
    - milestones/**
    - CLAUDE.md
    - plugins/**
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# Merge approved SPEC to main before proposing implementation

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
이 레포의 프로젝트 규칙(`rules/`)에 **호출측 시퀀스**를 명문화한다: spec 워크플로가 산출하고 사용자가 최종 승인한 SPEC 문서를, 구현(dispatch)을 제안·착수하기 **전에** `main` 브랜치로 커밋·머지하도록 한다.

현재는 spec이 SPEC 문서를 작성한 뒤 그 파일을 커밋하지 않은 채 구현 제안으로 넘어간다. 이 변경은 그 사이에 "승인된 SPEC을 main에 반영" 단계를 강제하는 규칙을 추가한다. spec 스킬과 autopilot 공용 스킬은 건드리지 않으며(spec은 순수 유지), 머지 절차 자체는 새로 정의하지 않고 기존 `rules/engineering/branch-and-slug.md`의 "feat 브랜치 + commit" · "원격 동기화" 절차를 단일 출처로 재사용한다. 이 규칙이 추가하는 것은 그 절차의 **호출 시점(타이밍)과 우선순위**다.

## 완료 조건
<!-- 5문장 패턴과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
1. **항상**: 이 레포의 `rules/` 아래에는 "사용자가 최종 승인한 SPEC을 구현 제안·착수 전에 `main`에 머지한다"는 호출측 시퀀스가 단일 출처로 기술된 규칙 문장이 존재해야 한다. (해당 규칙 파일을 열어 그 시퀀스 문장이 있는지로 확인 가능)
2. **…할 때**: spec 워크플로가 SPEC 문서를 산출하고 사용자가 그 SPEC을 최종 승인할 때, 호출자는 `branch-and-slug.md`의 기존 commit + `main` ff-merge + origin 동기화 절차로 그 SPEC 문서를 `main`에 반영한 **뒤에야** 구현(dispatch)을 제안·착수해야 한다. (관찰: dispatch가 시작되기 전 `git log main`에 해당 SPEC commit이 존재한다)
3. **…인 동안**: SPEC이 아직 최종 승인되지 않은 동안에는 어떤 머지도 일어나지 않아야 한다. 머지의 권한 출처는 step 7의 최종 SPEC 승인 하나이며, 규칙은 별도의 머지 확인 질문을 추가로 요구하지 않아야 한다.
4. **…이면(오류)**: `main`으로의 ff-merge 또는 origin push가 거부되면, 시스템은 force push 없이 중단하고 사용자에게 PR 흐름 전환을 안내해야 한다(기존 `branch-and-slug.md` 실패 처리와 동일하게 동작·참조).
5. **항상**: SPEC에 `[NEEDS CLARIFICATION]` 마커가 남아 있어도 머지는 그대로 수행되어야 한다 — 머지 수행 여부는 마커 유무를 검사하지 않는다. 단, 마커가 남아 있으면 자율 실행(dispatch)은 여전히 차단되며, 규칙은 그 사실과 `--resume` 해결 경로를 안내해야 한다.
6. **항상**: 규칙은 머지 절차(브랜치 생성·SPEC만 commit·ff-merge·push·force 금지·실패 처리)를 중복 기술하지 않고 `rules/engineering/branch-and-slug.md`를 단일 출처로 참조해야 한다.

## 범위
포함:
- `rules/` 아래 SPEC-머지 호출측 시퀀스 규칙의 추가 또는 기존 규칙 확장
- 그 규칙에서 `branch-and-slug.md`의 머지 절차를 단일 출처로 참조
- "머지 전에는 구현(dispatch)을 제안·착수하지 않는다"는 우선순위를, spec 스킬 step 7의 옵트인 자동 핸드오프보다 이 프로젝트 규칙이 우선함을 명시

비-목표 / 제외:
- spec 스킬, using-autopilot, dispatch, loop 등 autopilot 플러그인 공용 스킬 파일(`plugins/**`) 변경 — 이 변경은 이 레포의 `rules/` 범위로 한정한다
- `branch-and-slug.md`의 머지 절차 자체(브랜치·commit·ff-merge·push 단계)의 재정의
- 머지 시점에 마커를 검사하는 로직 추가
- 별도 머지 확인 질문(AskUserQuestion) 추가
- 타 프로젝트(autopilot 설치처 일반)에 자동 머지 동작을 배포하는 것

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- **spec 순수 유지**: spec 스킬과 autopilot 공용 스킬 파일은 수정하지 않는다. 변경은 이 레포 `rules/` 범위로 한정한다.
- **머지 절차 DRY**: feat 브랜치 생성·SPEC 문서만 `git add`(`git add .` 금지)·`main` ff-merge·origin 동기화·force push 금지·실패 시 PR 폴백은 `rules/engineering/branch-and-slug.md`가 단일 출처다. 새 규칙은 이 절차를 참조만 하고 복제하지 않는다.
- **승인 권한 단일화**: step 7 최종 SPEC 승인이 머지 권한의 단일 출처다 — 머지 직전 별도 확인 질문을 추가하지 않는다.
- **마커 무관 머지**: 머지 수행 분기는 `[NEEDS CLARIFICATION]` 마커를 검사하지 않는다.
- **우선순위 명시**: spec step 7의 옵트인 자동 핸드오프(머지 전 dispatch 자동 호출)와 충돌할 경우, 이 프로젝트 규칙이 우선하여 호출자는 머지 전에 dispatch를 착수하지 않는다 — 규칙에 이 우선순위를 명문화한다.
- 규칙 파일 배치는 `rules/engineering/branch-and-slug.md` 확장 또는 `rules/orchestration/` 아래 새 규칙 중 어느 쪽이든 가능하나, 시퀀스(타이밍·우선순위)만 명문화하고 머지 절차는 참조한다.

## 위험
- 마커가 남은 미완성 SPEC도 `main`에 머지되므로, `main` 히스토리에 미완성 SPEC commit이 남는다(사용자가 명시적으로 선택). 이후 `--resume`으로 마커를 해결한 commit이 별도로 `main`에 반영되어야 한다.
- branch 보호로 `main` 직접 push가 막힌 환경에서는 ff-merge push가 거부되어 PR 폴백으로 전환된다(기존 절차) — 이 경우 "머지 후 구현 제안" 흐름이 PR 머지 완료까지 지연될 수 있다.
- spec step 7의 옵트인 자동 핸드오프가 머지보다 먼저 실행되면 규칙의 의도가 깨진다 — 규칙의 우선순위 명시(제약 5)로 방어하나, 호출자가 그 우선순위를 따르는지에 의존한다.
