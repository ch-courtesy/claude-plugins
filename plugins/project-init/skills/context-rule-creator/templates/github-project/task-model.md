---
label: GitHub Project
description: Issue + Project로 저장. 원격 협업·이슈 트래킹 통합이 필요할 때.
inputs:
  - name: project_url
    header: "Project URL"
    question: "이 프로젝트가 사용할 GitHub Project URL/번호?"
    options:
      - label: "건너뛰기 (나중에 채움)"
        description: "본문에 TODO 마커만 남기고 진행"
        value: "<TODO: GitHub Project URL/번호>"
      - label: "이 레포 기본 Project 사용"
        description: "본문에 'gh project list로 확인 후 채움' TODO를 남깁니다"
        value: "<TODO: gh project list --owner <소유자> 결과로 확인 후 채움>"
on_create: |
  추가 파일은 만들지 않는다. TODO 마커가 남았으면 사용자가 직접 채워야 한다고 안내한다.
  Status field 옵션은 GitHub UI 또는 `gh` CLI로 설정해야 한다고 안내한다.
  `[decision]`/`[handoff]`는 comment prefix이므로 별도 라벨 셋업이 필요 없다고 안내한다.
---

# 컨텍스트 관리 지침 — 태스크 모델 (task-model · GitHub Project)

태스크를 **GitHub Project 백엔드**에 어떻게 표현·저장하는지 정의합니다. 백엔드와 무관한 운영 규율·상태 전이 절차는 짝이 되는 `task-ops` 지침을 따릅니다.

이 프로젝트는 **GitHub Project 백엔드**를 사용합니다. 모든 태스크는 GitHub Issue로 만들고 Project에 추가합니다.

## 연결된 GitHub Project

- URL/번호: {{project_url}}

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
| Owner | Issue Assignee (진행 중·차단일 때만 설정, 선택) |
| 핸드오프 메모 | 마지막 `[handoff]` prefix comment |

태스크 시작 신호 발생 시 issue가 없으면: 작업 중단 → `gh issue create` → Project 추가(`gh project item-*`) → 작업 재개. 단순 정보 조회(`gh issue list` 등)는 작업 시작 신호가 아닙니다.

## Issue body 구조 (순서 고정)

새 태스크 issue 본문은 다음 섹션 순서로 작성합니다.

```markdown
## 목표
측정·확인 가능한 결과 상태를 1~3문장으로 작성.

## 배경
문제·상황·리스크를 처음 보는 사람도 이해할 만큼 작성.

## 제안
접근, 구현 순서, 도구·라이브러리, 대안과 선택 이유를 이어서 실행 가능하게 작성.

## 검증 계획
테스트·도구·관찰 지표·수동 단계로 DoD 확인 방법을 작성.

## 완료 기준 (Definition of Done)
- [ ] ...
- [ ] ...
```

- 목표는 무엇, 제안은 어떻게, DoD는 끝났는지의 체크리스트입니다.
- 검증 계획은 DoD를 확인하는 방법입니다.
- 진행 로그·결정은 issue body가 아니라 comments에 누적합니다. 시각·작성자는 GitHub 메타데이터를 사용합니다.

## comments에 기록할 것

- 결정·차단 사유·놀라운 발견·외부 영향이 있는 변경만 적습니다.
- 모든 도구 호출이나 사소한 시도는 적지 않습니다.
- 결정은 `[decision]`, 인계는 `[handoff]`, 차단은 `[blocked]` prefix를 comment 첫 줄에 둡니다. 라벨이 아니라 본문 마커입니다.

## 상태 어휘와 백엔드 매핑

이 프로젝트가 사용하는 상태 집합: {{state_set}}

- 각 상태는 Project의 **Status field** 옵션으로 표현합니다. 위 집합에 없는 값은 쓰지 않습니다.
- 상태는 Status field 한 곳으로만 표현하고 중복 라벨을 붙이지 않습니다.
- Status field 옵션은 사람이 GitHub UI/CLI로 설정합니다 (이 지침의 범위 밖).
- 상태가 진행하는 순서와 각 라이프사이클 모멘트의 목표 상태(전이 트리거)는 `task-ops`가 정의합니다.

## 공통 규칙

- commit message·PR description에 issue 번호를 포함해 cross-reference를 만듭니다 (예: `Closes #42`, `Refs #42`).
- 시각·작성자 메타데이터는 GitHub가 자동 기록하므로 본문에 중복 작성하지 않습니다.
- Project URL, Status field 옵션은 사람이 결정하고 GitHub UI/CLI로 진행합니다 (이 지침의 범위 밖). `[decision]`/`[handoff]`는 라벨이 아니라 comment 본문 prefix 컨벤션이므로 별도 셋업이 필요 없습니다.
