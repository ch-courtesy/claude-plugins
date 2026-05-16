# spec step 2 — task 상태 정합

진입점 `SKILL.md` step 1(사전 검사) 통과 직후, task-id로 식별되는 외부 task를 조회해 4갈래 분기로 상태를 설계 상태로 정합한다. 본 단계는 일반 모드와 `--resume` 모드 모두에 동일하게 적용된다. 본 문서만 읽고도 단계를 끝까지 수행할 수 있게 자기완결적으로 기술한다.

## 백엔드 매핑 위임

본 문서는 backing-neutral 추상 어휘(task·task-id·task 상태·설계 상태·설계 이전 상태·설계 이후 상태·record 식별자)만 사용한다. 추상 어휘 ↔ 프로젝트 백엔드 구체 매핑(record 식별자 형식, 상태 라벨, 조회·생성·편집·상태 전이 명령, task-id ↔ record 매핑 규칙)은 `rules/context.md`가 단일 출처로 책임진다. 본 절차 실행 시 그 매핑을 적용해 구체 명령을 합성한다. 본 문서가 구체 라벨·명령을 재선언하면 `rules/context.md` 갱신 시 drift를 잡을 자동화가 없으므로, 추상 표현만 남긴다 (단일 출처 원칙).

## 조회 절차

- task-id로 task 존재 확인 (백엔드 매핑이 정한 조회 명령).
- 존재 시 그 task의 현재 상태 읽기 (백엔드 매핑이 정한 상태 조회 명령).

## 4갈래 분기

1. **(a) task 부재** (조회 결과 없음): 새 task를 생성하고 task 상태를 설계 상태로 설정. 새 task의 record 식별자를 새 task-id로 사용하며 — 이후 워크플로의 `<c>`는 새 task-id로 **교체**한다. `AskUserQuestion`으로 사용자에게 새 task-id를 명시적으로 안내한 후 진행. 새 task-id에 대해 사전 검사(단계 1)의 폴더 존재 검사·형식 검증을 다시 적용한다 (위험: 새 task-id의 `milestones/<m>/loops/<c>/` 폴더가 이미 있을 수 있음).
2. **(b) 기존 task가 설계 상태**: 상태를 변경하지 않고 다음 단계로 진행 (resume 케이스).
3. **(c) 기존 task가 설계 이전 상태**: task 상태를 설계 상태로 전이한 뒤 다음 단계로 진행.
4. **(d) 기존 task가 설계 이후 상태**: 새 task를 생성·task 상태를 설계 상태로 설정. 새 task의 record 식별자로 task-id를 **교체**하고 `AskUserQuestion`으로 사용자에게 새 task-id를 명시적으로 안내한 후 진행. (a)와 동일하게 새 task-id에 대해 사전 검사를 재적용.

## (a)·(d) 새 task 생성 시 title/body 수집

step 2 시점에는 아직 명확화 라운드(step 5) 전이라 task 본문에 쓸 문제·목표·범위가 수집되지 않은 상태다. 임의 값으로 채우면 실행 일관성이 깨지므로 다음 절차로 최소 정보를 명시적으로 확보한다:

- **Title**: `AskUserQuestion`으로 한 줄 제목을 수집 (1문항, 자유 입력 옵션 포함). 사용자가 "그대로 task-id 사용"을 선택하거나 입력이 비어 있으면 원래 task-id 문자열을 fallback 제목으로 사용한다.
- **Body**: 최소 본문은 다음 두 줄로 고정 — 임의 확장 금지:
  ```
  spec 워크플로우 step 2에서 자동 생성. 본문은 SPEC.md 작성·승인 후 갱신될 예정.
  SPEC: milestones/<m>/loops/<new-task-id>/SPEC.md
  ```
  본문 템플릿의 플레이스홀더 처리는 **두 단계로 나뉜다**:
  - **`<m>` (milestone)**: step 1에서 이미 결정된 값(`--milestone <m>` 또는 default `regular`). task 생성 호출 *전에* 실제 milestone 문자열로 치환한다.
  - **`<new-task-id>` (백엔드 record 식별자)**: task 생성 호출 시점엔 아직 발급되지 않은 값. `<m>`만 치환한 임시 body(`<new-task-id>`는 리터럴로 남김)로 task를 생성하고, 반환된 식별자(`N`)로 즉시 body update 호출을 보내 리터럴을 실제 식별자로 치환한다.
  update 실패 시 abort 규칙은 다른 백엔드 호출과 동일하다.

  명확화 라운드(step 5) 완료 시점에 본 task 본문을 update할지 여부는 본 SPEC 범위 밖이며, 필요하면 사용자가 수동으로 보강한다.

본 절차로 입력이 결정된 뒤에만 task 생성 호출(title·body 함께)을 발행한다. 사용자가 title 수집 단계에서 명시적 취소를 선택하면 (a)·(d) 분기는 abort로 처리한다 — `milestones/` 디렉터리도 생성하지 않는다.

## 호출 실패 시 abort

task 조회·생성·편집·상태 전이 호출 중 어느 하나라도 0이 아닌 exit으로 실패하면 명확한 에러 메시지와 함께 abort. 자동 roll-back은 수행하지 않으며 부분 실패 상태로 다음 단계로 진행하지 않는다.

## 범위 외 (비-목표)

loop `start` 시점의 설계 상태 → 진행 상태 전이, SPEC 승인 후 자동 후속 전이는 본 단계의 책임이 아니다 (다른 스킬·이벤트가 담당).
