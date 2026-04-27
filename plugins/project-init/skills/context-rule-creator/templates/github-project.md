---
label: GitHub Project
description: Issue + Project로 저장. 원격 협업·이슈 트래킹 통합이 필요할 때.
on_create: |
  추가 파일은 만들지 않는다. 어떤 Project에 연결할지, Status field 옵션 셋업은 사용자가 GitHub UI 또는 `gh` CLI로 직접 진행해야 한다는 안내를 출력한다. `[decision]`/`[handoff]`는 GitHub 라벨이 아니라 comment 본문 prefix 컨벤션이므로 별도 셋업이 필요하지 않다는 점도 함께 안내한다.
---

# 컨텍스트 관리 지침

AI 에이전트 간에 작업 컨텍스트를 전달하기 위한 영속성 규칙입니다. 휘발 메모리(세션·대화)에 의존하지 않고, 한 에이전트가 끝낸 작업을 다른 에이전트가 이어받을 수 있어야 합니다.

이 프로젝트는 **GitHub Project 백엔드**를 사용합니다. 모든 태스크는 GitHub Issue로 만들고 Project에 추가합니다.

## 태스크 우선 원칙 (no-task-no-work)

- 모든 작업은 관련 issue가 존재한 상태에서만 시작합니다. 관련 issue가 없으면 작업을 멈추고 먼저 새 issue를 만듭니다.
- **`Backlog`는 계획이 비어 있어도 됩니다.** 제목과 한두 줄 설명만으로 아이디어를 캡처할 수 있습니다. 캡처 마찰을 낮춰 떠오르는 즉시 영구 저장소에 남기기 위함입니다.
- **`In Design` 또는 `In Progress`로 전이할 때 계획 섹션이 채워져 있어야 합니다.** issue body의 계획 섹션(목표·배경·제안·검증 계획·완료 기준)을 다른 에이전트가 이해할 수 있을 만큼 채웁니다. 빈 섹션이나 `TBD` 상태로 전이하지 않습니다.
- 사소한 태스크라도 각 섹션은 짧게라도 명확히 작성합니다. 분량이 짧은 것은 괜찮지만 비어 있는 것은 안 됩니다.
- 시작한 뒤에 알게 된 사항은 comments에 기록하고, 필요하면 issue body의 계획 섹션도 갱신합니다.

## 태스크 = Issue

| 개념 | GitHub Project 매핑 |
|---|---|
| Task | Issue (Project item) |
| ID | Issue number (예: `#42`) |
| Parent / Subtask | Sub-issue 관계 |
| Status | Project의 Status field |
| Progress log | Issue **comments** (시각·작성자 자동 기록) |
| Decisions | comment + `[decision]` prefix |
| Reference | Issue body 링크 / cross-reference |
| Owner | Issue Assignee (in_progress·blocked일 때만 설정, 선택) |
| 핸드오프 메모 | Issue body 상단 핸드오프 섹션 + 마지막 `[handoff]` prefix comment |

## Issue body 구조 (순서 고정)

새 태스크 issue를 만들 때 본문은 다음 섹션 순서로 구성합니다.

```markdown
## 핸드오프 메모
가장 최근 인계 사항. 다음 에이전트가 이어받을 때 알아야 할 것 (현재 상태·다음 단계·주의점).
issue 생성 시점에는 비어 있어도 되고, 인계가 일어날 때마다 이 섹션을 갱신합니다.

## 목표
무엇을 달성하려는지. 결과 상태를 측정·확인 가능한 형태로 1~3 문장.

## 배경
왜 필요한지. 어떤 문제·상황에서 출발했고 무엇이 걸려 있는지. 처음 보는 사람도 맥락을 잡을 수 있을 만큼.

## 제안
어떤 접근·단계·대안으로 목표를 달성할지. 구현 순서, 사용할 도구·라이브러리, 검토한 대안과 선택 이유. 다른 에이전트가 받아 들었을 때 자체 판단 없이 이어갈 수 있을 만큼.

## 검증 계획
결과를 어떻게 확인할지. 사용할 테스트·도구·관찰 지표·수동 단계. DoD의 각 항목을 어떤 방법으로 확인하는지 매핑.

## 완료 기준 (Definition of Done)
- [ ] ...
- [ ] ...
```

- **핸드오프 메모를 가장 위**에 둡니다. 인계받는 에이전트가 가장 먼저 읽어야 하기 때문입니다.
- **계획 섹션(목표·배경·제안·검증 계획·DoD)은 issue 생성 시 모두 채웁니다.** 빈 채로 작업을 시작하지 않습니다.
- **목표·제안·DoD는 다른 층위입니다**: 목표는 "무엇을(What)", 제안은 "어떻게(How)", DoD는 "끝났는가(Done?)"의 체크리스트.
- **검증 계획과 DoD는 분리합니다**: DoD는 "끝났는가"의 체크리스트, 검증 계획은 그 체크리스트를 "어떻게 확인하는가"의 방법론.
- 진행 로그·결정은 issue body가 아니라 **comments**에 누적합니다. comments는 GitHub가 시각·작성자를 자동 기록하므로 본문에 별도 메타데이터를 적지 않습니다.

## comments에 기록할 것

- 결정·차단 사유·놀라운 발견·외부 영향이 있는 변경.
- 모든 도구 호출이나 사소한 시도까지는 적지 않습니다 (잡음 폭증 방지).
- 결정은 comment 첫 줄에 `[decision]` prefix를 달아 식별 가능하게 합니다. 인계 comment는 `[handoff]` prefix를 사용합니다. 이 prefix는 GitHub의 라벨 기능이 아니라 본문 마커 컨벤션이며, GitHub 검색(`is:comment "[decision]"`)으로 필터링합니다.

## 상태 어휘 (Project Status field)

`Backlog` → `In Design` → `In Progress` → `Review` → `Done`

- `Backlog`: 캡처만 된 상태 (계획 비어도 OK).
- `In Design`: 계획 작성 중. 본격 실행 전 단계.
- `In Progress`: 실행 중.
- `Review`: 검토 중 (예: PR 리뷰).
- `Done`: 완료.
- `Blocked`: 차단으로 일시 정지. 해소되면 직전 상태로 복귀합니다.
- `Cancelled`: 사유는 종료 comment에 기록합니다.

상태 전이는 Project의 Status field 값으로만 표현하고, 같은 의미의 라벨을 중복으로 붙이지 않습니다.

## 운영 규칙

1. **시작 전**: 관련 issue 존재 확인. 없으면 작업을 멈추고 새 issue를 먼저 만듭니다. issue body·comments를 읽고 **body 상단 핸드오프 메모와 마지막 `[handoff]` comment를 가장 먼저** 확인합니다.
2. **시작 시**: Status를 `In Progress`로, Assignee를 본인으로 설정합니다. "시작" comment를 남깁니다.
3. **진행 중**: 의미 있는 발견·결정·차단을 **즉시** comment로 기록합니다. 계획 섹션이 변경되면 issue body의 해당 섹션도 갱신합니다.
4. **완료 시**: 검증 계획에 따라 DoD 점검 → Status를 `Review` 또는 `Done`으로 → issue body의 핸드오프 메모 최신화 → `[handoff]` prefix comment 추가 → Assignee 해제.
5. **append-only**: comments는 수정·삭제하지 않습니다. 정정은 새 comment로 추가합니다.

## 태스크 단위

- 1 issue ≈ 한 에이전트가 한 세션에 끝낼 수 있는 분량.
- 더 크면 sub-issue로 분할합니다. 부모 issue는 sub-issue 목록과 진행 요약을 유지합니다.
- 깊이는 2~3 단계 이내를 권장합니다.

## 공통 규칙

- 코드 변경의 commit message·PR description에 issue 번호를 포함해 자동 cross-reference를 만듭니다 (예: `Closes #42`, `Refs #42`).
- 시각·작성자 메타데이터는 GitHub가 자동 기록하므로 본문에 중복 작성하지 않습니다.
- Project URL, Status field 옵션은 사람이 결정하고 GitHub UI/CLI로 진행합니다 (이 지침의 범위 밖). `[decision]`/`[handoff]`는 라벨이 아니라 comment 본문 prefix 컨벤션이므로 별도 셋업이 필요 없습니다.
