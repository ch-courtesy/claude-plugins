---
scope:
  include:
    - plugins/project-init/skills/version-control-rule-creator/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# version-control git 공통 지침 (force-push 허용 토글)

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
`version-control-rule-creator`에 **git 계열 공통 지침 sub-룰**을 추가한다. 이 sub-룰은 git 계열 백엔드에서 공통으로 적용되는 version-control 지침을 `rules/version-control/git.md`로 생성하며, 그 첫 항목으로 **force push 정책**을 담는다. 생성 시 사용자에게 **force push 허용 여부**를 묻고(디폴트=금지) 선택에 따라 파일을 생성한다.

force push는 git 전용 개념이므로, 이 sub-룰은 **git 계열 백엔드에서만** 제공된다:

- VCS 백엔드가 git 계열(github·gitlab 등)일 때만 sub-룰 메뉴에 뜨고 생성된다. 비-git 백엔드면 제공하지 않는다.
- git 계열인지는 **기존 백엔드 판별 결과를 재사용**해 판단한다 — 새 탐지 로직을 추가하지 않고, 이미 판별된 호스팅 백엔드(github·gitlab)를 git 계열로 분류한다.
- 같은 git 계열 안에서는 호스팅 백엔드(github/gitlab)와 무관하게 **동일한 본문**을 생성한다(git 계열 공통). 출력 파일명은 항상 `rules/version-control/git.md`이다.

force push 분기 동작:

- 디폴트(금지)를 고르면 생성된 `git.md`에 force push 금지 절이 포함된다.
- 허용을 고르면 같은 `git.md`가 생성되되 **force push 금지 절만 빠진** 채 나머지 본문이 남는다.

이를 위해 `version-control-rule-creator`에 ① 사용자 선택지를 받아 본문 placeholder를 치환하는 **선택지(inputs) 메커니즘**과 ② git 계열 공통 sub-룰을 표현·게이팅하는 처리를 도입한다. inputs는 형제 스킬 `engineering-rule-creator`가 이미 쓰는 frontmatter 방식과 같은 스키마·동작을 따른다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

- **항상** `version-control-rule-creator`는 선택된 sub-룰 템플릿의 frontmatter에 `inputs`가 있으면 각 입력을 사용자에게 단일 선택으로 묻고, 선택값으로 템플릿 본문의 동명 placeholder(`{{<name>}}`)를 치환해 `rules/version-control/<sub>.md`를 기록한다.
- 판별된 백엔드가 **git 계열일 때**, git 공통 sub-룰이 생성 가능한 sub-룰 목록에 포함된다.
- 판별된 백엔드가 **git 계열이 아닐 때**, git 공통 sub-룰은 목록에 포함되지 않고 생성되지 않으며, 그 사실이 사용자에게 안내된다.
- 사용자가 git 공통 sub-룰을 생성**할 때**, force push 허용 여부를 묻는 선택지가 제시되고 금지 옵션이 추천(첫 번째)으로 표시된다.
- 사용자가 force push **금지(디폴트)** 를 선택**할 때**, 생성된 `rules/version-control/git.md`에 force push 금지 절이 포함된다.
- 사용자가 force push **허용**을 선택**할 때**, 생성된 `rules/version-control/git.md`에는 force push 금지 절이 빠진 채 나머지 본문이 남는다.
- 같은 git 계열 안에서 origin이 github든 gitlab든 생성되는 `git.md` 본문은 **동일**하다(force push 선택값에 의한 차이 외에는 백엔드별 차이가 없다).
- force push 선택 입력이 누락되거나 비어 **있으면**, 디폴트(금지)가 적용되어 금지 절이 포함된 파일이 생성된다.

## 범위
포함:
- `version-control-rule-creator`의 SKILL.md에 ① inputs 선택지 파싱·치환 단계, ② git 계열 공통 sub-룰의 게이팅·표현 처리 추가.
- `version-control-rule-creator`의 `templates/` 아래 git 계열 공통 지침 템플릿 신규 추가(force push 금지/허용 토글 placeholder 포함, 출력 `rules/version-control/git.md`).

비-목표 / 제외:
- 기존 `review-approval`(github/gitlab 백엔드 변형) sub-룰의 본문·백엔드 판별 흐름 변경.
- 새로운 백엔드 탐지/판별 로직 추가(git 계열 여부는 기존 판별 결과 재사용).
- 비-git VCS 백엔드 자체의 신규 지원(현재 지원 백엔드는 github·gitlab이며 둘 다 git 계열).
- `rules/` 아래 실제 지침 파일 생성·수정(런타임 생성 산출물이므로 SPEC 구현 범위 밖).
- force push 외의 다른 git 공통 항목(브랜치 전략·커밋 컨벤션 등) 신설(이 sub-룰이 향후 담을 수 있으나 이번 범위 밖).
- `engineering-rule-creator`·`context-rule-creator`·`workspace-rule-creator` 등 형제 스킬 변경.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- **스킬(SKILL.md) 생성·편집은 `superpowers:writing-skills`(skill creator)를 거쳐 수행한다.** vc-rule-creator의 SKILL.md를 직접 손으로 고치지 않고 해당 스킬의 절차를 따른다.
- **공통 지침 출력 파일명은 `rules/version-control/git.md`로 고정한다.** github/gitlab별로 파일을 복제하지 않고 git 계열 전체에 같은 본문을 적용한다.
- **inputs 메커니즘은 `engineering-rule-creator`의 inputs 방식을 미러링한다.** 같은 frontmatter 스키마(`name`, `header`, `question`, `options[{label, description, value?}]`)와 같은 치환 규칙(선택값=`value` 우선, 없으면 `label`)을 쓴다. 단, force push 입력은 응답 누락·빈 값일 때 placeholder 보존이 아니라 **디폴트(금지)** 를 적용한다.
- **force push 금지/허용 분기는 본문 placeholder 치환으로 표현한다.** 금지 옵션의 `value`는 force push 금지 절 텍스트를, 허용 옵션의 `value`는 빈 문자열을 공급하여, 허용 시 금지 절만 사라지고 나머지 본문은 그대로 남게 한다. 별도의 조건부 렌더링 로직을 SKILL.md에 추가하지 않는다.
- **git 계열 게이팅은 기존 백엔드 판별 결과를 재사용한다.** 새 origin 파싱·probe를 추가하지 않고, 이미 판별된 호스팅 백엔드(github·gitlab)를 git 계열로 분류하는 정적 매핑만 둔다. 향후 비-git 백엔드가 추가되면 그 백엔드를 git 계열에서 제외하는 것으로 자연히 게이팅된다.
- **SKILL.md 변경은 위 두 메커니즘(inputs, git 계열 공통 게이팅) 도입에 한정한다.** 기존 `review-approval` 백엔드 변형 판별·단일 sub-룰 기록 흐름은 보존한다. "한 호출 = 한 sub-룰" 원칙을 유지한다.
- 기존 파일 보호 규약 유지: 대상 `rules/version-control/git.md`가 이미 있으면 덮어쓰지 않고 diff를 보여 명시적 교체 선택일 때만 덮어쓴다.

## 위험 (있을 때만)
- inputs·git 계열 게이팅 도입이 기존 백엔드 변형(`review-approval`)의 자동 판별·기록 흐름을 깨뜨릴 위험 — `review-approval`은 inputs를 갖지 않고 백엔드 변형으로 동작하므로 두 경로가 독립적으로 동작해야 한다.
- sub-룰이 둘(`review-approval`, git 공통)이 되면서 sub-룰 단일 선택 단계가 정상 동작해야 한다(두 sub-룰을 합쳐 기록하지 않는다).
- git 계열 분류를 정적 매핑으로 두면, 미래에 비-git 백엔드가 추가될 때 그 매핑을 갱신하지 않으면 force push 지침이 잘못 제공될 수 있다 — 매핑의 단일 출처를 명확히 하고 기본값을 "git 계열 아님(미제공)"으로 안전하게 둔다.
- 허용 옵션의 빈 `value` 치환이 본문에 빈 줄·깨진 마크다운을 남기지 않도록, placeholder 주변 서식을 절 단위로 깔끔히 제거해야 한다.
