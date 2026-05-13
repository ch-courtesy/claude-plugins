---
name: loop
description: 자율 수행 루프(랄프 루프) 운영 인터페이스. start/status/stop/list/cleanup/logs 서브커맨드로 자율 task의 lifecycle을 관리합니다. SPEC 작성은 별도 'autopilot:spec' 스킬을 사용. 본 스킬은 자기완결적이며 헌법·드라이버·템플릿을 모두 references/에 포함합니다.
---

# loop

자율 수행 루프의 통합 운영 인터페이스. 인자로 subcommand와 sub args를 받아 자율 task lifecycle을 관리합니다.

본 스킬은 **자기완결적**입니다 — 워커 헌법(`references/constitution.md`), 외부 셸 드라이버(`references/loop.sh`), SPEC·메모리 파일 템플릿이 모두 이 스킬 패키지에 포함됩니다. target 프로젝트에는 런타임 상태가 모두 `milestones/<m>/loops/<c>/` 단일 nested 트리 안에 생성됩니다 (워크트리 `.worktree/`, lock `.lock`, SPEC·메타 파일). ad-hoc 단일 task는 `regular` milestone(catch-all)로 자동 정규화됩니다.

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

### start <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>] [--no-monitor]

검증 후 워크트리·락 생성 + 이터레이션 루프 시작.

`Bash(bash $SKILL_DIR/references/loop.sh start <task-id> [...flags], run_in_background: true)` 호출 — `run_in_background: true`는 필수다. 동기 호출하면 loop.sh의 이터레이션 루프가 메인 대화를 블록해 아래 "자동 Monitor 가설" 자체가 불가능해진다. task-id가 단일 컴포넌트면 `regular/<input>`로 자동 정규화. loop.sh는 다음을 검증·수행:
- `--spec <path>` 지정 시 외부 파일을 `milestones/<m>/loops/<c>/SPEC.md`로 복사 (prepare 대체)
- `milestones/<m>/loops/<c>/SPEC.md` 존재 + `[NEEDS CLARIFICATION]` 마커 없음 + placeholder 모두 치환됨 (legacy `.loops/<task-id>/SPEC.md` fallback 없음 — v0.2 cutover)
- 락 미보유 — lock 파일은 `milestones/<m>/loops/<c>/.lock`
- 워크트리 없으면 생성 (메인 레포 내부 nested 위치 `milestones/<m>/loops/<c>/.worktree/` — `.gitignore`로 추적 차단)
- 헌법(`references/constitution.md`)을 워크트리의 CLAUDE.md로 복사
- 메모리 파일 스텁 시드
- 락 획득 + 이터레이션 루프

#### 자동 Monitor 가설 (기본 동작)

`--no-monitor`를 명시하지 않은 경우, 백그라운드로 띄운 `loop.sh start`의 stdout 스트림 위에 `Monitor` 도구를 즉시 가설하여 핵심 이벤트(이터 시작·종료, halt, escalation, done 등)를 사용자에게 자동 알림한다. 매 시작마다 별도 결정 질문을 묻지 않는다 — 기본 ON이며 비활성화는 호출 시 `--no-monitor` 플래그로만.

권장 기본값:
- `persistent: true`
- `timeout_ms: 3600000` (1시간)
- 필터 정규식: `이터 #|HALT|WARN|FAIL|ERROR|rate limit|claude 비정상|에스컬레이션|DONE`

`--no-monitor` 플래그는 **SKILL.md 차원 옵션**이다 — 모델이 args 파싱 시 이 토큰을 분리·소비하여 `Monitor` 가설 자체를 생략하고, `loop.sh`로는 **전달하지 않는다** (셸 드라이버는 본 플래그를 모름). 따라서 본 플래그는 **본 스킬을 통한 호출 시점에만** 작용하며, 사용자가 셸 드라이버 `loop.sh start`를 직접 호출하는 경우엔 효력이 없다.

`spec` 스킬 단계 9의 "지금 loop start 호출" 결정으로 자동 연계되는 경우에도 추가 모니터 결정 질문 없이 본 기본 동작(Monitor 가설 포함)이 그대로 적용된다.

#### DONE 이후 PR 생성·재사용 phase (opt-in)

SPEC.md frontmatter에 `request_review: true`가 있으면, task가 `DONE`에 도달한 직후 같은 워크트리에서 PR 생성(또는 동일 브랜치의 open PR 재사용) 단계가 자동 실행됩니다. 기본값은 비활성(키 미지정 또는 `false`).

활성화 시 동작:
- 현재 브랜치를 `origin`으로 push
- default 브랜치 자동 감지 (`gh repo view` → `git symbolic-ref refs/remotes/origin/HEAD`)
- 동일 head 브랜치에 open PR이 없으면 **새 PR 생성**, 있으면 **기존 PR을 in-place로 갱신** (제목·body 동기화)
- PR 제목 = SPEC 문서의 H1, body = SPEC "무엇을 만들 것인가" 본문 + base..HEAD commit log
- task-id가 `^[0-9]+$`이면 body 마지막에 `Closes #<id>` 자동 추가
- reviewer·label·assignee는 일체 설정 안 함
- 성공 시 PR URL·state(open)를 stdout으로 출력, worktree·local 브랜치 보존
- push·pr create·pr edit 중 하나라도 실패하면 non-zero exit으로 단계 중단 (워크트리는 유지)
- default 브랜치 감지 실패 시 push·pr 호출 전 abort

기존 PR body의 사용자 수기 편집 보호를 위해 자동 영역은 `<!-- autopilot:pr-body:begin --> ... <!-- autopilot:pr-body:end -->` marker fence 안에만 작성됩니다. 후속 단계(리뷰 모니터·자동 fix·worktree 정리)는 별도 task에서 다룹니다.

요구: `gh` CLI 설치 + OAuth 인증. 키 이름 `request_review`는 `spec-template.md`·드라이버(`loop.sh`·`pr-phase.sh`)와 동기화돼 있어야 합니다.

### status [<task-id>] / stop <task-id> / list / cleanup <task-id> [--force] / logs <task-id> [--tail | --iter N]

각각 `Bash(bash $SKILL_DIR/references/loop.sh <subcommand> [args])`로 위임. 결과를 사용자에게 형식화 출력.

`status` 출력 형식 상세는 `references/status-format.md` 참조.

### 인자 없는 호출

사용법 안내 + 사용 가능한 subcommand 목록 출력.

## 첫 호출 시 setup

start 첫 호출에 자동:
- `.gitignore`에 다음 패턴이 없으면 추가: `milestones/**/loops/**/.worktree/`, `milestones/**/loops/**/.lock`
- 기존 `.loops/locks/` 라인이 있으면 제거 (v0.1 → v0.2 마이그레이션)
- 변경분을 `.gitignore` 단독 chore commit으로 격리 — 사용자의 staged/unstaged 변경과 commit 단위를 침범하지 않는다
- `.gitignore` 갱신·commit 실패 시 워크트리·lock 생성 중단 후 비-zero exit

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

기본 헌법은 `references/constitution.md`. 프로젝트별 override는 향후 `milestones/<m>/loops/<c>/constitution.override.md`(target) 메커니즘으로 추가 예정 (현재 미지원).

## 규칙

- 본 스킬은 target 프로젝트의 `milestones/<m>/loops/<c>/` nested 트리(워크트리 `.worktree/`, lock `.lock`, SPEC·메타 파일)만 다룬다. `rules/`나 다른 디렉토리에 파일 생성하지 않음.
- subcommand 위임 시 결과 코드를 그대로 사용자에게 보여주지 않고 형식화·요약.
- 사용자가 명시적 요청한 subcommand만 실행. 다른 subcommand 자동 추론하지 않음.
