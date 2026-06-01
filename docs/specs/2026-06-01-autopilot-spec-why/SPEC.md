---
scope:
  include:
    - plugins/autopilot/skills/spec/**
    - plugins/autopilot/.claude-plugin/plugin.json
    - tests/autopilot/test-spec-skill.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# autopilot:spec 에 WHY(목적) 섹션 추가

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
`autopilot:spec` 스킬이 발행하는 SPEC 문서에 변경의 **WHY(왜 이 변경을 하는가, 목적)**를 1급 산출물로 보존하도록 만든다. 현재는 WHAT(완료 조건)만 문서에 남고 WHY는 인터뷰 중 평가만 된 뒤 휘발한다 — 이 변경은 (a) SPEC 템플릿에 WHY를 담는 자리를 신설하고, (b) 명확화 인터뷰의 목적 커버리지를 종결 게이트로 승격하며, (c) 자체 검토·clarity 리드아웃·테스트 계약이 그 WHY 보존을 점검하도록 한다. WHY는 완료 조건을 대체하지 않고 그 의도 방향을 보조하는 종속 앵커로만 둔다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- **항상**: SPEC 템플릿에는 "무엇을 만들 것인가" 다음이자 "완료 조건" 앞 위치에 목적을 담는 별도 섹션과 그 자리를 채우는 placeholder 한 칸이 존재해야 한다. (해당 섹션 제목과 placeholder 토큰이 템플릿 파일에서 grep으로 확인되고, 그 위치가 "무엇을 만들 것인가" 뒤·"완료 조건" 앞이어야 한다.)
- **항상**: SPEC 작성 단계 지침에는 그 목적 placeholder가 치환 대상 목록에 포함되고, 목적은 별도 섹션에 1–3문장으로 두며 완료 조건의 종속 앵커이고 검증 기준이 아니라는 규칙이 명시돼야 한다.
- **…할 때**: 사용자가 간단한 변경 task로 인터뷰를 끝까지 진행해 SPEC이 발행될 때, 발행된 SPEC 문서에는 그 목적 섹션이 비어있지 않게 채워져 있어야 한다.
- **…이면(오류)**: 인터뷰 종결 시 변경의 목적(왜)이 모호성 없이 잡히지 않았으면, 발행 SPEC의 목적 섹션 자리에 목적/왜를 묻는 미해결 마커(`[NEEDS CLARIFICATION: ...]`)가 남아야 한다.
- **항상**: 명확화 인터뷰 방법론 문서의 "충분" 종결 조건 목록에 "변경의 목적(왜)이 모호성 없이 잡혔다"가 포함돼야 한다.
- **항상**: clarity 점수 문서의 목적 차원 설명이 "목적(왜)이 SPEC 문서에 문장으로 남았는가"라는 보존 의무와 연결돼 있어야 한다(차원·척도·임계 구조 자체는 그대로 유지).
- **항상**: 자체 검토 문서의 검사 항목 수는 5개로 유지되어야 하며(여섯 번째 축 신설 없음), 그 5개 중 한 축이 목적 섹션이 비어있지 않고 WHAT·완료 조건과 정합하는지를 점검하도록 흡수돼야 한다.
- **항상**: 스킬 본문(SKILL.md)의 워크플로 단계 헤더 수는 정확히 7이어야 한다(목적 보존을 위한 새 단계 헤더를 추가하지 않는다).
- **항상**: 스킬 본문(SKILL.md)에는 대문자 약어 `EARS` 문자열이 없어야 하고, "WHAT/HOW" 방어선 명시와 "완료 조건" 라벨이 보존돼야 한다.
- **항상**: 플러그인 매니페스트의 버전 값이 `0.14.0`이어야 한다.
- **항상**: spec 스킬 계약 테스트 스크립트가 위 목적 섹션·placeholder 존재와 SKILL.md의 목적 종속 명시를 단언하는 검사를 포함해야 한다.
- **항상**: 변경 후 `tests/autopilot/test-spec-skill.sh`와 `tests/autopilot/test-spec-skill-frontmatter.sh`가 종료 코드 0으로 통과해야 한다(기존 단언과 신 목적 단언이 함께 green).

## 범위
포함:
- `plugins/autopilot/skills/spec/references/spec-template.md` — 목적 섹션 + placeholder 신설
- `plugins/autopilot/skills/spec/SKILL.md` — step 5 placeholder 목록·목적 규칙, step 3 종결 게이트 문구
- `plugins/autopilot/skills/spec/references/clarification.md` — "충분" 종결 조건에 목적 항목 추가
- `plugins/autopilot/skills/spec/references/clarity-score.md` — 목적 차원을 보존 의무와 연결
- `plugins/autopilot/skills/spec/references/self-review.md` — 5축 중 한 축에 목적 섹션 점검 흡수
- `plugins/autopilot/.claude-plugin/plugin.json` — 버전 0.13.1 → 0.14.0
- `tests/autopilot/test-spec-skill.sh` — 신 목적 계약 단언 추가

비-목표 / 제외:
- 완료 조건(5문장 패턴) 문법·언어 규칙 변경 없음 — 목적은 완료 조건에 인코딩하지 않는다.
- clarity 점수의 척도·임계·전체 게이트화 없음 — 목적 한정 종결 게이트만 하드화하고 나머지는 소프트 권고 유지.
- 자체 검토 축 개수 변경 없음(5축 유지).
- spec 스킬 외 다른 스킬(loop·dispatch·conductor)·rules·CLAUDE.md 변경 없음.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 스킬 본문(SKILL.md)의 워크플로 단계 헤더 수는 정확히 7로 유지한다. 목적 보존 로직은 새 단계가 아니라 기존 단계 3(명확화 인터뷰)·5(SPEC 작성)·6(자체 검토) 본문 안에 흡수한다.
- SKILL.md 본문에 대문자 `EARS` 문자열을 도입하지 않는다(소문자 `references/ears-patterns.md` 경로 참조는 허용). "WHAT/HOW" 방어선과 "완료 조건" 라벨을 보존한다.
- 자체 검토는 5축 계약을 유지한다 — 여섯 번째 축을 신설하지 않고 기존 축에 목적 점검을 흡수한다.
- 목적 섹션 내용은 1–3문장의 목표·동기로 제한하고, 완료 조건의 종속 앵커로만 둔다. 목적을 완료 조건(트리거·조건·응답)에 인코딩하지 않는다.
- 버전의 단일 출처는 플러그인 매니페스트(`plugin.json`)이며, `plugins/`는 워치 디렉토리이므로 이 변경이 머지되는 같은 변경 안에서 버전이 올라가야 한다(`rules/engineering/versioning.md`).
- SKILL.md를 편집할 때는 스킬 작성 가이드(`superpowers:writing-skills`)를 경유한다.

## 위험
- step 흡수에 실패해 새 단계 헤더를 추가하면 계약 테스트의 7단계 단언이 깨진다 → 목적 로직을 단계 3·5·6 본문 문장으로만 추가해 헤더 수를 보존한다.
- 목적 섹션을 장황하게 쓰면 구현 모델이 완료 조건을 재해석할 여지가 생긴다 → 1–3문장 제한과 "완료 조건의 종속 앵커, 검증 기준 아님" 규칙을 템플릿 주석과 작성 지침에 함께 박는다.
- 목적 종결 게이트가 너무 강하면 사소한 변경에서도 마커가 남발될 수 있다 → 기존 미해결 마커 위임 메커니즘을 재사용하고, 목적이 최초 진술에서 이미 명확하면 마커를 남기지 않는다.
