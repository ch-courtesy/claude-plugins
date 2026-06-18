---
scope:
  include:
    - plugins/project-init/**
    - .agents/plugins/marketplace.json
    - .claude-plugin/marketplace.json
    - README.md
    - CHANGELOG.md
  exclude:
    - plugins/autopilot/**
    - plugins/roundtable/**
    - plugins/skill-rubric/**
---

# Project Init Codex 완전 동등성 확장

## 무엇을 만들 것인가

`project-init`의 스킬·템플릿·스크립트를 단일 공유 코어로 유지하면서 Claude와 Codex의 배포·hook 차이만 얇은 어댑터로 분리한다. 같은 초기 상태와 사용자 선택에서는 두 런타임이 동일한 파일과 처리 결과를 만들어야 한다.

## 완료 조건

1. Codex 저장소 marketplace가 `project-init`을 공식 로컬 source shape로 노출한다.
2. Claude와 Codex가 기본 plugin hook 위치의 같은 `hooks/hooks.json`과 `hooks/rules-index.sh`를 사용한다.
3. 공통 스킬 절차 본문은 특정 런타임의 질문·스킬 호출 도구명에 의존하지 않는다.
4. 구조화 질문 기능이 없는 표면에서는 동일 선택지를 직접 질문하며 기능 부재 자체를 이유로 추천값을 임의 적용하지 않는다. 스킬별 명시적 누락 응답 계약은 보존한다.
5. 같은 초기 프로젝트와 응답을 사용하면 Claude와 Codex의 생성 파일 및 보존·덮어쓰기 결과가 같다.
6. `project-init`의 Claude/Codex manifest와 Claude marketplace 버전은 `0.21.0`으로 일치한다.
7. 기존 project-init 계약 테스트와 신규 Codex parity 계약 테스트가 통과한다.

## 설계

- 공유 코어: `plugins/project-init/skills/`, `shared/bootstrap/`, 템플릿, `hooks/rules-index.sh`.
- 공유 hook: 기본 plugin hook 위치인 `plugins/project-init/hooks/hooks.json`과 `hooks/rules-index.sh`. Codex가 제공하는 `CLAUDE_PLUGIN_ROOT` 호환 변수를 사용하므로 별도 hook 어댑터가 필요 없다.
- Claude 어댑터: `.claude-plugin/plugin.json`, 루트 `.claude-plugin/marketplace.json`.
- Codex 어댑터: `.codex-plugin/plugin.json`, 루트 `.agents/plugins/marketplace.json`.
- `allowed-tools` frontmatter는 Claude 호환 메타데이터로 보존하되 공통 절차 본문은 이를 실행 계약으로 사용하지 않는다.
- Codex hook이 신뢰되지 않은 경우 hook만 건너뛰며 파일 변경은 일어나지 않는다.

## 검증

- 신규 `codex-parity-contract.test.sh`로 marketplace, hook adapter, 버전 동기화, 런타임 중립 스킬 본문을 정적 검증한다.
- 기존 모든 project-init shell 계약 테스트를 실행한다.
- 가능한 환경에서는 공식 Codex plugin validator를 보조 실행한다.
- 실제 Claude/Codex 런타임 smoke 검증이 필요한 항목은 설치 후 동일 fixture와 응답으로 실행해 byte diff가 없는지 확인한다.

## 제약

- 스킬 이름, 트리거, 생성 경로, 질문 순서, 기본값, overwrite 승인 규칙은 바꾸지 않는다.
- 벤더별 스킬 트리를 복제하거나 코드젠하지 않는다.
- Codex marketplace에는 이번 범위의 `project-init`만 등록하고 version 필드는 넣지 않는다.
- `.codex-plugin/plugin.json`에는 `hooks` override를 넣지 않고 Codex의 기본 `hooks/hooks.json` 발견 규칙을 사용한다.
