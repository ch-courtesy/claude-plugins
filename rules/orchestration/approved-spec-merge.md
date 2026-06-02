# 승인된 SPEC을 main에 반영한 뒤 구현을 제안한다

사용자가 최종 승인한 SPEC 문서를, 구현(`autopilot:dispatch`)을 **제안·착수하기 전에** `main` 브랜치로 commit·ff-merge·동기화하는 **호출측 시퀀스(타이밍·우선순위)**의 단일 출처입니다.

이 규칙은 머지 *절차*를 새로 정의하지 않습니다. 브랜치 생성·SPEC 문서만 commit·`main` ff-merge·origin 동기화·force push 금지·실패 처리의 단일 출처는 `rules/engineering/branch-and-slug.md`(`feat 브랜치 + commit`·`원격 동기화` 절)이며, 본 규칙은 그 절차의 **호출 시점**만 고정합니다.

(이 머지는 SPEC 문서를 구현 *전에* `main`에 반영하는 것입니다. 구현 *완료 후* 작업 공간 커밋의 PR·리뷰·머지 통합 흐름은 `rules/orchestration/forge-integration.md`가 단일 출처로, 별개의 단계입니다.)

## 시퀀스

spec 워크플로(`autopilot:spec`)가 SPEC 문서를 산출하고 사용자가 그 SPEC을 **최종 승인**(spec 스킬 step 7의 완성 SPEC 전체 단일 승인)하면, 호출자는 다음 순서를 지킵니다.

1. **머지 먼저**: `rules/engineering/branch-and-slug.md`의 `feat 브랜치 + commit` 절차로 SPEC 문서만 commit하고, 이어 `원격 동기화` 절차로 `main`에 ff-merge·push해 SPEC 문서를 `main`에 반영합니다.
2. **그 뒤 구현 제안**: `main` 반영이 끝난 **뒤에야** 구현(`autopilot:dispatch`)을 제안·착수합니다. 머지 전에는 dispatch를 제안하지도, 착수하지도 않습니다.

관찰 가능한 불변식: dispatch가 시작되기 전 `git log main`에 해당 SPEC commit이 존재합니다.

## 승인 권한과 머지 시점

- 머지의 권한 출처는 **step 7의 최종 SPEC 승인 하나**입니다. 본 규칙은 머지 직전 별도의 머지 확인 질문(`AskUserQuestion` 등)을 **추가하지 않습니다** — 최종 승인이 곧 머지 착수 신호입니다.
- SPEC이 아직 최종 승인되지 않은 동안에는 **어떤 머지도 일어나지 않습니다.**

## 우선순위 (spec step 7 옵트인 핸드오프보다 우선)

spec 스킬 step 7은 미해결 마커 없음 + 최종 승인 + 명시 동의 시 머지 없이 곧장 `autopilot:dispatch`를 자동 호출하는 옵트인 자동 핸드오프를 둡니다. 이와 충돌할 경우 **이 프로젝트 규칙이 우선**합니다 — 호출자는 자동 핸드오프로 넘어가기 전에 위 시퀀스(머지 먼저)를 먼저 수행하며, **머지 전에는 dispatch를 착수하지 않습니다.**

## 마커가 남아 있을 때

- 머지 수행 여부는 `[NEEDS CLARIFICATION]` 마커 유무를 **검사하지 않습니다.** 마커가 남아 있어도 위 시퀀스대로 SPEC 문서를 그대로 `main`에 머지합니다.
- 단, 마커가 남아 있으면 **자율 실행(dispatch)은 여전히 차단**됩니다. 이 경우 호출자는 그 사실과 함께 `autopilot:spec --resume <spec-path>`로 마커를 해소하는 경로를 사용자에게 안내합니다. 마커 해소 commit은 이후 별도로 `main`에 반영되어야 합니다.

## 실패 처리

`main`으로의 ff-merge 또는 origin push가 거부되면, `rules/engineering/branch-and-slug.md`의 실패 처리와 동일하게 **force push 없이 중단**하고 사용자에게 PR 흐름 전환을 안내합니다. 본 규칙은 별도의 실패 분기를 정의하지 않고 그 단일 출처를 따릅니다.
