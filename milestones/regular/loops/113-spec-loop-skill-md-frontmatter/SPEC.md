---
scope:
  include: ["plugins/autopilot/skills/spec/**", "plugins/autopilot/skills/loop/**", "tests/autopilot/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-skill-allow-tools.sh"
---

# spec·loop 스킬 SKILL.md frontmatter에 권한 허용 패턴 명시

## 무엇을 만들 것인가
`autopilot:spec`·`autopilot:loop` 두 스킬을 호출할 때 권한 prompt가 거의 발생하지 않도록, 각 스킬의 `SKILL.md` frontmatter에 사용 권한 패턴을 명시한다. 패턴 집합은 issue #113 본문이 enumerate한 직전 세션 실측 결과를 기준으로 한다. 외부 시스템 상태를 변경할 수 있는 `gh` CLI는 `gh pr` 계열만 허용하고 그 외에는 포함하지 않는다. `Bash(*)` 같은 catch-all 광역 권한은 금지한다.

## 수용 기준 (EARS)
- **AC1**: 시스템은 `plugins/autopilot/skills/spec/SKILL.md` frontmatter에 권한 허용 패턴 배열을 포함한다.
- **AC2**: 시스템은 `plugins/autopilot/skills/loop/SKILL.md` frontmatter에 권한 허용 패턴 배열을 포함한다.
- **AC3**: 위 두 SKILL.md의 frontmatter는 YAML로 parse 성공한다.
- **AC4**: 위 두 frontmatter의 허용 패턴 배열은 catch-all 패턴(`Bash(*)`·`*` 단독)을 포함하지 않는다.
- **AC5**: 위 두 frontmatter의 허용 패턴 배열은 `gh pr` prefix를 제외한 모든 `gh ` prefix 패턴을 포함하지 않는다.
- **AC6**: 위 두 frontmatter의 허용 패턴 배열은 각 배열 내에서 중복 항목을 포함하지 않는다.
- **AC7**: `spec/SKILL.md`의 허용 패턴 배열은 issue #113 본문 `autopilot:spec` 섹션과 `공통·보조` 섹션이 enumerate한 패턴(gh 패턴 제외)을 모두 포함한다.
- **AC8**: `loop/SKILL.md`의 허용 패턴 배열은 issue #113 본문 `autopilot:loop` 섹션과 `공통·보조` 섹션이 enumerate한 패턴(gh 패턴 제외)을 모두 포함한다.

## 범위
포함:
- `plugins/autopilot/skills/spec/SKILL.md` frontmatter에 허용 패턴 배열 추가
- `plugins/autopilot/skills/loop/SKILL.md` frontmatter에 허용 패턴 배열 추가
- 정적 검사 verify script 추가 (위 AC1~AC8 자동 검증)

비-목표 / 제외:
- `dispatch`·`prd` 등 다른 autopilot 스킬 (후속 issue로 분리)
- `~/.claude/settings.json`·`.claude/settings.json`·`.claude/settings.local.json` 변경
- `fewer-permission-prompts` 스킬 도입·비교 (별도 경로, 본 SPEC 범위 밖)
- 권한 prompt 발생 빈도 동적 측정

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash tests/autopilot/test-skill-allow-tools.sh
```

## 제약 (있을 때만)
- 본 repo는 plugin source repo이며, 실제 권한 prompt 감소 효과는 사용자 환경의 plugin cache가 새 `SKILL.md`를 동기화한 뒤에만 관측된다.
- `SKILL.md` frontmatter에 사용할 정확한 key 이름(`allow-tools` 혹은 `allowed-tools`)은 Claude Code의 frontmatter 처리 명세에 따르며, loop 워커가 구현 단계에서 1회 확인해 두 SKILL.md에 일관 적용한다.
- AC7·AC8의 "issue #113 본문 enumerate 패턴"은 SPEC 작성 시점의 issue body 내용을 정답으로 한다. verify script는 그 정답 집합을 frozen reference로 보유해 외부 API 호출 없이 비교한다.

## 위험 (있을 때만)
- `SKILL.md` frontmatter의 허용-패턴 키가 실제로 Claude Code skill loader에서 권한 자동 허용에 사용되지 않을 가능성 — 이 경우 본 SPEC의 효과(prompt 빈도 감소)는 실현되지 않는다. loop 구현 초기에 1회 동작 확인 후 진행한다.
- enumerate된 패턴 일부가 실제 호출과 좁게 불일치할 수 있음(경로·인자 변동). 보수적으로 유지하되 누락 발견 시 후속 PR로 추가한다.
