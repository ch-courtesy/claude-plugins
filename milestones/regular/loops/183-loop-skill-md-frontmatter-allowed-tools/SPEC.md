---
scope:
  include: ["plugins/autopilot/skills/loop/SKILL.md"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "grep -qF 'Bash(bash /Users/*/.claude/plugins/cache/*/autopilot/*/skills/loop/references/*.sh *)' plugins/autopilot/skills/loop/SKILL.md && grep -qF 'Bash(tail -F /private/tmp/claude-* 2>/dev/null | grep -E --line-buffered *)' plugins/autopilot/skills/loop/SKILL.md && grep -qF 'Bash(gh pr view *)' plugins/autopilot/skills/loop/SKILL.md && grep -qF 'Bash(gh pr checks *)' plugins/autopilot/skills/loop/SKILL.md && grep -qF 'Bash(git status --porcelain*)' plugins/autopilot/skills/loop/SKILL.md && ! grep -qF 'Bash(git checkout HEAD -- *)' plugins/autopilot/skills/loop/SKILL.md && ! grep -qF 'Bash(gh issue ' plugins/autopilot/skills/loop/SKILL.md"
ears_language: ko
---

# loop SKILL.md — frontmatter allowed-tools 에 세션에서 자주 프롬프되던 패턴 보강

## 무엇을 만들 것인가

loop 스킬 (`plugins/autopilot/skills/loop/SKILL.md`) 의 YAML frontmatter `allowed-tools` 리스트에 다음 카테고리의 Bash 명령 패턴을 glob 와일드카드 형식으로 추가한다 — (1) version-pinned cache path 의 loop 드라이버·phase 스크립트 호출, (2) bg job output 파일의 Monitor tail+grep, (3) GitHub PR read-only 조회 (`gh pr view`·`gh pr checks` — `gh issue *` 와 `gh pr merge/comment` 는 제외, 메모리 노트와 정합), (4) main repo working tree 의 git inspect (`git status --porcelain` — `git checkout HEAD -- *` 는 미커밋 변경 무음 파기 위험으로 AC4-neg 제외). 추가는 frontmatter `allowed-tools` 리스트 내에 한정되며, 본문·다른 frontmatter 키·자매 스킬(`spec`·`dispatch`·`prd`) 의 SKILL.md 는 변경하지 않는다.

배경: loop 스킬을 통한 호출 세션에서 동일 명령에 prompt 가 반복 발생함이 관측됐다. settings.json·settings.local.json 영구 등록 0건으로, 매 호출마다 "allow once" 가 반복되는 마찰이 누적된다. 기존 frontmatter 가 이미 다수 패턴(`Bash(bash * loop.sh start *)`·`Bash(tail -F /private/tmp/* | grep -E --line-buffered *)` 등)을 선언하고 있어, 동일 메커니즘으로 새 패턴을 누적·일관성 있게 확장한다. gh CLI 의 외부 상태 변경 가능성 우려는 PR read-only 만 예외로 허용해 메모리 노트 `feedback_allowlist_exclude_github` 의 정신(외부 상태 변경 가능 명령 제외)과 정합한다.

## 수용 기준 (EARS)

- **AC1** (Ubiquitous): `allowed-tools` 에 `Bash(bash /Users/*/.claude/plugins/cache/*/autopilot/*/skills/loop/references/*.sh *)` 패턴이 한 줄로 포함된다.
- **AC2** (Ubiquitous): `allowed-tools` 에 `Bash(tail -F /private/tmp/claude-* 2>/dev/null | grep -E --line-buffered *)` 패턴이 한 줄로 포함된다 — Monitor 의 실제 tail+pipe+redirect 조합과 일치하도록 pipe(`| grep`)와 `2>/dev/null` 를 패턴에 명시 포함하고, 비지원 glob 문법(`**`)은 사용하지 않는다.
- **AC3** (Ubiquitous): `allowed-tools` 에 `Bash(gh pr view *)` 와 `Bash(gh pr checks *)` 두 패턴이 각각 한 줄로 포함된다.
- **AC4** (Ubiquitous): `allowed-tools` 에 `Bash(git status --porcelain*)` 패턴이 한 줄로 포함된다.
- **AC4-neg** (Unwanted): `allowed-tools` 에 `Bash(git checkout HEAD -- *)` 패턴은 추가되지 **않는다** — `git checkout HEAD -- <path>` 는 미커밋 변경을 무음 파기하는 write 연산이라 destructive 위험으로 자동 승인 범위 제외 (PR #187 reviewer BLOCKING thread 3264181657 반영).
- **AC5** (Unwanted): `allowed-tools` 에 `gh issue *`·`gh pr merge *`·`gh pr comment *` 같은 외부 상태 변경 가능 gh 패턴은 신규 추가되지 않는다 (기존 미포함 상태 유지, 메모리 노트 `feedback_allowlist_exclude_github` 정합).
- **AC6** (Unwanted): 본 변경은 frontmatter `allowed-tools` 리스트 외 다른 어떤 필드·본문 텍스트·자매 스킬(`spec`·`dispatch`·`prd`) 의 SKILL.md 도 수정하지 않는다.

## 범위

포함:

- `plugins/autopilot/skills/loop/SKILL.md` — frontmatter `allowed-tools` 에 5개 신규 패턴 추가 (AC1·AC2·AC3 두 항목·AC4 한 항목). `git checkout HEAD -- *` 는 AC4-neg 에 따라 제외 (PR #187 reviewer BLOCKING 반영).

비-목표 / 제외:

- 자매 스킬 (`spec`·`dispatch`·`prd`) 의 SKILL.md — 별개 SPEC 으로 분리
- `settings.json`·`settings.local.json` `permissions.allow` — frontmatter 단일 경로로 충분, 별개 트랙
- `gh issue *`·`gh pr merge`·`gh pr comment` 등 외부 상태 변경 가능 gh 명령 — 본 SPEC 명시 제외 (AC5)
- 메모리 노트 `feedback_allowlist_exclude_github` 갱신 — 별도 세션 액션 (SPEC 외)
- frontmatter `allowed-tools` 메커니즘의 실효성 자체 검증 — 별개 SPEC (본 SPEC 는 의도 표현·일관성 확장만 책임)

## 검증

frontmatter `verify` 명령이 0 exit 으로 끝나야 합니다 (5개 grep -qF 체인 + 2개 negation — AC4-neg 와 AC5):

```bash
grep -qF 'Bash(bash /Users/*/.claude/plugins/cache/*/autopilot/*/skills/loop/references/*.sh *)' plugins/autopilot/skills/loop/SKILL.md && \
grep -qF 'Bash(tail -F /private/tmp/claude-* 2>/dev/null | grep -E --line-buffered *)' plugins/autopilot/skills/loop/SKILL.md && \
grep -qF 'Bash(gh pr view *)' plugins/autopilot/skills/loop/SKILL.md && \
grep -qF 'Bash(gh pr checks *)' plugins/autopilot/skills/loop/SKILL.md && \
grep -qF 'Bash(git status --porcelain*)' plugins/autopilot/skills/loop/SKILL.md && \
! grep -qF 'Bash(git checkout HEAD -- *)' plugins/autopilot/skills/loop/SKILL.md && \
! grep -qF 'Bash(gh issue ' plugins/autopilot/skills/loop/SKILL.md
```

추가 보조 검사 (PR 리뷰 시점, AC6 형식 일관성):

```bash
# AC6 — 5개 신규 패턴이 모두 "  - Bash(" 2칸 들여쓰기 형식
awk '/^---$/{c++;next} c==1 && /^  - Bash\(/' plugins/autopilot/skills/loop/SKILL.md \
  | grep -cE 'cache/\*/autopilot|/private/tmp/claude-\*|gh pr view|gh pr checks|git status --porcelain'
# 기대값: 5 이상
```

## 제약

- 추가 패턴은 기존 SPEC 113 주석 그룹과 동일한 줄 들여쓰기·형식(`  - Bash(...)` 2칸 들여쓰기)을 따른다.
- glob 와일드카드 형식만 사용 — hard-coded version 번호(`0.5.1`) 명시 금지.
- `gh issue *`·`gh pr merge`·`gh pr comment` 등 외부 상태 변경 가능 gh 명령 추가 금지 (AC5, 메모리 노트 정합).
- self-referential: 본 SPEC 호출 자체는 옛 규칙으로 마치고 새 패턴은 본 SPEC 머지 후의 다음 loop 호출부터 효력 (`feedback_no_self_apply_during_spec` 정합).

## 위험

- frontmatter `allowed-tools` 메커니즘이 실제 prompt 를 막지 못할 가능성 — 본 세션에서 기존 패턴이 보유돼 있음에도 일부 prompt 가 떴다는 관측. 실효성 검증은 별개 SPEC 책임이지만, 본 SPEC 가 효과 없으면 사용자가 prompt 마찰 해소 기대를 충족 못 할 수 있음.
- `Bash(bash /Users/*/.claude/plugins/cache/*/...)` 의 `*` 가 `/` 를 가로질러 매칭 가능한지는 Claude Code 의 Bash 패턴 룰에 의존. 매칭 룰이 prefix-only 라면 본 패턴이 무력화될 수 있음 — 별도 매칭 룰 확인 또는 prefix 형 보강 SPEC 필요할 수 있음.
- glob 패턴 (`/private/tmp/claude-*/**/tasks/*.output*`) 가 다른 사용자의 다른 경로 (예: `/private/tmp/claude-XXX/...`) 까지 의도치 않게 매칭할 가능성 — 본 패턴은 사용자 격리 디렉토리 안의 자기 job output 만 의도하지만, glob 가 사용자별 isolation 을 강제하지 못함. 실무적으로 단일 사용자 환경에서는 충돌 없음.
