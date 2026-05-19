---
scope:
  include:
    - "plugins/autopilot/skills/loop/references/loop.sh"
    - "plugins/autopilot/skills/spec/SKILL.md"
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "grep -qE '마커 패턴 구조|콜론.*식별 신호|구체 질문 표식' plugins/autopilot/skills/loop/references/loop.sh && grep -qE '마커 패턴 구조|콜론.*식별 신호|구체 질문 표식' plugins/autopilot/skills/spec/SKILL.md"
# test_sweep_paths: reviewed-no-sweep
ears_language: ko
request_review: true
---

# loop 자율 마커 검출 식별 강화 — 마커 인용·escape를 진짜 마커와 구별

## 무엇을 만들 것인가

spec 워크플로우와 자율 루프 드라이버의 SPEC.md 마커 검사 로직이 마커 이름 인용·escape 표기를 실제 미해결 마커와 구별하지 못해 self-referential SPEC(예: 마커 자체의 동작을 정의하는 SPEC) 진입을 false-positive로 차단하는 문제가 있다. 본 task는 마커 검사가 "마커 패턴 구조"를 식별 신호로 삼아 진짜 마커만 잡고, 본문에서의 인용·escape 등장은 허용하도록 검출 로직을 통일·강화한다.

배경: 본 세션의 192번 SPEC이 새 게이트의 동작을 정의하기 위해 본문에 마커 이름을 4건 인용했으나 (AC 본문·verify grep 패턴 인용 등), 자율 루프 드라이버의 단순 substring 검사가 이를 미해결 마커로 오인해 loop start를 차단했다. spec 스킬의 --resume step 1도 동일한 검사 로직을 공유해 같은 false-positive를 갖는다. 근본 원인은 검사가 "마커 패턴 구조"(공식 마커가 실제 박힐 때의 표식)를 신호로 쓰지 않고 substring 매칭만 하기 때문이며, 처방은 그 구조적 표식을 식별 신호로 삼아 인용·escape 등장과 구별하는 것이다.

## 수용 기준 (EARS)

- **AC1** (Ubiquitous): 자율 루프 드라이버의 SPEC.md 마커 검사는 "마커 패턴 구조"(콜론 + 구체 질문 표식)를 식별 신호로 사용해 실제 미해결 마커만 차단한다.
- **AC2** (Ubiquitous): spec 스킬의 --resume 진입 시 마커 0개 판정 로직도 동일한 식별 신호 규칙을 사용해 self-referential SPEC의 인용·escape를 false-positive로 잡지 않는다.
- **AC3** (Event-driven): SPEC.md 본문에 마커 이름이 인용·escape 형태로만 등장하고 콜론 + 구체 질문 표식이 없으면 마커 검사는 통과한다 (loop start 진입 허용, --resume 진입 시 "해결할 마커 없음" 종료).
- **AC4** (Unwanted): 본 변경은 마커 검사가 위치한 지점 외에는 다른 어떤 spec/loop/dispatch/prd 스킬 파일도 수정하지 않으며 target 프로젝트 코드·문서도 건드리지 않는다.
- **AC5** (State-driven): 본 SPEC 자체의 호출은 옛 규칙으로 마치고, 새 식별 신호 규칙은 본 SPEC이 default 브랜치에 merge된 후의 다음 spec/loop 호출부터 효력을 가진다.

## 범위

포함:

- 자율 루프 드라이버의 진입 게이트에 있는 SPEC.md 마커 검사 로직
- spec 스킬의 --resume 진입 시 잔존 마커 0개 판정 로직

비-목표 / 제외:

- spec 스킬이 마커를 박을 때 사용하는 마커 형식 자체 — 이미 콜론 표식을 포함한 형식이라 변경 불요
- 192번 SPEC.md를 retroactive 갱신 — 새 규칙이 머지되면 자연 통과
- 다른 스킬 (`dispatch` · `prd` · loop의 본 진입 게이트 외 단계) — 영향 없음
- target 프로젝트 코드·문서

## 검증

이 명령이 0 exit으로 끝나야 합니다 (2개 grep -qE 체인 — 식별 신호 표현 검출):

```bash
grep -qE '마커 패턴 구조|콜론.*식별 신호|구체 질문 표식' plugins/autopilot/skills/loop/references/loop.sh && \
grep -qE '마커 패턴 구조|콜론.*식별 신호|구체 질문 표식' plugins/autopilot/skills/spec/SKILL.md
```

PR 리뷰 시점 보조 검사 (수동):

- 두 파일 모두 새 식별 신호 규칙에 따라 실제 검출 로직이 갱신됐는지 (코드 line 직접 확인)
- 192번 SPEC.md를 새 규칙으로 검사하면 통과하는지 (행동 검증)
- 본 SPEC.md를 새 규칙으로 검사하면 통과되는지 (self-ref 안전)

## 제약

- self-referential: 메모리 노트 `feedback_no_self_apply_during_spec`에 따라 본 SPEC 호출 자체는 옛 규칙으로 마치고, 새 식별 신호 규칙은 본 SPEC이 default 브랜치에 merge된 후의 다음 spec/loop 호출부터 효력.
- 본 SPEC.md 본문은 마커 이름의 substring을 박지 않는다 — 옛 단순 substring 검사가 본 SPEC.md commit 후 loop start를 차단하지 않도록 자연어 표현·우회 grep 패턴으로 self-ref 안전을 확보한다.
- spec 스킬이 박는 마커 형식 자체는 이미 콜론 + 구체 질문을 포함하므로 박기 측은 무손상이며 본 변경은 검출 측만 강화한다.

## 위험

- 새 식별 신호 규칙이 너무 좁아 정당한 마커 형식의 미해결 항목을 놓칠 수 있음 — 콜론 + 구체 질문 표식이 권장 마커 형식의 표준이므로 실무적 누락 가능성 낮음.
- 너무 넓어 본문 정상 텍스트를 진짜 마커로 오인할 수 있음 — 식별 신호 조합은 일반 문장에서 드물어 false-positive 낮음.
- 본 SPEC commit 후 loop start 진입 자체가 옛 규칙으로 검사됨 (self-ref). 본 SPEC.md에 마커 substring을 안 박는 본문 작성 규칙으로 회피.
