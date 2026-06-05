---
scope:
  include: ["plugins/autopilot/skills/fsd/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# fsd merges SPEC to target branch before dispatch

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
`fsd start`가 SPEC을 구현 오케스트레이터(`dispatch`)에 위임하기 **직전에**, 입력 SPEC 문서(들)가 task의 **타겟 통합 브랜치**(레포 기본 브랜치)에 fast-forward로 머지되어 있도록 보장하는 단계를 fsd에 추가한다. 자연어 의도로 진입해 fsd가 spec을 실행해 SPEC을 새로 생성한 경우든, 이미 만들어진 SPEC 경로로 직접 intake한 경우든, `start`를 거치는 모든 경우에 동일하게 적용된다. 이미 타겟 브랜치에 같은 내용이 올라가 있으면 다시 만들지 않고 통과하는 멱등 동작이다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->
fsd 자동 파이프라인이 SPEC을 떠서 곧바로 구현을 위임하면 "그 SPEC이 어떤 의도로 통과됐는지"가 통합 브랜치 이력에 남지 않아, 구현후 통합 PR에서 의도(SPEC)와 구현이 한 덩어리로 엉켜 선반영을 빠뜨리기 쉽다. dispatch 착수 전에 SPEC을 타겟 브랜치에 먼저 안착시켜, 의도가 구현과 분리된 별도 머지로 항상 이력에 남도록 보장한다.

## 완료 조건
<!-- 5문장 패턴. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- **항상**, `fsd start`는 입력 SPEC 문서(들)를 `dispatch`에 위임하기 전에 그 SPEC 문서(들)가 타겟 통합 브랜치에 머지되어 있도록 보장한다 — dispatch 위임이 시작되는 시점에 타겟 브랜치의 git 이력에 해당 SPEC 문서 commit이 존재한다.
- **항상**, 타겟 통합 브랜치는 리터럴 `main`으로 하드코딩하지 않고 레포의 기본 통합 브랜치를 감지해 결정한다 — 기본 브랜치가 `main`이 아닌 레포에서도 그 기본 브랜치에 SPEC이 안착한다.
- 입력 SPEC이 이미 타겟 브랜치에 같은 내용으로 올라가 있을 때, 머지 단계는 새 commit을 만들지 않고 통과하며 같은 SPEC으로 `start`를 재실행해도 중복 SPEC commit이 생기지 않는다(멱등).
- 입력 SPEC 중 하나라도 미해결 `[NEEDS CLARIFICATION` 마커를 포함하면, SPEC을 타겟 브랜치에 올리지도 dispatch에 위임하지도 않고 기존 미해결-마커 가드대로 `state=needs-clarification`으로 차단한다 — 미완 SPEC은 타겟 브랜치 이력에 남지 않는다.
- SPEC을 타겟 브랜치에 fast-forward 머지하거나 원격에 반영하지 못하면(비-fast-forward·push 거부 등 **오류**이면), `start`는 `dispatch` 위임을 시작하지 않고 중단하며, SPEC이 타겟 브랜치에 안착하지 못했음과 PR 흐름·재시도 안내를 출력하고, 어떤 경우에도 force push를 하지 않는다.
- **항상**, 이 변경 후에도 `spec` 스킬 정의 파일은 수정되지 않는다 — SPEC을 브랜치에 반영하는 책임은 fsd(오케스트레이터)에만 있고 spec은 SPEC 문서만 산출하는 불변식이 보존된다.

## 범위
포함:
- `fsd start` 경로(자연어 의도 진입·직접 SPEC 경로 intake 두 경우 모두)에 dispatch 위임 직전의 SPEC-to-target-branch ff-merge 전제조건 추가.
- 타겟(기본 통합) 브랜치 감지 로직.
- fsd 동작 문서(SKILL.md)에 이 전제조건과 실패 시 차단 동작 반영.
- fsd selftest로 새 전제조건(머지 성공·멱등 통과·마커 차단·머지 실패 시 dispatch 미시작)을 검증.

비-목표 / 제외:
- `spec` 스킬 정의 파일 수정 — 절대 변경하지 않는다(외부 상태 무생성 불변식 보존).
- `rules/` 하위 지침(예: `branch-and-slug.md`) 수정 — fsd는 기존 ff-merge 절차를 단일 출처로 **소비**만 한다.
- 구현 완료 후 작업 브랜치를 통합하는 PR·머지 단계(`merge`/C4, `forge` 통합) 변경 — SPEC 선반영과 구현후 통합은 별개의 두 머지이며 후자는 건드리지 않는다.
- `review`·`poll` 핸들러의 의미 변경, 새 forge backend 도입.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- SPEC을 타겟 브랜치에 반영하는 절차는 `rules/engineering/branch-and-slug.md`의 "feat 브랜치 + commit" · "원격 동기화" 절차를 **단일 출처로 따른다** — 그 절차를 fsd 안에 중복 재정의하지 않고, 감지된 타겟(기본) 브랜치를 대상으로 적용한다(절차 문서의 리터럴 `main`은 기본 브랜치의 예시로 해석한다).
- 미해결 마커 가드가 SPEC-to-target 머지보다 **먼저** 실행된다 — 마커를 가진 SPEC은 타겟 브랜치에 올라가지 않는다.
- force push 금지. 충돌·push 거부 시 중단하고 PR 흐름·재시도를 안내한다(`no-force-push` 규칙).
- fsd 불변식 유지: forge CLI(`gh` 등)를 직접 호출하지 않고 `git`만 사용한다. `.fsd/` 밖의 파일 경로를 만들지 않는다(git 이력 생성은 파일 경로 생성이 아니다).
- 라우터·헬퍼는 bash 3.2+ 호환으로 작성한다.

## 위험
- branch-and-slug 절차의 리터럴 `main`과 감지된 타겟 브랜치 사이의 드리프트 — fsd가 감지 브랜치로 절차를 적용하되 단일 출처 절차의 형태(feat 브랜치 경유·ff-only·force 금지)를 벗어나지 않도록 한다.
- `start`가 이제 원격(fetch/push)을 건드리므로 네트워크·권한 실패가 dispatch 차단으로 이어질 수 있다 — 전제조건이므로 의도된 동작이나, SPEC 미안착 실패와 dispatch 실패를 메시지로 분명히 구분한다.
- 멱등성 회귀 — 같은 SPEC 재-start 시 이미 안착한 SPEC을 중복 commit하지 않도록, 내용 동일성으로 no-op을 판정한다.
