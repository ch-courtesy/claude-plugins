---
scope:
  include: ["plugins/autopilot/skills/spec/SKILL.md", "plugins/autopilot/skills/spec/references/feat-branch-commit.md", "tests/autopilot/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-spec-skill-frontmatter.sh"
test_sweep_paths:
  - "tests/autopilot/test-skill-allow-tools.sh"
ears_language: ko
request_review: true
---

# spec 스킬 SKILL.md frontmatter allowed-tools 보강 + §9.5.1 sed→awk 정규화

## 무엇을 만들 것인가
다음 두 개의 독립 작업을 한 번에 처리한다. (1) `autopilot:spec` 스킬 본문 실행에 필요한 권한·도구를 frontmatter 허용 목록에 명시해 사용자 환경의 권한 prompt 발생을 최소화한다. 단 권한 정책은 먼저 트랙 SPEC(SPEC #113)이 수립한 원칙—non-pr `gh ` prefix 배제·catch-all 금지—을 동일하게 적용한다. (2) 동일 스킬의 슬러그 추출 파이프라인이 macOS BSD sed에서 syntax error로 실패하는 문제를 BSD·GNU 양립 입력 파서(awk 기반 또는 BSD 호환 sed)로 교체해 모든 타겟 구동 환경에서 스킬 흐름이 끝까지 실행되게 한다.

## 수용 기준 (EARS)
- **AC1**: 시스템은 `plugins/autopilot/skills/spec/SKILL.md` frontmatter의 `allowed-tools` 목록에 다음 9개 항목을 모두 포함한다 — `Bash(awk:*)`, `Bash(printf:*)`, `Bash(pwd:*)`, `Bash(mktemp:*)`, `ToolSearch`, `EnterWorktree`, `ExitWorktree`, `TaskCreate`, `TaskUpdate`.
- **AC2**: 시스템의 위 `allowed-tools` 목록의 모든 Bash 항목은 trailing `:*` 형식을 사용한다 — trailing ` *`(공백 + 별표) 형식을 사용하지 않는다.
- **AC3**: 시스템의 위 frontmatter는 YAML로 parse 성공한다.
- **AC4**: 시스템의 위 `allowed-tools` 목록은 catch-all 패턴(`Bash(*)`·`*` 단독)을 포함하지 않는다.
- **AC5**: 시스템의 위 `allowed-tools` 목록은 `gh pr` prefix가 아닌 모든 `gh ` prefix 패턴을 포함하지 않는다 (SPEC 113 일관성).
- **AC6**: 시스템의 위 `allowed-tools` 목록은 중복 항목을 포함하지 않는다.
- **AC7**: `plugins/autopilot/skills/spec/references/feat-branch-commit.md` §9.5.1의 H1 제목 추출 명령은 macOS BSD sed와 GNU sed 모두에서 syntax error 없이 실행 가능한 형태(awk 기반 또는 BSD 호환 sed 표현)로 작성된다.
- **AC8**: 본 SPEC의 `verify` 항목에 명시된 명령이 0 exit으로 통과한다.

## 범위
포함:
- `plugins/autopilot/skills/spec/SKILL.md` frontmatter `allowed-tools` 신규 항목 추가 + 기존 공백형식→콜론형식 정규화
- `plugins/autopilot/skills/spec/references/feat-branch-commit.md` §9.5.1 H1 추출 코드 BSD 호환 fix
- `tests/autopilot/test-spec-skill-frontmatter.sh`(또는 동등 명칭) verify 스크립트 추가·수정

비-목표 / 제외:
- `loop`·`dispatch`·`prd` 등 다른 autopilot 스킬 보강
- `~/.claude/settings.json`·`.claude/settings.json`·`.claude/settings.local.json` 변경
- 사용자 환경 dogfooding(실측 prompt 0회) — [handoff] comment로 위임
- `references/spec-template.md` 관련 슬러그 추출 외 다른 sed/awk 명령 일괄 검사
- spec/SKILL.md 본문(사용자에게 보이는 본문 텍스트) 수정 — frontmatter와 references/ 두 파일만 손댐

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash tests/autopilot/test-spec-skill-frontmatter.sh
```

스크립트는 다음을 검사한다:
- `plugins/autopilot/skills/spec/SKILL.md` YAML frontmatter parse 성공
- `allowed-tools` 에 AC1의 9개 항목 모두 포함 확인
- trailing ` *`(공백+별표) 패턴 0개 (AC2)
- catch-all `Bash(*)`·`*` 단독 0개 (AC4)
- non-pr `gh ` 패턴 0개 (AC5)
- 중복 항목 0개 (AC6)
- `references/feat-branch-commit.md` §9.5.1의 H1 추출 명령이 macOS BSD sed와 GNU sed 양쪽에서 파싱되는지 — 실제 실행이 아닌 정적 검사(`grep`·`awk` 코드는 BSD·GNU 호환, 기존 `sed -n '/^---$/,/^---$/!{/^# /{...q;}}'` 패턴 부재 확인) + 샘플 SPEC.md 입력으로 H1 추출 동작 동등성 확인(awk fallback 출력 == 기대 H1)

## 제약 (있을 때만)
- 본 repo는 plugin source repo이며 실제 권한 prompt 감소 효과는 사용자 환경의 plugin cache가 새 SKILL.md를 동기화한 뒤에만 관측된다.
- AC5의 SPEC 113 일관성 원칙은 spec 스킬 자체가 §2 task 정합·§8.2 issue body sync에서 `gh issue view`·`gh issue edit`·`gh project ...`를 호출한다는 사실과 의도적 트레이드오프다 — 해당 호출은 사용자 환경에서 일회성 prompt를 유발할 수 있으나 외부 상태 변경 가능성 평가에 따른 동의 활용 범위는 유지한다.
- spec 스킬은 자기-참조 SPEC을 같은 호출에 미리 적용하지 않는 메모리 룰(`feedback_no_self_apply_during_spec`)을 따른다 — 본 SPEC가 정의한 새 contract는 다음 spec 호출부터 적용된다.

## 위험 (있을 때만)
- `SKILL.md` frontmatter의 `allowed-tools` 키가 Claude Code skill loader의 권한 자동 허용 메커니즘과 동일한 키임을 가정한다 — 메이저 차이가 있을 경우 권한 prompt 감소 효과가 실현되지 않는다 (SPEC 113에서 이미 검증되었으면 낮아짐).
- macOS BSD sed 패턴 교체 코드가 기존 동작(YAML frontmatter 이후 첫 H1 추출)과 동등하지 않을 위험 — verify에 샘플 SPEC.md 입력 → 예상 H1 출력 비교를 포함해 행위 동등성 확인.
