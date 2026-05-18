---
scope:
  include: ["plugins/autopilot/skills/loop/SKILL.md", "tests/autopilot/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-loop-skill-frontmatter.sh"
test_sweep_paths:
  - "tests/autopilot/test-skill-allow-tools.sh"
ears_language: ko
request_review: true
---

# loop 스킬 SKILL.md frontmatter — Read 추가 + 공백→콜론 정규화

## 무엇을 만들 것인가
`autopilot:loop` 스킬 본문 흐름 실행에 필요한 권한·도구를 frontmatter 허용 목록에 명시해 사용자 환경의 권한 prompt 발생을 최소화한다. 정책은 먼저 트랙 SPEC(SPEC #113·#108)이 수립한 두 원칙—non-pr `gh ` prefix 배제·catch-all 금지·trailing 콜론 형식 통일—을 동일하게 적용한다. 추가로 본 스킬 운영 흐름에서 `references/loop.sh`·`references/pr-phase.sh`·`references/constitution.md` 등 보조 파일 점검에 필요한 파일 읽기 수단을 frontmatter에 명시 등록한다.

## 수용 기준 (EARS)
- **AC1**: 시스템은 `plugins/autopilot/skills/loop/SKILL.md` frontmatter의 `allowed-tools` 목록에 `Read` 항목을 포함한다.
- **AC2**: 시스템의 위 `allowed-tools` 목록의 모든 Bash 항목은 trailing `:*` 형식을 사용한다 — trailing ` *`(공백+별표) 형식을 사용하지 않는다.
- **AC3**: 시스템의 위 frontmatter는 YAML로 parse 성공한다.
- **AC4**: 시스템의 위 `allowed-tools` 목록은 catch-all 패턴(`Bash(*)`·`*` 단독)을 포함하지 않는다.
- **AC5**: 시스템의 위 `allowed-tools` 목록은 `gh pr` prefix가 아닌 모든 `gh ` prefix 패턴을 포함하지 않는다 (SPEC #113 일관성).
- **AC6**: 시스템의 위 `allowed-tools` 목록은 중복 항목을 포함하지 않는다.
- **AC7**: 본 SPEC의 `verify` 항목에 명시된 명령이 0 exit으로 통과한다.

## 범위
포함:
- `plugins/autopilot/skills/loop/SKILL.md` frontmatter `allowed-tools`에 `Read` 추가 + 기존 공백형식→콜론형식 정규화
- `tests/autopilot/test-loop-skill-frontmatter.sh`(또는 동등 명칭) verify 스크립트 추가·수정

비-목표 / 제외:
- `spec`·`dispatch`·`prd` 등 다른 autopilot 스킬 보강 (각자 SPEC으로)
- `~/.claude/settings.json`·`.claude/settings.json`·`.claude/settings.local.json` 변경
- 사용자 환경 dogfooding(실측 prompt 0회) — [handoff] comment로 위임
- `references/` 하위 보조 파일(`loop.sh` 등) 본문 수정
- loop SKILL.md 본문(사용자에게 보이는 본문 텍스트) 수정 — frontmatter 한 파일만 손댐

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash tests/autopilot/test-loop-skill-frontmatter.sh
```

스크립트는 다음을 검사한다:
- `plugins/autopilot/skills/loop/SKILL.md` YAML frontmatter parse 성공 (AC3)
- `allowed-tools`에 `Read` 항목 포함 확인 (AC1)
- trailing ` *`(공백+별표) 패턴 0개 (AC2)
- catch-all `Bash(*)`·`*` 단독 0개 (AC4)
- non-pr `gh ` 패턴 0개 (AC5)
- 중복 항목 0개 (AC6)

## 제약 (있을 때만)
- 본 repo는 plugin source repo이며 실제 권한 prompt 감소 효과는 사용자 환경의 plugin cache가 새 SKILL.md를 동기화한 뒤에만 관측된다.
- 본 SPEC와 SPEC #108은 둘 다 `tests/autopilot/test-skill-allow-tools.sh`(SPEC #113 검증 스크립트)에 영향을 줄 가능성이 있다. `test_sweep_paths`로 화이트리스트화해 두 SPEC이 동시 진행 중에도 "테스트 약화" 게이트가 오탐하지 않게 한다.
- AC5의 SPEC #113 일관성 원칙은 본 스킬 자체가 PR phase에서 `gh pr` 계열을 호출한다는 사실과 정합된다 — `gh pr`은 허용, 다른 `gh ` prefix는 배제.

## 위험 (있을 때만)
- `SKILL.md` frontmatter의 `allowed-tools` 키가 Claude Code skill loader의 권한 자동 허용 메커니즘과 동일한 키임을 가정한다 — 메이저 차이가 있을 경우 권한 prompt 감소 효과가 실현되지 않는다 (SPEC #113·#108에서 이미 검증되면 낮아짐).
- 본 SPEC와 SPEC #108의 merge 시점이 겹치면 한쪽이 머지된 뒤 다른 쪽이 rebase 필요. `test_sweep_paths` 선언으로 자동 게이트 충돌은 피할 수 있으나, 두 PR의 `test-skill-allow-tools.sh` 갱신 내용이 충돌하면 수동 해결 필요.
