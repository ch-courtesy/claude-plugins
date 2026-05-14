---
scope:
  include: ["plugins/autopilot/skills/spec/SKILL.md"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: 'desc=$(grep -E "^description: " plugins/autopilot/skills/spec/SKILL.md) && echo "$desc" | grep -qE "(새로 만들|기능 추가|동작 수정|지침 작성)" && echo "$desc" | grep -qE "(SPEC\.md|feat 브랜치|autopilot loop|PR)" && ! echo "$desc" | grep -qi "brainstorm"'
ears_language: ko
---

# autopilot:spec description 강화 — 창작·신규 작성 신호에서 자연 우선 선택

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 이 섹션은 *무엇을* 만드는지만 적습니다. 기술 스택·파일 경로·라이브러리·클래스명 등 구현 결정은 "제약" 섹션으로 옮기세요. loop이 자율적으로 접근법을 조정할 수 있도록 의도를 기술-중립적으로. -->
autopilot:spec 스킬의 description을 보강한다.

(i) "X 새로 만들자", "기능 추가", "동작 수정", "지침 작성" 등 창작·신규 작성 신호를 한국어 어휘로 풍부하게 포함한다.

(ii) 이 레포의 표준 워크플로우 — 자기완결적 SPEC.md 작성 → feat 브랜치 분기·SPEC commit → autopilot loop 실행 → PR — 를 description 안에 명시한다.

변경 대상은 description 텍스트 한 곳에 한정한다. 다른 스킬·hook·매칭 로직은 건들지 않는다.

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

각 기준이 verify 명령 안에서 *어떤 형태로든* fail 가능해야 합니다 (Independent-Test 규칙). 불가능한 기준은 명확화 마커로 표시. -->
- [Ubiquitous] autopilot:spec의 description은 "새로 만들", "기능 추가", "동작 수정", "지침 작성" 등 창작·신규 작성 트리거 어휘를 포함한다.
- [Ubiquitous] autopilot:spec의 description은 자기완결적 SPEC.md·feat 브랜치·autopilot loop·PR 연계가 이 레포의 표준 워크플로우임을 명시한다.
- [State-driven] description 텍스트가 다른 스킬 이름(brainstorming 등)을 명시적으로 언급하지 않은 상태가 유지된다.
- [Event-driven] 사용자가 "X 새로 만들자", "Y 작성", "Z 추가", "동작 수정" 류 자연어 신호를 보낼 때, 모델이 autopilot:spec을 후보로 식별한다 (수동 트리거 테스트로 정성 검증).
- [Unwanted] 사용자가 brainstorming 또는 plan mode를 명시적으로 요청한 경우, 변경된 description이 그 명시 요청을 덮지 않는다 (description에 강제 명령형 표현을 쓰지 않음으로 달성).

## 범위
포함:
- `plugins/autopilot/skills/spec/SKILL.md`의 frontmatter `description:` 값

비-목표 / 제외:
- SKILL.md 본문 텍스트 (description 이외 영역)
- 다른 스킬(superpowers:brainstorming 포함), hooks, settings.json, harness skill 매칭 로직
- 영어 트리거 어휘 흡수 — 본 작업은 한국어 자연어 입력 중심으로 한정
- "brainstorming 금지" 같은 명시적 룰·훅 도입

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
desc=$(grep -E "^description: " plugins/autopilot/skills/spec/SKILL.md) \
  && echo "$desc" | grep -qE "(새로 만들|기능 추가|동작 수정|지침 작성)" \
  && echo "$desc" | grep -qE "(SPEC\.md|feat 브랜치|autopilot loop|PR)" \
  && ! echo "$desc" | grep -qi "brainstorm"
```

(description 라인 한 줄로 범위를 좁혀 본문에 이미 있는 키워드와 격리.)

수동 트리거 테스트(정성, 별도 기록): 새 세션에서 `"지침 새로 만들자"`·`"기능 추가하자"` 입력 시 autopilot:spec이 후보로 등장하는지 확인.

## 제약 (있을 때만)
<!-- 환경·도구·호환성·성능 등 알려진 제약. 워커가 이를 모르면 잘못된 가정으로 시간 낭비.
  WHAT/HOW 방어선 결과 "무엇을 만들 것인가"에서 빠진 기술 스택·라이브러리·테스트 스타일 가이드도 여기에. -->
- frontmatter YAML 형식·이스케이프를 유지한다 (단일 라인 double-quoted string).
- 기존 호출 형식 안내(`Skill(skill="spec", args="<task-id> [--milestone <m>] [--resume]")`)는 description에 남기거나 SKILL.md 본문으로 이동한다 — 손실 없이 보존한다.

## 위험 (있을 때만)
<!-- 이미 알려진 dead-end·함정·금지 영역. 워커의 NOTES.md "실패한 접근"의 사전 시드. -->
- description이 길어져 일부 IDE의 스킬 목록 표시에서 잘릴 가능성. 길이 균형을 고려해야 한다.
- 영어 자연어 입력에서는 여전히 superpowers:brainstorming이 우선 매칭될 수 있다 — 본 작업은 한국어 입력 중심 trade-off를 의도적으로 수용한다.
