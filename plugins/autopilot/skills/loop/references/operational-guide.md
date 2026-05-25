# 자율 루프 운영 가이드 (optimized)

`loop.sh`와 헌법·템플릿은 `references/`에 있고, target runtime 상태는 `milestones/<m>/loops/<c>/`에 생성된다.

## 핵심

- 매 이터는 새 `claude --print` 프로세스. 기억은 파일·task 메모리·신호에 있다.
- 작업 위치는 `milestones/<m>/loops/<c>/.worktree/`.
- `.worktree/`와 `.lock`은 `.gitignore` 대상.
- 워크트리 `CLAUDE.md`는 로컬 exclude로 main에 새지 않는다. 사용자 레벨 CLAUDE/settings는 차단 불가이므로 시작 전 확인 권장.

## 보안

루프는 무인 동작을 위해 `claude --dangerously-skip-permissions`로 실행된다. 워크트리에 secrets, `.env`, credentials, SSH key를 두지 말고 SPEC에 secrets를 쓰지 않는다. 신뢰 못 한 외부 SPEC은 받지 않는다.

## 구조

```text
milestones/<m>/loops/<c>/
├── SPEC.md
├── .lock
└── .worktree/
    ├── CLAUDE.md
    ├── .iterations/<n>.log
    └── milestones/<m>/loops/<c>/SPEC.md
```

단일 task는 `regular/<task-id>`로 정규화한다. 완료는 task 저장소의 `LOOP_DONE_LABEL`에 의존한다.

## 명령

```bash
loop.sh start   <task-id> [--spec path] [--max-iterations N] [--wall-clock-minutes N] [--watch]
loop.sh status  [<task-id>]
loop.sh stop    <task-id>
loop.sh list
loop.sh cleanup <task-id> [--force]
loop.sh logs    <task-id> [--tail | --iter N]
```

새 task는 `Skill(skill: "spec", args: "<task-id>")`로 SPEC을 만든 뒤 `loop.sh start <task-id>`를 실행한다.

## 운영

- `--spec <path>`는 외부 SPEC을 canonical 경로로 복사한 뒤 start한다.
- `stop`은 SIGTERM 후 lock 해제.
- `cleanup --force`는 실행 중이면 SIGTERM 후 SIGKILL 가능. 정상은 `stop` 후 cleanup.
- DONE_WITH_CONCERNS는 완료 대신 `[handoff]`의 `## 의심점`에 기록하고 다음 이터가 처리한다.
- ESCALATION은 troubleshooting 참조 후 SPEC/task 메모리 보정, notes/unblocked/resume 신호 발행, 재시작 순서.

## 환경 변수

| 변수 | 플래그 | 기본 | 의미 |
|---|---|---|---|
| `MAX_CONCURRENT` | - | 3 | 동시 task |
| `MAX_ITERATIONS` | `--max-iterations` | 30 | 이터 상한 |
| `WALL_CLOCK_MINUTES` | `--wall-clock-minutes` | 120 | 시간 상한 |
| - | `--watch` | off | blocked 해제 신호까지 polling |
| `WATCH_TIMEOUT_HOURS` | - | 24 | watch timeout |

## 객관 게이트

driver는 이터 후 다음 위반을 halt + blocked 처리한다: 이터/시간 상한, 테스트 약화, 의존성 manifest 변경, scope 위반, suppressor 추가, secrets(gitleaks 설치 시), `fix:symptom` streak, 변경 파일 진동.

`test_paths`는 테스트 경로 override, `test_sweep_paths`는 합법적 테스트 rename/cleanup/delete sweep 예외. sweep 밖 기존 테스트 변경은 계속 보호한다.

## 의존성

`bash` 4+, `git`, `yq`(mikefarah), `claude`, `sha256sum` 또는 `shasum`, 선택 `gitleaks`.

## 락

SIGTERM/SIGINT는 자식 프로세스 종료 후 lock 해제. SIGKILL은 orphan 가능성이 있으므로 피한다. stale lock은 다음 start/stop에서 PID 유효성 검사로 자동 정리한다.
