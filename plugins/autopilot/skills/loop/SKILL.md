---
name: loop
description: 스펙 파일 기반 로컬 자율 수행 루프(랄프 루프) 운영 인터페이스. 스펙 파일 경로를 받아 격리 작업 공간에서 자율 구현하고 DONE/BLOCKED 파일로 신호한다. start/status/stop/list/cleanup/logs 서브커맨드로 lifecycle을 관리한다.
allowed-tools:
  - Monitor
  - Read
  - Bash(bash * loop.sh start:*)
  - Bash(bash * loop.sh status:*)
  - Bash(bash * loop.sh stop:*)
  - Bash(bash * loop.sh list)
  - Bash(bash * loop.sh cleanup:*)
  - Bash(bash * loop.sh logs:*)
  - Bash(git -C * status:*)
  - Bash(git -C * log:*)
  - Bash(git -C * diff:*)
  - Bash(git -C * stash list)
  - Bash(git -C * stash show:*)
  - Bash(git -C * stash pop:*)
---

# loop

스펙 파일 하나를 받아 로컬에서 자율 구현하는 최소 실행기다. 정체성은 **스펙 파일의 절대 경로**다. 작업 공간은 스펙 파일 디렉토리 아래 `.worktree`(이미 보조 worktree 안이면 현재 cwd), 이터 간 노트는 작업 공간 안에, 완료·차단은 **DONE·BLOCKED 신호 파일**로 표현한다.

워커 헌법은 `references/constitution.md`, 셸 드라이버는 `references/loop.sh`가 단일 출처다.

## 호출

`Skill(skill: "loop", args: "<subcommand> [<args>]")`

loop은 어떤 도구가 만든 스펙이든 **임의의 스펙 파일 경로**를 받는다.

## Subcommands

### start <spec-path> [--max-iterations N] [--wall-clock-minutes N] [--no-monitor] [--events-only]

반드시 `Bash(bash $SKILL_DIR/references/loop.sh start <spec-path> [...flags], run_in_background: true)`로 실행한다. 동기 실행은 Monitor 가설을 막으므로 금지.

driver 동작: 스펙 파일 존재 검증, lock 획득, 작업 공간 준비(주 작업트리면 `<spec_dir>/.worktree` git worktree 생성 + 헌법을 CLAUDE.md로 복사; 보조 worktree 안이면 현재 cwd 사용), 이터레이션 루프. 매 이터는 새 `claude --print` 프로세스다.

#### 플랜 게이트 (스펙 강화 필요)

이터 계획 단계에서 스펙으로부터 실행 계획을 형성할 수 없다고 판단하면, 워커는 BLOCKED 신호에 `category: spec-gap`과 사유를 적고 정지한다. driver는 **1회차의 spec-gap BLOCKED**를 "스펙 강화 필요" 에러(exit 3)로 표면화한다. 스펙을 보강한 뒤 재시작한다.

#### Monitor

기본 ON. `--no-monitor`가 없으면 start 직후 `Monitor`를 붙인다. 기본 필터는 빈 줄과 단독 dot만 제외하고 stdout raw 라인을 통과시킨다. `--events-only`는 SKILL.md 차원 옵션이며 `loop.sh`로 전달하지 않는다 — 핵심 이벤트(`이터 #`, HALT, WARN, FAIL, ERROR, rate limit, claude 비정상, DONE/BLOCKED 신호)만 알림한다. `--no-monitor`가 함께 있으면 `--no-monitor`가 우선한다.

### 완료·차단 신호

- **DONE**: 이터가 완료를 판정하면 워커가 DONE 신호 파일을 남긴다. driver는 정상 종료하며 작업 공간을 보존한다.
- **BLOCKED**: 이터가 차단을 판정하면 워커가 BLOCKED 신호 파일(첫 줄 `category:`, 본문에 사유)을 남긴다. driver는 내용을 출력하고 정지한다. 객관 게이트 위반 시 driver가 직접 `category: gate-violation` BLOCKED를 쓴다.

### status / stop / list / cleanup / logs

각각 `Bash(bash $SKILL_DIR/references/loop.sh <subcommand> [args])`로 위임하고 결과를 요약한다. `status` 형식은 `references/status-format.md`. 상태·lock은 스펙 디렉토리에 둔다(실행 중 `<spec_dir>/.loop.lock`, 작업 공간 `<spec_dir>/.worktree`). `list`는 작업트리를 스캔해 실행을 열거한다. `cleanup`은 DONE 확인 후(또는 `--force`) 워크트리·임시 브랜치를 제거한다.

## references

| 파일 | 역할 |
|---|---|
| `constitution.md` | 워커 헌법 |
| `loop.sh` | 핵심 driver |
| `operational-guide.md` | 운영 가이드 |
| `status-format.md` | status 출력 |
| `troubleshooting.md` | 차단 처리 |
| `agent-prompts.md` | 이터 내 Agent brief |

## 의존성

`git`, `bash` 4+, `yq`(mikefarah), `claude` CLI, `sha256sum` 또는 `shasum`, 선택적으로 `gitleaks`.

## 규칙

- 명시된 subcommand만 실행한다. 다른 subcommand를 자동 추론하지 않는다.
- 작업 공간(`<spec_dir>/.worktree`)·lock·신호 파일 외 파일은 만들지 않는다.
- subcommand exit code를 그대로 던지지 말고 사용자에게 요약한다.
- 프로젝트별 constitution override는 아직 미지원이다.
