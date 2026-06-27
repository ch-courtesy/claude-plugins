# scope-coverage 매핑 관례 (create-task 자체 소유 단일 출처)

`scope-coverage-check.sh`가 소스 경로 → 프로젝트 테스트 경로를 매핑할 때 따르는 관례.
구현체는 `scope-coverage-check.sh`이며, 이 문서는 인간 가독 규약 문서다.

## 매핑 규칙

| 소스 패턴 | 기대 테스트 경로 |
|---|---|
| `plugins/autopilot/skills/<S>/...` | `tests/autopilot/test-<S>*.sh` (파일 glob) |
| `plugins/autopilot/skills/<S>/...` | `tests/autopilot/<S>/` (디렉터리, 있으면) |
| `plugins/autopilot/task-backend/...` | `plugins/autopilot/task-backend/tests/` |

`<S>`는 스킬 이름(예: `create-task`, `loop`, `execute-task`, `feature`, `fix`).

## 커버드(covered) 판정

`scope.include`의 항목 중 기대 테스트 경로를 **prefix-포함**하거나 **정확히 일치**하면 커버드로 본다.
예: scope에 `tests/autopilot/` 이나 `tests/autopilot/test-create-task*.sh` 가 있으면 create-task 커버.

## 오탐 방지 조건

- **기존 테스트 없는 신규 소스**: 매핑된 테스트 경로가 파일시스템에 존재하지 않으면 검사하지 않는다. 존재 확인이 전제다.
- **테스트-only 경로**: `plugins/autopilot/` 외 경로(예: `tests/`, `CHANGELOG.md`, `rules/`)는 소스로 취급하지 않는다.
- **문서-only 경로**: `rules/**`, `CHANGELOG.md`, `*.md` 등은 소스 취급 안 함.

## #483과 역할 분담

| 역할 | 책임 |
|---|---|
| **#483 (작성자 명시)** | 완료 조건이 요구하는 **새** 회귀 테스트 경로를 scope.include에 포함 — 작성자(feature/fix)가 책임 |
| **#498 (시스템 검증)** | scope 내 소스를 덮는 **기존** 테스트 경로 누락을 등록 시 자동 플래그 — 시스템(create-task)이 책임 |
