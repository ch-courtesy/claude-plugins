# 작업 계획

`.loops/`(locks)와 외부 sibling 워크트리를 모두 메인 레포 내부 `milestones/<m>/loops/<c>/` 단일 트리로 통합한다. 단일 task는 `<m>=regular`로 정규화. `.gitignore`가 새 경로를 자동 무시하도록 첫 호출 setup을 갱신.

## 마일스톤

### M1: 경로 정의 통합 — loop.sh `compute_paths`
- **정의**: `compute_paths`가 `WT`/`LOCK_DIR`/`LOCK_FILE`을 새 nested 경로로 계산. 모든 호출 경로(start/status/stop/cleanup/logs)가 일관된 값 사용.
- **검증**: 새 워크트리·lock 경로 단위 테스트 (test-loop-sh.sh TEST 3·4·5·48·49) PASS.
- **영향 영역**: `plugins/autopilot/skills/loop/references/loop.sh`의 `compute_paths` (WT, LOCK_DIR, LOCK_FILE), `cmd_status`의 lock path 계산.
- [x] 완료

### M2: `.gitignore` 자동 관리 — 새 패턴 add + 기존 `.loops/locks/` 제거 + 단일 chore commit
- **정의**: `ensure_loops_setup`이 `milestones/**/loops/**/.worktree/`·`milestones/**/loops/**/.lock` 라인을 idempotent하게 추가하고 기존 `.loops/locks/` 라인이 있으면 제거. 변경 시 `.gitignore` 단일 파일 chore commit으로 격리. 갱신·commit 실패 시 die.
- **검증**: TEST 34·35·36 PASS — 새 패턴 추가·legacy 제거·idempotent·newline 안전 + 단독 chore commit 검사.
- **영향 영역**: loop.sh `ensure_loops_setup`.
- [x] 완료

### M3: cleanup path guard — 워크트리 경로 prefix 검사
- **정의**: `cmd_cleanup`이 워크트리 제거 직전 `WT`가 (a) 비어있지 않고 (b) `PROJECT_ROOT/` prefix이고 (c) `*/milestones/*/loops/*/.worktree` 패턴인지 검증. 미충족 시 die.
- **검증**: 기존 cleanup 시나리오 (TEST 8/14/15/etc.) 통과 + path guard 안전성 코드 리뷰.
- **영향 영역**: loop.sh `cmd_cleanup`, dispatch.sh `cmd_cleanup`.
- [x] 완료

### M4: dispatch.sh 경로 일원화 — child_wt_path / child_lock_path / cleanup 순회
- **정의**: `child_wt_path`·`child_lock_path`가 새 nested 경로 반환. `cmd_status`/`cmd_stop`/`cmd_cleanup`/`cmd_list`가 `WT_BASE/<m>/`가 아닌 `milestones/<m>/loops/`를 순회.
- **검증**: test-dispatch-integration.sh 13개 테스트 모두 PASS.
- **영향 영역**: dispatch.sh 전체.
- [x] 완료

### M5: spec 스킬 SPEC 저장 경로 갱신
- **정의**: spec SKILL.md의 사전 검사·SPEC 저장·`--resume` 경로·step 7 mkdir·step 9 안내를 `milestones/<m>/loops/<c>/`로. spec-template.md의 `scope.exclude` `.loops/**` 제거.
- **검증**: test-skill-install.sh의 spec 스킬 frontmatter 검사 PASS + 시각 검토.
- **영향 영역**: `plugins/autopilot/skills/spec/SKILL.md`, `plugins/autopilot/skills/spec/references/spec-template.md`.
- [x] 완료

### M6: 운영 문서 동기화
- **정의**: loop SKILL.md, operational-guide.md, troubleshooting.md, constitution.md §2 워크트리 위치, dispatch SKILL.md의 `.loops/`·외부 sibling 관련 문구·예시·디렉터리 다이어그램 갱신. troubleshooting.md에 v0.1 → v0.2 마이그레이션 가이드 추가.
- **검증**: 시각 검토 + grep `.loops/` 잔존 — 의도된 cutover·migration 설명만 남았는지 확인.
- **영향 영역**: 위 문서들.
- [x] 완료

### M7: 테스트 sweep (`tests/autopilot/**`)
- **정의**: 모든 lock·WT 경로 expectation을 새 nested 경로로 일괄 변경. `.loops/locks/` 검사·setup 제거. `.gitignore` 패턴 검사 갱신.
- **검증**: verify 명령 4종 모두 0 exit.
- **영향 영역**: test-loop-sh.sh·test-dispatch-integration.sh·test-skill-install.sh.
- [x] 완료

## 의존 관계

- M7 (테스트 갱신, RED) → M1·M2·M3·M4 (구현, GREEN) 순차 ✓
- M5·M6 (문서) 병렬 가능 ✓
- M1·M4는 같은 PR로(경로 일관성) ✓

## 완료 판정 (헌법 §3.4·§3.5)

- [x] 모든 마일스톤 체크
- [x] 4-Level Verifier 통과 — Existence·Substantive·Wired·Runtime
- [x] Self-Review 4축 통과 — Completeness·Quality·Discipline·Testing
- [x] verify 명령 0 exit (test-loop-sh + test-dispatch-skill + test-dispatch-integration + test-skill-install 모두 PASS)
- [x] 자기 분류 누적에 `fix:symptom` 연속 없음 (단일 feat commit)
