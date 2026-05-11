# 작업 노트

큐레이션된 학습. 다음 이터가 같은 막다른 길을 다시 가지 않게 하는 신호.

## 확정된 사실 (재발견 비용 절약)

### `ensure_loops_setup`이 chore commit을 만들 때 worktree iter 1이 .gitignore를 worker 변경으로 오인

`ensure_loops_setup`이 `.gitignore`에 새 패턴을 추가하고 main 브랜치에 chore commit을 만들면, 직후 생성되는 worktree 브랜치의 HEAD = chore commit, HEAD~1 = baseline. iter 1의 `diff_vs_scope`가 `git diff --name-only HEAD~1 HEAD`를 읽으면 `.gitignore`가 "이번 이터 변경"으로 보여 scope 위반으로 halt한다.

**해결**: `git worktree add` 직후 worktree에서 `git commit --allow-empty -m "chore: autopilot worktree baseline"` 을 한 번 실행해 HEAD를 한 단계 진행시킨다. 이렇게 하면 iter 1의 HEAD~1..HEAD diff가 (empty baseline) → 없음으로 깨끗하게 격리된다.

### `git commit -- <pathspec>`은 staged index를 건드리지 않고 명시 경로만 commit

사용자의 in-flight staged 변경이 있어도 `git commit -m "..." -- .gitignore`는 .gitignore만 commit하고 다른 staged 변경은 그대로 둔다. `ensure_loops_setup`이 .gitignore 단독 chore commit으로 격리할 때 안전.

### 워크트리를 메인 레포 안에 두려면 `.gitignore` 무시 필수

`git worktree add <project>/milestones/<m>/loops/<c>/.worktree`는 정상 동작하지만, 메인 레포 입장에서 그 디렉터리는 untracked. `.gitignore`로 `milestones/**/loops/**/.worktree/` 무시 처리 안 하면 메인 트리에서 워크트리 파일이 untracked로 보이고 IDE·git 명령이 혼란을 겪는다.

## 실패한 접근 (재시도 금지)

(없음)

## 미해결 가설

(없음)

## 작동하는 패턴

### MAX_CONCURRENT lock 카운트 (분산 lock 환경)

이전: `find $LOCK_DIR -name "*.lock" -type f | wc -l` (중앙집중 lock 디렉터리).

새: `find $PROJECT_ROOT/milestones -mindepth 4 -maxdepth 4 -type f -name '.lock' | wc -l`. `milestones/<m>/loops/<c>/.lock` 정확히 depth 4. minor depth 제약으로 다른 우연한 `.lock` 매칭을 피한다.

### cleanup path guard (얇고 충분한)

복잡한 realpath 비교 없이 다음 3조건으로 충분:
1. `[[ -n "$WT" ]]`
2. `[[ "$WT" == "$PROJECT_ROOT"/* ]]`
3. `case "$WT" in */milestones/*/loops/*/.worktree) ;; *) die ;; esac`

realpath 미설치 환경 의존 없음, 변수 누락·외부 경로·메인 레포 자체 손상 방지에 충분.
