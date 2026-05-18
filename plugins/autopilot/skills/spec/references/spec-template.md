---
scope:
  include: {{scope_include}}
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "{{verify_command}}"
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
#
# ears_language (선택): "수용 기준 (EARS)" 산출 시 사용할 작성 언어. 허용 값:
#   `ko` · `en` · `hybrid`. 미명시 시 디폴트는 `ko`(프로젝트 기본 언어).
#   3모드 정의·예시는 references/ears-patterns.md "EARS 작성 언어" 절 참조.
# ears_language: ko
#
# request_review (default true): loop이 task DONE 직후 PR **자동 리뷰·머지 루프**를
#   활성화한다. PR 생성·재사용 자체는 default ON으로 본 키와 무관하며, 차단하려면 `--no-pr`
#   플래그를 쓴다. true면 PR 생성·재사용 직후 추가로:
#     1) pre-PR rebase (default 브랜치 기준, 충돌 시 1회 자동 해소),
#     2) review-fix 백그라운드 루프 (30s 폴링 — 새 PR 코멘트·리뷰마다 재-rebase → 자동 fix
#        → commit·push, 필요 시 1개 반박 코멘트),
#     3) 자동 머지 (reviewDecision `APPROVED` 또는 owner `/done`·`합격`·`통과` 코멘트 →
#        `gh pr merge --squash`),
#     4) cleanup (머지 후 worktree 제거 + 로컬·origin feat 브랜치 삭제).
#   비활성화하려면 `request_review: false`로 명시. 키 자체를 생략하면 loop의 yq fallback에
#   따라 false로 처리됨 (이전 동작 보존 — 기존 SPEC들 영향 없음).
#   요구: `gh` CLI(OAuth 인증) + `yq`. 자세한 동작은 plugins/autopilot/skills/loop/SKILL.md 참조.
request_review: true
---

# {{task_title}}

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 이 섹션은 *무엇을* 만드는지만 적습니다. 기술 스택·파일 경로·라이브러리·클래스명 등 구현 결정은 "제약" 섹션으로 옮기세요. loop이 자율적으로 접근법을 조정할 수 있도록 의도를 기술-중립적으로. -->
{{task_description}}

## 수용 기준 (EARS)
<!-- 5개 EARS 패턴 중 하나로 작성. 자세한 사례는 references/ears-patterns.md 참조.
  작성 언어 default는 `ko`(프로젝트 기본 언어). 아래 형식은 ko 기준 — en·hybrid는
  references/ears-patterns.md "EARS 작성 언어" 절 참조.
  - Ubiquitous: "시스템은 <응답>한다"
  - Event-driven: "<트리거>할 때, 시스템은 <응답>한다"
  - State-driven: "<상태>인 동안, 시스템은 <지속 응답>한다"
  - Optional: "<조건>인 경우, 시스템은 <응답>한다"
  - Unwanted: "<불가용/오류>이면, 시스템은 <복구·거부>한다"

frontmatter `ears_language` 키로 개별 SPEC이 `en`·`ko`·`hybrid` 중 하나를
override할 수 있다(미명시 시 ko).

각 기준이 verify 명령 안에서 *어떤 형태로든* fail 가능해야 합니다 (Independent-Test 규칙). 불가능한 기준은 [NEEDS CLARIFICATION: <질문>]으로 표시. -->
{{acceptance_criteria}}

## 범위
포함:
{{scope_in}}

비-목표 / 제외:
{{scope_out}}

## 검증
이 명령이 0 exit으로 끝나야 합니다:
{{verify_command}}

## 제약 (있을 때만)
<!-- 환경·도구·호환성·성능 등 알려진 제약. 워커가 이를 모르면 잘못된 가정으로 시간 낭비.
  WHAT/HOW 방어선 결과 "무엇을 만들 것인가"에서 빠진 기술 스택·라이브러리·테스트 스타일 가이드도 여기에. -->
{{constraints}}

## 위험 (있을 때만)
<!-- 이미 알려진 dead-end·함정·금지 영역. 워커의 NOTES.md "실패한 접근"의 사전 시드. -->
{{risks}}
