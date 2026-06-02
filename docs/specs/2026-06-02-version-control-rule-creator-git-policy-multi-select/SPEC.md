---
scope:
  include:
    - plugins/project-init/skills/version-control-rule-creator/SKILL.md
    - plugins/project-init/skills/version-control-rule-creator/templates/git.md
    - plugins/project-init/skills/version-control-rule-creator/tests/**
    - plugins/project-init/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# version-control rule creator git policy multi-select

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

`version-control-rule-creator` 스킬에서 git 계열 공통 지침(`git.md`)이 사용자에게 노출되고 입력되는 방식을 바꾼다.

1. **git을 review-approval과 경쟁하는 선택지로 노출하지 않는다.** 호스팅 백엔드가 git 계열(GitHub·GitLab)로 판별되면, git 계열 공통 지침은 그 백엔드 version-control 룰셋의 일부로 함께 다뤄진다. "review-approval이냐 git이냐"를 고르게 하는 둘 중 하나 메뉴를 두지 않는다.

2. **git이 공통으로 분리된 이유를 사용자에게 노출하지 않는다.** git.md가 GitHub·GitLab 양쪽에 모두 적용되어야 하는 지침을 중복 제거 목적으로 공통으로 뺀 것이라는 사실, 그리고 git 계열 게이팅의 근거는 내부 구현 사정이므로 사용자 대면 문구로 드러내지 않는다. 사용자에게는 force push 같은 **정책 선택만** 노출한다.

3. **git 정책 입력을 하나의 multi-select 질문으로 만든다.** 기존의 force push 단일 정책 single-select(금지/허용)를, 여러 git 공통 정책을 한 번에 고르는 **단일 multi-select 질문**으로 바꾼다. force push 금지는 그 multi-select의 첫 항목이자 기본 선택(체크) 항목이다. 항목을 체크하면 그 정책 절이 본문에 들어가고, 해제하면 빠진다(force push 미체크 = 허용).

4. **본문은 단일 집계 위치에 선택 항목들을 연결한다.** git.md 본문에는 정책별 개별 placeholder가 아니라 **하나의 집계 placeholder**를 두고, 선택된 multi-select 항목들의 절 텍스트를 그 자리에 순서대로 연결해 채운다. 향후 다른 git 공통 정책이 추가될 때 frontmatter의 multi-select에 **옵션 항목만 추가**하면 끝나며, 본문 placeholder·질문 수·SKILL.md 본문 로직은 바뀌지 않는다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

- **항상** `templates/git.md`는 git 공통 정책 입력을 **하나의 multi-select 질문**으로 선언한다(여러 정책 옵션을 한 질문에서 다중 선택). 정책별로 질문을 따로 두지 않는다.
- **항상** 그 multi-select의 옵션 중 **force push 금지가 첫 번째 항목이며 기본 선택(체크)** 으로 표시된다.
- **항상** `templates/git.md` 본문에는 선택된 옵션들의 절을 연결해 채우는 **단일 집계 placeholder**가 있고, 정책별 개별 placeholder(`{{force_push_policy}}` 같은 1정책-1placeholder)는 없다.
- 사용자가 정책을 **하나 이상 선택했을 때**, 선택된 각 옵션의 절 텍스트가 집계 placeholder 자리에 옵션 표시 순서대로 연결되어 `rules/version-control/git.md` 본문에 들어간다.
- 사용자가 **force push 금지 항목을 선택했을 때** force push 금지 절이 본문에 포함되고, 선택하지 않으면 그 절이 빠진다(빈 치환이 빈 줄·깨진 마크다운을 남기지 않는다).
- 호스팅 백엔드가 git 계열로 판별된 **동안**, `git.md`는 항상 생성된다. 아무 정책도 선택되지 않아도 도입부(헤더 + git 계열 분류 명시)는 남고 정책 절 영역만 비워진다.
- git 정책 입력 응답이 **누락되면(디폴트 경로)** force push 금지가 기본 적용되어 금지 절이 포함된 `git.md`가 생성된다(기존 default-on-missing 동작 보존).
- **항상** 새 git 공통 정책 추가는 `templates/git.md` frontmatter의 multi-select에 **옵션 항목만 추가**하면 되도록 구조화되어 있다 — SKILL.md 본문 로직·본문 집계 placeholder·질문 수를 바꾸지 않고 항목만 누적된다.
- **항상** SKILL.md는 git 계열 공통 지침을 review-approval과 "둘 중 하나"로 고르게 하는 single-select 메뉴 항목으로 노출하지 않으며, git이 공통으로 분리된 이유(중복 제거)·git 계열 게이팅 근거를 사용자 대면 문구로 노출하지 않는다.
- 백엔드가 git 계열로 판별**될 때**, 그 백엔드의 변경 제안 심사·승인 지침(review-approval, 백엔드 변형)과 git 계열 공통 지침(git.md)이 함께 산출되며, review-approval 본문(PR/MR 용어)은 이 변경으로 달라지지 않는다.
- **항상** `tests/` 아래 구조 검증 테스트가 위 multi-select·단일 집계 placeholder·force push 첫 항목/기본 체크·always-create 빈 정책 동작을 검증하도록 갱신되어 있고, 실행하면 통과한다(exit 0).
- **항상** `plugins/project-init/.claude-plugin/plugin.json`과 `.claude-plugin/marketplace.json`의 project-init 버전이 SemVer로 함께 올라가 있고 두 값이 일치한다.

## 범위
포함:
- `plugins/project-init/skills/version-control-rule-creator/SKILL.md` — 입력 메커니즘 문구(정적 multi-select 집계 입력), git 노출 방식(경쟁 메뉴 제거·근거 비노출), git 계열 산출 흐름.
- `plugins/project-init/skills/version-control-rule-creator/templates/git.md` — frontmatter inputs를 단일 multi-select로, 본문을 단일 집계 placeholder로.
- `plugins/project-init/skills/version-control-rule-creator/tests/**` — 구조 검증 테스트를 새 모델로 갱신(또는 신규).
- `plugins/project-init/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — project-init 버전 동반 범프.

비-목표 / 제외:
- review-approval 템플릿(`.github`/`.gitlab`) 본문·백엔드 판별 로직(공식 도메인 정밀 매칭 + self-hosted read-only probe) 변경.
- 이번 변경에서 force push 외의 실제 새 정책 항목 추가(구조만 확장 가능하게 두고, 항목은 force push 하나).
- `engineering-rule-creator` 자체 변경. 단 version-control SKILL.md의 "engineering-rule-creator inputs 미러링" 문구는 새 multi-select 집계 메커니즘 설명으로 갱신할 수 있다.
- `rules/`, `milestones/`, `CLAUDE.md` 등 카테고리·스킬 밖 파일.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- **템플릿 본문은 그대로 복사 + placeholder 치환만.** 본문별 분기 로직을 SKILL.md에 넣지 않는다. 새 multi-select 집계도 특정 정책에 종속되지 않는 일반 메커니즘(선택된 옵션 value들을 집계 placeholder에 연결)으로 기술한다. 빈 치환 시 절 단위로 서식을 정리해 빈 줄·깨진 마크다운을 남기지 않는다.
- **백엔드 판별 로직 유지.** git origin remote URL 파싱 → 공식 도메인 호스트명 정밀 매칭(네트워크 없음) + self-hosted read-only API probe, 추측 금지(inconclusive면 중단·안내). origin 미설정 시 생성하지 않고 안내.
- **출력 규약 유지.** git 공통 지침 출력은 `rules/version-control/git.md`(백엔드 식별자 미포함). 기존 파일은 명시 동의 없이 덮어쓰지 않으며 diff를 보여주고 `덮어쓴다`/`보존한다`를 묻는다. 자유 텍스트·침묵은 동의가 아니다.
- **"한 호출 = 한 sub-룰" 문구는 불변 제약이 아니다.** 현재 SKILL.md의 해당 문구(및 line 22의 engineering-rule-creator 미러링 진술)는 그 스킬만의 관습일 뿐 사용자가 합의한 계약이 아니다. 본 SPEC의 모델(git 계열이면 review-approval + git 함께 산출, git 정책은 multi-select 세부로 노출)이 그 문구와 충돌하면 문구 자체를 새 모델에 맞게 고친다 — 없는 계약을 지어내 설계를 묶지 않는다.
- **multi-select는 force push 한 항목이어도 노출한다.** 현재 정책이 force push 하나뿐이어도, 사용자가 금지/허용을 실제로 결정해야 하므로 single-select로 자동 처리하지 않고 multi-select 질문으로 제시한다.
- **plugins/ 버전 동반.** plugin.json 단일 출처와 marketplace.json 미러를 같은 변경 안에서 올리고 값이 일치해야 한다(`rules/engineering/versioning.md`).

## 위험 (있을 때만)
- **기존 구조 테스트와의 충돌.** `tests/git-common-force-push.test.sh`는 현재 single-select 형태(금지 first+Recommended, 허용 empty value, 단일 `{{force_push_policy}}` placeholder, value-over-label)를 검증한다. 새 모델로 갱신하지 않으면 이 테스트가 거짓 실패/거짓 통과를 낸다 — 테스트 갱신을 완료 조건에 포함했다.
- **빈 정책 git.md의 빈약함.** 모든 정책 미선택 시 git.md가 도입부만 남아 "규칙 없는 규칙 파일"이 된다. always-create를 택했으므로(도입부가 git 계열 분류 앵커이자 향후 정책의 자리) 의도된 동작이나, 도입부 문구가 그 자체로 의미를 갖도록 둔다.
- **집계 연결의 서식.** 여러 절을 연결할 때 절 사이 간격·헤더 수준이 어긋나면 마크다운이 깨질 수 있다. 절 단위 서식 정리를 제약으로 명시했다.
