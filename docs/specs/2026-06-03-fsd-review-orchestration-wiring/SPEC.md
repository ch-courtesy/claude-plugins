---
scope:
  include:
    - plugins/autopilot/skills/fsd/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
depends_on: ["2026-06-03-autopilot-review-producer-skill"]
# ears_language: ko
---

# fsd 리뷰 오케스트레이션 배선

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
fsd 오케스트레이터가 `autopilot:review` 생산자 스킬을 호출해 리뷰 판정을 받고, 그 판정에 따라 파이프라인을 전이시키도록 배선한다. 현재 미배선(C0 스켈레톤 스텁)인 `fsd review`·`fsd poll` 진입구를 열고, 반복·수렴(iterate-until-approved)을 오케스트레이터가 소유하도록 한다.

- `fsd review <task-id>`는 더 이상 미구현 안내를 내지 않고, 리뷰 생산자를 한 번 호출해 판정(approve/request_changes/unavailable)을 얻은 뒤: `request_changes`이면 분류된 재작업 브리프로 구현(loop/dispatch)을 재위임하고 리뷰 라운드를 증가시키며, `approve`이면 머지 단계로 진행 가능 상태로 전이하고, `unavailable`이면 사람에게 에스컬레이션한다.
- `fsd poll`은 진행 중인 리뷰 상태 작업을 드레인하며 위 전이를 자동 적용한다.
- 반복의 무한루프 가드(라운드 수 상한·핑퐁·무진전)는 오케스트레이터가 소유한다.

기존 `review-loop.sh`의 채택 분류·SPEC 델타·재구현 위임·가드 로직은 보존하되, 리뷰를 **조회**하던 부분(기존엔 봇 리뷰 fetch)을 새 생산자 스킬 호출로 교체한다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->
리뷰 생산자가 판정을 만들어도, 그 판정을 받아 재구현·재리뷰·머지로 잇는 오케스트레이션이 없으면 파이프라인이 리뷰 단계에서 끊긴다. fsd의 잠긴 `review`·`poll` 진입구를 열어 "리뷰 → (차단 시)재구현 → 재리뷰 → 승인 → 머지"를 task 단위로 자동으로 닫는다.

## 완료 조건
<!-- 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- 작업 식별자로 `fsd review`가 호출될 때, 미구현 안내 대신 리뷰 생산자를 호출해 머신리더블 판정 한 건을 얻고 그 판정에 따라 작업 상태를 전이시킨다.
- 리뷰 판정이 `request_changes`이면, 분류된 재작업 브리프(반드시 반영 항목)로 구현을 재위임하고 리뷰 라운드 카운터를 1 증가시킨 뒤 같은 작업 브랜치로 재푸시한다(새 PR을 만들지 않으며 강제 푸시하지 않는다).
- 리뷰 판정이 `approve`이면, 작업을 머지 진행 가능 상태로 전이시키고 추가 재구현 라운드를 시작하지 않는다.
- 리뷰 판정이 `unavailable`이거나 사람 리뷰어의 변경 요청이면, 자동 재구현을 멈추고 사람에게 에스컬레이션한다.
- 리뷰 라운드 수가 상한을 초과하거나, 변경 요청이 남았는데 반드시 반영 항목이 없거나(무진전), 차단성 지적 집합이 직전 라운드와 동일하면(핑퐁), 반복을 멈추고 에스컬레이션한다.
- `fsd poll`이 호출될 때, 진행 중인 리뷰 상태 작업들에 대해 위 전이를 드레인 방식으로 적용한다.
- 오케스트레이션의 결정적 동작(생산자 호출·판정 분기·라운드 증가·가드)은 외부 인터페이스(리뷰 생산자·구현 위임·forge·backend)를 주입 가능한 명령 변수로 둔 self-test로 mock만으로 통과한다.

## 범위
포함:
- `plugins/autopilot/skills/fsd/references/fsd.sh` — `cmd_review`(및 필요한 `cmd_poll` 연계) 스텁을 실제 오케스트레이션 호출로 전환.
- `plugins/autopilot/skills/fsd/references/poll.sh` — 리뷰 생산자 호출 경로(주입 가능 명령 변수)로 재지정.
- `plugins/autopilot/skills/fsd/references/review-loop.sh` — 리뷰 조회 부분을 새 생산자 호출로 교체하고 분류·SPEC 델타·재구현·가드는 보존.
- `plugins/autopilot/skills/fsd/SKILL.md` — `review`·`poll` 서브커맨드 계약을 미구현에서 배선됨으로 갱신.

비-목표 / 제외:
- 리뷰 생산(다관점 lens·findings·verdict 산출)은 이 SPEC이 만들지 않는다 — 선행 SPEC의 `autopilot:review` 생산자를 호출만 한다.
- 머지 실행 자체(`fsd merge`, C4)는 이 SPEC 범위가 아니다 — approve 후 머지 진행 가능 상태로의 전이까지만 다룬다.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 강제(force) 푸시 금지, 새 PR 생성 금지(같은 head 브랜치 갱신만) — 기존 `review-loop.sh` 불변식을 보존한다.
- 채택 분류는 `rules/change-adoption.md`를, 리뷰 원칙은 `rules/review.md`를 단일 출처로 따른다(재정의 금지).
- 스크립트는 bash 3.2+ 호환으로 작성하고, 라이브러리/엔트리 겸용 스크립트는 `BASH_SOURCE`/`$0` 가드로 source 시 디스패처가 실행되지 않게 한다.
- fsd는 `.fsd/` 밖 경로를 만들지 않으며, 구현 위임은 공개 서브커맨드로만 한다.
- 리뷰 생산자 의존은 주입 가능 명령 변수(기본값=형제 `autopilot:review` 스킬 호출)로 두어 self-test가 mock으로 독립 검증되게 한다.

## 위험 (있을 때만)
- `review-loop.sh`의 리뷰 조회를 생산자 호출로 교체할 때 기존 selftest의 mock 인터페이스 형태가 바뀌어 회귀가 숨을 수 있다 — 교체 후 selftest를 새 인터페이스에 맞춰 갱신하고 모든 가드 케이스(라운드캡·핑퐁·무진전·사람 에스컬레이션)를 보존 검증한다.
- 생산자 판정 스키마와 오케스트레이터가 기대하는 필드가 어긋나면 분기가 깨진다 — 선행 SPEC의 머신리더블 판정 스키마를 계약으로 고정해 양쪽이 같은 출처를 참조하게 한다.
