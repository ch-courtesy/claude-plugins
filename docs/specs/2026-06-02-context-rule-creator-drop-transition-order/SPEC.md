---
scope:
  include:
    - plugins/project-init/skills/context-rule-creator/SKILL.md
    - plugins/project-init/skills/context-rule-creator/templates/task-ops.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# context-rule-creator 상태 수집에서 전이 순서 질문 제거 및 이벤트 카탈로그 개편

## 무엇을 만들 것인가
context-rule-creator 스킬의 상태 구성 수집 절차(SKILL.md 5단계)와 그 산출 템플릿(task-ops.md)을 다음과 같이 바꾼다.

- 별도의 "전이 순서" 질문을 없앤다. 사용자는 더 이상 상태 진행 순서를 직접 나열하지 않는다.
- 라이프사이클 이벤트별 목표 상태를 묻는 단계의 이벤트 카탈로그를 개편한다. 맨 앞에 "아직 진행되지 않은 초기 상태"를 묻는 이벤트("태스크 최초 등록")를 추가하고, 기존 "검증 통과" 이벤트를 "리뷰 요청"(검증/리뷰에 진입한 상태)으로 바꾼다.
- 상태 진행 순서(기본 흐름)는 사용자에게 묻지 않고, 순서가 정해진 라이프사이클 이벤트들의 목표 상태 응답을 종합해 스킬이 자동으로 구성한다.

핵심 근거: 라이프사이클 이벤트는 본래 진행 순서를 갖는다(최초 등록 → 계획 → 구현 → 리뷰 → 머지). 따라서 각 이벤트의 목표 상태만 받으면 전이 순서는 그로부터 추정할 수 있으므로, 별도의 전이 순서 질문은 불필요하다.

## 완료 조건
- 항상, context-rule-creator의 SKILL.md 상태 구성 수집 절차에는 "전이 순서"를 독립 질문으로 묻는 단계가 존재하지 않는다.
- 항상, SKILL.md와 task-ops.md 어디에도 `{{transition_order}}`를 사용자에게 직접 입력받는다는 서술이 남아 있지 않다.
- 라이프사이클 이벤트별 목표 상태를 수집할 때, 이벤트 카탈로그의 첫 항목은 "태스크 최초 등록"(아직 진행되지 않은 초기 상태)이며 placeholder는 `{{event_initial}}`이고, 이 항목을 계획/스펙 문서 생성보다 먼저 묻는다.
- 라이프사이클 이벤트 카탈로그에 "검증 통과"(`{{event_verify_pass}}`) 항목이 더 이상 존재하지 않고, 그 자리에 "리뷰 요청"(검증/리뷰에 진입한 상태) 항목이 placeholder `{{event_review_start}}`로 존재한다.
- task-ops.md를 조립할 때, "기본 흐름:" 줄의 `{{transition_order}}`는 순서가 정해진 on-path 이벤트들의 목표 상태 응답(`{{event_initial}}` → `{{event_plan_doc}}` → `{{event_impl_start}}` → `{{event_review_start}}` → `{{event_merge_done}}`)을 종합해 스킬이 자동으로 채운다. 차단·해제 같은 off-path 이벤트는 기본 흐름에 포함하지 않는다.
- task-ops.md의 이벤트 카탈로그 표가 위 개편된 이벤트 집합(초기·계획·구현·리뷰요청·머지·차단·해제)과 placeholder를 그대로 반영한다.
- SKILL.md 5단계의 단계 번호와 본문 서술이 전이 순서 질문 제거 후에도 모순 없이 일관된다(①·② 같은 잔여 번호 참조나 "②의 전이 순서" 같은 죽은 참조가 남지 않는다).

## 범위
포함:
- `plugins/project-init/skills/context-rule-creator/SKILL.md` 5단계 상태 구성 수집 절차 및 이를 참조하는 본문·규칙 서술 갱신
- `plugins/project-init/skills/context-rule-creator/templates/task-ops.md`의 "상태와 전이" 절(기본 흐름 줄·이벤트 카탈로그 표) 갱신

비-목표 / 제외:
- 백엔드별 `task-model.md` 템플릿(filesystem·beads·github-project)의 본문 변경 — `{{state_set}}`만 사용하므로 이번 변경 대상 아님
- 상태 집합(①) 수집 방식 변경 — 그대로 유지
- 정적 입력(`inputs`)·백엔드 선택·확인 게이트·파일 기록 절차 등 그 외 절차 변경
- 새 백엔드 추가나 출력 파일명·디렉터리 레이아웃 변경

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- placeholder 네이밍 고정: 초기 상태 이벤트는 `{{event_initial}}`, 리뷰 진입 이벤트는 `{{event_review_start}}`를 사용한다.
- 기존 placeholder `{{state_set}}`, `{{event_plan_doc}}`, `{{event_impl_start}}`, `{{event_merge_done}}`, `{{event_blocked}}`, `{{event_unblocked}}`의 이름과 의미는 유지한다.
- task-ops.md의 "상태와 전이" 절을 제외한 다른 절(태스크 우선 원칙·운영 규칙·기록 규율 등)은 변경하지 않는다.
- 템플릿 본문은 placeholder 치환 외에는 그대로 복사한다는 기존 스킬 규칙을 깨지 않는다 — 자동 추정되는 기본 흐름도 placeholder 치환 형태(`{{transition_order}}`에 종합값을 채움)로 유지한다.

## 위험 (있을 때만)
- 단계 번호 재정렬 시 SKILL.md 본문 다른 곳(예: 6단계 "본문 조립", 규칙 절의 "전이 순서" 언급)에 죽은 참조가 남을 수 있다 — 5단계 외 참조 지점도 함께 점검해야 한다.
- "리뷰 요청" 이벤트의 트리거 서술(기존 "검증 통과 (DoD 모두 체크 + 검증 PASS + 변경 반영)")을 리뷰 진입 의미로 다시 써야 하며, "머지/완료" 이벤트 서술과 의미가 겹치지 않도록 경계를 분명히 해야 한다.
