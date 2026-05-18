---
scope:
  include: ["plugins/autopilot/skills/loop/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh"
---

# Push sync policy: rebase locally, merge on remote

## 무엇을 만들 것인가

loop의 자율 push 흐름이 base 동기화 단계에서 *동기화 시점에 자기 브랜치가 원격에 이미 존재하는지*를 검사해 두 경로로 분기한다. 원격 트래킹 브랜치가 없으면 rebase로 base 위에 자기 commit들을 재배치(history 재작성)하고, 이미 존재하면 merge로 base 변경분만 흡수해 자기 commit의 SHA를 보존한다. 어떤 경로에서도 force push는 도입하지 않으며, 분기 자체는 단일 sync helper에 위치해 PR 생성 직전·review-fix iter의 모든 push 직전 호출 지점에서 동일하게 재사용된다. 동기화 중 충돌이 발생하면 기존 sync 모듈의 1회 자동 해소 절차를 그대로 사용하고, 실패 시 보수적 좌절로 복구한다.

## 수용 기준 (EARS)

- **AC1** (Event-driven): loop이 push 직전 base 동기화를 수행할 때, 시스템은 동기화 시점의 원격 트래킹 브랜치 존재 여부를 판정해 rebase 경로 또는 merge 경로로 분기한다.
- **AC2** (Optional): 원격 트래킹 브랜치가 부재인 경우, 시스템은 자기 브랜치를 base 위로 rebase로 재배치한다.
- **AC3** (Optional): 원격 트래킹 브랜치가 이미 존재하는 경우, 시스템은 base 변경분을 자기 브랜치에 merge로 흡수해 자기 commit의 SHA를 보존한다.
- **AC4** (Ubiquitous): 시스템은 push 경로에서 force push(`--force`·`--force-with-lease` 포함)를 사용하지 않는다.
- **AC5** (Event-driven): 동기화 중 충돌이 발생할 때, 시스템은 기존 sync 모듈의 자동 해소 절차를 1회 시도한다.
- **AC6** (Unwanted): 자동 해소 1회 시도 후에도 충돌이 남아 있으면, 시스템은 원래 워크트리 상태로 복구하고 비-zero exit으로 종료한다.
- **AC7** (Ubiquitous): PR 생성 직전·review-fix iter의 모든 push 직전 동기화는 동일한 sync helper를 통해 수행된다 (각 phase 안의 직접 `git rebase`·`git merge` 라인 부재).

## 범위

포함:

- `plugins/autopilot/skills/loop/references/rebase-phase.sh` — 분기 도입 (helper 본체)
- `plugins/autopilot/skills/loop/references/pr-phase.sh` — inline rebase 블록 제거 후 helper 호출로 통일
- `plugins/autopilot/skills/loop/references/review-fix-phase.sh` — 이미 helper 호출 중이므로 검증만 (코드 변경 없을 수 있음)
- `plugins/autopilot/skills/loop/SKILL.md` — 정책 설명 갱신
- `plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh` — merge 경로 케이스 추가

비-목표 / 제외:

- helper 파일명 변경 (rename — 환경 변수·문서 파급 회피)
- force push · force-with-lease 도입
- `cleanup-phase.sh`의 `git push --delete` (push sync 경로 아님)
- 일반 워크플로(CLAUDE.md·git hooks)의 push 정책
- 다른 워커가 같은 브랜치에 push한 외부 mutation 흡수 (별도 issue 가능성)

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh
```

SPEC 구현 중 추가될 케이스:

- 원격 트래킹 부재 fixture → rebase 경로 수행 확인 (AC2)
- 원격 트래킹 존재 fixture → merge commit 생성·자기 commit SHA 보존 확인 (AC3)
- force 관련 플래그 grep → push 경로에 부재 확인 (AC4)
- 충돌 fixture + 해소 실패 → 워크트리 복구 + 비-zero exit (AC6)
- pr-phase·review-fix-phase grep → 직접 `git rebase`·`git merge` 라인 부재 (AC7)

## 제약

- 기존 sync 모듈의 자동 해소 절차는 `AUTOPILOT_REBASE_ALLOWED_TOOLS` 환경 변수에 의존 (이름은 REBASE로 남으나 rename은 범위 제외).
- merge 충돌 자동 해소 로직은 `MERGE_HEAD` 존재 상태를 처리해야 하며 rebase 시의 `REBASE_HEAD` 상태와 분별되어 동작한다.
- 분기 검사 `git ls-remote --heads origin <branch>`는 원격 접근 권한에 의존 (기존 push와 동일 권한이므로 새로운 제약 아님).
- `git symbolic-ref --quiet refs/remotes/origin/HEAD` 의존 (기존 fallback `gh repo view` 그대로 유지).
- bash 4 이상 (loop.sh 기존 가정과 동일).

## 위험

- merge 경로에서 `Merge origin/<base> into ...` commit이 PR `## Commits` 섹션에 노출됨 (사용자 합의 — 상위 설정이 squash-merge면 최종 history에는 미포함).
- review-fix iter는 매 회 동기화를 수행하므로, base 변화 없는 경우에도 merge 경로에서 불필요 commit이 생성되지 않도록 (`--ff-only` 사전 시도 등) 주의 필요.
- 다른 워커가 같은 PR 브랜치에 commit을 추가한 경우(외부 mutation)는 현 SPEC 범위 밖 — 현재 동작대로는 `git push origin <branch>`가 non-FF로 거부될 수 있으므로 별도 처리 필요 (이슈 별도 제기 권장).
- helper 이름이 `rebase-phase.sh` 그대로 유지되어 의미·이름 불일치 — 향후 독자가 혼란에 빠질 수 있음 (rename 없이 내부 주석·SKILL.md로 의도 명시).
