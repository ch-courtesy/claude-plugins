---
name: loop
description: 자율 수행 루프(랄프 루프) 운영 인터페이스. start/status/stop/list/cleanup/logs 서브커맨드로 자율 task의 lifecycle을 관리합니다. SPEC 작성은 별도 'autopilot:spec' 스킬을 사용. 본 스킬은 자기완결적이며 헌법·드라이버·템플릿을 모두 references/에 포함합니다.
---

# loop

자율 수행 루프의 통합 운영 인터페이스. 인자로 subcommand와 sub args를 받아 자율 task lifecycle을 관리합니다.

본 스킬은 **자기완결적**입니다 — 워커 헌법(`references/constitution.md`), 외부 셸 드라이버(`references/loop.sh`), SPEC·메모리 파일 템플릿이 모두 이 스킬 패키지에 포함됩니다. target 프로젝트에는 런타임 상태(`.loops/<task-id>/`, `.loops/locks/`)만 생성됩니다.

## 호출 방법

`Skill(skill: "loop", args: "<subcommand> [<args>]")`

또는 사용자가 자연어로 의도 전달 시 모델이 자동 호출.

## SPEC.md 생성

새 task의 SPEC.md는 별도 스킬 `autopilot:spec`에서 대화형으로 생성합니다:

```
Skill(skill: "spec", args: "<task-id>")
```

자세한 흐름은 `plugins/autopilot/skills/spec/SKILL.md` 참조. SPEC 작성이 끝나면 본 스킬의 `start` 서브커맨드로 이어 호출.

## Subcommand

### start <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>]

검증 후 워크트리·락 생성 + 이터레이션 루프 시작.

`Bash(bash $SKILL_DIR/references/loop.sh start <task-id> [...flags])` 호출. loop.sh는 다음을 검증·수행:
- `--spec <path>` 지정 시 외부 파일을 `.loops/<task-id>/SPEC.md`로 복사 (prepare 대체)
- `.loops/<task-id>/SPEC.md` 존재 + `[NEEDS CLARIFICATION]` 마커 없음 + placeholder 모두 치환됨
- 락 미보유
- 워크트리 없으면 생성 (sibling 위치 `<project>/../<project-name>-loops/<task-id>/`)
- 헌법(`references/constitution.md`)을 워크트리의 CLAUDE.md로 복사
- 메모리 파일 스텁 시드
- 락 획득 + 이터레이션 루프

### status [<task-id>] / stop <task-id> / list / cleanup <task-id> [--force] / logs <task-id> [--tail | --iter N]

각각 `Bash(bash $SKILL_DIR/references/loop.sh <subcommand> [args])`로 위임. 결과를 사용자에게 형식화 출력.

`status` 출력 형식 상세는 `references/status-format.md` 참조.

### 인자 없는 호출

사용법 안내 + 사용 가능한 subcommand 목록 출력.

## 첫 호출 시 setup

target 프로젝트에 `.loops/locks/` 부재 시 start 첫 호출에 자동:
- `mkdir -p .loops/locks`
- `.gitignore`에 `.loops/locks/` 라인 추가 (없으면)

설치 단계가 별도로 필요 없음 — 스킬 첫 호출이 알아서 setup.

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `constitution.md` | 워커 헌법. start 시점에 워크트리 CLAUDE.md로 복사 |
| `loop.sh` | 외부 셸 드라이버. 모든 subcommand의 핵심 로직 |
| `plan-template.md`, `notes-template.md`, `handoff-template.md`, `runlog-template.md`, `escalation-template.md` | 메모리 파일 스텁 |
| `operational-guide.md` | 사용자용 운영 가이드 (워크플로·환경 변수·객관 게이트 표·의존성) |
| `status-format.md` | status 출력 형식 가이드 |
| `troubleshooting.md` | ESCALATION 카테고리별 처리 가이드 |
| `agent-prompts.md` | 이터 내 Agent dispatch 브리프 양식 3종 (spec-compliance-reviewer · code-quality-reviewer · parallel-hypothesis-tester). 헌법 §11.6 참조 |

## 의존성 (target 프로젝트)

- `git` (worktree 지원)
- `bash` 4+
- `yq` (mikefarah)
- `claude` CLI
- `gitleaks` (선택, secrets 게이트용)

## 헌법 customization

기본 헌법은 `references/constitution.md`. 프로젝트별 override는 향후 `.loops/constitution.override.md`(target) 메커니즘으로 추가 예정 (현재 미지원).

## 규칙

- 본 스킬은 target 프로젝트의 `.loops/`만 다룬다. `rules/`나 다른 디렉토리에 파일 생성하지 않음.
- subcommand 위임 시 결과 코드를 그대로 사용자에게 보여주지 않고 형식화·요약.
- 사용자가 명시적 요청한 subcommand만 실행. 다른 subcommand 자동 추론하지 않음.
