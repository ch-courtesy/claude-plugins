# 자율 루프 운영 가이드 (optimized)

`loop.sh`와 헌법은 `references/`에 있다. runtime 상태는 스펙 파일 디렉토리 아래 `.worktree/`에 둔다(lock 포함).

## 핵심

- 매 이터는 새 `claude --print` 프로세스. 기억은 코드·git history·작업 공간 파일에 있다.
- 정체성은 스펙 파일의 절대 경로다.
- 작업 위치는 `<spec_dir>/.worktree/`. 이미 보조 worktree 안에서 호출되면 새로 만들지 않고 현재 cwd를 쓴다.
- 이터 간 기록은 작업 공간의 **노트**, 완료·차단은 **DONE·BLOCKED 신호**다.
- 작업 공간(`CLAUDE.md` 헌법 복사본·`.loop/`)은 git-common-dir의 info/exclude로 추적에서 분리된다(lock 포함, `.loop/` 안).

## 보안

루프는 무인 동작을 위해 `claude --dangerously-skip-permissions`로 실행된다. 작업 공간에 secrets·`.env`·credentials·SSH key를 두지 말고 스펙에 secrets를 쓰지 않는다. 신뢰 못 한 외부 스펙은 받지 않는다.

## 구조

```text
<spec_dir>/
├── <spec>.md            # 스펙 파일 (정체성)
└── .worktree/           # 작업 공간 (git worktree, info/exclude)
    ├── CLAUDE.md        # 헌법 복사본
    └── .loop/
        ├── .lock        # 실행 중에만 (PID, noclobber 원자 획득)
        ├── BASE_SHA
        ├── SPEC_PATH    # 스펙 경로 (list 스캔이 정체성 복원에 사용)
        ├── notes.md     # 이터 간 노트
        ├── iterations/<n>.log
        ├── DONE         # 완료 신호 (생성 시)
        └── BLOCKED      # 차단 신호 (생성 시, 첫 줄 category:)
```

`<key>`(status 표시용 12자)는 스펙 절대 경로의 sha256 앞 12자다. start 시 임시 브랜치 `loop/<key>`를 만들고 작업 공간을 그 위에 올리며, cleanup이 워크트리와 함께 이 임시 브랜치를 제거한다.

## 명령

```bash
loop.sh start   <spec-path> [--max-iterations N] [--wall-clock-minutes N]
loop.sh status  [<spec-path>]
loop.sh stop    <spec-path>
loop.sh list
loop.sh cleanup <spec-path> [--force]
loop.sh logs    <spec-path> [--iter N]
```

스펙 파일을 준비한 뒤 `loop.sh start <spec-path>`로 실행한다.

## 운영

- `stop`은 SIGTERM 후 lock 해제. 작업 공간은 유지된다.
- `cleanup`은 DONE 확인 후(또는 `--force`) 워크트리·임시 브랜치(`loop/<key>`)·lock을 제거한다. 실행 중이면 `--force`가 SIGTERM 후 SIGKILL 가능.
- **플랜 게이트**: 1회차 계획 단계에서 플랜 형성 불가면 워커가 BLOCKED(`category: spec-gap`)를 쓰고, driver는 "스펙 강화 필요" 에러(exit 3)로 종료한다. 스펙을 보강한 뒤 재시작한다.
- **차단 해제**: BLOCKED 신호를 읽고 원인 보정 후 BLOCKED 파일을 삭제한 뒤 재시작한다.
- `list`는 작업트리를 스캔해 실행을 열거한다(중앙 registry 없음).

## 환경 변수

| 변수 | 플래그 | 기본 | 의미 |
|---|---|---|---|
| `MAX_ITERATIONS` | `--max-iterations` | 30 | 이터 상한 |
| `WALL_CLOCK_MINUTES` | `--wall-clock-minutes` | 120 | 시간 상한 |
| `CLAUDE_FAIL_STREAK_LIMIT` | - | 3 | claude 비정상 exit 연속 허용 |

## 객관 게이트

driver는 이터 후 다음 위반을 halt + BLOCKED(`category: gate-violation`) 처리한다: 이터/시간 상한, 테스트 약화, 의존성 manifest 변경, scope 위반, suppressor 추가, secrets(gitleaks 설치 시), `fix:symptom` streak, 변경 파일 진동.

`test_paths`는 테스트 경로 override, `test_sweep_paths`는 합법적 테스트 rename/cleanup/delete sweep 예외. sweep 밖 기존 테스트 변경은 계속 보호한다.

## 의존성

`bash` 4+, `git`, `yq`(mikefarah), `claude`, `sha256sum` 또는 `shasum`, 선택 `gitleaks`.

## 락

SIGTERM/SIGINT는 자식 프로세스 종료 후 lock 해제. SIGKILL은 orphan 가능성이 있으므로 피한다. stale lock(PID 비활성)은 다음 start/stop에서 자동 정리한다.
