---
scope:
  include: ["plugins/autopilot/skills/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh && ! grep -rn -F 'touch DONE' plugins/autopilot/skills && ! grep -rnE -- '-f.*/DONE' plugins/autopilot/skills/loop/references plugins/autopilot/skills/dispatch/references && ! grep -F '├── DONE' plugins/autopilot/skills/loop/references/operational-guide.md"
---

# DONE sentinel 제거 — loop·dispatch 라벨 단일 경로 통합

## 무엇을 만들 것인가

loop·dispatch 두 서브시스템이 child task의 완료 신호를 감지하는 방식을 GitHub Issue 라벨 단일 경로로 통합하고, 기존 sentinel `DONE` 파일에 대한 잔존 참조(코드·문서·테스트 mock·운영 가이드 트리)를 제거합니다. 완료 검출의 단일 출처를 라벨 한 곳으로 모아 이중 신호와 dead code를 없애고, loop·dispatch가 공용 helper를 공유해 중복을 피합니다.

현재 상태: `loop.sh` 는 이미 SPEC 134/150 마이그레이션 이후 `task_status_is_done`(`LOOP_DONE_LABEL` 라벨 존재 검사) 단일 의존으로 완료를 판정하지만, `dispatch.sh` 는 여전히 `[[ -f "$wt/DONE" ]]` 파일 존재 검사를 wave 단위 sentinel polling 의 첫 키로 사용합니다. 어떤 코드 경로도 `DONE` 파일을 실제로 생성하지 않으므로 dispatch 의 검사는 dead code 입니다. 본 SPEC 은 dispatch 의 검사를 라벨 기반으로 전환하고, 두 서브시스템 양쪽의 잔존 텍스트·트리·cleanup 패턴·테스트 mock 을 일괄 정리합니다.

## 수용 기준 (EARS)

- **AC1** (Ubiquitous): 시스템은 child task 의 완료를 GitHub Issue 라벨(`LOOP_DONE_LABEL`, 기본값 `loop:done`) 존재 여부 단일 의존으로 판정한다.
- **AC2** (Event-driven): wave 내 모든 child issue 에 완료 라벨이 부착된 상태에서 dispatch `watch_wave` 가 실행되면, dispatch 는 exit 100 으로 종료한다.
- **AC3** (Unwanted): 변경 후 코드 트리에서 `touch DONE` 또는 `-f .*/DONE` 패턴이 `plugins/autopilot/skills` 하위에 남아 있으면 verify 가 실패한다.
- **AC4** (Unwanted): `plugins/autopilot/skills/loop/references/operational-guide.md` 의 워크트리 트리 다이어그램에 `├── DONE` 라인이 존재하면 verify 가 실패한다.
- **AC5** (Event-driven): 변경 후 `test-spec-loop-contract.sh` 와 AC3·AC4 grep 검사를 묶은 verify 명령이 0 exit 으로 통과한다.
- **AC6** (Ubiquitous): `loop:done` 라벨을 확인하는 helper(`task_status_is_done`·`task_label_present`) 는 loop.sh 와 dispatch.sh 양쪽에서 호출 가능하며 동일한 라벨 검출 로직을 공유한다(sourcing 또는 helper 추출 — 구현 방식 자율).

## 범위

포함:

- `plugins/autopilot/skills/dispatch/references/dispatch.sh` — `child_state` 의 DONE 파일 검사를 라벨 기반 검사로 교체, cleanup·watch_wave 의 DONE 참조 제거·재서술
- `plugins/autopilot/skills/loop/references/loop.sh` — gitignore-like 필터의 `DONE` 항목(L645·649), cleanup 패턴 배열의 `"DONE"`(L1091), 로그 메시지 `DONE 신호 감지`(L1115), cleanup 도움말 텍스트(L1602) 등 stale 참조 정리·재서술
- `plugins/autopilot/skills/loop/references/operational-guide.md` — 워크트리 트리 다이어그램의 `├── DONE` 라인 제거 + `DONE 후 정리`·`DONE 파일 생성`·`DONE 후 머지` 등 stale 표현을 라벨 기준으로 재서술
- `plugins/autopilot/skills/loop/SKILL.md` — `Bash(rm */DONE)` 권한(L20), `DONE 이후 PR phase`·`DONE 이후 PR 리뷰 자동 fix` 표현 재정리
- `plugins/autopilot/skills/dispatch/SKILL.md` — sentinel watch 설명에서 `DONE/ESCALATION` 표현을 라벨·escalation 분리 표현으로 재서술
- `plugins/autopilot/skills/spec/SKILL.md` — `Bash(rm */DONE)` 권한(L58) 제거
- `plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh` — `touch DONE` mock(L66) 제거, 주석(L15·L60·L73) 재서술, mock 셋업이 `loop:done` 라벨 부착 경로로 완료를 신호하도록 수정

비-목표 / 제외:

- 다른 sentinel 메커니즘 (FAIL·`.loop/ESCALATION.md`·DONE_WITH_CONCERNS) 변경 — DONE 외 sentinel 은 그대로 유지
- `loop:done` 라벨 메커니즘·이름·`LOOP_DONE_LABEL` 환경 변수 자체 변경
- `review-fix-phase.sh` 의 worker prompt 내 `"After working, output 'DONE' on the last line."` 텍스트 신호 — 이는 파일 sentinel 과 무관한 stdout 텍스트 컨벤션
- 폴링 cadence 자체 변경 (`WATCH_POLL_SECONDS` 기본 2s 유지, 필요 시 별도 task)

## 검증

이 명령이 0 exit 으로 끝나야 합니다:

```bash
bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh \
 && ! grep -rn -F 'touch DONE' plugins/autopilot/skills \
 && ! grep -rnE -- '-f.*/DONE' plugins/autopilot/skills/loop/references plugins/autopilot/skills/dispatch/references \
 && ! grep -F '├── DONE' plugins/autopilot/skills/loop/references/operational-guide.md
```

각 AC 매핑:

- AC1·AC6: `test-spec-loop-contract.sh` 가 mock claude → 라벨 부착 → loop.sh 가 라벨 단일 의존으로 완료 감지하는 라운드트립을 검증
- AC2: dispatch 의 wave 완료 시 exit 100 — `test-spec-loop-contract.sh` 또는 추가 dispatch 픽스처 테스트로 검증 (구현 단계에서 dispatch fixture 추가 가능)
- AC3: `! grep -F 'touch DONE'`·`! grep -E '-f.*/DONE'` 가 잔존 시 fail
- AC4: `! grep -F '├── DONE'` 가 잔존 시 fail
- AC5: 전체 명령이 0 exit

## 제약

- `gh` CLI 가 설치·인증된 상태에서 동작. `LOOP_DONE_LABEL` 기본값 `loop:done` 라벨은 이미 존재 (loop.sh `ensure_label_exists` 자동 생성 경로 유지).
- `loop.sh` 의 `task_status_is_done`·`task_label_present` helper 는 dispatch.sh 에서도 호출 가능해야 한다 — 함수 sourcing(`source loop.sh` 일부 또는 분리된 `_helpers.sh`) 또는 helper 추출 중 자유 선택. 구현은 두 스크립트가 동일 라벨 검출 로직을 공유한다는 결과만 보장.
- 슬러그·브랜치·디렉토리 컨벤션은 `autopilot:spec` step 9.5 결정적 규칙(`feat-branch-commit.md` §9.5.1)을 따른다 — 본 SPEC 디렉토리는 `milestones/regular/loops/175-done-sentinel-loop-dispatch/`, 브랜치는 `feat/175-done-sentinel-loop-dispatch`.
- bash 3.2+ 호환 유지 (macOS 기본 bash).
- 다른 sentinel(ESCALATION·FAIL) 의 파일 기반 메커니즘은 그대로 유지하며, 라벨 통합은 `loop:done` 한 신호에 한정.

## 위험

- dispatch 가 gh API 의존으로 전환되어 rate limit·네트워크 지연의 영향을 받게 됩니다. 일반 wave 크기 ≤ 10, 폴링 2s 기준 시간당 ~18,000 호출 가능 — 실측 후 필요 시 폴링 간격 조정 또는 라벨 cache 도입을 후속 task 로 분리합니다.
- helper 추출/sourcing 으로 loop·dispatch 가 공용 의존성을 갖게 되어 한 쪽 변경 시 다른 쪽 동작 검증이 필요합니다.
- 다중 영역(loop·dispatch·docs·tests)을 단일 SPEC 으로 진행 (사용자 확인됨, 2026-05-19).
- `review-fix-phase.sh` 의 worker→stdout `"DONE"` 텍스트 신호와 파일 sentinel `DONE` 을 혼동하지 않도록 주의 — 본 SPEC 범위는 후자 한정.
- 정적 grep 검증만으로는 의미적 잔존(예: `var=DONE`)을 모두 잡지 못할 수 있음 — 코드 리뷰에서 의미적 잔존을 추가로 점검.
