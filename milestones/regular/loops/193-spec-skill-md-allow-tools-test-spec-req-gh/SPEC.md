---
scope:
  include: ["plugins/autopilot/skills/spec/SKILL.md", "tests/autopilot/test-skill-allow-tools.sh"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-skill-allow-tools.sh"
request_review: true
test_sweep_paths:
  - "tests/autopilot/test-skill-allow-tools.sh"
---

# spec SKILL.md allow-tools 확장 + test SPEC_REQ 싱크 + gh 제외 규칙 완화

## 무엇을 만들 것인가
plugins/autopilot/skills/spec/SKILL.md의 frontmatter `allowed-tools` 배열에 spec 워크플로 운용 중 사용자 세션에서 권한 prompt를 일으키는 명령 패턴을 추가하고, tests/autopilot/test-skill-allow-tools.sh의 `SPEC_REQ` 상수 배열을 동일하게 갱신해 AC7 검증이 누락을 catch하게 한다. 추가 대상 4 범주: (1) `gh issue view/edit/create`·`gh project field-list/item-list/item-add/item-edit` — task 상태 정합·라벨 부여·body sync·Project Status 전이에 필수, (2) loop 운용과 유사한 일반 git 명령(fetch·push·switch·rebase·branch·log·show·status·rev-parse·rev-list·merge-base·show-ref 등)과 `git add`/`git commit` — §9.5 feat 브랜치 생성·SPEC.md commit·main ff-merge·push, (3) `python3 -c` inline — §8.2 fence-aware Issue body 재구성에 사용, (4) `mkdir`·`head`·`cat` — slug-bearing 디렉토리 생성·SPEC.md 확인·context 탐색. 동시에 test 스크립트의 "gh pr 외 모든 gh 제외" 조건을 완화해 `gh pr`·`gh issue`·`gh project` 3 prefix를 skill-scope 예외로 허용한다. user-scope `~/.claude/settings.json`과 프로젝트 `.claude/settings.json`은 여전히 모든 gh 제외 정책 유지 — 본 SPEC은 skill-scope 한정.

## 수용 기준 (EARS)
- **AC1 (Ubiquitous)**: plugins/autopilot/skills/spec/SKILL.md frontmatter `allowed-tools` 배열에 4 범주(gh issue/project · git 명령 · python3 inline · 일반 util) 패턴이 SPEC 170 형식 `:*` trailing으로 포함된다.
- **AC2 (Ubiquitous)**: tests/autopilot/test-skill-allow-tools.sh의 `SPEC_REQ` 상수 배열에 AC1의 새 패턴들이 모두 등재되어 AC7 검증이 누락을 catch한다.
- **AC3 (Ubiquitous)**: test-skill-allow-tools.sh의 "gh exclude" 명세·구현이 `gh pr`·`gh issue`·`gh project` 3 prefix를 예외로 명시·허용하도록 완화된다.
- **AC4 (Unwanted/조건)**: user-scope `~/.claude/settings.json`과 프로젝트 `.claude/settings.json`은 본 SPEC 작업으로 변경되지 않는다 — skill-scope SKILL.md frontmatter만 변경 대상.
- **AC5 (Ubiquitous)**: `bash tests/autopilot/test-skill-allow-tools.sh`가 0 exit으로 끝난다 (기존 AC1–AC8 전부 통과 — catch-all 금지·`gh pr`+`gh issue`+`gh project` 외 제외·중복 없음·SPEC_REQ·LOOP_REQ·COMMON_REQ 기준 패턴 존재 모두 확인).

## 범위
포함:
- `plugins/autopilot/skills/spec/SKILL.md` — frontmatter `allowed-tools` 배열에 4 범주 패턴 추가.
- `tests/autopilot/test-skill-allow-tools.sh` — `SPEC_REQ` 상수 배열에 새 패턴들 추가 + "gh exclude" 명세·구현 완화 (`gh pr`·`gh issue`·`gh project` 3 prefix 예외).

비-목표 / 제외:
- `plugins/autopilot/skills/loop/SKILL.md` 수정 — SPEC 190의 영역.
- `plugins/autopilot/skills/spec/references/*.md` 수정 — 스펙 템플릿·self-review·task-state-alignment 등 다른 reference는 변경 안 함.
- user-scope `~/.claude/settings.json`·프로젝트 `.claude/settings.json` 변경.
- `plugins/autopilot/skills/loop/references/*.sh` 등 loop 측 명령 로직 변경.
- 메모리 자체 갱신 — `feedback_allowlist_exclude_github`의 완화된 판은 메모리 꾸미는 별도 세션으로 처리.

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash tests/autopilot/test-skill-allow-tools.sh
```

## 제약 (있을 때만)
- 패턴 형식: SPEC 170 정규화 `:*` trailing wildcard. 공백+별표 ` *` 형식 금지.
- AC3 gh exclude 완화는 test 구현(코드)와 주석(AC5 문구) 모두 업데이트 — drift 주의.
- `SPEC_REQ` 배열 동일 순서·철자로 SKILL.md `allowed-tools`와 동기화 필수 — AC7이 ID 비교로 일대일 매칭.
- 메모리 `feedback_allowlist_exclude_github`의 완화 판은 본 SPEC 머지 후 별도 메모리 꾸미는 세션에서 처리 — 본 SPEC은 스킬·테스트 변경만 다룬다.
- 자체-재귀 (`feedback_no_self_apply_during_spec`): 본 SPEC을 작성·수행하는 *현 호출*은 새 권한이 아직 머지되지 않은 상태라 끝까지 권한 prompt가 발생할 수 있다 — 새 동작은 본 SPEC PR 머지 후의 다음 spec 호출부터 적용된다.

## 위험 (있을 때만)
- **gh 권한 확장으로 의도치 않은 mutation 가능성**: `gh issue edit`·`gh project item-edit` 등이 의도 외 객체에 적용될 위양성 — skill-scope 한정으로 surface 제한하지만 와일드카드 패턴 매칭 폭은 신중히 검토 필요.
- **SKILL.md ↔ 테스트 drift**: `SPEC_REQ`가 SKILL.md `allowed-tools`와 어긋나면 AC2 fail. 동시 수정·single commit으로 완화.
- **AC3 완화 이후 정책 인플레이션**: 다른 mutating gh 명령 요구가 추가 제안될 수 있음 — 그때마다 별도 SPEC으로 정책 검토.
- **메모리 규칙과의 불일치 우려**: `feedback_allowlist_exclude_github`는 user-scope·skill-scope 정책을 함께 기술. 본 SPEC이 skill-scope 정책만 완화하지만, 메모리 본문 갱신을 따로 하지 않으면 미래 세션이 옛 규칙으로 판단할 수 있음 — 사용자가 별도 세션에서 메모리 갱신 권장.
