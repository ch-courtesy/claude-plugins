---
scope:
  include:
    - plugins/autopilot/skills/spec/**
    - plugins/autopilot/skills/loop/**
    - plugins/autopilot/skills/dispatch/**
    - rules/engineering/branch-and-slug.md
    - docs/specs/**
    - tests/autopilot/**
  exclude:
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# spec/loop/dispatch: per-spec directory layout 전환

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

SPEC 문서의 저장 컨벤션을 **단일 파일**에서 **per-spec 디렉토리**로 바꾼다.

- 현재: 각 SPEC은 `docs/specs/<YYYY-MM-DD>-<slug>.md` 단일 파일이다. 그리고 loop 실행이 만드는 per-spec 아티팩트(워크트리·락·실행 메타·신호)가 모두 공통 부모인 `docs/specs/` 최상위에 형제로 흩뿌려져, 서로 다른 스펙의 실행이 같은 락·워크트리 경로를 공유해 충돌한다.
- 변경: 각 SPEC은 자신의 디렉토리 `docs/specs/<YYYY-MM-DD>-<slug>/`를 가지며, 문서 본문은 그 안의 `SPEC.md`에 둔다. 그 스펙의 loop 실행이 만드는 모든 per-spec 아티팩트(워크트리·락·실행 메타·신호)는 **그 스펙 디렉토리 하위에만** 생성되어, 스펙별로 격리된다.

이 전환은 SPEC을 산출하는 쪽(spec 스킬 작성 경로), SPEC을 입력으로 읽어 실행하는 쪽(loop 실행, dispatch DAG 해석, spec `--resume`), 그리고 컨벤션의 단일 출처(slug·파일명 규칙 문서)에 일관되게 적용된다. 기존에 단일 파일로 저장된 SPEC들은 새 레이아웃으로 이전한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

1. (Ubiquitous) spec 스킬이 새 SPEC을 작성하면, 산출물은 항상 `docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md` 디렉토리 레이아웃으로 생성되어야 하며, `docs/specs/<YYYY-MM-DD>-<slug>.md` 단일 파일은 생성하지 않아야 한다.

2. (Event-driven) When loop이 한 스펙에 대해 실행되면, 그 실행이 만드는 워크트리·락·실행 메타·신호 등 모든 per-spec 아티팩트는 그 스펙의 `docs/specs/<YYYY-MM-DD>-<slug>/` 디렉토리 하위에 생성되어야 하며, `docs/specs/` 최상위나 다른 스펙의 디렉토리에는 생성하지 않아야 한다.

3. (State-driven) While 서로 다른 두 스펙이 동시에 loop으로 실행되는 동안, 두 실행의 락·워크트리·신호 아티팩트는 각자의 스펙 디렉토리에 격리되어 서로 충돌하거나 덮어쓰지 않아야 한다.

4. (Ubiquitous) loop 실행·dispatch DAG 해석·spec `--resume`가 스펙 문서 경로를 입력으로 받을 때, 구 형식(`<YYYY-MM-DD>-<slug>.md`)과 신 형식(`<YYYY-MM-DD>-<slug>/SPEC.md`) 경로를 모두 정상적으로 해석·실행해야 한다.

5. (Ubiquitous) dispatch가 신 형식 스펙 경로에서 slug·상태 식별자·`depends_on` 의존성을 해석할 때, 구 형식과 동일한 의미의 slug를 도출하고 형제 SPEC 의존성을 올바르게 찾아 해석해야 한다.

6. (If) If 스펙 제목에서 빈 slug가 도출되면, fallback 디렉토리를 만들지 않고 abort하여 제목 수정을 요청해야 한다.

7. (Event-driven) When 기존 `docs/specs/`의 단일 파일 SPEC들을 이전하면, 각 SPEC은 대응하는 `<YYYY-MM-DD>-<slug>/SPEC.md`로 옮겨져 있어야 하고, 이전 후 같은 slug의 구 단일 파일 경로는 남지 않아야 한다.

8. (Ubiquitous) slug·파일명 컨벤션의 단일 출처 규칙 문서는 산출 경로를 신 디렉토리 레이아웃(`<YYYY-MM-DD>-<slug>/SPEC.md`)으로 기술해야 하고, 그 문서 안의 모든 경로 예시·commit 스테이징 지시가 신 레이아웃과 일치해야 하며, 구 단일 파일 경로 표현이 남지 않아야 한다.

## 범위
포함:
- spec 스킬: SPEC 작성 산출 경로를 신 디렉토리 레이아웃으로 변경. `--resume` 입력 경로는 구·신 형식 모두 수용.
- loop 스킬: per-spec 아티팩트(워크트리·락·실행 메타·신호)가 스펙 디렉토리 하위에 격리되도록 보장. 스펙 경로 입력은 구·신 형식 모두 수용. 관련 문서·테스트의 경로 표현 갱신.
- dispatch 스킬: 신 형식 스펙 경로에서 slug·상태 식별자·`depends_on` 해석이 동작하도록 갱신. 구 형식 경로 입력도 계속 수용.
- slug·파일명 컨벤션 단일 출처 규칙 문서: 신 레이아웃으로 갱신(파일명 규칙 + commit 스테이징 절차).
- 기존 `docs/specs/`의 단일 파일 SPEC들을 신 레이아웃으로 이전.

비-목표 / 제외:
- SPEC 본문 파일명을 `SPEC.md` 외의 다른 이름으로 두는 변형.
- per-spec 디렉토리 안의 아티팩트(워크트리·락·신호) 내부 포맷·이름 변경 — 위치만 스펙 디렉토리 하위로 격리하고 포맷은 유지.
- 검증 진입 명령(테스트·lint·빌드)의 정의 — 프로젝트 규칙이 단일 출처.
- slug 도출 알고리즘 자체의 변경(ASCII lowercase·치환·압축 규칙은 유지).

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 경로 컨벤션의 단일 출처는 slug·파일명 규칙 문서이며, spec·loop·dispatch 세 스킬은 그 문서가 정의한 레이아웃을 따른다. 세 스킬과 규칙 문서 사이에 경로 표현이 불일치하면 결함으로 본다.
- "어떤 형식이든 수용"은 스펙 경로를 **읽어 실행·해석하는** 쪽(loop 실행, dispatch DAG 해석, spec `--resume`)에만 적용된다. spec **작성(authoring)** 모드는 항상 신 형식만 산출한다.
- backward-compat 해석 로직은 신 형식의 스펙 디렉토리 자체를 스펙 본문으로 오인하지 않아야 한다 — 디렉토리(`<slug>/`)와 본문(`<slug>/SPEC.md`)을 구분해 해석한다.
- 마이그레이션은 현재 `docs/specs/` 최상위에 남아 있을 수 있는 실행 중 흔적(락·워크트리 메타)을 인지하고, 활성 loop 실행 상태를 깨지 않도록 처리한다.

## 위험 (있을 때만)
- dispatch의 slug 충돌 식별(상태 파일 `state.<slug>-<sha7>` 류)과 `depends_on` 형제 매칭이 신 레이아웃에서 회귀할 수 있다 — 다른 날짜 같은 slug, 같은 basename 입력 충돌 케이스.
- 현재 `docs/specs/` 최상위에 실행 중 loop 흔적(락 PID·워크트리)이 존재하여, 마이그레이션이 진행 중 실행과 경합할 수 있다.
- loop의 정리(cleanup) 검증과 실행 목록 스캔이 워크트리·락·메타를 고정 경로/깊이로 가정하고 있어, 신 레이아웃의 디렉토리 깊이 변화에 맞춰 함께 갱신되지 않으면 목록·정리가 누락될 수 있다.
- 이 SPEC 문서 자신을 포함한 기존 SPEC들의 이전 중, 구·신 형식을 동시에 수용하는 과도기 로직의 경계 오류로 같은 스펙이 두 번 인식될 수 있다.
