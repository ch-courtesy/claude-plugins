---
scope:
  include: ["plugins/autopilot/skills/loop/**", "plugins/autopilot/skills/spec/references/spec-template.md", "tests/autopilot/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-loop-pr-phase.sh && bash tests/autopilot/test-loop-sh.sh"
test_sweep_paths:
  - "tests/autopilot/test-loop-pr-phase.sh"
# test_paths (선택): 테스트 약화 게이트가 추적할 경로/파일명 패턴 (git pathspec).
#   미지정 시 기본 컨벤션(tests/·test/·__tests__/·spec/·src/test/ 디렉토리 +
#   *.test.{js,ts,jsx,tsx,py}·*.spec.{js,ts,rb}·*_test.{go,py,rb}·test_*.py·*_spec.rb)
#   비표준 컨벤션·언어(예: C++ *.t.cpp, Elixir test/) 시 명시.
# test_paths:
#   - "custom/test/**"
#   - "**/*.t.cpp"
#
# test_sweep_paths (선택): 합법적 sweep(대규모 rename·cleanup 등)을 SPEC 작성 시점에
#   화이트리스트화. 매칭되는 파일은 weakening 해시 비교 셋에서 제외된다 — 수정·삭제해도
#   "테스트 약화" halt 발생 안 함. 매칭 규칙은 test_paths와 동일한 git pathspec.
#   선언 후 매칭 파일이 0건이면 stderr 경고만 (halt 없음 — 패턴 오타·미생성 상태 보존).
#   주의: sweep 밖의 기존 테스트 변경은 여전히 halt — sweep은 화이트리스트 면제.
# test_sweep_paths:
#   - "tests/legacy_to_remove/**"
#   - "tests/test_specific_to_rename.py"
---

# loop: DONE 이후 PR 생성·재사용 단계 (opt-in)

## 무엇을 만들 것인가
`autopilot:loop`이 task를 DONE으로 마친 직후, opt-in으로 활성화되는 새 단계로 진입해 같은 worktree에서 PR 생성(또는 동일 브랜치 open PR 재사용)까지 수행하도록 확장한다. 이 단계는 자동 push, default 브랜치 자동 감지, SPEC + commits 기반 body 합성, 숫자 task-id의 이슈 자동 링크를 책임지며, reviewer·label·assignee 등 메타데이터는 일체 설정하지 않는다. 단계가 끝나도 worktree와 local 브랜치는 보존되어 후속 단계(리뷰 모니터·자동 fix 사이클)가 인계받는다. 리뷰 코멘트 모니터링·코멘트 분류·자동 fix·답글 게시·worktree 정리는 이번 SPEC의 비-목표이며 별도 SPEC으로 다룬다.

## 수용 기준 (EARS)
1. request-review 옵션이 비활성 상태인 동안, 루프는 PR 생성 단계를 실행하지 않고 종료한다.
2. request-review 옵션이 활성 상태이고 task가 DONE에 도달한 경우, 루프는 현재 브랜치를 push하고 동일 브랜치의 open PR이 없으면 default 브랜치를 base로 새 PR을 생성하며, 있으면 기존 PR을 재사용한다.
3. 동일 브랜치에 이미 open PR이 존재할 때, 루프는 새 PR을 생성하지 않고 기존 PR의 제목과 body를 in-place로 갱신한다.
4. 생성·갱신되는 PR의 제목은 SPEC 문서의 제목과 일치해야 한다.
5. 생성·갱신되는 PR의 body는 SPEC "무엇을 만들 것인가" 본문과 resolved base 브랜치부터 HEAD까지의 commit 로그를 합성해 구성해야 한다.
6. task-id가 `^[0-9]+$` 패턴과 매칭되는 경우, 루프는 합성된 PR body의 마지막 줄에 `Closes #<task-id>`를 추가한다.
7. 루프는 PR 생성·갱신 시 reviewer·label·assignee를 설정하지 않는다.
8. 브랜치 push, PR 생성, PR 갱신 중 어느 하나라도 실패할 시, 루프는 non-zero exit으로 단계를 중단하고 하위 도구의 stderr을 그대로 전달해야 한다.
9. PR 생성·갱신 단계가 성공으로 끝날 때, 루프는 worktree와 local 브랜치를 유지하고 PR URL과 state를 stdout으로 출력한다.
10. 레포지토리의 default 브랜치를 감지할 수 없을 시, 루프는 push·PR 명령을 호출하기 전에 non-zero exit으로 단계를 중단해야 한다.

## 범위
포함:
- `plugins/autopilot/skills/loop/` — driver(`loop.sh`·helper), `SKILL.md`(opt-in 플래그·frontmatter 키 명세), 관련 references 문서
- `plugins/autopilot/skills/spec/references/spec-template.md` — frontmatter `request_review` 키 가이드 추가
- `tests/autopilot/` — 새 phase 단위·e2e 테스트 스크립트 추가 및 기존 회귀 테스트 갱신

비-목표 / 제외:
- 별도 스킬 신설(`autopilot:request-review`·`autopilot:review` 등)
- PR 리뷰 코멘트 모니터링·폴링
- 코멘트 분류·자동 fix 사이클
- 답글 게시(commit message로만 응답하는 정책 유지)
- worktree·local 브랜치 정리(후속 단계 책임)
- reviewer·label·assignee 자동 지정
- watch 모드·자동 트리거 레이어

## 검증
이 명령이 0 exit으로 끝나야 합니다:
`bash tests/autopilot/test-loop-pr-phase.sh && bash tests/autopilot/test-loop-sh.sh`

- 신규 `test-loop-pr-phase.sh` — 새 phase 단위·e2e 시나리오: opt-out·새 PR 생성·기존 PR 재사용·push 실패·gh 호출 실패·이슈 자동 링크·메타 미설정·default 브랜치 감지 실패.
- 기존 `test-loop-sh.sh` — 기존 DONE 종료·worktree 동작이 깨지지 않음을 회귀 검증.
- e2e 단계의 GitHub 호출은 `gh` CLI stub(mock) 또는 일회용 sandbox 레포 중 워커가 선택하되, 둘 다 verify 안에서 0 exit으로 수렴해야 한다.

## 제약 (있을 때만)
- `gh` CLI 설치 + OAuth 인증 환경(개인 토큰·CI 토큰 미사용).
- `loop.sh`는 이미 약 1063줄. 새 phase 로직은 별도 함수 또는 helper script(예: `references/pr-phase.sh`)로 분리해 driver 비대화 회피.
- base 브랜치 자동 감지는 `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`와 `git symbolic-ref refs/remotes/origin/HEAD` 둘 중 하나로 충분. 둘 다 실패하면 수용 기준 10에 따라 abort.
- opt-in 활성화는 SPEC frontmatter 키(`request_review: true` 후보) 또는 CLI 플래그. 두 채널을 모두 둘지 한 채널만 둘지는 워커가 결정하되, `SKILL.md`·`spec-template.md`·driver 사이에 명칭과 의미가 동기화돼야 함.
- 기존 PR body 재사용 시 사용자 수기 편집 영역 보존을 위해 `<!-- autopilot:pr-body:begin --> ... <!-- autopilot:pr-body:end -->` marker fence 안 영역만 갱신.
- task-id가 `^[0-9]+$` 미매칭(nested·alpha 포함)이면 이슈 자동 링크는 생략.
- 답글 게시 안 함 — commit message에 결정 근거 명시(feedback memory 정책).
- 작업 환경: macOS·zsh. driver와 helper는 bash로 작성.

## 위험 (있을 때만)
- `gh pr edit`이 사용자의 수기 편집을 덮어쓸 위험. 제약의 marker fence로 격리하지만, 기존 PR body에 fence가 없으면 한 번은 전면 재작성됨 — 첫 갱신 직전 fence 삽입 로직 필요.
- default 브랜치 자동 감지 실패(신생 fork·shallow clone·`origin/HEAD` 미설정) 환경에서는 자동 fallback 없이 abort — 수용 기준 10의 의도 동작.
- 동일 task-id가 여러 branch로 분기된 경우 PR이 branch별로 분리됨(드물지만 추적 분산 가능).
- push 거부(non-FF·hook·권한) 시 자동 rebase·force-push 시도 안 함 — 즉시 abort.
- `request_review` opt-in 키·플래그 이름이 `SKILL.md`·`spec-template.md`·driver 사이에서 비동기화되면 활성 안 됨. 테스트가 동기화 회귀를 잡아야 함.

## 후속 task (분리됨)
이 SPEC은 분해된 첫 부분(PR 생성·재사용까지)입니다. 후속:
- 리뷰 코멘트 모니터링·자동 fix·완료 승인 감지·worktree·branch 정리까지의 phase — 본 SPEC 완료 후 별도 task-id로 `Skill(skill: "spec", args: "<id-followup>")` 호출. 같은 worktree·같은 task-id 컨벤션 위에서 다음 phase로 이어지도록 설계.
