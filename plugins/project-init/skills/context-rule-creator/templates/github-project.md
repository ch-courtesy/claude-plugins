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

# 컨텍스트 관리 지침

AI 에이전트 간 작업 컨텍스트를 영속화하는 규칙입니다. 세션 기억에 의존하지 않고 다음 에이전트가 이어받을 수 있어야 합니다.

이 프로젝트는 **GitHub Project 백엔드**를 사용합니다. 모든 태스크는 GitHub Issue로 만들고 Project에 추가합니다.

## 연결된 GitHub Project

- URL/번호: {{project_url}}

## 태스크 우선 원칙 (no-task-no-work)

비자명한 작업은 **관련 issue가 있을 때만 시작합니다**. 없으면 먼저 issue를 만듭니다. `Backlog`는 제목 + 1-2줄 설명만으로 충분하며, "작다"·"즉흥적"이라는 이유로 생략하지 않습니다.

### 작업 시작 신호

- 첫 `Edit`/`Write` 호출
- `git add`/`git commit` 호출
- 외부 상태를 바꾸는 도구 호출 (`gh issue create`, `gh project item-*`, 외부 API, 인프라 변경 등)
- 한 카테고리에서 다파일 변경을 시작할 때

신호 발생 시 issue가 없으면 작업 중단 → issue 생성 → Project 추가 → 작업 재개. 사용자에게 생성 사실을 알립니다.

### 예외

- 사용자가 명시적으로 "이번엔 이슈 없이"·"룰 무시"처럼 면제해준 경우.
- 단순 정보 조회(파일 read, `git log`, `gh issue list`, 검색)는 작업 시작 신호가 아닙니다.

### 계획 섹션 채움

- `Backlog`는 제목 + 1-2줄 설명만 있어도 됩니다.
- `In Design` 또는 `In Progress`로 전이할 때는 목표·배경·제안·검증 계획·완료 기준을 채웁니다. 빈 섹션이나 `TBD`로 전이하지 않습니다.
- 짧아도 명확해야 합니다. 시작 후 알게 된 사항은 comments에 남기고, 필요하면 issue body도 갱신합니다.

### 위반 발견 시

작업 중 issue 누락을 발견하면 즉시 멈추고 retroactive issue를 만듭니다. 마지막 `[handoff]` comment에 사유를 남긴 뒤 재개합니다.

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
| 핸드오프 메모 | 마지막 `[handoff]` prefix comment |

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
- 결정은 `[decision]`, 인계는 `[handoff]` prefix를 comment 첫 줄에 둡니다. 라벨이 아니라 본문 마커입니다.

## 상태와 전이

기본 흐름: `Backlog` → `In Design` → `In Progress` → `Review` → `Done`

보조 상태: `Blocked`(차단, 해소 시 직전 상태 복귀), `Cancelled`(사유 comment 후 종료)

상태는 Project Status field로만 표현하고 중복 라벨을 붙이지 않습니다. 전이는 작업 에이전트 책임입니다.

| 이벤트 | 전이 |
|---|---|
| 첫 작업 시작 신호 (Edit/Write, `git add`/`git commit`) | `Backlog` 또는 `In Design` → **`In Progress`** |
| DoD 모두 체크 + 검증 PASS + 변경 push | `In Progress` → **`Review`** |
| PR 머지 또는 사용자의 명시적 "완료"·"Done"·"닫아줘" 신호 | `Review` → **`Done`** |
| 차단 사유 발견 | Any → **`Blocked`** (`[blocked]` prefix comment에 사유 기록) |
| 차단 해제 | `Blocked` → 직전 상태 |

`Review` → `Done`은 사용자 명시 신호가 있을 때만 수행합니다.

## 운영 규칙

1. **시작 전**: 관련 issue를 확인하고 없으면 만듭니다. issue body와 마지막 `[handoff]`를 먼저 읽습니다.
2. **시작 시**: Status를 `In Progress`로, Assignee를 본인으로 설정하고 시작 comment를 남깁니다.
3. **진행 중**: 의미 있는 발견·결정·차단을 즉시 comment로 기록합니다. 계획이 바뀌면 issue body도 갱신합니다.
4. **commit 전**: 자동화 가능한 검증 계획을 모두 실행합니다. 실패하면 commit하지 말고 수정 후 재검증합니다. 수동 검증은 마지막 `[handoff]`에 담당자·시점을 남깁니다.
5. **완료 시**: DoD 점검 → `Review` 또는 `Done` 전이 → `[handoff]` 추가 → Assignee 해제.
6. **append-only**: comments는 수정·삭제하지 않습니다. 정정은 새 comment로 추가합니다.

## 태스크 단위

- 1 issue는 한 에이전트가 한 세션에 끝낼 수 있는 분량을 권장합니다.
- 더 크면 sub-issue로 분할합니다. 부모 issue는 sub-issue 목록과 진행 요약을 유지합니다.
- 깊이는 2~3 단계 이내를 권장합니다.

## 공통 규칙

- commit message·PR description에 issue 번호를 포함해 cross-reference를 만듭니다 (예: `Closes #42`, `Refs #42`).
- 시각·작성자 메타데이터는 GitHub가 자동 기록하므로 본문에 중복 작성하지 않습니다.
- Project URL, Status field 옵션은 사람이 결정하고 GitHub UI/CLI로 진행합니다 (이 지침의 범위 밖). `[decision]`/`[handoff]`는 라벨이 아니라 comment 본문 prefix 컨벤션이므로 별도 셋업이 필요 없습니다.
