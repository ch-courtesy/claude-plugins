# 다음 이터에게 (HANDOFF)

## 직전 이터: 1 (완료 — DONE 후보)

## 이번에 무엇을 했는가

`.loops/`(locks)와 외부 sibling 워크트리를 메인 레포 내부 `milestones/<m>/loops/<c>/` 단일 nested 트리로 통합. 단일 task는 `<m>=regular`로 정규화. `.gitignore`가 첫 호출 setup에서 자동 정렬되고, 기존 `.loops/locks/` 라인은 제거된다. cleanup에 path guard 추가.

핵심 변경:
1. `loop.sh`
   - `compute_paths`: `WT=$LOOPS_DIR/.worktree`, `LOCK_FILE=$LOOPS_DIR/.lock`, `LOOPS_DIR=$PROJECT_ROOT/milestones/<m>/loops/<c>`. `LOOP_WORKTREE_BASE`/`WT_BASE` 제거.
   - `ensure_loops_setup`: 새 패턴 2개 add + legacy `.loops/locks/` 제거 + `git commit -- .gitignore`로 단독 chore commit 격리. 실패 시 die.
   - `acquire_lock`: MAX_CONCURRENT 카운트를 `find $PROJECT_ROOT/milestones -mindepth 4 -maxdepth 4 -name '.lock'`로.
   - `cmd_start`: 워크트리 생성 직후 `git commit --allow-empty "chore: autopilot worktree baseline"` 추가 — iter 1의 HEAD~1..HEAD diff가 부모 브랜치의 ensure_loops_setup chore commit을 worker 변경으로 오인하지 않도록 분리.
   - `cmd_status`: 각 task의 wt/lock 경로를 nested 위치에서 계산.
   - `cmd_cleanup`: WT empty/`PROJECT_ROOT` prefix/`*/milestones/*/loops/*/.worktree` 패턴 검증 (path guard).
2. `dispatch.sh`
   - `child_wt_path`/`child_lock_path` 새 nested 경로 반환. `child_archive_path` 헬퍼 추가.
   - `compute_milestone_paths`에 `LOOPS_BASE=$MILESTONE_DIR/loops`. `WT_BASE`·`LOCK_DIR` 제거.
   - `cmd_status`/`cmd_stop`/`cmd_list`/`cmd_cleanup`: `WT_BASE/<m>/` → `LOOPS_BASE` 또는 `<entry>/loops` 순회. cleanup에 path guard 추가.
3. spec/SKILL.md + spec-template.md: SPEC 저장 경로 `milestones/<m>/loops/<c>/`. `scope.exclude`의 `.loops/**` 제거.
4. loop/SKILL.md + operational-guide.md + troubleshooting.md + constitution.md §2 + dispatch/SKILL.md: 디렉터리 다이어그램·예시·환경변수 표 갱신. troubleshooting.md에 v0.1 → v0.2 마이그레이션 가이드 추가.
5. 테스트 4종: 워크트리·lock 경로 expectation을 nested로 일괄 변경. TEST 34는 legacy `.loops/locks/` 제거 + 단독 chore commit 검사로 갱신. TEST 35는 idempotent (HEAD 변동 없음) 검사로 강화.

## 무엇이 막혔거나 막힐 수 있는가

- 없음. 모든 verify 4종 (test-loop-sh·test-dispatch-skill·test-dispatch-integration·test-skill-install) 0 exit.

## 다음 단계 추천

- 본 이터의 DONE 후보. 이후 별 PR로 `docs/superpowers/specs/2026-05-11-autopilot-prd-dispatch-design.md` §6의 sentinel 경로 문구도 새 정책에 맞게 갱신 권장 (SPEC §비-목표에서 제외 명시).
