---
scope:
  include:
    - plugins/autopilot/skills/loop/SKILL.md
  exclude:
    - plugins/autopilot/skills/loop/references/**
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# loop start 시그니처의 loop.sh 인자·SKILL 차원 옵션 경계 명시

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

`autopilot:loop` 스킬 문서(`SKILL.md`)의 `start` 서브커맨드 시그니처가, **`loop.sh`로 전달되는 인자**와 **`loop.sh`로 전달하면 안 되는 SKILL 차원 모니터링 옵션**을 한눈에 구분할 수 있도록 다시 표기한다.

현재 `start` 헤딩은 네 플래그를 한 bracket 묶음으로 나열한다:

```
### start <spec-path> [--max-iterations N] [--wall-clock-minutes N] [--no-monitor] [--events-only]
```

그리고 바로 다음 줄이 `Bash(bash $SKILL_DIR/references/loop.sh start <spec-path> [...flags] ...)`로 호출하라고 지시한다. 두 줄이 합쳐져 **네 플래그 전부가 `loop.sh start`의 인자**라는 인상을 준다. 그러나 실제로는 네 개 중 두 개만 `loop.sh`가 받는 인자다:

| 플래그 | 차원 | loop.sh 전달 |
|---|---|---|
| `--max-iterations N` | loop.sh 인자 | 전달함 |
| `--wall-clock-minutes N` | loop.sh 인자 | 전달함 |
| `--no-monitor` | SKILL 차원(모니터링) | **전달 안 함** |
| `--events-only` | SKILL 차원(모니터링) | **전달 안 함** |

`loop.sh`의 `start` 파서는 `--max-iterations`·`--wall-clock-minutes` 외의 옵션을 만나면 `lock 획득 전`에 `die "알 수 없는 옵션"`으로 즉시 실패한다. 그래서 SKILL 차원 옵션을 `[...flags]` 자리에 함께 넘기면 lock도 못 잡고 실행이 죽는다. 경계를 설명하는 문장은 현재 Monitor 절(시그니처에서 여러 줄 떨어진 산문)에만 있어, 명령을 조립하려고 시그니처를 읽는 시점에는 보이지 않는다 — 이것이 같은 실수가 반복되는 affordance 결함이다.

해결 방향(확정된 렌더링): `start` 헤딩 bracket에는 `loop.sh`가 실제로 받는 인자(`--max-iterations`·`--wall-clock-minutes`)만 남기고, SKILL 차원 모니터링 옵션(`--no-monitor`·`--events-only`)은 헤딩 bracket에서 제거한다. 대신 시그니처 **바로 인접 위치**에, 그 두 옵션이 SKILL 차원이며 `loop.sh`에 전달하지 않는다는 점과 상세는 Monitor 절을 보라는 짧은 주석을 둔다.

이 변경은 문서(`SKILL.md`)의 표기만 바꾼다. `loop.sh`의 동작·파서·플래그 처리, Monitor 절이 기술하는 `--no-monitor`/`--events-only`의 실제 의미는 바꾸지 않는다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. THE `start` 서브커맨드 헤딩의 인자 bracket 묶음은 `loop.sh`가 실제로 받는 인자(`--max-iterations`·`--wall-clock-minutes`)만 포함하고 `--no-monitor`·`--events-only`를 포함하지 않아야 한다.
2. THE `--no-monitor`·`--events-only`가 SKILL 차원 옵션이며 `loop.sh`에 전달하지 않는다는 안내는, `start` 헤딩과 같은 화면에서 함께 읽히는 인접 위치(헤딩과 첫 본문 단락 사이)에 있어야 한다.
3. THE 그 인접 안내는 두 옵션의 상세를 중복 기술하지 않고 Monitor 절(또는 동등한 단일 출처)을 가리키는 포인터 형태여야 한다.
4. WHEN 독자가 `start` 시그니처만 읽고 `loop.sh start` 명령을 조립할 때, 헤딩 bracket의 플래그를 그대로 `loop.sh`에 전달해도 `알 수 없는 옵션` 실패가 발생하지 않아야 한다(헤딩 bracket에 SKILL 차원 옵션이 더는 없으므로).
5. THE Monitor 절(현재 47행)의 `--no-monitor`·`--events-only` 의미 설명과 우선순위 규칙(`--no-monitor`가 함께 있으면 우선)은 본 변경으로 의미가 약화·삭제되지 않고 유지되어야 한다.
6. THE `loop.sh`의 인자 파서·플래그 처리·동작은 본 변경으로 수정되지 않아야 한다(문서만 변경).
7. THE 변경 후 문서는 두 SKILL 차원 옵션을 `loop.sh` 인자처럼 보이게 하는 다른 표기(예: `[...flags]` 예시 안에 섞어 넣기)를 새로 만들지 않아야 한다.

## 범위
포함:
- `plugins/autopilot/skills/loop/SKILL.md`의 `start` 서브커맨드 시그니처 헤딩(현 39행) 및 그 인접 안내(헤딩과 첫 본문 단락 사이)의 표기 수정.
- SKILL 차원 모니터링 옵션 경계를 시그니처 인접 위치에서 즉시 알 수 있게 하는 짧은 포인터 문구 추가.

비-목표 / 제외:
- `references/loop.sh`의 인자 파서·플래그·동작 변경 — 본 변경은 문서 표기만 고친다.
- Monitor 절의 `--no-monitor`/`--events-only` 의미 재정의 — 기존 설명은 유지하고 포인터만 추가한다.
- 다른 서브커맨드(`status`/`stop`/`list`/`cleanup`/`logs`/`env`/`gates`/`paths`/`deps`) 시그니처 표기 변경.
- `dispatch`·`conductor` 등 다른 스킬 문서나 `loop`를 호출하는 상위 오케스트레이터 문서 변경.
- 새 플래그 추가·기존 플래그 의미 변경.

## 의존성

없음 (단일 문서 변경).

## 제약

- 변경 대상 파일은 `plugins/autopilot/skills/loop/SKILL.md` 하나로 한정한다.
- 확정된 렌더링을 따른다: `start` 헤딩 bracket에는 `loop.sh` 인자만, SKILL 차원 모니터링 옵션은 헤딩 바로 아래 인접 주석으로 분리하고 Monitor 절을 가리킨다.
- 문서 언어·용어는 기존 `SKILL.md` 문체(한국어 본문, 영문 플래그/명령 토큰)와 일관되게 유지한다.
- `loop.sh` 동작은 손대지 않는다 — 표기 결함 해소가 목적이며 기능 변경이 아니다.

## 위험

- (낮음) 시그니처 헤딩이 곧 anchor가 되는 경우, 헤딩 텍스트 변경이 기존 문서 내부 링크를 깨뜨릴 수 있다 — 변경 전 동일 문서 내 해당 헤딩으로의 링크 유무를 확인해 함께 정비한다.
- (낮음) 인접 주석이 Monitor 절과 내용이 중복되면 단일 출처 원칙을 약화시킨다 — 주석은 포인터에 그치고 의미 설명은 Monitor 절에만 둔다(완료 조건 3).

## 검증

완료 조건이 인수 바(acceptance bar)의 단일 출처다. 검증을 실행하는 진입 명령은 프로젝트 규칙(`rules/`)에서 온다 — 본 SPEC은 진입 명령을 싣지 않는다.
