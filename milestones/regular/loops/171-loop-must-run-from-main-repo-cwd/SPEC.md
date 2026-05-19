---
scope:
  include: ["plugins/autopilot/skills/loop/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh"
test_sweep_paths:
  - "plugins/autopilot/skills/loop/tests/**"
---

# Loop must run from main repo cwd

## 무엇을 만들 것인가

loop 스킬의 `start` 서브커맨드가 호출될 때, 시스템은 호출 워킹 디렉토리가 git 저장소의 *주 작업트리(main working tree)*인지 확인하고 그렇지 않은 경우 — 즉 보조 worktree 안에서 호출된 경우 — 즉시 거부한다. 이는 셸 드라이버 본체가 호출 cwd 기준으로 PROJECT_ROOT를 동적 결정해 `milestones/<m>/loops/<c>/.worktree/` nested 구조를 만들기 때문이다. 보조 worktree에서 호출되면 PROJECT_ROOT가 그 worktree path로 잡혀 nested wt가 비-캐노니컬 경로에 생성되고, 후속 cleanup·rebase 검증이 전제하는 PROJECT_ROOT 가정도 깨진다. 거부 동작은 셸 드라이버 본체에 위치해 스킬을 통한 호출이든 셸 드라이버 직접 호출이든 동일하게 작동하며, 사용자가 docs만으로도 같은 제약에 도달할 수 있도록 스킬 문서의 호출 방법 절에도 명시 지침을 함께 추가한다.

## 수용 기준 (EARS)

- **AC1** (Event-driven): loop의 `start` 서브커맨드가 호출될 때, 시스템은 호출 워킹 디렉토리가 git 저장소의 주 작업트리인지 검사한다.
- **AC2** (Unwanted): 호출 워킹 디렉토리가 보조 worktree로 판정되는 경우, 시스템은 명확한 오류 메시지(예상 cwd · 실제 cwd · 해결 안내 포함)와 함께 비-zero exit으로 즉시 거부한다.
- **AC3** (Optional): 호출 워킹 디렉토리가 주 작업트리인 경우, 시스템은 기존 start 동작을 변경 없이 그대로 수행한다.
- **AC4** (Ubiquitous): 거부·검사 로직은 셸 드라이버 본체에 위치해 스킬을 통한 호출과 셸 드라이버 직접 호출 모두에 동일하게 작동한다.
- **AC5** (Ubiquitous): 스킬 문서의 호출 방법 절에 호출 cwd가 주 작업트리여야 한다는 지침이 거부 동작과 일관된 표현으로 명시된다.

## 범위

포함:

- `plugins/autopilot/skills/loop/references/loop.sh` — `start` 서브커맨드 진입 직후 cwd 검사 가드 추가
- `plugins/autopilot/skills/loop/SKILL.md` — 호출 방법 절에 주 작업트리 필수 지침 명시
- `plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh` — 보조 worktree fixture 케이스 추가

비-목표 / 제외:

- `operational-guide.md` (사용자가 SKILL.md만 선택)
- `status`·`stop`·`list`·`cleanup`·`logs` 등 다른 subcommand 검사 — `start`만의 범위
- spec 워크플로우의 worktree 호출 변경 (spec은 worktree 안에서 SPEC.md 작성 제약 없음 — 별개 문제)
- 워크트리 안에서 nested loop을 의도적으로 돌리고 싶은 advanced 케이스 — 본 SPEC은 일률 차단

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh
```

SPEC 구현 중 추가될 케이스:

- 보조 worktree fixture에서 `loop.sh start` 호출 → 비-zero exit + 오류 메시지 매칭 (AC2)
- 주 작업트리 cwd에서 기존 케이스 보존 (AC3)
- `loop.sh` start 진입부 grep — 검사 함수 호출 확인 (AC1·AC4)
- `SKILL.md` grep — "주 작업트리" 또는 "main repo cwd" 동등 표현 존재 (AC5)

## 제약

- "주 작업트리" 판별은 일반 git 저장소 케이스의 `.git` 디렉토리 vs 파일 존재 여부(또는 `git rev-parse --git-common-dir` vs `--git-dir` 비교)로 수행. bare repo·submodule·detached HEAD 등 비표준 환경은 보장 범위 외.
- `start` 서브커맨드에만 가드 적용 — 다른 subcommand(`status`·`stop`·`list`·`cleanup`·`logs`)는 기존 동작 유지.
- bash 4 이상 (loop.sh 기존 가정과 동일).
- 오류 메시지는 사용자가 main repo cwd로 이동하는 안내를 포함해야 함 (AC2 그대로 구현).

## 위험

- worktree 안에서 의도적으로 nested loop을 돌리고 싶은 advanced 사용자 케이스가 제한됨 (드문 케이스 — 니즈 감지 시 분리 SPEC으로 해제·우회 옵션 제공 검토).
- "주 작업트리" 정의가 git 공식 문서의 *main working tree* 개념과 일치한다는 전제. git 향후 버전이 이 구조를 변경하면 검사 로직 재검토 필요.
- spec 워크플로우가 worktree 안에서 SPEC.md를 만든 후 그 자리에서 loop start를 호출하던 종래 패턴이 차단됨 — ExitWorktree 후 main으로 돌아가 호출하도록 안내 조정 필요.
- 테스트 fixture가 `git worktree add`가 되는 환경을 요구 — CI·로컬 둘 다 일반적 git 설치이면 충족.
