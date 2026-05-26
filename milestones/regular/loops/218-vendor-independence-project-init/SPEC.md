---
scope:
  include: ["plugins/project-init/**", ".agents/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; for f in plugins/project-init/.claude-plugin/plugin.json plugins/project-init/.codex-plugin/plugin.json .agents/plugins/marketplace.json; do jq . $f >/dev/null; done; test project-init = $(jq -r .name plugins/project-init/.codex-plugin/plugin.json); grep -q project-init .agents/plugins/marketplace.json; test -f plugins/project-init/skills/bootstrap/AGENTS.md; ! grep -rIl AskUserQuestion plugins/project-init/skills'"
# test_sweep_paths: reviewed-no-sweep
# test_paths: optional git pathspec override for weakening gate.
# test_sweep_paths: optional git pathspec whitelist for legitimate test rename/cleanup/delete sweep.
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
# request_review: true enables review-fix auto loop after PR create/reuse. Use --no-pr to skip PR phase.
request_review: true
---

# vendor-independence: 공유 코어 + 얇은 벤더 오버레이 기초 (project-init)

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
project-init 플러그인이 단일 소스를 유지한 채 Claude Code와 Codex CLI 양쪽에서 설치·사용 가능해지도록 하는 **벤더 독립 오버레이 메커니즘의 기초**를 만든다. 스킬 본문은 두 벤더가 공유하는 중립 코어로 두고, 벤더별 차이(매니페스트·프로젝트 지침 파일)만 얇은 오버레이로 분리한다. 이 슬라이스는 project-init만 대상으로 메커니즘을 확립·검증하며, 동일 패턴이 이후 다른 플러그인으로 확장될 수 있는 형태여야 한다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 verify에서 fail 가능해야 함. -->
- 시스템은 project-init에 대해 Claude Code용 매니페스트와 Codex CLI용 매니페스트를 모두 제공해, 두 벤더 각각이 자신의 매니페스트로 project-init를 인식할 수 있어야 한다.
- 시스템은 벤더-중립 마켓플레이스 루트의 플러그인 목록에 project-init를 포함해야 한다.
- 시스템은 project-init의 스킬 본문이 특정 벤더 전용 도구 이름·지침 파일명에 의존하지 않는 중립 표현만 사용하도록 해, 스킬 본문에 벤더 강제 도구 리터럴이 남아 있지 않아야 한다.
- 시스템은 project-init 부트스트랩 지침을 Codex 환경용 형태로, 기존 Claude용 형태와 공존하도록 제공해야 한다.
- When 검증 명령을 실행하면, 시스템은 모든 매니페스트의 JSON 유효성·중립 마켓플레이스의 project-init 포함·Codex 지침 파일 존재·스킬 본문의 벤더-중립성을 0 exit으로 확인해야 한다.
- If 매니페스트가 유효하지 않거나 스킬 본문에 벤더 강제 도구 리터럴이 남아 있으면, 검증 명령은 비-0 exit으로 실패해야 한다.

## 범위
포함:
- project-init 플러그인에 Codex용 매니페스트(공존 오버레이) 추가
- 벤더-중립 마켓플레이스 루트에 project-init 등록
- project-init 스킬 본문(SKILL.md)의 벤더 결합 표현(벤더 강제 도구 호출 문구·특정 벤더 지침 파일명 전용 참조) 중립화
- project-init 부트스트랩 지침의 Codex용 오버레이 추가 (Claude용과 공존)

비-목표 / 제외:
- autopilot 플러그인(4 스킬)과 그 셸 스크립트의 벤더 독립 — 별도 후속 task
- 셸 스크립트의 `claude` CLI 호출을 `codex exec`로 추상화하는 작업 — 별도 후속 task
- tests/ 디렉토리의 벤더 독립 변환 — 별도 후속 task
- 루트 `.claude-plugin/marketplace.json`과 벤더-중립 마켓플레이스의 전면 통합·정리(project-init 등록 외)
- Claude용 프로젝트 지침 파일 수정 — 오버레이로 공존시키며 수정하지 않는다

## 검증
이 명령이 0 exit으로 끝나야 합니다:
`bash -c 'set -e; for f in plugins/project-init/.claude-plugin/plugin.json plugins/project-init/.codex-plugin/plugin.json .agents/plugins/marketplace.json; do jq . $f >/dev/null; done; test project-init = $(jq -r .name plugins/project-init/.codex-plugin/plugin.json); grep -q project-init .agents/plugins/marketplace.json; test -f plugins/project-init/skills/bootstrap/AGENTS.md; ! grep -rIl AskUserQuestion plugins/project-init/skills'`

## 제약 (있을 때만)
- 오버레이 메커니즘은 "공존 매니페스트 + 공유 중립 skills/"를 따른다: 각 플러그인 디렉토리에 Claude용·Codex용 매니페스트를 공존시키고 skills/(SKILL.md + references)는 단일 중립 소스로 공유한다. 별도 생성/빌드 단계나 skills/ 복제본을 두지 않는다.
- Codex용 매니페스트 스키마는 기존 `plugins/superpowers/.codex-plugin/plugin.json` 선례(name·version·description·author·license·keywords·interface 블록)를 따른다. Codex 매니페스트의 버전은 Codex 라인 자체 SoT로 신설한다(`0.1.0`).
- 벤더-중립 마켓플레이스 루트는 기존 `.agents/plugins/marketplace.json`을 확장해 채택한다(현 superpowers 항목 보존 + project-init 추가). 기존 스키마(source/policy/interface) 형태를 유지한다.
- 벤더 지침 파일은 오버레이로 공존시킨다: Claude용 `CLAUDE.md`는 변경 없이 유지하고 Codex용 `AGENTS.md`를 같은 위치에 추가한다.
- skills/ 본문 중립화 방향: 벤더 강제 도구 호출 문구(예: "예외 없이 특정 도구로 묻는다")는 "사용자에게 명시적으로 질문한다"는 중립 표현으로, 특정 벤더 지침 파일명 전용 참조는 벤더-중립 지침-파일 표현으로 일반화한다. 중립화는 의미를 보존하고 동작을 바꾸지 않는다.
- 본 슬라이스 대상은 project-init에 한정한다. autopilot·셸 스크립트·tests는 손대지 않는다.

## 위험 (있을 때만)
- Codex 매니페스트 스키마는 공식 docs 직접 확인이 어려워 커뮤니티 선례(superpowers `.codex-plugin/plugin.json`) 기반으로 확정한다. 실제 스키마가 다르면 Codex 매니페스트 필드 조정이 필요하나 디렉토리 구조·오버레이 메커니즘은 그대로 유지된다.
- 스킬 본문의 벤더 강제 도구 문구를 중립화하면 project-init의 Claude 라인 스킬 본문에서도 강제 표현이 사라진다. Claude용 강제는 공존하는 Claude 지침 파일(`CLAUDE.md`)이 유지하므로 일관성이 보존된다(의도된 trade-off).
- `.agents/` 마켓플레이스를 중립 루트로 정식 채택하면 이후 플러그인 변환이 이 포맷에 의존하게 된다. 본 슬라이스에서 포맷을 안정적으로 확정한다.
- 후속 분리 task(decomposition gate (a) 메모): (1) autopilot 4 스킬의 벤더 독립, (2) 셸 스크립트 `claude` → `codex exec` 추상화(loop.sh·rebase-phase.sh·review-fix-phase.sh 등 5개), (3) tests/ 벤더 독립 변환, (4) 루트 마켓플레이스 전면 통합. 모두 본 슬라이스에서 확립한 메커니즘을 재사용한다.
