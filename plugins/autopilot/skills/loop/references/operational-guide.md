# 자율 루프 운영 가이드 (optimized)

`loop.sh`와 헌법은 `references/`에 있다. runtime 상태는 스펙 파일 디렉토리 아래에 둔다 — lock은 `.loop-lock`(spec_dir 직속, 워크트리 생성 전 획득해 race 보호), 노트·신호·이터 로그는 `.worktree/.loop/`.

## 핵심

- 매 이터는 새 프로세스. 기억은 코드·git history·작업 공간 파일에 있다.
- 정체성은 스펙 파일의 절대 경로다.
- 작업 위치는 `<spec_dir>/.worktree/`. 이미 보조 worktree 안에서 호출되면 새로 만들지 않고 현재 cwd를 쓴다.
- 이터 간 기록은 작업 공간의 **노트**, 완료·차단은 **DONE·BLOCKED 신호**다.
- 작업 공간(`CLAUDE.md` 헌법 복사본·`.loop/`)과 spec_dir의 `.loop-lock`은 git 추적에서 분리된다.

## 보안

루프는 무인 동작을 위해 `claude --dangerously-skip-permissions`로 실행된다. 작업 공간에 secrets·`.env`·credentials·SSH key를 두지 말고 스펙에 secrets를 쓰지 않는다. 신뢰 못 한 외부 스펙은 받지 않는다.

## 구조

```text
<spec_dir>/
├── <spec>.md            # 스펙 파일 (정체성)
├── .loop-lock           # 실행 중에만 (PID; 워크트리 생성 전 획득)
└── .worktree/           # 작업 공간 (git worktree, info/exclude)
    ├── CLAUDE.md        # 헌법 복사본
    └── .loop/
        ├── BASE_SHA
        ├── SPEC_PATH    # 스펙 경로 (list 스캔이 정체성 복원에 사용)
        ├── notes.md     # 이터 간 노트
        ├── iterations/<n>.log
        ├── DONE         # 완료 신호 (생성 시)
        └── BLOCKED      # 차단 신호 (생성 시, 첫 줄 category:)
```

`<key>`(status 표시용 12자)는 스펙 절대 경로의 sha256 앞 12자다. 작업 공간은 detached HEAD 워크트리 위에 올라가므로 별도 브랜치 ref를 만들지 않는다 — cleanup 시 워크트리 제거만으로 정리된다(미커밋·미통합 작업은 reflog에 남아 git GC 정책을 따른다).

## 명령

사용 가능한 subcommand 전체 목록·시그니처: `loop.sh`(인자 없이 실행). 스펙 파일을 준비한 뒤 `loop.sh start <spec-path>`로 시작한다.

## 운영

- `stop`은 실행을 정지한다(작업 공간 유지).
- `cleanup`은 DONE 확인 후 워크트리를 제거한다(detached HEAD라 브랜치 삭제는 없음). 실행 중이거나 DONE이 없으면 `--force`로 강제 정리.
- **플랜 게이트**: 1회차 계획 단계에서 플랜 형성 불가면 워커가 BLOCKED(`category: spec-gap`)를 쓰고, driver는 "스펙 강화 필요" 에러(exit 3)로 종료한다. 스펙을 보강한 뒤 재시작한다.
- **차단 해제**: BLOCKED 신호를 읽고 원인 보정 후 BLOCKED 파일을 삭제한 뒤 재시작한다.
- stale `.loop-lock`(PID 비활성)은 다음 `start`/`stop`에서 자동 정리된다.

## 환경 변수

설정 가능한 환경 변수와 기본값은 `loop.sh env` 로 확인.

## 객관 게이트

게이트 목록·SPEC frontmatter override(`test_paths`·`test_sweep_paths`) 는 `loop.sh gates` 로 확인. 위반 시 halt + BLOCKED(`category: gate-violation`).

## 의존성

필수·선택 의존성과 현재 설치 상태: `loop.sh deps`.
