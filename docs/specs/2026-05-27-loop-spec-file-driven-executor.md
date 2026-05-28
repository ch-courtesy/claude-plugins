---
scope:
  include:
    - plugins/autopilot/skills/loop/SKILL.md
    - plugins/autopilot/skills/loop/references/loop.sh
    - plugins/autopilot/skills/loop/references/constitution.md
    - plugins/autopilot/skills/loop/references/operational-guide.md
    - plugins/autopilot/skills/loop/references/status-format.md
    - plugins/autopilot/skills/loop/references/troubleshooting.md
    - plugins/autopilot/skills/loop/references/agent-prompts.md
    - plugins/autopilot/skills/loop/references/pr-phase.sh
    - plugins/autopilot/skills/loop/references/review-fix-phase.sh
    - plugins/autopilot/skills/loop/references/cleanup-phase.sh
    - plugins/autopilot/skills/loop/references/rebase-phase.sh
    - plugins/autopilot/skills/loop/references/task-storage.sh
    - rules/orchestration/forge-integration.md
  exclude:
    - milestones/**
    - CLAUDE.md
verify: "! test -e plugins/autopilot/skills/loop/references/pr-phase.sh && ! test -e plugins/autopilot/skills/loop/references/review-fix-phase.sh && ! test -e plugins/autopilot/skills/loop/references/cleanup-phase.sh && ! test -e plugins/autopilot/skills/loop/references/rebase-phase.sh && ! test -e plugins/autopilot/skills/loop/references/task-storage.sh && test -f rules/orchestration/forge-integration.md && grep -q BLOCKED plugins/autopilot/skills/loop/references/loop.sh && grep -q DONE plugins/autopilot/skills/loop/references/loop.sh && ! grep -Eq 'gh pr|pr-phase|review-fix-phase|cleanup-phase|task-storage' plugins/autopilot/skills/loop/references/loop.sh"
# test_sweep_paths: reviewed-no-sweep
# test_paths: optional git pathspec override for weakening gate.
# test_sweep_paths: optional git pathspec whitelist for legitimate test rename/cleanup/delete sweep.
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# loop spec-file-driven executor 재설계

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
loop 스킬을 "임의의 스펙 파일을 받아 로컬에서 자율 구현하는 최소 실행기"로 재설계한다.

- 임의 스펙 파일 경로를 시작 인자로 받는다. 특정 작성 스킬의 산출물에 한정하지 않는다(예: 다른 스킬이 만든 스펙 파일도 받는다).
- 그 스펙으로부터 실행 계획을 형성할 수 없으면 "스펙 강화 필요"를 뜻하는 에러로 종료한다. 계획 형성 가능성은 이터레이션 계획 단계의 휴리스틱 판단으로 정한다.
- 작업 공간은 스펙 파일이 위치한 디렉토리 아래의 격리 작업 영역(.worktree)이다. 이미 격리된 작업 영역 안에서 호출되면 새로 만들지 않고 현재 위치를 작업 공간으로 쓴다.
- 스펙 파일 경로 자체를 실행 단위의 고유 식별자로 쓴다. 별도 task 식별자·task 저장소 개념에 의존하지 않는다.
- 이터레이션 간 기억은 작업 공간 내 파일로 저장·갱신한다.
- 완료·차단은 작업 공간의 DONE·BLOCKED 파일로 신호한다. 라벨·외부 task 신호를 쓰지 않는다.
- forge/PR 연동(변경 제안·리뷰·머지·base sync·정리)을 코어에서 제거한다.
- 자율 이터레이션 엔진과 방법론(테스트 우선·다단계 검증·객관 게이트·근본원인 조사)은 코어에 유지한다.
- 코어에서 제거되는 forge/PR·task·orchestration 연동의 책임과 계약은 외부 지침 문서로 분리해, 호출 레이어가 그 지침에 따라 수행한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 verify에서 fail 가능해야 함. -->
1. loop은 임의의 스펙 파일 경로를 시작 인자로 받아야 한다.
2. 스펙으로부터 실행 계획을 형성할 수 없을 때, loop은 "스펙 강화 필요"를 뜻하는 에러로 종료해야 한다.
3. 호출 위치가 격리된 작업 영역이 아닐 때, loop은 스펙 파일 디렉토리 아래에 격리 작업 영역을 만들어야 한다.
4. 호출 위치가 이미 격리된 작업 영역일 때, loop은 새 작업 영역을 만들지 않고 현재 위치를 작업 공간으로 사용해야 한다.
5. loop은 스펙 파일 경로를 실행 단위 고유 식별자로 사용해야 하며, task 식별자·task 저장소 개념에 의존하지 않아야 한다.
6. loop은 이터레이션 간 기억을 작업 공간 내 파일로 저장·갱신해야 한다.
7. 이터레이션이 완료를 판정하면, loop은 작업 공간에 DONE 신호 파일을 남겨야 한다.
8. 이터레이션이 차단을 판정하면, loop은 작업 공간에 차단 사유를 담은 BLOCKED 신호 파일을 남겨야 한다.
9. loop 코어(스킬 정의·driver·헌법)는 forge/PR 연동·변경 제안·리뷰·머지·정리·task 저장소 코드를 포함하지 않아야 한다.
10. loop 코어는 자율 이터레이션 엔진과 방법론(테스트 우선·다단계 검증·객관 게이트·근본원인 조사)을 유지해야 한다.
11. 코어에서 제거된 forge/PR·task·orchestration 연동의 계약은 target rules/ 외부 지침 문서로 제공되어야 한다.

## 범위
포함:
- loop 스킬 정의 문서를 스펙 파일 인자·플랜 게이트·격리 작업 영역·파일 메모리·DONE/BLOCKED 계약으로 재서술.
- loop driver를 위 동작으로 재작성: 스펙 경로 식별자, 파일 메모리, DONE/BLOCKED 신호, 플랜 게이트, task·PR·forge 코드 제거.
- 헌법을 코어 방법론 중심으로 정리: task·forge·PR 어휘 제거, 파일 메모리·DONE/BLOCKED 어휘로 전환, 외부 지침 참조.
- 운영·status·troubleshooting·agent-prompts 문서에서 task·PR 의존 서술 제거·갱신.
- 코어에서 제거되는 phase 스크립트(변경 제안·리뷰·정리·base sync)와 task 저장소 스크립트 삭제.
- forge/PR·task·orchestration 연동 계약을 담는 target rules/ 외부 지침 신설(`rules/orchestration/forge-integration.md`).

비-목표 / 제외:
- forge/PR 자동화 실행 코드를 어떤 형태로든 코어·스킬에 보존하기 (계약은 지침 문서로만 남긴다).
- DONE 이후 후속 동작(PR 생성·머지 등)을 loop이 직접 수행하기.
- 기본값과 다른 새 backend·실행 엔진의 실제 도입.
- 이전 추상화 SPEC(이 SPEC이 대체).
- 기존 task/orchestration 지침(`rules/context.md`·`rules/orchestration/`)의 재정의 (참조만).

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
! test -e plugins/autopilot/skills/loop/references/pr-phase.sh \
  && ! test -e plugins/autopilot/skills/loop/references/review-fix-phase.sh \
  && ! test -e plugins/autopilot/skills/loop/references/cleanup-phase.sh \
  && ! test -e plugins/autopilot/skills/loop/references/rebase-phase.sh \
  && ! test -e plugins/autopilot/skills/loop/references/task-storage.sh \
  && test -f rules/orchestration/forge-integration.md \
  && grep -q BLOCKED plugins/autopilot/skills/loop/references/loop.sh \
  && grep -q DONE plugins/autopilot/skills/loop/references/loop.sh \
  && ! grep -Eq 'gh pr|pr-phase|review-fix-phase|cleanup-phase|task-storage' plugins/autopilot/skills/loop/references/loop.sh
```
행위 기준(2·3·4·7·8)은 self-referential이라 verify로 직접 실행할 수 없다. 구현 중 격리 환경에서 직접 테스트로 확인한다.

## 제약 (있을 때만)
- **self-referential**: 이 SPEC은 loop가 자기 driver·스킬 정의·헌법을 수정·삭제한다. 헌법은 "워커는 헌법을 수정하지 않는다"·"설계·명세 문서 수정 금지"를 규정하므로 **autopilot:loop 자율 워커로 실행할 수 없다**. 직접(대화형) 구현으로 진행한다.
- WHAT만 정의한다. 메모리 파일명·DONE/BLOCKED 파일 포맷·플랜 게이트 판정 문구·격리 영역 감지 방식은 구현 재량이다.
- 구체 매핑·연동 절차는 외부 지침에 두되 특정 명령 나열은 최소화한다.
- 워크트리·문서에 secrets·credentials를 두지 않는다.

## 위험 (있을 때만)
- **대규모 driver 삭제·재작성**: 자율 안전 보장(게이트·검증) 회귀 위험. 행위 기준을 격리 환경 직접 테스트로 보강한다.
- **forge 자동화 완전 제거**: 기존 PR·리뷰·머지 흐름에 의존하던 사용처가 끊긴다. 그 책임을 외부 지침과 호출 레이어로 이관하고 지침에 명시한다.
- **self-referential**: autopilot:loop로 실행하면 헌법 위반으로 거부/ESCALATION한다. → loop 비권장, 직접 구현.
