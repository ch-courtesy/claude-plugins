---
scope:
  include:
    - "plugins/autopilot/skills/loop/**"
    - "tests/autopilot/test-loop-pr-phase.sh"
    - "tests/autopilot/test-loop-sh.sh"
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-loop-pr-phase.sh && bash tests/autopilot/test-loop-sh.sh"
test_sweep_paths:
  - "tests/autopilot/test-loop-pr-phase.sh"
  - "tests/autopilot/test-loop-sh.sh"
---

# autopilot:loop PR/Monitor lifecycle 종단 자동화

## 무엇을 만들 것인가

autopilot:loop 스킬이 task DONE 이후의 PR/Monitor lifecycle을 종단까지 하나의 자동 파이프라인으로 수행하도록 강화한다. 사용자는 리뷰 단계·cleanup 승인에만 개입하고, 나머지 단계는 자율 수행된다.

통합되는 단계는 다음 다섯이다.

1. PR 자동 생성을 default 동작으로 전환한다. 기존 PR 비활성화를 사용하던 호출자는 명시적 opt-out 수단으로 하위 호환이 유지된다.
2. PR 생성 직전에 PR base branch로부터 rebase를 수행해 target 변경분을 흡수한다.
3. rebase 또는 머지 과정에서 충돌이 발생하면 1회 자동 해결을 시도하고, 실패 시 명시적으로 사용자에게 알린다.
4. PR 자동 모니터링이 check 완료(success/failure)에도 리뷰·완료 상태로 전이되지 않은 stuck 패턴을 감지하면 check를 재트리거하며, 상한 내에서만 재시도한다.
5. PR이 merged 또는 closed 상태로 전이하면 worktree·feat 브랜치 cleanup 여부를 사용자에게 명시적으로 확인하고, 승인 없이는 삭제하지 않는다.

## 수용 기준 (EARS)

- AC1 (Event-driven): task가 DONE 상태로 종결될 때, 시스템은 별도 opt-in 플래그 없이 PR 생성 단계를 default로 수행한다.
- AC2 (Optional): 사용자가 PR 자동 생성 opt-out 플래그(`--no-pr`)를 지정한 경우, 시스템은 PR 생성 단계를 건너뛴다.
- AC3 (Event-driven): PR 생성을 수행할 때, 시스템은 그 직전에 PR base branch(default `main`)로부터 rebase를 수행한 뒤 PR을 생성한다.
- AC4 (Unwanted): rebase 또는 머지 중 충돌이 발생하면, 시스템은 1회의 자동 해결을 시도하고, 그 시도가 실패한 경우 진행을 중단하고 사용자에게 명시적으로 알린다.
- AC5 (Event-driven): PR check가 success 또는 failure로 완료됐으나 PR 상태가 review·done이 아닌 stuck 상태를 Monitor가 감지할 때, 시스템은 최대 3회 이내에서 check를 재트리거하며, 상한에 도달하면 사용자에게 알린다.
- AC6 (Event-driven): PR이 merged 또는 closed 상태로 전이할 때, 시스템은 worktree·feat 브랜치 cleanup 여부를 사용자에게 명시적으로 확인하고, 명시적 승인이 없는 경우 어떤 항목도 자동 삭제하지 않는다.

## 범위

포함:
- `plugins/autopilot/skills/loop/SKILL.md`
- `plugins/autopilot/skills/loop/references/` 하위에서 PR/Monitor lifecycle을 다루는 파일 (예: `pr-phase.sh`, `operational-guide.md`, `constitution.md`)
- `plugins/autopilot/skills/loop/references/loop.sh` (현 위치)
- `tests/autopilot/test-loop-pr-phase.sh` · `tests/autopilot/test-loop-sh.sh` 의 회귀·신규 시나리오 확장

비-목표 / 제외:
- autopilot:dispatch · autopilot:spec · autopilot:prd · 다른 스킬 변경
- 프로젝트 루트의 `rules/`, `milestones/`, `CLAUDE.md` 수정
- `gh` 외 PR 생성 백엔드 도입
- 충돌 자동 해결 다회 재시도 · 머지 전략 학습·고도화
- PR base branch override 설정 인터페이스 신규 설계 (default `main` 또는 기존 설정 경로를 그대로 사용)
- Monitor stuck 감지 이외 상태의 일반 PR 상태 추론 재설계

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```
bash tests/autopilot/test-loop-pr-phase.sh && bash tests/autopilot/test-loop-sh.sh
```

최종적으로 위 명령이 0 exit으로 통과해야 한다. AC1이 기존 시나리오의 가정(예: `request_review` 키 부재 시 PR skip)을 뒤집기 때문에 양 테스트 파일은 `test_sweep_paths` 화이트리스트에 선언되어 있다 — 합법적 재작성(시나리오 의미 갱신)과 새 시나리오(AC1–AC6 default·opt-out·rebase·conflict·retrigger·cleanup) 추가가 모두 허용된다. `gh`·`git push` 등 외부 호출은 테스트 내 stub binary로 격리되어 실제 네트워크·원격 접근은 발생하지 않는다 (기존 컨벤션 유지).

## 제약

- PR 생성 default 전환 시 기존 PR 비활성화 호출자는 명시적 opt-out 플래그 `--no-pr`로 동일 동작을 재현할 수 있어야 한다.
- rebase target은 PR base branch이며, 명시적 설정이 없으면 `main`을 default로 사용한다. autopilot:spec이 feat 브랜치를 `main`에서 분기하는 결정과 일관되어야 한다.
- 충돌 자동 해결은 최대 1회 시도. 실패 시 재시도 없이 좌절·사용자 알림.
- Monitor check 재트리거 상한은 default 3회. 상한 도달 시 사용자 알림.
- cleanup은 제안·확인만 제공하며, AskUserQuestion 명시 승인 없이는 worktree·브랜치를 삭제하지 않는다.
- 외부 호출(`gh`·`git push`)은 테스트에서 stub binary로 격리되어 실제 네트워크·원격 접근에 의존하지 않는다 (기존 컨벤션).

## 위험

- 충돌 자동 해결 시도가 conflict marker의 의도를 잘못 해석해 코드를 손상시킬 수 있다. 입력 제약으로 "1회 시도 후 좌절"을 보존해 활동 시간·포함 범위를 제한하고, 실패 경로를 명확하게 사용자로 위임한다.
- check 재트리거 로직이 무한 루프를 형성할 위험 — 상한 3회로 고정하고, 상한 도달 로그가 명시적으로 사용자에게 노출되게 한다.
- PR 자동 생성 default 전환이 기존 워크플로를 쓰는 호출자·CI 등을 안 보이게 깨트릴 수 있다. `--no-pr` opt-out으로 하위 호환을 보장하고, 회귀 테스트에 opt-out 사용 시나리오를 포함한다.
- rebase 자동화가 PR diff 범위를 의도치 않게 확장해 리뷰어 경험을 해칠 위험. base branch fast-forward 조건을 명시적으로 검증하고 실패 시 충돌 경로로 위임한다.
