---
scope:
  include: ["plugins/autopilot/skills/loop/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh"
test_sweep_paths:
  - "plugins/autopilot/skills/loop/tests/**"
---

# Loop이 worktree 내부에서 호출될 때 nested worktree 생성 생략

## 무엇을 만들 것인가

loop 스킬의 `start` 서브커맨드가 호출될 때, 시스템은 호출 워킹 디렉토리가 git 저장소의 *주 작업트리(main working tree)*인지 *보조 worktree*인지 검사한다. 주 작업트리에서 호출된 경우 기존 동작을 그대로 수행해 `milestones/<m>/loops/<c>/.worktree/` nested worktree를 생성·사용한다. **보조 worktree 안에서 호출된 경우 nested worktree 생성을 생략**하고 현재 호출 cwd의 worktree를 그대로 작업 공간으로 사용한다. 이는 spec 워크플로우가 worktree 안에서 SPEC.md를 만든 직후 그 자리에서 loop start를 호출하는 흐름이나, 사용자가 임의 worktree에서 의도적으로 loop을 돌리는 케이스를 지원하기 위함이다. 이전 reject(거부) 접근법은 worktree-내부 호출을 일률 차단해 사용자 마찰을 일으켰던 반면, skip 접근법은 isolation 목적이 이미 충족된 상황(보조 worktree 자체가 격리된 작업 공간)을 인지해 중복 nested worktree 생성을 방지한다. 사용자가 docs만으로도 동일 동작에 도달할 수 있도록 스킬 문서의 호출 방법 절에도 명시 지침을 추가한다.

## 수용 기준 (EARS)

- **AC1** (Event-driven): loop의 `start` 서브커맨드가 호출될 때, 시스템은 호출 워킹 디렉토리가 git 저장소의 주 작업트리인지 보조 worktree인지 검사한다.
- **AC2** (Optional/조건): 호출 워킹 디렉토리가 주 작업트리인 경우, 시스템은 기존 start 동작을 변경 없이 그대로 수행한다 (canonical nested worktree 생성·lock 획득·이터레이션 루프).
- **AC3** (Optional/조건): 호출 워킹 디렉토리가 보조 worktree로 판정되는 경우, 시스템은 nested worktree 생성을 생략하고 현재 cwd의 worktree를 작업 공간으로 사용한다. SPEC.md·헌법·lock 등 통상 nested worktree 안에 두는 파일은 현재 worktree 안의 동등 경로(또는 `milestones/<m>/loops/<c>/` 안)에 배치한다.
- **AC4** (Ubiquitous): worktree 검사와 분기 로직은 셸 드라이버 본체에 위치해 스킬을 통한 호출과 셸 드라이버 직접 호출 모두에 동일하게 작동한다.
- **AC5** (Ubiquitous): 스킬 문서의 호출 방법 절에 "주 작업트리: nested worktree 생성 / 보조 worktree: 현재 worktree 사용 (생략)" 분기 동작이 명시된다.
- **AC6** (Unwanted/조건): 보조 worktree에서 호출된 경우라도 lock·SPEC 검증 등 기존 안전 검사(SPEC.md 존재·placeholder 없음·`[NEEDS CLARIFICATION]` 없음·락 미보유)는 동일하게 수행한다 — skip 대상은 nested worktree 생성·헌법 복사 등의 *worktree 셋업 단계*만이다.

## 범위

포함:

- `plugins/autopilot/skills/loop/references/loop.sh` — `start` 서브커맨드 진입 직후 cwd 분기 로직 추가 (주 작업트리 vs 보조 worktree), 보조 worktree 분기에서 nested worktree 생성·헌법 복사 단계 skip.
- `plugins/autopilot/skills/loop/SKILL.md` — 호출 방법 절에 두 분기 동작 명시.
- `plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh` — 보조 worktree 호출 분기 케이스 추가.

비-목표 / 제외:

- `operational-guide.md` 등 사용자가 SKILL.md 외 reference 갱신 (SKILL.md만 대상).
- `status`·`stop`·`list`·`cleanup`·`logs` 등 다른 subcommand 검사 — `start`만의 범위.
- spec 워크플로우의 worktree 호출 변경 (spec은 worktree 안에서 SPEC.md 작성 제약 없음 — 별개 문제).
- 보조 worktree에서 호출된 경우의 PROJECT_ROOT 재정의·canonical 경로 재계산 등 후속 흐름의 세부 조정 (별도 SPEC으로 보강 검토).

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash plugins/autopilot/skills/loop/tests/test-loop-review-fix-phase.sh
```

SPEC 구현 중 추가될 케이스:

- 주 작업트리 cwd 호출 → 기존 nested worktree 생성 동작 보존 (AC2).
- 보조 worktree cwd 호출 → nested worktree 생성 skip + 현재 cwd 사용 (AC3).
- 두 분기 모두 lock·SPEC 검증 동작 동일 수행 (AC6).
- `loop.sh` start 진입부 grep — 분기 함수 호출 확인 (AC1·AC4).
- `SKILL.md` grep — "주 작업트리" / "보조 worktree" 분기 표현 존재 (AC5).

## 제약

- "주 작업트리" 판별은 일반 git 저장소 케이스의 `.git` 디렉토리 vs 파일 존재 여부(또는 `git rev-parse --git-common-dir` vs `--git-dir` 비교)로 수행. bare repo·submodule·detached HEAD 등 비표준 환경은 보장 범위 외.
- `start` 서브커맨드에만 분기 적용 — 다른 subcommand(`status`·`stop`·`list`·`cleanup`·`logs`)는 기존 동작 유지.
- bash 4 이상 (loop.sh 기존 가정과 동일).
- 보조 worktree 분기에서도 lock·SPEC 검증은 기존과 동일하게 수행 — skip 대상은 worktree 셋업 단계만이다.

## 위험

- 보조 worktree에서 nested wt 생성을 skip한 결과, lock·SPEC 경로 등 후속 흐름이 cwd 기준 상대 경로로 동작할 때 canonical 경로와 mismatch할 가능성 — 구현 시 PROJECT_ROOT·LOOPS_DIR 결정 로직과의 정합 확인 필요.
- "주 작업트리" 정의가 git 공식 문서의 *main working tree* 개념과 일치한다는 전제. git 향후 버전이 이 구조를 변경하면 검사 로직 재검토 필요.
- skip 분기에서 cleanup·rebase 흐름이 보조 worktree를 의도적으로 건드릴 수 있어 사용자가 미리 진행 중이던 작업을 덮어쓸 수 있음 — 보조 worktree는 사용자가 의도해서 들어간 환경임을 전제로, 위험성은 cleanup 단계에서 prompt·확인으로 완화.
- 테스트 fixture가 `git worktree add`가 되는 환경을 요구 — CI·로컬 둘 다 일반적 git 설치이면 충족.
