---
scope:
  include:
    - plugins/autopilot/skills/fsd/references/forge-integration.md
    - plugins/autopilot/skills/fsd/references/forge.sh
    - rules/orchestration/forge-integration.md
    - rules/orchestration/approved-spec-merge.md
    - plugins/autopilot/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - milestones/**
    - CLAUDE.md
verify: "test -f plugins/autopilot/skills/fsd/references/forge-integration.md && ! test -f rules/orchestration/forge-integration.md && ! grep -rIn 'rules/orchestration/forge-integration' plugins rules .claude-plugin && test $(find plugins rules -name forge-integration.md | wc -l) -eq 1"
# ears_language: ko
---

# Consolidate forge-integration rule into fsd skill

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
자율 실행기(loop) 코어와 forge 통합(호출) 레이어 사이의 책임 경계·완료/차단 신호 계약·통합 흐름·보안 경계를 정의한 forge-integration 계약을, 그 유일한 구현·소비자인 `autopilot:fsd` 스킬과 **함께 다니도록** 이전한다. 이 계약은 현재 저장소 루트의 범용 규칙 디렉터리에 있어 플러그인과 함께 배포되지 않으며, 그 결과 fsd가 인용하는 단일 출처가 설치 환경에서 부재(dangling)가 된다. 계약을 fsd 스킬 안으로 옮겨 **단일 출처를 fsd로 모으고**, 범용 규칙 영역에서 autopilot 전용 결합을 제거한다. 범위는 forge-integration 한 계약에 한정한다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- 항상 forge-integration 계약 문서는 `plugins/autopilot/skills/fsd/references/forge-integration.md` 한 파일에 존재하며, 그 본문은 이전 규칙의 책임 경계표·신호 계약(완료/차단)·완료 후 통합 흐름·보안 경계를 그대로 담는다.
- 항상 저장소 루트의 `rules/orchestration/forge-integration.md`는 더 이상 존재하지 않는다.
- 항상 저장소 전체에서 `forge-integration.md`라는 이름의 파일은 정확히 하나만 존재한다(위 fsd references 경로 아래).
- 항상 `plugins/autopilot/skills/fsd/references/forge.sh`의 forge-integration 인용은 같은 references 디렉터리 안의 번들 상대경로를 가리키며, `rules/orchestration/forge-integration.md`라는 경로 문자열을 더 이상 포함하지 않는다.
- 항상 `rules/orchestration/approved-spec-merge.md`의 forge-integration 교차참조는 새 번들 경로(`plugins/autopilot/skills/fsd/references/forge-integration.md`)를 가리킨다.
- 라이브 코드·규칙 영역(`plugins/`·`rules/`·`.claude-plugin/`)에서 `rules/orchestration/forge-integration` 문자열을 검색하는 동안 매치가 없다(역사 기록인 `docs/specs/`·`milestones/`는 제외).
- 항상 autopilot 플러그인 버전은 `plugins/autopilot/.claude-plugin/plugin.json`(단일 출처)과 루트 `.claude-plugin/marketplace.json`의 autopilot 항목(미러) 둘 다에서 동일하게 `0.16.1`이다(이전 `0.16.0`에서 PATCH 범프).
- `plugins/autopilot/skills/fsd/references/forge.sh`를 `--help`로 실행하면 오류 없이 usage를 출력한다(주석만 변경, 로직 무회귀).

## 범위
포함:
- forge-integration 계약 문서를 fsd references 디렉터리로 이전(신규 번들본 작성 + 루트 원본 삭제).
- `forge.sh`의 forge-integration 인용 1줄을 번들 상대경로로 갱신.
- `approved-spec-merge.md`의 forge-integration 교차참조 1줄을 새 번들 경로로 갱신.
- autopilot 플러그인 버전 PATCH 범프(plugin.json + marketplace.json 미러).

비-목표 / 제외:
- fsd가 인용하는 다른 repo-root 규칙(branch-and-slug·versioning·review·change-adoption·context·task-state-alignment·issue-sync) 이전 — 이번 범위 밖, 일시적 비대칭 수용.
- forge-integration 본문의 일반화(autopilot 전용 계약이므로 표현을 벤더 중립화하지 않는다).
- forge-integration 본문의 내부 교차참조(rules/context.md·task-state-alignment.md·issue-sync.md) 수정.
- loop 스킬, fsd SKILL.md, repo CLAUDE.md, 나머지 orchestration siblings, forge.sh의 다른 인용(branch-and-slug 등).

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- forge-integration 본문은 **그대로 이전**한다 — autopilot 전용 계약이므로 일반화하지 않고, 내부 교차참조도 변경하지 않는다.
- `forge.sh`는 forge-integration을 가리키는 인용 1줄만 수정한다. line 20(branch-and-slug)을 비롯한 다른 repo-root 인용은 건드리지 않는다.
- 버전 범프는 SoT(`plugins/autopilot/.claude-plugin/plugin.json`)와 미러(루트 `.claude-plugin/marketplace.json`)를 같은 변경에서 함께 올린다(SemVer PATCH — 동작 변화 없는 출처 재배치). 단일 출처 규칙은 `rules/engineering/versioning.md`.
- git 반영(브랜치·commit·main 동기화)은 직접 main 편집 없이 프로젝트 규칙(`rules/engineering/branch-and-slug.md`)을 따른다.

## 위험 (있을 때만)
- repo CLAUDE.md의 카테고리 룰 로딩은 `rules/orchestration/`를 디렉터리로 읽지만, forge-integration 제거 후에도 siblings(approved-spec-merge·issue-sync·task-state-alignment)가 남아 디렉터리·로딩은 유지된다 — 깨지지 않음.
- 역사적 `docs/specs/`·`milestones/` 문서가 옛 경로를 언급하지만 이는 기록이므로 변경 대상이 아니며 dangling 판정에서 제외한다.
