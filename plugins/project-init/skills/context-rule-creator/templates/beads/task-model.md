---
label: Beads (bd)
description: git-native·의존성 인식 트래커. `.beads/*.jsonl`로 git 커밋. 에이전트 핸드오프·자동 ready 식별이 필요할 때.
on_create: |
  `bd` CLI가 설치돼 있는지 확인하고, 없으면 설치 안내(https://github.com/steveyegge/beads)를 한다.
  프로젝트 루트에서 `bd init`을 실행해 `.beads/`를 생성하라고 안내한다(이슈 ID prefix는 디렉터리명에서 파생됨).
  `.beads/*.db`(SQLite 캐시)는 `.gitignore`에 두고 `.beads/*.jsonl`만 커밋하라고 안내한다. 샘플 이슈는 만들지 않는다.
---

# 컨텍스트 관리 지침 — 태스크 모델 (task-model · beads)

태스크를 **beads 백엔드**에 어떻게 표현·저장하는지 정의합니다. 백엔드와 무관한 운영 규율·상태 전이 절차는 짝이 되는 `task-ops` 지침을 따릅니다.

이 프로젝트는 **beads(bd) 백엔드**를 사용합니다. 모든 태스크는 `bd`로 생성하고 `.beads/*.jsonl`(소스 오브 트루스)로 git에 커밋합니다. SQLite 캐시(`.beads/*.db`)는 jsonl에서 재생성되므로 git에 올리지 않습니다.

## beads 저장소

- 소스: `.beads/*.jsonl` — 한 줄에 한 issue. git에 커밋합니다.
- 캐시: `.beads/*.db` — jsonl에서 파생되는 SQLite. `.gitignore`에 두고 커밋하지 않습니다.
- 초기화: 프로젝트 루트에서 한 번 `bd init`. issue ID prefix는 디렉터리명에서 자동 도출됩니다.

## 태스크 = bd issue

| 개념 | beads 매핑 |
|---|---|
| Task | bd issue |
| ID | `bd-xxxx` 해시 ID (예: `bd-a1b2`); 서브태스크는 계층 ID `bd-a1b2.1` |
| Parent / Subtask | `parent-child` 의존성 (또는 계층 ID) |
| Status | issue `status` 필드 |
| Progress log | issue `notes` (append) — `bd update <id> --notes ...` |
| Decisions | `notes`에 `[decision]` prefix |
| Reference | `description`/`design` 내 링크, `related` 의존성 |
| Owner | `assignee` (진행 중·차단일 때만 설정, 선택) |
| 핸드오프 메모 | `notes`의 마지막 `[handoff]` prefix 항목 |
| 작업 중 발견된 후속 | 새 issue + `discovered-from` 의존성 |

태스크 시작 신호 발생 시 issue가 없으면: 작업 중단 → `bd create "<제목>" -t task -p <우선순위>` → 필요한 의존성 연결(`bd dep add <child> <parent>`) → 작업 재개. 단순 정보 조회(`bd list`·`bd show <id>`·`bd ready` 등)는 작업 시작 신호가 아닙니다.

## issue 본문 구조 (구조화 필드 매핑)

새 태스크는 beads의 구조화 필드에 다음과 같이 매핑해 작성합니다. `bd create` 시 채우고, 진행 중 변경 사항은 `bd update`로 갱신합니다.

| 프로젝트 섹션 | beads 필드 |
|---|---|
| 목표 + 배경 | `description` |
| 제안 + 검증 계획 | `design` |
| 완료 기준 (Definition of Done) | `acceptance_criteria` (체크리스트) |

```
description:
  ## 목표
  측정·확인 가능한 결과 상태를 1~3문장으로 작성.

  ## 배경
  문제·상황·리스크를 처음 보는 사람도 이해할 만큼 작성.

design:
  ## 제안
  접근, 구현 순서, 도구·라이브러리, 대안과 선택 이유를 실행 가능하게 작성.

  ## 검증 계획
  테스트·도구·관찰 지표·수동 단계로 DoD 확인 방법을 작성.

acceptance_criteria:
  - [ ] ...
  - [ ] ...
```

- 목표는 무엇, 제안은 어떻게, `acceptance_criteria`는 끝났는지의 체크리스트입니다.
- 검증 계획은 `acceptance_criteria`를 확인하는 방법입니다.
- 진행 로그·결정은 `description`/`design`이 아니라 `notes`에 누적합니다. 시각·작성자는 beads/git 메타데이터를 사용합니다.

## notes에 기록할 것

- 결정·차단 사유·놀라운 발견·외부 영향이 있는 변경만 적습니다.
- 모든 명령 호출이나 사소한 시도는 적지 않습니다.
- 결정은 `[decision]`, 인계는 `[handoff]`, 차단은 `[blocked]` prefix를 `notes` 항목 첫 줄에 둡니다. 라벨이 아니라 본문 마커입니다.
- `notes`는 append-only로 누적합니다. 정정은 새 항목으로 추가합니다.

## 상태 집합과 백엔드 매핑

이 프로젝트가 사용하는 상태 집합: {{state_set}}

- 각 상태는 issue의 **`status`** 필드 값으로 표현합니다. 위 집합에 없는 값은 쓰지 않습니다.
- 상태는 `status` 한 곳으로만 표현하고 별도 label·계층으로 중복 표시하지 않습니다.
- 상태가 진행하는 순서와 각 라이프사이클 이벤트의 목표 상태(전이 이벤트)는 `task-ops`가 정의합니다.

## 공통 규칙

- `.beads/*.jsonl`은 git에 커밋합니다. `.beads/*.db`(캐시)는 커밋하지 않습니다.
- 작업 중 새 후속 작업을 발견하면 새 issue를 만들고 `discovered-from` 의존성으로 출처 issue와 연결합니다.
- 차단 없는 작업은 `bd ready`로 식별합니다 — 모든 차단 의존성이 닫힌 issue만 노출됩니다.
- commit message·PR description에 issue ID를 포함해 cross-reference를 만듭니다 (예: `Closes bd-a1b2`, `Refs bd-a1b2`).
- 시각·작성자 메타데이터는 beads와 git이 자동 기록하므로 본문에 중복 작성하지 않습니다.
