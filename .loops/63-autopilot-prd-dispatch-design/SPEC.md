---
scope:
  include:
    - "plugins/autopilot/skills/prd/**"
    - "plugins/autopilot/skills/dispatch/**"
    - "plugins/autopilot/skills/loop/references/loop.sh"
    - "plugins/autopilot/skills/loop/SKILL.md"
    - "plugins/autopilot/.claude-plugin/plugin.json"
    - "tests/autopilot/**"
  exclude:
    - rules/**
    - .loops/**
    - CLAUDE.md
    - docs/superpowers/**
verify: "for t in tests/autopilot/test-*.sh; do bash \"$t\" || exit 1; done"
---

# autopilot:prd · dispatch 다중 task 자율 분해·실행 스킬 구현

설계 문서: `docs/superpowers/specs/2026-05-11-autopilot-prd-dispatch-design.md` (issue #63 산출).

## 무엇을 만들 것인가

autopilot 플러그인에 multi-task scope를 지원하는 두 sibling 스킬을 추가하고, 단일 task 저장 구조를 milestone 단위로 통일한다. 외부 셸 ralph-loop 표준은 변경하지 않으며, 기존 `spec`·`loop` 스킬의 동작 의미는 그대로 유지한다.

- **prd 스킬** — PRD/design 문서를 대화형 9-step으로 작성. spec과 동일한 단계 골격이되 출력은 자유 산문 PRD. `--import <path>`·`--resume` 모드 포함.
- **dispatch 스킬** — 검증된 PRD를 자동 분해해 child SPEC들을 spec 위임으로 생성하고, DAG(wave) 단위로 loop을 병렬 실행. `start/status/stop/list/cleanup/logs/resume` 서브커맨드로 ops도 책임 (별도 milestone 스킬 미도입).
- **저장 구조 통일** — `milestones/<m>/{prd,dispatch,loops}/` 단일 트리. ad-hoc 단일 task는 `regular` milestone(catch-all)에 흡수.
- **task-id 규칙** — 항상 `<milestone>/<task>` 2-컴포넌트. 단일 컴포넌트 입력 시 `regular/` 자동 prefix.
- **loop.sh 변경** — SPEC 경로를 `milestones/<m>/loops/<c>/SPEC.md` 단일로 변경 (legacy `.loops/<id>/` 경로는 v0.2 cutover로 제거).

자기완결성은 4중 가드(prd step 9, prd --import 자체검토, dispatch 입구, spec step 9)로 확보. `[ASSUMED: ... because ...]` 패턴은 도입하지 않는다.

## 수용 기준 (EARS)

**prd 스킬**

- 사용자가 `Skill(skill="prd", args="<milestone-id>")`을 호출하면, 시스템은 9-step 대화 흐름을 실행하고 `milestones/<milestone-id>/prd/PRD.md`를 작성한다.
- 사용자가 `prd <id> --import <path>`를 호출하면, 시스템은 외부 PRD를 복사하고 step 7 자체 검토만 실행해 부족 부분을 spec의 클래리피케이션 마커 구문(여는 대괄호 + `NEEDS CLARIFICATION:` + 질문 + 닫는 대괄호)으로 표시한 후 `prd <id> --resume`을 안내한다.
- 미해결 마커가 남은 PRD에 대해 사용자가 `prd <id> --resume`을 호출하면, 시스템은 그 마커들에 묶인 명확화 라운드와 섹션 승인만 다시 연다.
- `prd` step 9가 PRD 본문에 남은 클래리피케이션 마커를 감지하면, 시스템은 정상 종료를 차단하고 `--resume`을 지시한다.
- 대상 `milestones/<id>/prd/` 디렉터리에 이미 `PRD.md`가 있으면, 시스템은 사용자에게 `(a) 다른 milestone-id`, `(b) --resume`, `(c) 백업 후 새로 작성` 중 하나를 묻는다.

**dispatch 스킬 (분해 단계)**

- 사용자가 `Skill(skill="dispatch", args="<m>")` (또는 `dispatch start <m>`)를 호출하면, 시스템은 `milestones/<m>/prd/PRD.md`가 존재하고 마커 0개임을 요구하며, 미충족 시 abort하고 `prd` 호출을 안내한다.
- 입력 PRD가 검증을 통과하면, 시스템은 세 조건(단일 컨텍스트 윈도우 fit·테스트 폐쇄성·파일 격리성)을 동시에 충족하는 분해 후보를 산출한다.
- 분해 결과가 하드 캡(1차 분해 ≤ 8 단위, 재귀 깊이 ≤ 2, 총 ≤ 20 단위)을 초과하면, 시스템은 abort하고 PRD 자체 분해를 권고한다.
- 토포 정렬 중 의존성 cycle이 감지되면, 시스템은 abort하고 cycle을 보고한다.
- 분해 plan이 계산되면, 시스템은 wave별 표를 제시하고 사용자에게 `(a) 승인`, `(b) 피드백으로 수정`, `(c) 취소` 중 하나를 묻는다.
- 사용자가 분해 plan을 승인하면, 시스템은 `milestones/<m>/dispatch/DAG.md`를 생성해 단위·의존성·wave 순서를 기록한다.

**dispatch 스킬 (spec 위임)**

- 승인된 DAG의 각 단위에 대해, 시스템은 PRD 본문과 단위 행을 컨텍스트로 전달하며 `Skill(skill="spec", args="<m>/<c>")`을 호출한다.
- 모든 `spec` 호출이 완료되면, 시스템은 최종 확인 표(SPEC 경로·verify 명령·의존성)를 제시하고 실행 전 사용자 승인을 요구한다.

**dispatch 스킬 (실행 단계)**

- wave 실행이 시작되면, 시스템은 그 wave 내 모든 단위에 대해 `loop start <m>/<c>`를 병렬(백그라운드)로 호출한다.
- wave가 진행되는 동안, 시스템은 각 단위 워크트리의 `DONE` 또는 `.loop/ESCALATION.md` sentinel 파일을 내부 상태 파싱 없이 감시한다.
- 어떤 단위에서든 `.loop/ESCALATION.md`가 출현하면, 시스템은 같은 wave 내 다른 진행 단위들에 `loop stop`을 호출하고 결과를 `milestones/<m>/dispatch/DISPATCH_LOG.md`에 기록한 뒤 escalation 카테고리와 본문을 사용자에게 제시하고 다음 wave 시작을 거부한다.
- wave 내 모든 단위가 `DONE`을 보고하면, 시스템은 wave 결과를 `DISPATCH_LOG.md`에 추가하고 다음 wave로 진행한다.
- 모든 wave가 성공적으로 완료되면, 시스템은 최종 요약 표를 출력한다.

**dispatch 스킬 (ops 서브커맨드)**

- 사용자가 `dispatch list`를 호출하면, 시스템은 모든 milestone(`regular` 포함)과 요약 상태를 나열한다.
- 사용자가 `dispatch status <m>`을 호출하면, 시스템은 PRD 존재·DAG 상태·단위별 loop 상태를 보고한다. `regular`의 경우 자식 loop 상태만 보고한다.
- 사용자가 `dispatch stop <m>`을 호출하면, 시스템은 `<m>`의 진행 중인 모든 자식에 `loop stop`을 호출하고 행동을 `DISPATCH_LOG.md`에 추가한다.
- 사용자가 `dispatch resume <m>`을 호출하면, 시스템은 현재 상태(분해 중 vs 실행 중)를 감지하고 올바른 단계에서 이어간다.
- 사용자가 `dispatch cleanup [<m>]`을 호출하면, 시스템은 완료된 워크트리와 자식 loop 상태를 제거하되 PRD와 DAG는 보존한다.
- 사용자가 `dispatch logs <m>`을 호출하면, 시스템은 `DISPATCH_LOG.md`를 stdout에 출력한다.

**loop.sh 변경**

- `loop.sh`가 단일 컴포넌트 task-id를 해석하면, 시스템은 `regular/`를 prefix해 정규화한다.
- `loop.sh`가 SPEC 파일을 조회할 때, 시스템은 `milestones/<m>/loops/<c>/SPEC.md`만 읽는다(legacy fallback 없음).
- 해석된 SPEC 경로가 존재하지 않으면, 시스템은 명확한 에러로 abort한다.
- 워크트리 경로 스킴(`<project>-loops/<task-id>/`)은 변경하지 않는다.

**저장 구조와 자기완결성**

- `regular` milestone은 ad-hoc 단일 task의 catch-all로 동작하며, `dispatch start regular`는 PRD 부재로 거부된다.
- `dispatch`가 클래리피케이션 마커가 남은 PRD를 읽으면, 시스템은 abort하고 사용자에게 `prd --resume` 실행을 안내한다.

## 범위

포함:
- `plugins/autopilot/skills/prd/` — SKILL.md + `references/{prd-template.md,self-review.md}`
- `plugins/autopilot/skills/dispatch/` — SKILL.md + 필요한 references
- `plugins/autopilot/skills/loop/references/loop.sh` — task-id 정규화 + SPEC 경로 단일화
- `plugins/autopilot/skills/loop/SKILL.md` — 경로 변경에 따른 참조 갱신 (필요 시)
- `plugins/autopilot/.claude-plugin/plugin.json` — version bump (0.1.0 → 0.2.0)
- `tests/autopilot/test-prd-skill.sh` (신규)
- `tests/autopilot/test-dispatch-skill.sh` (신규)
- `tests/autopilot/test-dispatch-integration.sh` (신규)
- `tests/autopilot/test-loop-sh.sh` — 경로 단일화 분기 테스트 갱신
- `tests/autopilot/test-skill-install.sh` — prd·dispatch install 검증 추가

비-목표 / 제외:
- legacy `.loops/<id>/SPEC.md` fallback·자동 마이그레이션·경고 (cutover로 처리)
- `[ASSUMED: ... because ...]` 패턴
- 3+ depth nested task-id
- gh issue·branch 자동 생성 (프로젝트 룰 영역)
- Devin식 dynamic re-planning (재계획은 사용자 책임)
- 단계별 게이트 외의 자율도(완전 무인·heuristic-confidence)
- design 문서 본문 수정 (`docs/superpowers/**`는 scope.exclude)

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```
for t in tests/autopilot/test-*.sh; do bash "$t" || exit 1; done
```

각 테스트는 자체 시나리오에 대해 명시적 assert를 가져야 하며, 통과 = "0개 fail"임을 보장한다.

## 제약

- **bash 3.2 호환** — macOS 기본 bash가 3.2. 4.x 전용 문법(`declare -A`, `[[ =~ ]]` 일부) 금지.
- **외부 셸 ralph-loop 표준 유지** — in-process Stop 훅, Anthropic 공식 ralph-wiggum 패턴 도입 금지. 모든 자율 실행은 `while + claude -p` 외부 루프 모델로.
- **claude --bare 사용 불가** — OAuth 환경(API key 미보유). 격리는 scratch cwd + `--add-dir` + `--system-prompt-file` 조합으로.
- **헌법 정합** — `references/constitution.md`의 Iron Laws·제1 원칙·scope.include·테스트 약화 게이트 모두 준수. 새 스킬도 동일 헌법 인용.
- **단일 책임 원칙** — prd는 PRD 작성만, dispatch는 분해+실행+ops만, spec/loop은 변경 없음 (loop.sh 경로 분기만 예외). spec을 brainstorming 같은 다른 영역으로 확장하지 않음 (해당 안건은 issue #65로 분리).
- **외부 셸 ralph-loop의 동시 실행 격리** — wave 병렬에서 여러 child loop이 동시 실행될 때 워크트리·lock 모두 기존 loop.sh가 제공. dispatch는 sentinel 파일 존재 감시만.

## 위험

- **자기 자신을 수정하는 자율 실행** — loop이 autopilot 자체를 빌드. `scope.exclude`에서 `.loops/**`·`CLAUDE.md`·`rules/**`·`docs/superpowers/**`를 빼더라도, `plugins/autopilot/skills/loop/`를 수정하는 도중 loop이 자기 동작에 영향을 줄 수 있음. 안전망: 변경 후 verify가 fresh 통과해야만 DONE.
- **single-SPEC에 multi-task 분량** — 본 SPEC은 본래 dispatch가 분해해야 할 규모. dispatch가 부재한 상태의 bootstrap. iter 30·120분 캡 초과 시 ESCALATION으로 자연 정지.
- **sentinel watch polling 비용** — 새 dispatch 코드가 파일 존재 폴링을 한다. 짧은 sleep·timeout 가드 없으면 CPU·시간 낭비. 구현 시 `inotify` 대신 `sleep 2s + test -e` 정도로 단순 유지하되 timeout 부재 위험 검토.
- **bash 3.2 + 병렬 wave** — 백그라운드 프로세스 관리(`jobs`·`wait`·PID 추적)를 3.2 문법으로 작성해야 함. 4.x associative array 못 씀.
- **테스트 면적 폭증** — prd·dispatch·loop.sh·통합 4종 테스트가 모두 새로 들어가므로 verify 시간이 늘어남. RED 단계에서 의도한 fail이 다른 unrelated test 변경으로 위장될 위험. 각 테스트는 독립 디렉터리에서 실행.
- **자기완결성 4중 가드의 우회 가능성** — 마커 패턴이 spec의 클래리피케이션 마커 형식과 정확히 일치해야 차단됨. 변형(예: 다른 brackets·동의어 영문구·다국어 표기)이 들어가면 통과. 가드 구현 시 변형까지 잡는 정규식 필요.
