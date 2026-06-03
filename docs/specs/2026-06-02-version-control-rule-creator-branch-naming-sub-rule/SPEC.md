---
scope:
  include:
    - plugins/project-init/skills/version-control-rule-creator/**
    - plugins/project-init/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# version-control-rule-creator branch-naming sub-rule 추가

## 무엇을 만들 것인가

`project-init:version-control-rule-creator`에 feature 브랜치 네이밍 규약을 생성하는 **`branch-naming` sub-룰**을 추가한다. 이 sub-룰은 git 백엔드의 브랜치 이름 정책(작업 종류 접두사, 표기, 이슈 ID, 길이·금지문자 등)을 **한 번의 다중 선택으로 골라** 프로젝트의 `rules/version-control/branch-naming.md` 지침으로 산출한다.

브랜치 네이밍은 호스팅 백엔드(GitHub/GitLab)와 무관한 팀 정책이므로 백엔드 변형 없는 단일 sub-룰로 둔다. 디스패처(SKILL.md)는 이미 `templates/*.md`를 열거해 sub-룰을 인식하므로, 이 sub-룰은 새 템플릿 파일 추가만으로 카테고리에 편입된다(디스패처 로직 변경 없음).

## 완료 조건

- 브랜치 네이밍 sub-룰 템플릿은 항상 `templates/` 아래 **단일 파일**로 존재하며, 같은 sub-룰의 백엔드 변형 파일(`branch-naming.<backend>.md`)은 존재하지 않는다.
- 스킬이 sub-룰 후보를 열거**할 때**, 브랜치 네이밍 sub-룰이 기존 `review-approval`과 함께 사용자 single-select 후보로 나타난다.
- 사용자가 브랜치 네이밍 sub-룰을 고른 **동안**, 한 번의 다중 선택으로 적용 정책을 고르고, 선택된 정책의 본문만 표시 순서대로 집계되어 `rules/version-control/branch-naming.md` 하나로 기록된다.
- 아무 정책도 선택되지 않으**면**, 산출 본문에는 도입부(헤더 + 목적 문장)만 남고 집계 위치에 빈 줄·깨진 마크다운이 남지 않는다.
- 구조 수용 테스트가 추가되어 통과하고, 기존 git 공통 정책 구조 테스트가 무회귀로 통과한다.
- 플러그인 버전 단일 출처와 그 미러의 project-init 버전 값이 서로 일치하며, 이번 변경분만큼 증가해 있다.

## 범위
포함:
- version-control-rule-creator의 새 sub-룰 템플릿 파일 1개.
- version-control-rule-creator의 새 구조 수용 테스트 1개.
- 플러그인 버전 단일 출처와 루트 마켓플레이스 미러의 project-init 버전 동반 증가.

비-목표 / 제외:
- 디스패처(SKILL.md) 로직·문구 변경. 새 sub-룰은 `templates/` 파일 추가만으로 인식되므로 SKILL.md는 건드리지 않는다.
- 다른 sub-룰 템플릿(`review-approval.*`, `git`)·다른 카테고리 지침(`rules/review.md`, `rules/engineering/versioning.md`) 변경.
- 브랜치 lifecycle(머지 후 삭제·base 브랜치·force push 등) 정책 — force push는 이미 `git` 공통 sub-룰 소관이다. 이 sub-룰은 **이름 규약**만 다룬다.

## 검증
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약

- 새 파일은 정확히 둘: `plugins/project-init/skills/version-control-rule-creator/templates/branch-naming.md`(sub-룰 ID `branch-naming`, 백엔드 변형 없음 → 출력 `rules/version-control/branch-naming.md`)와 `plugins/project-init/skills/version-control-rule-creator/tests/branch-naming.test.sh`.
- 템플릿 본문 모델은 같은 디렉터리의 `templates/git.md`를 미러링한다: frontmatter에 **단일 `multi_select` 입력**(`name: branch_policies`), 본문은 **단일 집계 placeholder** `{{branch_policies}}` 하나, 정책별 개별 placeholder 없음, 도입부(H1 헤더 + 목적 문장)는 빈 선택에도 생존.
- 입력 옵션은 표시 순서대로 4개: `type 접두사 필수`(default-checked), `소문자 kebab-case`(default-checked), `이슈/티켓 ID 포함`, `길이·금지문자 제한`. 각 옵션은 `label`·`description`·`value`(산출 본문 절)를 갖고, **첫 두 옵션(`type 접두사 필수`·`소문자 kebab-case`)에만** `default: true`이며 나머지 두 옵션은 미체크다(`default: true` 마커는 정확히 2개). 각 옵션 본문의 구체 문구는 승인된 계획 파일(`/home/coder/.claude/plans/feature-abstract-wigderson.md`)의 템플릿 전문을 그대로 따른다.
- 구조 테스트는 `tests/git-common-force-push.test.sh`의 구조(`set -u`, `check`/`lineno` 헬퍼, `PASS`/`FAILED` + exit code)를 미러링하고 다음을 검증한다: 템플릿 존재·`sub_rule: branch-naming`, `inputs` 블록과 `multi_select: true`, `- name:` 항목이 **정확히 1개**이고 이름이 `branch_policies`, `default: true` 마커가 **정확히 2개**이며 첫 두 옵션에 속하고 3·4번째 옵션엔 없음, 본문 distinct placeholder가 `{{branch_policies}}` 하나뿐, 닫힌 frontmatter + 본문 H1, 백엔드 변형 파일(`branch-naming.<backend>.md`) 부재.
- `plugins/`는 워치 디렉터리이므로 버전 동반이 필수다: 단일 출처 `plugins/project-init/.claude-plugin/plugin.json`과 미러 `.claude-plugin/marketplace.json`의 project-init 항목을 같은 변경 안에서 `0.12.0` → `0.13.0`(새 기능 = MINOR)으로 함께 올리고, 두 값을 일치시킨다(`rules/engineering/versioning.md`).
- SKILL.md는 수정하지 않는다.

## 위험

- 새 선택 가능 sub-룰이 둘이 되면 디스패처가 single-select를 묻게 되어 기존 review-approval 자동 선택 흐름이 바뀐다. 이는 SKILL.md가 명시한 설계된 확장 동작이며 회귀가 아니다 — 기존 git 공통 구조 테스트가 무회귀로 통과하는지로 SKILL.md 무변경을 확인한다.
