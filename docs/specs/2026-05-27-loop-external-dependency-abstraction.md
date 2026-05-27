---
scope:
  include:
    - rules/external-dependencies.md
    - plugins/autopilot/skills/loop/SKILL.md
    - plugins/autopilot/skills/loop/references/constitution.md
  exclude:
    - plugins/autopilot/skills/loop/references/*.sh
    - milestones/**
    - CLAUDE.md
verify: "test -f rules/external-dependencies.md && grep -q forge rules/external-dependencies.md && grep -q '워커 엔진' rules/external-dependencies.md && grep -q 유틸 rules/external-dependencies.md && grep -q context.md rules/external-dependencies.md && grep -q external-dependencies plugins/autopilot/skills/loop/SKILL.md && grep -q external-dependencies plugins/autopilot/skills/loop/references/constitution.md"
# test_sweep_paths: reviewed-no-sweep
# test_paths: optional git pathspec override for weakening gate.
# test_sweep_paths: optional git pathspec whitelist for legitimate test rename/cleanup/delete sweep.
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# loop external-dependency abstraction 지침

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
loop 스킬이 사용하는 외부 의존을 "추상 능력 어휘 ↔ 구체 매핑" 두 층으로 분리하는 지침 문서를 만든다.

지침은 네 능력 도메인 각각에 대해 추상 어휘와 이 프로젝트의 구체 매핑을 **단일 출처**로 정의한다:

1. **forge 연산** — 변경 제안(PR)의 생성·재사용, 리뷰 채널의 폴링·응답, 통합(머지), 통합 후 정리.
2. **task storage** — 완료·상태·인계 신호와 식별자. 이 도메인의 구체 매핑은 기존 컨텍스트 관리 지침을 단일 출처로 **참조**하며 중복 정의하지 않는다.
3. **워커 엔진** — 매 이터레이션을 실행하는 무인 실행 엔진.
4. **유틸(보조) 도구** — 설정 파싱, secret 스캔, 체크섬 산출 등 보조 능력.

그리고 loop 스킬의 헌법과 스킬 정의 문서는 흐름·동작을 위 추상 어휘로 서술하고, 구체 매핑의 단일 출처로 이 지침을 가리키도록 재서술한다. 결과적으로 backend·forge·엔진·보조 도구를 교체할 때 이 지침 하나만 갱신하면 스킬 본문과 헌법은 불변이어야 한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 verify에서 fail 가능해야 함. -->
1. 시스템은 외부 의존 추상화 지침 문서를 제공해야 한다.
2. 시스템은 그 지침에서 forge 연산·task storage·워커 엔진·유틸 도구 네 도메인 각각에 대해 추상 어휘와 구체 매핑을 정의해야 한다.
3. task storage 도메인의 구체 매핑에 대해, 시스템은 기존 컨텍스트 관리 지침을 단일 출처로 참조해야 하며 같은 매핑을 중복 정의하지 않아야 한다.
4. loop 스킬 정의 문서는 forge·워커·유틸 흐름을 추상 어휘로 서술하고 구체 매핑의 단일 출처로 이 지침을 참조해야 한다.
5. loop 헌법의 추상 어휘는 forge·워커·유틸 능력을 포함하고 그 구체 매핑 책임을 이 지침에 위임해야 한다.
6. 시스템은 loop 스킬의 의존성 목록을 런타임 사실로 유지하되, 그 목록이 구체 매핑의 유일한 출처가 되지 않도록 해야 한다.
7. phase 실행 스크립트(변경 제안·리뷰·통합·동기화)가 이 작업의 변경 대상이 될 때, 시스템은 그 변경을 거부해야 한다.

## 범위
포함:
- 외부 의존 추상화 지침 문서 신설.
- loop 스킬 정의 문서를 추상 어휘 + 지침 참조로 재서술.
- loop 헌법의 추상 어휘 섹션을 forge·워커·유틸 능력까지 확장하고 매핑 책임을 지침에 위임.

비-목표 / 제외:
- forge·워커·유틸을 호출하는 phase 실행 스크립트의 코드 리팩토링 (불변 유지).
- 추상화 인터페이스·플러그인 코드 도입 (이번 작업은 지침 기반 분리만).
- task storage 매핑의 재정의 (기존 컨텍스트 관리 지침을 참조만).
- 기본값과 다른 새 backend·엔진·도구의 실제 도입.

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
test -f rules/external-dependencies.md \
  && grep -q forge rules/external-dependencies.md \
  && grep -q '워커 엔진' rules/external-dependencies.md \
  && grep -q 유틸 rules/external-dependencies.md \
  && grep -q context.md rules/external-dependencies.md \
  && grep -q external-dependencies plugins/autopilot/skills/loop/SKILL.md \
  && grep -q external-dependencies plugins/autopilot/skills/loop/references/constitution.md
```

## 제약 (있을 때만)
- 헌법(constitution.md)은 워커가 수정할 수 없는 거버넌스 문서이고, 헌법은 "설계·명세 문서 수정 금지"를 규정한다. 이 SPEC은 헌법과 스킬 정의 문서를 수정 대상으로 포함하므로 **autopilot:loop 자율 워커로 실행할 수 없다**(self-referential). 직접(대화형) 구현으로 진행한다.
- WHAT만 정의한다. 지침 문서의 구조·소제목·문구는 구현 재량이다.
- 구체 매핑은 이 프로젝트의 현재 기본값을 기술하되 특정 명령 나열은 최소화한다.
- 워크트리·문서에 secrets·credentials를 두지 않는다.

## 위험 (있을 때만)
- **self-referential**: SPEC이 loop 자신의 스킬 정의·헌법을 수정한다. autopilot:loop로 실행하면 헌법의 "워커는 헌법을 수정하지 않는다"·"설계·명세 문서 수정 금지"와 충돌해 워커가 거부/ESCALATION한다. → loop 비권장, 직접 구현.
- **추상화 과잉**: 의존성 목록까지 추상화하면 실제 런타임 요구가 흐려진다. → 의존성 목록은 사실로 유지(수용 기준 6).
- **단일 출처 위반**: task storage 매핑을 새 지침과 컨텍스트 관리 지침 양쪽에 적으면 중복이 된다. → 참조로만 연결(수용 기준 3).
