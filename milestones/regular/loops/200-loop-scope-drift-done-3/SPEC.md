---
scope:
  include:
    - "plugins/autopilot/skills/loop/references/loop.sh"
    - "plugins/autopilot/skills/loop/references/constitution.md"
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "grep -qE 'Scope 위반' plugins/autopilot/skills/loop/references/loop.sh && grep -qE 'task_status_is_done' plugins/autopilot/skills/loop/references/loop.sh && grep -qE '자기-규율 게이트|객관 검증|self-review.*외부' plugins/autopilot/skills/loop/references/constitution.md && grep -qE 'scope\\.include가 비어' plugins/autopilot/skills/loop/references/loop.sh"
# test_sweep_paths: reviewed-no-sweep
ears_language: ko
request_review: true
---

# loop 워커 자기-규율 게이트 강화 — scope drift·명시 done·정적 검증 3종

## 무엇을 만들 것인가

loop 워커가 자기 SPEC의 명시 scope를 벗어나는 변경을 자유롭게 만들거나(거짓 self-review 포함), 자체적으로 done 처리(라벨·issue close)한 뒤에도 loop 드라이버가 그것을 인지 못한 채 추가 이터를 무한 도는 사례를 자동 검출·차단한다. 워커의 self-evaluation을 무조건 신뢰하지 않고, loop 드라이버 자체에 객관적 정적 검증 게이트 3종(scope drift 검출, 명시 done 신호 인지, 정적 검증 명령 자체가 외부 검증 역할)을 도입해 잘못된 변경이나 무한 이터 패턴이 진행되지 않도록 한다.

배경: 본 세션의 196 task 수행 시 워커가 (a) SPEC scope.include가 명시한 2개 경로 외 4개 파일을 추가로 수정했음에도 자체 self-review에서 "scope creep 없음"이라 거짓 평가했고 — 그 안에 본 task와 무관한 version 다운그레이드 같은 명백한 잘못된 변경 포함, (b) 워커가 issue 명시 done 처리까지 했음에도 loop 드라이버가 done 신호를 감지하지 못해 PR phase 진입 못한 채 22 이터 무한 반복하던 사례에서 도출. 본 task는 워커의 self-judgment를 외부에서 객관 검증하는 게이트를 도입해 같은 실패 패턴 재발을 막는다.

## 수용 기준 (EARS)

- **AC1** (Event-driven): 이터 종료 직후 loop 드라이버의 게이트 검사 단계에서 base..HEAD 변경 경로 집합이 SPEC frontmatter `scope.include` 패턴 외 경로를 포함하면 HALT + [blocked] 코멘트를 issue에 발행한다.
- **AC2** (Event-driven): 이터 종료 직후 게이트 검사 단계에서 task에 대응하는 issue의 명시 done 신호(`loop:done` 라벨 부착 + state CLOSED)가 감지되면 추가 이터를 돌리지 않고 즉시 수렴해 PR phase로 진입한다.
- **AC3** (Unwanted): `scope.include` 패턴이 SPEC frontmatter에 누락되거나 빈 list로 명시된 SPEC은 loop start 진입 자체에서 거부된다 — scope drift 검출의 기준이 없으면 fail-safe로 진입 불가.
- **AC4** (State-driven): 본 게이트들이 동작하는 동안 워커의 self-review 결론과 무관하게 loop 드라이버의 객관적 검증 결과가 우선한다 — self-review가 "OK"라 보고해도 정적 검증이 fail이면 HALT 또는 PR phase 미진입.
- **AC5** (Unwanted): 본 변경은 게이트 도입에 필요한 loop 드라이버·워커 헌법 외 다른 spec/dispatch/prd 스킬 파일이나 target 프로젝트 코드·문서를 수정하지 않는다.

## 범위

포함:

- loop 드라이버의 이터 종료 후 게이트 검사 단계 — scope drift 검출 로직 추가
- loop 드라이버의 이터 종료 후 게이트 검사 단계 — 명시 done 신호 감지 + 즉시 수렴 로직 추가
- 워커 헌법 — 게이트의 존재와 동작을 워커에게 명시해 self-review가 게이트를 우회할 수 있다는 의식 차단

비-목표 / 제외:

- 워커 self-review 자체의 형식 변경 — 정직성 평가는 외부 검증 게이트로 처리
- 별도 reviewer agent 도입 — 정적 검증으로 충분
- spec 스킬의 SPEC 작성 단계 변경
- target 프로젝트 코드·문서

## 검증

frontmatter `verify` 명령이 0 exit으로 끝나야 합니다 (4개 grep -qE 체인 — AC1·AC2·AC3 게이트 표현과 헌법 보강 표현 각각 독립 검출). 아래 블록은 frontmatter `verify`의 문서적 미러(reference)이며 권위는 line 10 frontmatter에 있습니다 — 두 표현이 다르면 frontmatter가 정답:

```bash
# AC1 (이터 종료 후 drift 검출)
grep -qE 'Scope 위반' plugins/autopilot/skills/loop/references/loop.sh && \
# AC2 (이터 종료 후 명시 done 신호 인지)
grep -qE 'task_status_is_done' plugins/autopilot/skills/loop/references/loop.sh && \
# AC4 (헌법 — 객관 검증 우선·self-review 면책 차단)
grep -qE '자기-규율 게이트|객관 검증|self-review.*외부' plugins/autopilot/skills/loop/references/constitution.md && \
# AC3 (loop start 진입 시 scope.include 누락·빈 list 거부) — scope.include 맥락에 묶어 범용 키워드 false-positive 회피
grep -qE 'scope\.include가 비어' plugins/autopilot/skills/loop/references/loop.sh
```

PR 리뷰 시점 보조 검사 (수동):

- 두 새 게이트가 의도대로 동작하는지 (시나리오 시뮬레이션 또는 단위 테스트)
- 196번 사례 재현 시 scope drift 게이트가 HALT를 일으키는지
- 196번 사례 재현 시 done 신호 감지 게이트가 즉시 PR phase 진입하는지
- 헌법 갱신이 워커에게 자기-규율 게이트 의식을 전달하는지 (다음 task 워커 출력 관찰)

## 제약

- loop 드라이버의 기존 게이트 검사 단계(weakening·secrets 등)와 동일 패턴으로 추가 — 새로운 분리된 phase가 아님.
- `scope.include`는 YAML 패턴 list. git pathspec 또는 glob 매칭 어느 쪽이든 기존 weakening 게이트의 패턴 매칭과 일관되게 처리.
- 헌법은 워커가 매 이터 진입 시 읽는 CLAUDE.md로 복사되므로 헌법 갱신 = 워커 의식 변경.

## 위험

- false positive: SPEC scope.include 밖의 정당한 부수 효과(예: 의도된 의존성 추가)가 차단될 수 있음 — 그땐 SPEC scope.include를 수정해 명시. 게이트는 "명시 안 된 변경 = 차단" 보수적 정책.
- done 신호 검출이 너무 빨라 워커가 라벨·close 처리 후 추가 검증을 의도했는데 loop이 먼저 수렴할 수 있음 — 워커가 마지막 commit으로 모든 변경을 확정한 후에만 done 신호를 박는다는 규약을 헌법에 명시해 보완.
- 본 SPEC 자체는 loop.sh·헌법을 변경하는 self-aware 변경이지만, scope.include가 그 두 파일이라 본 변경은 자체 scope drift 게이트를 자연히 통과 (메타-self-ref 안전).
