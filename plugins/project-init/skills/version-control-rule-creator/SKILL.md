---
name: version-control-rule-creator
description: 현재 프로젝트의 git origin remote에서 호스팅 백엔드(GitHub/GitLab)를 자동 판별해, 그 백엔드에 맞는 변경 제안(PR/MR) 심사·승인 지침을 `rules/version-control/<sub>.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 버전 관리(VCS) 워크플로 지침을 새로 만들고 싶어 할 때.
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - WebFetch
  - Glob
  - Bash(ls:*)
  - Bash(mkdir -p:*)
  - Bash(diff:*)
  - Bash(git diff:*)
  - Bash(git remote get-url:*)
  - Bash(git config:*)
  - Bash(python3 references/template_tools.py parse-name:*)
  - Bash(python3 references/template_tools.py git-family:*)
  - Bash(python3 references/template_tools.py aggregate:*)
---

# version-control-rule-creator

**버전 관리(VCS) 카테고리의 sub-룰 디스패처**입니다 — `templates/*.md`를 `rules/version-control/<sub>.md`(`<sub>` = sub-룰 ID)로 기록합니다. 백엔드 변형을 가진 sub-룰(예: `review-approval`)은 사용자 메뉴 선택이 아니라 git origin remote URL 파싱으로 백엔드를 자동 판별해 그 변형 본문을 쓰고, 백엔드가 **git 계열**로 판별되면 git 계열 공통 지침(`git`)을 그 백엔드 룰셋의 **동반 출력**으로 함께 산출합니다. 첫 sub-룰은 변경 제안 심사·승인(`review-approval`)이며 브랜치 전략·커밋 컨벤션 등 다른 git sub-룰로 확장할 수 있습니다.

## 참조 (단일 출처)

실수하기 쉬운 결정적 작업과 비대한 상세 절차는 아래로 고정합니다. SKILL.md 본문은 계약·요약만 담고 상세는 이 참조들이 단일 출처입니다(중복 서술 금지).

- `references/template_tools.py` — 결정적 작업 스크립트: `parse-name`(파일명 → sub-룰 ID·백엔드), `git-family`(백엔드 git 계열 분류), `aggregate`(선택 옵션 값 집계 연결). `python3 references/template_tools.py <subcommand> ...`로 호출합니다.
- `references/backend-detection.md` — 백엔드 판별 절차의 상세(공식 도메인 정밀 매칭·self-hosted probe·inconclusive 중단·git 계열 정적 매핑).
- `references/input-substitution.md` — 입력 치환 규칙의 상세(스키마·질문·1옵션 폴백·집계/단일 치환·빈 선택 정리·누락 디폴트). 완전한 placeholder 예시는 이 파일에 둡니다.

## 템플릿 레이아웃과 파일명 규약

이 파일 옆 `templates/` 아래에만 둡니다. 다른 경로는 탐색하지 않습니다.

- `templates/<sub>.<backend>.md` — **백엔드 변형**을 가진 sub-룰. `<sub>`가 sub-룰 ID, `<backend>`가 백엔드 식별자(`github`·`gitlab`)입니다. 예: `review-approval.github.md`, `review-approval.gitlab.md`.
- `templates/<sub>.md` — 백엔드 변형이 **없는** sub-룰(후속 확장용). 파일명에서 `.md`를 뺀 값이 sub-룰 ID입니다.

파일명에서 sub-룰 ID와 (있으면) 백엔드 식별자를 가르는 판정은 `references/template_tools.py parse-name <파일명>`으로 고정합니다(즉흥 파싱 금지). **출력 파일명에는 백엔드 식별자를 남기지 않습니다** — `review-approval.github.md`든 `review-approval.gitlab.md`든 출력은 항상 `rules/version-control/review-approval.md` 하나입니다.

## 생성 절차

1. **템플릿 열거.** `templates/*.md`만 읽습니다. 각 파일을 `parse-name`으로 sub-룰 ID와 (있으면) 백엔드 변형으로 식별하고, 같은 sub-룰 ID의 변형 집합을 묶습니다.

2. **백엔드 판별 (후보 확정 전 1회, 결과 재사용).** 백엔드 변형 sub-룰이나 git 계열 동반 산출(`git`)이 후보에 있으면, sub-룰 선택 **전에** 백엔드를 1회 판별하고 그 결과를 3단계의 git 계열 동반 산출 판정과 4단계의 변형 본문 선택에서 **재사용**합니다 — 재판별하지 않습니다. 판별 절차(공식 도메인 호스트명 정밀 매칭·self-hosted read-only API probe·substring 매칭 금지·inconclusive/origin 미설정 시 추측 없는 중단·안내)는 `references/backend-detection.md`를 읽고 그대로 따르고, git 계열 분류(정적 매핑 멤버십과 판정)는 `references/template_tools.py git-family <backend>`가 단일 출처입니다.

3. **sub-룰 선택과 git 공통 동반 산출.**
   - **백엔드 변형 sub-룰과 그 밖의 sub-룰(`review-approval`·`branch-naming` 등).** 어느 것을 쓸지 묻는 선택 질문 **없이** 적용 가능한 모든 sub-룰을 고정 순서(`review-approval` → `branch-naming`)로 각각 기록합니다. 백엔드 변형 sub-룰은 2단계에서 판별된 백엔드의 변형 본문을 씁니다. 단순 재실행으로 이 집합을 바꾸지 않습니다.
   - **git 계열 공통 sub-룰(`git`)은 사용자 선택지가 아닙니다.** `templates/git.md`(백엔드 변형 없음, 출력 `rules/version-control/git.md`)는 **2단계 판별이 git 계열일 때 자동으로 함께 산출되는 동반 출력**입니다. 2단계가 **git 계열이면** 백엔드 변형 sub-룰(review-approval 등)과 git 공통 지침(`git.md`)을 **함께 산출**하고, **git 계열이 아니면** git 공통 지침을 산출하지 않습니다. 사용자에게는 산출 대상만 안내하고 분류 기준 같은 내부 사정은 노출하지 않습니다.

4. **본문 조립.** 산출 대상인 각 sub-룰의 (백엔드 변형이 있으면 2단계에서 판별된 백엔드의) 템플릿에서 **frontmatter를 제거한 본문**을 그대로 취합합니다. 본문은 입력 치환 외에 변형하지 않습니다. 판별된 백엔드의 변형 파일이 없으면 그 사실을 알리고 종료합니다.

5. **입력(inputs) 치환.** 산출 대상 템플릿 frontmatter에 `inputs`가 있으면 처리하고, 없으면 건너뜁니다. 한 입력은 `multi_select`에 따라 **다중 선택(집계)** 또는 **단일 선택**으로 동작합니다(현재 `git`이 multi-select, `review-approval`의 `merge_method`가 single-select). 현재 런타임의 구조화된 사용자 질문 기능으로 한 번 묻고, 다중 선택은 **집계 치환**(선택값들을 표시 순서로 연결), 단일 선택은 **단일 치환**(고른 한 값)으로 본문의 여는 placeholder 토큰(`{{` 로 시작)을 채웁니다. 값은 `value` 우선·없으면 `label`, 응답 누락 시 `default` 옵션을 적용합니다(예: `git`의 force push 금지 기본 체크, `merge_method` 미응답 시 저장소 설정 따름). 집계 연결은 `references/template_tools.py aggregate ...`로 고정하고, 스키마·1옵션 폴백·빈 선택 정리·완전한 placeholder 예시 등 상세는 `references/input-substitution.md`가 단일 출처입니다.

6. **파일 기록.** 산출 대상인 각 sub-룰을 기록합니다. 대상 디렉터리 `rules/version-control/`가 없으면 먼저 생성하고, 본문을 `rules/version-control/<sub>.md`로(백엔드 식별자 없이) 기록합니다. 대상 파일이 이미 있으면 덮어쓰지 않고 **diff를 보여** `덮어쓴다 (교체)` / `보존한다 (취소)` 중 **명시적 교체 선택일 때만** 덮어씁니다. 자유 텍스트·침묵은 동의가 아닙니다.

7. **사후 작업.** 선택된 템플릿의 `on_create`가 있으면 파일 시스템을 건드리지 않는 안내성 지시만 수행합니다. 파일·디렉토리 생성/수정 지시는 무시하고 사용자에게 알립니다.

## 규칙

- 본 스킬은 `rules/version-control/` 아래 sub-룰 파일만 생성·갱신합니다(생성 절차 3단계의 고정 순서·동반 출력 집합대로). 카테고리 밖 파일이나 다른 카테고리의 기존 지침(범용 리뷰 원칙 `rules/review.md`·릴리스 버전 지침 `rules/engineering/versioning.md` 포함)은 변경하지 않습니다.
- 템플릿 본문은 그대로 복사하고 서로 합치지 않습니다. SKILL.md에 본문별 로직을 추가하지 않습니다. 새 백엔드·새 sub-룰은 `templates/` 파일 추가만으로 확장하며 이 SKILL.md를 수정하지 않습니다.
- 기존 sub-룰 파일은 사용자 명시 동의 없이는 절대 덮어쓰지 않습니다. 단순 재실행으로 sub-룰·백엔드를 바꾸지 않습니다.
