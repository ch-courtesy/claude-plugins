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
---

# version-control-rule-creator

공통 템플릿 디렉터리 `../../shared/version-control-rule-creator/templates/`의 `*.md` 중 하나를 `rules/version-control/<sub>.md`로 기록합니다. `<sub>`는 sub-룰 ID이며, 백엔드 변형을 가진 sub-룰은 git origin remote에서 자동 판별한 백엔드의 변형 본문을 씁니다.

본 스킬은 **버전 관리(VCS) 카테고리의 sub-룰 디스패처**입니다. 백엔드 변형을 가진 sub-룰(예: `review-approval`)은 사용자 메뉴 선택이 아니라 git origin remote URL 파싱으로 백엔드를 자동 판별해 그 변형 본문을 씁니다. 백엔드가 **git 계열**로 판별되면 git 계열 공통 지침(`git`)을 그 백엔드 룰셋의 **동반 출력**으로 함께 산출합니다 — git을 review-approval과 "둘 중 하나"로 고르게 하지 않습니다.

이 카테고리의 첫 sub-룰은 변경 제안 심사·승인(`review-approval`)이며, 브랜치 전략·커밋 컨벤션 등 다른 git sub-룰로 확장할 수 있습니다. 새 백엔드나 새 sub-룰을 추가하려면 공통 템플릿 디렉터리 `../../shared/version-control-rule-creator/templates/` 아래에 새 마크다운 파일을 두면 되고, **이 SKILL.md는 변경하지 않습니다**.

## 템플릿 레이아웃과 파일명 규약

공통 템플릿 디렉터리 `../../shared/version-control-rule-creator/templates/` 아래에만 둡니다. 다른 경로는 탐색하지 않습니다.

- `../../shared/version-control-rule-creator/templates/<sub>.<backend>.md` — **백엔드 변형**을 가진 sub-룰. `<sub>`가 sub-룰 ID, `<backend>`가 백엔드 식별자(`github`·`gitlab`)입니다. 예: `review-approval.github.md`, `review-approval.gitlab.md`.
- `../../shared/version-control-rule-creator/templates/<sub>.md` — 백엔드 변형이 **없는** sub-룰(후속 확장용). 파일명에서 `.md`를 뺀 값이 sub-룰 ID입니다.

판정 규칙: 파일명에서 `.md`를 제거한 뒤, 남은 문자열에 점(`.`)이 있으면 마지막 점 뒤가 백엔드 식별자이고 앞이 sub-룰 ID입니다(백엔드 변형). 점이 없으면 그 자체가 sub-룰 ID입니다(변형 없음).

**출력 파일명에는 백엔드 식별자를 남기지 않습니다.** `review-approval.github.md`든 `review-approval.gitlab.md`든 출력은 항상 `rules/version-control/review-approval.md` 하나입니다.

## 생성 절차

1. **템플릿 열거.** 공통 템플릿 디렉터리 `../../shared/version-control-rule-creator/templates/*.md`만 읽습니다. 위 파일명 규약으로 각 파일의 sub-룰 ID와 (있으면) 백엔드 변형을 식별합니다. 같은 sub-룰 ID의 변형 집합을 묶습니다.

2. **백엔드 판별 (후보 확정 전 1회).** 1단계에서 열거한 후보 중 백엔드 변형을 가진 sub-룰(예: `review-approval`)이 있거나 git 계열 여부에 따라 동반 산출되는 sub-룰(`git`)이 있으면, sub-룰을 선택하기 **전에** 백엔드를 1회 판별합니다. 이 판별 결과는 3단계의 git 계열 동반 산출 판정과 4단계의 백엔드 변형 본문 선택에서 **함께 재사용**하며 재판별하지 않습니다. git origin remote URL을 파싱해 호스트를 추출한 뒤, **공식 도메인은 호스트명 정밀 매칭으로(네트워크 호출 없음), self-hosted 호스트는 부작용 없는 read-only API probe로** 백엔드를 판별합니다. **호스트명 substring 매칭은 쓰지 않습니다**(`github-mirror.*`·`mygithub.com` 류 오판별 방지).
   - origin URL은 `git remote get-url origin`(또는 `git config --get remote.origin.url`)으로 읽습니다.
   - https 양식(`https://host/owner/repo.git`)과 ssh 양식(`git@host:owner/repo.git`·`ssh://git@host/owner/repo.git`) **모두**에서 호스트를 추출합니다.
   - **origin이 설정되어 있지 않으면**: 어떤 룰 파일도 생성하지 않고, origin remote를 먼저 설정하라고 안내한 뒤 종료합니다.
   - **(a) 공식 도메인 정밀 매칭 (네트워크 호출 없음).** 추출한 호스트가 아래 공식 도메인 집합에 **정밀히 일치**하면 호스트명만으로 백엔드를 판별하고 probe를 생략합니다.
     - GitHub: `github.com`, 그리고 `*.github.com`·`*.ghe.com`·`*.githubenterprise.com`에 대한 서브도메인.
     - GitLab: `gitlab.com`, 그리고 `*.gitlab.com`에 대한 서브도메인.
     - 정밀 매칭은 **라벨 경계**로 판단합니다 — 호스트가 그 도메인과 같거나 그 도메인을 온전한 접미사 라벨로 끝낼 때만 일치입니다(`host == d` 또는 `host`가 `.d`로 끝남). `github.com.evil.test`·`mygithub.com`처럼 문자열만 포함하는 경우는 일치가 아닙니다.
   - **(b) self-hosted read-only API probe (공식 도메인이 아닐 때만).** 호스트가 (a)에 해당하지 않으면, 그 호스트에 대해 **부작용 없는 read-only(GET류) API probe**로 백엔드를 식별합니다. 상태를 바꾸는 요청은 보내지 않습니다.
     - 잘 알려진 백엔드 식별 엔드포인트의 **상태코드·응답 헤더·본문 마커** 조합으로 github/gitlab을 판별합니다(예: GitLab은 `/api/v4/` 계열 응답·헤더, GitHub Enterprise는 `/api/v3` 계열 응답·헤더).
     - probe는 best-effort입니다. **timeout·도달 불가·인증요구(401/403)·식별 마커 부재는 모두 inconclusive**로 처리합니다.
   - **판별 실패 시 중단 (추측 금지).** (a) 정밀 매칭에도 해당하지 않고 (b) probe로도 백엔드를 확정하지 못하면(inconclusive 포함), 감지된 호스트와 지원 백엔드 목록(github·gitlab)을 안내하고 어떤 룰 파일도 생성하지 않고 종료합니다. 추측해서 생성하지 않습니다.
   - 후보 중 어떤 sub-룰도 백엔드 정보를 필요로 하지 않으면 이 단계를 건너뜁니다.

3. **sub-룰 선택과 git 공통 동반 산출.** 후보 sub-룰을 두 부류로 나눠 처리합니다.

   - **백엔드 변형 sub-룰과 그 밖의 sub-룰(`review-approval` 등).** sub-룰 ID가 하나면 자동 선택하고 둘 이상이면 `AskUserQuestion` single-select로 고릅니다. 이렇게 고른 sub-룰을 기록합니다. 단순 재실행으로 이 선택을 바꾸지 않습니다.
   - **git 계열 공통 sub-룰(`git`)은 사용자 선택지가 아닙니다.** `../../shared/version-control-rule-creator/templates/git.md`(백엔드 변형 없음, 출력 `rules/version-control/git.md`)는 **2단계 판별이 git 계열일 때 자동으로 함께 산출되는 동반 출력**입니다. review-approval과 "둘 중 하나"로 고르게 하는 메뉴 항목으로 노출하지 않습니다.
     - 판별된 백엔드를 git 계열로 분류하는 **정적 매핑**만 둡니다: `github`·`gitlab`은 git 계열입니다. 이 정적 매핑이 git 계열 분류의 단일 출처이며, 매핑에 없는 백엔드의 기본값은 **"git 계열 아님"**입니다. 향후 비-git 백엔드는 이 매핑에 넣지 않는 것만으로 동반 산출에서 자연히 빠집니다.
     - 2단계 판별이 **git 계열이면**: 위에서 고른 백엔드 변형 sub-룰(review-approval)과 git 공통 지침(`rules/version-control/git.md`)을 **함께 산출**합니다.
     - **git 계열이 아니면**: git 공통 지침을 산출하지 않습니다. 사용자에게는 산출 대상이 무엇인지만 안내하고, git이 왜 공통으로 분리됐는지·분류 기준 같은 내부 사정은 노출하지 않습니다.

4. **본문 조립.** 산출 대상인 각 sub-룰(백엔드 변형 sub-룰, 그리고 git 계열이면 동반 `git`)의 (백엔드 변형이 있으면 **2단계에서 판별된** 백엔드의) 템플릿에서 **frontmatter를 제거한 본문**을 그대로 취합니다. 본문은 placeholder 치환 외에 변형하지 않습니다.
   - 선택된 백엔드 변형 sub-룰에 2단계에서 판별된 백엔드의 변형 파일이 없으면, 그 사실을 알리고 종료합니다.

4-bis. **입력(inputs) 치환 — 정적 multi-select 집계 / single-select 단일 선택.** 산출 대상 템플릿 frontmatter에 `inputs`가 있으면 처리하고, 없으면 이 단계를 건너뜁니다. 한 입력은 `multi_select` 값에 따라 **다중 선택(집계)** 또는 **단일 선택** 두 모드 중 하나로 동작합니다. (현재 `git` 템플릿이 multi-select를, `review-approval` 템플릿의 `merge_method`가 single-select를 씁니다.)
   - **스키마.** 각 입력은 `name`, `header`, `question`, `multi_select`, `options[{label, description, value?, default?}]`를 가집니다. `multi_select: true`는 **한 질문에서 여러 정책을 다중 선택**함을 뜻하고, `multi_select: false`(또는 생략)는 **한 질문에서 정확히 하나를 고르는 단일 선택**을 뜻합니다.
   - **질문.** 입력을 `AskUserQuestion`으로 **한 번** 묻되, 다중 선택 입력은 **multi-select**로, 단일 선택 입력은 **single-select**로 제시합니다. 옵션 표시 순서는 frontmatter 순서를 따릅니다. `default: true`인 옵션은 **기본 선택(체크)** 상태로 제시합니다(추천·기본 옵션을 첫 번째에 둡니다). 사용자에게는 정책·방식 선택지만 노출하고, 정책이 공통으로 분리된 내부 사정·분류 기준은 노출하지 않습니다.
   - **집계 치환 (다중 선택).** 본문의 **단일 집계 placeholder** `{{<name>}}`를, **선택된 옵션들의 값을 표시 순서대로 연결**한 텍스트로 치환합니다. 값은 `value`가 있으면 `value`, 없으면 `label`을 씁니다(value 우선). 비어 있지 않은 "Other" 자유 입력도 연결 대상에 포함합니다. 절과 절 사이는 빈 줄 하나로 구분해 마크다운 서식을 유지합니다. **정책별 개별 placeholder는 두지 않습니다.**
   - **단일 치환 (단일 선택).** 본문의 placeholder `{{<name>}}`를 **선택된 한 옵션의 값**으로 치환합니다(`value` 우선, 없으면 `label`). 연결은 일어나지 않습니다.
   - **빈 선택.** (다중 선택에서) 아무 옵션도 선택되지 않으면 집계 결과는 빈 문자열이고, placeholder가 놓인 줄을 절 단위로 정리·제거해 빈 줄·깨진 마크다운을 남기지 않습니다. 도입부(헤더 + git 계열 분류)는 그대로 남습니다.
   - **누락 응답 (디폴트 경로).** 응답이 누락되면 `default: true`인 옵션(들)이 선택된 것으로 간주합니다. 다중 선택에서는 force push 금지(기본 체크)가 적용되어 금지 절이 포함된 `git.md`가 생성되고(force push 미체크 = 허용), 단일 선택에서는 기본 옵션 하나가 적용됩니다(예: `merge_method` 미응답 시 "저장소 설정을 따름" 절이 들어가 기존 수동 안내로 자연 degrade).
   - **확장.** 새 정책·방식은 frontmatter `options`에 **옵션 항목만 추가**하면 됩니다 — 이 SKILL.md 로직, 본문 placeholder, 질문 수는 바뀌지 않습니다.

5. **파일 기록.** 산출 대상인 각 sub-룰(백엔드 변형 sub-룰, 그리고 git 계열이면 동반 `git`)을 아래 규칙으로 각각 기록합니다.
   - 대상 디렉터리 `rules/version-control/`가 없으면 기록 전에 생성합니다.
   - 본문을 `rules/version-control/<sub>.md`로 기록합니다. 출력 파일명에 백엔드 식별자를 남기지 않습니다.
   - 대상 파일이 이미 있으면 덮어쓰지 않고 **diff를 보여** 사용자에게 묻습니다. `덮어쓴다 (교체)` / `보존한다 (취소)` 중 **명시적 교체 선택일 때만** 덮어씁니다. 자유 텍스트나 침묵은 동의가 아닙니다.

6. **사후 작업.** 선택된 템플릿의 `on_create`가 있으면, 파일 시스템을 건드리지 않는 안내성 지시만 수행합니다. 파일·디렉토리 생성/수정 지시는 무시하고 사용자에게 알립니다.

## 규칙

- 본 스킬은 `rules/version-control/` 아래 sub-룰 파일만 생성·갱신합니다. 한 실행에서 기록하는 백엔드 변형 sub-룰은 하나이며, 백엔드가 git 계열이면 git 공통 지침(`git.md`)을 그 **동반 출력**으로 함께 기록합니다. 카테고리 밖 파일이나 다른 카테고리의 기존 지침(범용 리뷰 원칙 `rules/review.md`·릴리스 버전 지침 `rules/engineering/versioning.md` 포함)은 변경하지 않습니다.
- 백엔드 변형 sub-룰은 한 번의 호출에서 하나만 고릅니다. git 계열일 때 동반 산출되는 git 공통 지침은 그 예외로, 백엔드 변형 sub-룰과 `git.md`가 함께 기록됩니다. 템플릿 본문을 서로 합치지는 않습니다.
- 템플릿 본문은 그대로 복사합니다. SKILL.md에 본문별 로직을 추가하지 않습니다. 새 백엔드·새 sub-룰은 공통 템플릿 디렉터리 `../../shared/version-control-rule-creator/templates/` 파일 추가만으로 확장하며 이 SKILL.md를 수정하지 않습니다.
- 백엔드 판별은 **공식 도메인 호스트명 정밀 매칭(네트워크 없음) + self-hosted read-only API probe**로 수행합니다. 호스트명 substring 매칭은 쓰지 않으며, 정밀 매칭에도 probe에도 걸리지 않으면(inconclusive 포함) 추측 없이 중단하고 안내합니다.
- 기존 sub-룰 파일은 사용자 명시 동의 없이는 절대 덮어쓰지 않습니다. 단순 재실행으로 sub-룰·백엔드를 바꾸지 않습니다.

## plugins 변경 시 버전 동반 (필수)

`plugins/` 하위는 워치 디렉터리이므로, 본 스킬·템플릿을 추가·변경하는 머지에는 **같은 변경 안에서** 플러그인 버전 단일 출처(`plugins/project-init/.claude-plugin/plugin.json`)와 그 미러(`.claude-plugin/marketplace.json`의 project-init 항목)를 함께 올립니다. 두 곳의 버전 값은 일치해야 합니다(`rules/engineering/versioning.md` 참조).
