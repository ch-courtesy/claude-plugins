---
scope:
  include:
    - plugins/project-init/skills/version-control-rule-creator/SKILL.md
    - plugins/project-init/skills/version-control-rule-creator/templates/review-approval.github.md
    - plugins/project-init/skills/version-control-rule-creator/templates/review-approval.gitlab.md
    - plugins/project-init/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# version-control-rule-creator 스킬

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

`project-init` 플러그인에 새 형제 rule-creator 스킬 `version-control-rule-creator`를 추가한다. 이 스킬은 git origin remote의 호스팅 백엔드(GitHub / GitLab)를 자동 판별하여, 그 백엔드에 맞는 **변경 제안(change proposal, GitHub PR·GitLab MR) 심사·승인 지침**을 새 `version-control` 카테고리의 sub-룰로 생성한다.

- 백엔드는 사용자 메뉴 선택이 아니라 git origin remote로부터 **자동 판별**한다.
- 생성되는 지침은 호스팅 백엔드의 **심사·승인 모델**(승인 상태·스레드 해소·필수 체크·소유권 경계·머지 방식)을 다룬다. CLI 명령 사용법은 다루지 않는다.
- 백엔드별 지침은 기존 범용 리뷰 원칙을 **대체하지 않고 그 위에 얹는** 백엔드 특화 규율이다.
- 이 카테고리는 첫 sub-룰(심사·승인) 외에 브랜치 전략·커밋 컨벤션 등 다른 git sub-룰로 확장 가능해야 하며, 확장은 새 템플릿 추가만으로 가능해야 한다(스킬 본문 변경 없이).
- 백엔드를 판별할 수 없으면(origin 없음·미지원 호스트) 추측해서 생성하지 않고 중단하고 안내한다.
- `plugins/` 하위에 산출물이 추가되므로, 같은 변경 안에서 플러그인 버전 단일 출처가 함께 올라가야 한다.

개념 경계(혼동 방지):
- 릴리스 버전 번호 지침(SemVer·changelog)과 범용 리뷰 9원칙 지침은 별개의 기존 산출물이며, 본 스킬은 그것들을 건드리지 않는다.
- 본 스킬이 만드는 것은 git/VCS 워크플로 카테고리의 백엔드별 심사·승인 sub-룰뿐이다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->

- WHEN 스킬이 호출되면, THE 스킬 SHALL 자신의 templates 디렉터리를 열거해 각 템플릿의 sub-룰 ID와 (있으면) 백엔드 변형을 식별한다.
- WHEN 백엔드 변형을 가진 sub-룰을 처리하면, THE 스킬 SHALL git origin remote URL을 https·ssh 양식 모두에서 파싱해 호스트로부터 백엔드(github/gitlab)를 판별한다.
- IF git origin remote가 설정되어 있지 않으면, THEN THE 스킬 SHALL 어떤 룰 파일도 생성하지 않고 origin을 먼저 설정하라는 안내를 출력하고 종료한다.
- IF origin 호스트가 지원 백엔드(github·gitlab) 중 어느 것에도 매핑되지 않으면, THEN THE 스킬 SHALL 감지된 호스트와 지원 백엔드 목록을 안내하고 어떤 룰 파일도 생성하지 않고 종료한다.
- WHEN 백엔드가 성공적으로 판별되면, THE 스킬 SHALL 해당 백엔드 변형의 frontmatter를 제거한 본문을 `version-control` 카테고리의 해당 sub-룰 파일 하나로 기록하며, 출력 파일명에 백엔드 식별자를 남기지 않는다.
- IF 기록 대상 sub-룰 파일이 이미 존재하면, THEN THE 스킬 SHALL 차이를 제시하고 사용자의 명시적 교체 동의가 있을 때만 덮어쓴다.
- THE 스킬 SHALL 한 번의 호출에서 `version-control` 카테고리의 단일 sub-룰 파일만 생성·갱신하고, 다른 카테고리의 기존 지침(범용 리뷰 원칙·릴리스 버전 지침 포함)을 변경하지 않는다.
- THE 생성된 심사·승인 지침 SHALL 범용 리뷰 원칙을 대체하지 않고 그 위에 백엔드 특화 심사·승인 규율을 더하며, PR/MR을 "변경 제안" 용어로 가리키고, CLI 명령 사용법을 포함하지 않는다.
- THE 생성된 GitHub 심사·승인 지침 SHALL 다음 규율을 백엔드 용어로 명시한다: 심사 단위(Pull Request)·승인 상태 의미(Comment/Approve/Request changes)·대화 스레드 해소·필수 상태 체크·소유권 경계·머지 방식·Draft 상태.
- THE 생성된 GitLab 심사·승인 지침 SHALL 다음 규율을 백엔드 용어로 명시한다: 심사 단위(Merge Request)·승인 규칙·스레드 해소·MR 파이프라인·소유권 경계·머지 방식·Draft 상태.
- WHERE 새 백엔드 또는 새 sub-룰을 추가하려면, THE 스킬 SHALL 새 템플릿 파일 추가만으로 확장 가능해야 하며 스킬 본문 수정을 요구하지 않는다.
- WHEN 부트스트랩 오케스트레이터가 카테고리를 열거하면, THE `version-control` 카테고리 SHALL rule-creator 슬러그로부터 자동으로 후보에 포함된다.
- WHEN `plugins/` 하위에 변경이 발생하면, THE 변경 SHALL 같은 변경 안에서 플러그인 버전 단일 출처(매니페스트)와 그 미러(마켓플레이스)를 함께 올린다.

## 범위
포함:
- `version-control-rule-creator` 스킬 본문(템플릿 디스패처 + git origin 백엔드 자동 판별 로직).
- GitHub·GitLab 두 백엔드의 변경 제안 심사·승인 지침 템플릿.
- 플러그인 버전 단일 출처와 마켓플레이스 미러의 동반 버전 상향.

비-목표 / 제외:
- 기존 범용 리뷰 원칙 지침과 릴리스 버전 지침의 내용 변경.
- generic/Bitbucket 등 GitHub·GitLab 외 백엔드 템플릿(본 SPEC 범위 밖, 후속 확장).
- 브랜치 전략·커밋 컨벤션 등 심사·승인 외 git sub-룰의 실제 내용(구조만 확장 가능하게 두고 내용은 후속).
- CLI 명령 사용법·자동화 스크립트.
- 백엔드 자동 판별을 강제·후킹하는 외부 메커니즘(git hook·CI).

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 형제 rule-creator 스킬과 구조·규약(템플릿 frontmatter 파싱, 기존 파일 덮어쓰기 보호, 본문 그대로 복사)을 일관되게 따른다.
- 백엔드 자동 판별은 git origin remote URL 파싱으로만 수행하고, 외부 네트워크 호출에 의존하지 않는다.
- 백엔드 변형은 파일명 규약으로 식별하며, 출력 sub-룰 파일명에는 백엔드 식별자를 남기지 않는다.
- 심사·승인 지침 본문은 호스팅 백엔드 중립 용어 "변경 제안"으로 PR/MR을 가리키고, 범용 리뷰 원칙을 복제하지 않고 참조·보강한다.

## 위험 (있을 때만)
- self-hosted GitHub Enterprise·GitLab은 호스트 문자열에 `github`/`gitlab`이 포함될 때만 판별된다. 이를 포함하지 않는 자가 호스팅 인스턴스는 미지원으로 분류되어 중단·안내된다(의도된 동작).
- `version-control` 카테고리는 기존 범용 리뷰 지침(별도 파일)과 개념이 인접해, 사용자가 둘을 혼동할 수 있다 — 지침 본문에서 범용 원칙과의 관계를 명시해 완화한다.
