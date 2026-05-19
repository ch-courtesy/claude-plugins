---
scope:
  include: ["plugins/autopilot/skills/loop/references/pr-phase.sh", "tests/autopilot/test-loop-pr-phase.sh"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-loop-pr-phase.sh"
request_review: true
test_sweep_paths:
  - "tests/autopilot/test-loop-pr-phase.sh"
---

# pr-phase PR 제목 포맷 개선 — `#<task-id>: <SPEC H1>` prefix

## 무엇을 만들 것인가
loop 스킬의 pr-phase가 PR을 생성·갱신할 때, 제목 포맷을 현재 단순 "SPEC H1 제목"에서 `#<task-id>: <SPEC H1 제목>` prefix 형태로 도입한다. `#<task-id>`가 GitHub의 자동 issue 링크 문법이므로 PR 제목에서 클릭·호버 시 해당 issue로 이동 가능해진다. task-id가 `^[0-9]+$` 패턴이 아닌 경우(예: slug 포함 task-id `105-spec-...`)는 `#` prefix를 생략하고 `<task-id>: <SPEC H1 제목>` 형태로 fallback한다. PR body의 자동 영역 marker fence·`Closes #<id>` trailer·push·gh CLI 호출 흐름은 변경하지 않는다.

## 수용 기준 (EARS)
- **AC1 (Event-driven)**: pr-phase가 새 PR을 생성할 때, task-id가 `^[0-9]+$` 패턴을 만족하면 PR 제목은 `#<task-id>: <SPEC H1 제목>` 포맷을 따른다.
- **AC2 (Event-driven)**: pr-phase가 기존 PR을 in-place 갱신(edit)할 때 제목도 위 포맷으로 동기화된다.
- **AC3 (Optional/조건)**: task-id가 `^[0-9]+$` 패턴이 아닌 경우(slug 포함·alphanumeric 혼합 등), 제목은 `<task-id>: <SPEC H1 제목>` 포맷(`#` 없이)을 따른다.
- **AC4 (Ubiquitous)**: PR body의 자동 영역 marker fence(`<!-- autopilot:pr-body:begin --> ... <!-- autopilot:pr-body:end -->`)·`Closes #<id>` trailer·기존 push·gh CLI 호출 흐름은 변경되지 않는다.
- **AC5 (Ubiquitous)**: pr-phase 관련 정적 테스트가 simulation·mock을 통해 새 제목 포맷을 검증하는 케이스를 포함한다 — 숫자 task-id 경로, slug 혼합 fallback 경로, 갱신 경로 각각.
- **AC6 (Ubiquitous)**: 해당 검증 명령(`bash tests/autopilot/test-loop-pr-phase.sh`)이 0 exit으로 끝난다.

## 범위
포함:
- `plugins/autopilot/skills/loop/references/pr-phase.sh` — PR 제목 조립 로직(생성·갱신 모두)에 `#<task-id>: ` prefix 도입, 숫자 패턴 검증, fallback 처리.
- `tests/autopilot/test-loop-pr-phase.sh` (또는 동등한 새 테스트 파일) — 제목 포맷 검증 케이스 추가 (숫자·slug·갱신 3 경로).

비-목표 / 제외:
- `plugins/autopilot/skills/loop/SKILL.md` frontmatter 수정 (다른 SPEC 영역).
- pr-phase.sh의 PR body 구성 로직·marker fence·push·gh CLI 호출 흐름 변경.
- `review-fix-phase.sh`·`cleanup-phase.sh`·`loop.sh` 수정.
- 기존 열린 PR의 retroactive 제목 변경 (현재 PR들).
- task-id·slug 도출 규칙 변경 (`references/feat-branch-commit.md` §9.5.1 불변).

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash tests/autopilot/test-loop-pr-phase.sh
```

## 제약 (있을 때만)
- task-id 숫자 검사는 정규식 `^[0-9]+$` 정확 일치. 숫자-문자 혼합·slug 포함 task-id는 fallback 포맷 분기.
- 기존 PR body trailer `Closes #<id>` 로직과 일관 유지 — 동일 task-id가 제목·trailer 둘 다 사용자 인지 가능한 형태.
- 테스트는 PR 존재 없이 simulation (function 호출·echo 검증) 또는 mock으로 구성 — 실제 gh 호출 없이 정적 검증 가능해야 한다.
- 자체-재귀 (`feedback_no_self_apply_during_spec`): 본 SPEC PR 제목은 이전 포맷 적용 (현재 세션 면제) — 새 포맷은 본 SPEC PR 머지 이후의 다음 spec/loop 호출부터 적용.

## 위험 (있을 때만)
- **GitHub 자동 링크 해석 불확실성**: PR 제목에서 접두 `#`이 다른 의미로 해석될 가능성. 일반 `#<num>` 패턴은 안전하지만 이상 시 테스트에서 감지.
- **테스트 fixture 한계**: pr-phase.sh가 simulation hook을 제공하지 않으면 함수 추출·변수 검증 수준으로 제한될 수 있음 — 구현 단계에서 결정.
- **외부 도구 깨짐 가능성**: 제목 형식 통일로 PR 목록에서 기존 제목 패턴 고수하던 외부 자동화(필터·webhook)가 영향받을 수 있음 — 권고이나 사용자 환경 외부라 본 SPEC 범위 외.
- **task-id가 알파벳-only인 엣지 케이스**: 본 SPEC AC3은 slug 포함·alphanumeric 가정. 순수 알파벳 task-id도 fallback 분기로 흘러가 처리됨.
