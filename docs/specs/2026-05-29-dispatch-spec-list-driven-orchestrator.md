---
scope:
  include:
    - plugins/autopilot/skills/dispatch/SKILL.md
    - plugins/autopilot/skills/dispatch/references/dispatch.sh
    - plugins/autopilot/skills/dispatch/references/dag-template.md
    - plugins/autopilot/skills/dispatch/references/decomposition-algorithm.md
    - plugins/autopilot/skills/dispatch/references/task-storage.sh
    - plugins/autopilot/.claude-plugin/plugin.json
    - tests/autopilot/test-dispatch-skill.sh
    - tests/autopilot/test-dispatch-integration.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "test -f plugins/autopilot/skills/dispatch/SKILL.md && test -f plugins/autopilot/skills/dispatch/references/dispatch.sh && ! test -e plugins/autopilot/skills/dispatch/references/task-storage.sh && ! test -e plugins/autopilot/skills/dispatch/references/decomposition-algorithm.md && ! test -e plugins/autopilot/skills/dispatch/references/dag-template.md && grep -q '^name: dispatch$' plugins/autopilot/skills/dispatch/SKILL.md && ! grep -Eq '(^|[^a-zA-Z])PRD([^a-zA-Z]|$)|milestones/' plugins/autopilot/skills/dispatch/SKILL.md && grep -q 'depends_on' plugins/autopilot/skills/dispatch/SKILL.md && grep -q '.dispatch/runs/' plugins/autopilot/skills/dispatch/SKILL.md && grep -qE 'dispatch start' plugins/autopilot/skills/dispatch/SKILL.md && grep -qE 'dispatch list' plugins/autopilot/skills/dispatch/SKILL.md && grep -qE 'dispatch status' plugins/autopilot/skills/dispatch/SKILL.md && grep -qE 'dispatch stop' plugins/autopilot/skills/dispatch/SKILL.md && grep -qE 'dispatch watch' plugins/autopilot/skills/dispatch/SKILL.md && ! grep -Eq 'task-storage|gh pr|gh issue|LOOP_DONE_LABEL|ESCALATION\\.md|milestones/' plugins/autopilot/skills/dispatch/references/dispatch.sh && grep -Eq '\"version\":\\s*\"0\\.(8|9|[1-9][0-9])\\.' plugins/autopilot/.claude-plugin/plugin.json"
test_sweep_paths:
  - tests/autopilot/test-dispatch-skill.sh
  - tests/autopilot/test-dispatch-integration.sh
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# dispatch spec-list-driven orchestrator 재설계

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
dispatch 스킬을 "1개 이상의 임의 SPEC 파일을 받아 의존성 DAG를 구성하고 wave 단위로 자율 실행기를 위임 호출한 뒤 결과를 취합하는 오케스트레이터"로 재설계한다.

- 1개 이상의 SPEC 파일 경로를 가변 인자로 받는다. 특정 작성 스킬의 산출물에 한정하지 않는다(파일로 존재하고 읽을 수 있으면 받는다).
- SPEC 사이 의존성은 각 SPEC의 frontmatter에 선언된 선행 단위 참조로부터 위상정렬해 wave를 자동으로 만든다. 외부 DAG 명세 파일을 요구하지 않는다.
- 의존성 cycle이 발견되면 cycle을 보고하고 실행을 시작하지 않는다.
- wave 안 SPEC들은 병렬로 자율 실행기에 위임한다. 기본 동시성 제한 없이 시작하고, 호출자가 옵션으로 상한을 줄 수 있다.
- 각 child의 종료 여부는 자율 실행기의 공개 인터페이스(status/stop 등)만으로 판단한다. 자율 실행기 내부 신호 파일 포맷·label·issue 상태에 직접 결합하지 않는다.
- 한 wave에서 child 하나라도 차단·실패로 끝나면 다음 wave 진입을 차단한다. 동일 wave에서 이미 시작된 다른 child의 진행은 계속한다.
- 호출마다 고유한 run-id(시각·입력 기반)를 만들고 작업 상태를 프로젝트 내 전용 디렉토리 아래에 run-id 단위로 보관한다.
- 보관된 상태로 중단 후 이어 수행한다. 완료된 child는 다시 실행하지 않고 미완 wave부터 진행한다.
- list·status·watch·stop은 run-id를 키로 동작한다. watch는 per-SPEC 상태를 주기적으로 refresh하다가 모든 child가 terminal에 도달하면 종료한다.
- 코어에서 PRD 입력 가정·milestone 계층 구조·task 저장소 코드·issue label 폴링·forge/PR 자동화 코드를 제거한다. 관련 책임과 계약은 외부 지침에 두고 호출 레이어가 수행한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 verify에서 fail 가능해야 함. -->
1. dispatch는 1개 이상의 SPEC 파일 경로를 가변 인자로 받아 실행을 시작해야 한다.
2. 입력으로 받은 경로 중 파일로 존재하지 않거나 읽을 수 없는 항목이 있으면, dispatch는 그 경로를 보고하고 실행을 시작하지 않아야 한다.
3. dispatch는 각 입력 SPEC의 frontmatter에 선언된 선행 단위 참조를 읽어 위상정렬로 실행 wave를 구성해야 한다. 어떠한 선행 단위도 가지지 않는 SPEC은 첫 wave에 들어가야 한다.
4. 입력 SPEC 사이에 의존성 cycle이 있을 때, dispatch는 cycle 구성 요소를 보고하고 실행을 시작하지 않아야 한다.
5. dispatch는 wave 단위로 순차 진행하며, 한 wave 안의 SPEC들은 병렬로 자율 실행기에 위임 호출해야 한다. 기본 동시 시작 제한은 없으며, 호출자가 상한 옵션을 주면 그 값을 동시 시작 상한으로 사용해야 한다.
6. dispatch는 child의 종료·차단 여부를 자율 실행기의 공개 인터페이스만으로 판단해야 하며, 자율 실행기 내부 신호 파일 포맷·외부 task 라벨·issue 상태에 직접 결합되지 않아야 한다.
7. 한 wave에서 어떤 child가 차단 또는 실패로 끝나면, dispatch는 다음 wave를 시작하지 않고 그 사실을 결과 보고에 포함해야 한다.
8. dispatch는 호출마다 고유한 run-id를 생성하고, 그 run-id 디렉토리 아래에 wave 구성·child 매핑·진행 상태를 보관해야 한다. run-id는 시각과 입력 SPEC 집합으로부터 결정성 있게 만들어진다.
9. dispatch가 기존 run-id로 재호출되면, 보관된 상태를 읽어 이미 완료된 child는 다시 실행하지 않고 미완 wave부터 이어 수행해야 한다.
10. dispatch는 run-id 단위로 진행 중 child에 대한 종료를 요청할 수 있어야 하며, 종료 처리는 자율 실행기에 위임해야 한다.
11. dispatch는 run-id 단위 상태 조회·실시간 감시·전체 run-id 목록 조회를 별도 서브커맨드로 제공해야 한다. 실시간 감시는 per-SPEC 상태(경로·소속 wave·진행 상태)를 주기적으로 refresh하고, 모든 child가 terminal에 도달하면 종료 코드로 결과를 대표해야 한다.
12. dispatch 코어(스킬 정의 문서·driver·하위 참조 파일)는 PRD 입력 가정·milestone 계층 구조·task 저장소 코드·issue label 폴링·forge/PR 자동화 코드를 포함하지 않아야 한다.
13. autopilot 플러그인 매니페스트의 버전이 0.8.0 이상이어야 한다.

## 범위
포함:
- dispatch 스킬 정의 문서를 SPEC 경로 가변인자·자동 DAG 추론·run-id 디렉토리·자율 실행기 위임·결과 취합 계약으로 재서술.
- dispatch driver를 위 동작으로 재작성: SPEC 입력 검증, 의존성 위상정렬, run-id 디렉토리 관리, wave 병렬 위임, child 종료 판단(자율 실행기 공개 인터페이스), 동시성 상한 옵션, --resume 동작.
- 기존 7 서브커맨드(start/status/stop/list/cleanup/logs/resume)를 새 5 서브커맨드(start/list/status/stop/watch)로 교체. cleanup·logs·resume의 의미는 각각 run-id 디렉토리 자체 정리·status 출력·start의 --resume 동작에 흡수.
- 코어에서 제거되는 컴포넌트 삭제: PRD 가정·milestone 계층 가정·task 저장소 스크립트·DAG 템플릿·분해 알고리즘 문서.
- autopilot 플러그인 매니페스트 버전을 0.8.0으로 bump.
- 새 계약에 맞춰 dispatch 스킬 구조 검증·통합 테스트를 재작성.

비-목표 / 제외:
- spec 스킬·loop 스킬의 재정의(참조만).
- forge/PR·task 연동 외부 지침(`rules/orchestration/forge-integration.md`)의 재정의(참조만).
- 기존 milestones/<m>/ 디렉토리 구조의 보존·하위 호환·migration 도구 제공(0.8.0 breaking, 이전 데이터와 단절).
- 입력 SPEC frontmatter의 형식 검증·미해결 마커 검사(자율 실행기가 자체 게이트로 처리).
- 동일 run-id 사이 cross-run 상태 공유.
- dispatch가 변경 제안(PR)·리뷰·머지·정리 등 forge 후속 동작을 직접 수행하기.

## 검증
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

상위 frontmatter의 `verify`는 정적 파일·문구 게이트만 검사한다(파일 존재·문서·driver의 키워드 포함/제거·플러그인 버전). 행위 기준(1·2·3·4·5·6·7·8·9·10·11)은 self-referential 또는 실행 의존이라 단일 grep으로 직접 실행할 수 없으며, 구현 중 격리 환경에서 입력 SPEC 픽스처를 두고 dispatch를 호출해 직접 테스트로 확인한다.

## 제약 (있을 때만)
- **self-referential**: 이 SPEC은 dispatch가 자기 driver·스킬 정의·내부 참조 문서를 수정·삭제한다. 자율 실행기 헌법이 "워커는 헌법·설계·명세 문서를 수정하지 않는다"를 규정하므로 **autopilot:loop 자율 워커로 실행할 수 없다**. 직접(대화형) 구현으로 진행한다.
- WHAT만 정의한다. 위상정렬 알고리즘 선택·run-id 해시 함수·상태 디렉토리 내부 파일 구조·status 표 포맷·watch refresh 주기·자율 실행기 호출 방식(셸 CLI/스킬 호출 등)은 구현 재량이다.
- depends_on 항목의 키 이름·값 형식(slug·상대 경로·절대 경로 등)이 자율 실행기 측과 일치하지 않으면 dispatch가 해석할 수 없다. 동일 프로젝트 안의 작성 스킬과 같은 표기 규약을 따른다(예: 동일 디렉토리 내 sibling slug).
- 워크트리·상태 디렉토리에 secrets·credentials를 두지 않는다.
- 작업 상태 디렉토리는 프로젝트 git 추적에서 제외한다.

## 위험 (있을 때만)
- **0.8.0 breaking**: 기존 `milestones/<m>/` 기반 호출 경로·DISPATCH_LOG·DAG.md를 가진 사용처는 동작하지 않는다. 사용자가 새 호출 형태로 직접 전환해야 한다.
- **외부 작성 도구와의 depends_on 표기 불일치**: 입력 SPEC을 만드는 작성 도구가 다른 키 이름·값 형식을 쓰면 wave가 한 덩어리로 합쳐지거나 cycle 오탐이 발생할 수 있다. 표기 규약을 작성 도구와 일치시킨다.
- **자율 실행기 인터페이스 변경 결합**: child 종료 판단이 자율 실행기 공개 인터페이스에 의존하므로 그 인터페이스 변경이 dispatch에 회귀를 일으킬 수 있다. 인터페이스를 호출 단위로 좁게 결합하고 변경 시 dispatch 테스트로 회귀를 감지한다.
- **대규모 driver 재작성**: watch/stop/status 회귀 위험. 행위 기준을 격리 환경 직접 테스트로 보강한다.
