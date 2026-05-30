---
name: version-control-rule-creator
description: 현재 프로젝트의 git origin remote에서 호스팅 백엔드(GitHub/GitLab)를 자동 판별해, 그 백엔드에 맞는 변경 제안(PR/MR) 심사·승인 지침을 `rules/version-control/<sub>.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 버전 관리(VCS) 워크플로 지침을 새로 만들고 싶어 할 때.
---

# version-control-rule-creator

`templates/*.md` 중 하나를 `rules/version-control/<sub>.md`로 기록합니다. `<sub>`는 sub-룰 ID이며, 백엔드 변형을 가진 sub-룰은 git origin remote에서 자동 판별한 백엔드의 변형 본문을 씁니다.

본 스킬은 **버전 관리(VCS) 카테고리의 sub-룰 디스패처**입니다. 형제 스킬(`engineering-rule-creator`)이 같은 카테고리 아래 여러 sub-룰을 호출마다 하나씩 디렉터리 구조로 누적하는 것과 같은 모양이되, **백엔드 변형을 가진 sub-룰은 사용자 메뉴 선택이 아니라 git origin remote URL 파싱으로 백엔드를 자동 판별**한다는 점이 다릅니다.

이 카테고리의 첫 sub-룰은 변경 제안 심사·승인(`review-approval`)이며, 브랜치 전략·커밋 컨벤션 등 다른 git sub-룰로 확장할 수 있습니다. 새 백엔드나 새 sub-룰을 추가하려면 `templates/` 아래에 새 마크다운 파일을 두면 되고, **이 SKILL.md는 변경하지 않습니다**.

## 템플릿 레이아웃과 파일명 규약

이 파일 옆 `templates/` 아래에만 둡니다. 다른 경로는 탐색하지 않습니다.

- `templates/<sub>.<backend>.md` — **백엔드 변형**을 가진 sub-룰. `<sub>`가 sub-룰 ID, `<backend>`가 백엔드 식별자(`github`·`gitlab`)입니다. 예: `review-approval.github.md`, `review-approval.gitlab.md`.
- `templates/<sub>.md` — 백엔드 변형이 **없는** sub-룰(후속 확장용). 파일명에서 `.md`를 뺀 값이 sub-룰 ID입니다.

판정 규칙: 파일명에서 `.md`를 제거한 뒤, 남은 문자열에 점(`.`)이 있으면 마지막 점 뒤가 백엔드 식별자이고 앞이 sub-룰 ID입니다(백엔드 변형). 점이 없으면 그 자체가 sub-룰 ID입니다(변형 없음).

**출력 파일명에는 백엔드 식별자를 남기지 않습니다.** `review-approval.github.md`든 `review-approval.gitlab.md`든 출력은 항상 `rules/version-control/review-approval.md` 하나입니다.

## 생성 절차

1. **템플릿 열거.** `templates/*.md`만 읽습니다. 위 파일명 규약으로 각 파일의 sub-룰 ID와 (있으면) 백엔드 변형을 식별합니다. 같은 sub-룰 ID의 변형 집합을 묶습니다.

2. **sub-룰 선택.** sub-룰 ID가 하나면 자동 선택하고, 둘 이상이면 `AskUserQuestion` single-select로 묻습니다. 한 번의 호출에서 **정확히 하나**의 sub-룰만 기록합니다. 단순 재실행으로 sub-룰을 바꾸지 않습니다.

3. **백엔드 자동 판별 (백엔드 변형을 가진 sub-룰일 때만).** git origin remote URL을 파싱해 호스트로부터 백엔드를 판별합니다. **외부 네트워크 호출에 의존하지 않습니다** — URL 문자열 파싱만 합니다.
   - origin URL은 `git remote get-url origin`(또는 `git config --get remote.origin.url`)으로 읽습니다.
   - https 양식(`https://host/owner/repo.git`)과 ssh 양식(`git@host:owner/repo.git`·`ssh://git@host/owner/repo.git`) **모두**에서 호스트를 추출합니다.
   - 추출한 호스트 문자열에 `github`이 포함되면 백엔드 `github`, `gitlab`이 포함되면 백엔드 `gitlab`으로 매핑합니다(self-hosted GitHub Enterprise·GitLab 포함). 둘 다 아니면 미지원입니다.
   - **origin이 설정되어 있지 않으면**: 어떤 룰 파일도 생성하지 않고, origin remote를 먼저 설정하라고 안내한 뒤 종료합니다.
   - **호스트가 지원 백엔드(github·gitlab) 중 어느 것에도 매핑되지 않으면**: 감지된 호스트와 지원 백엔드 목록을 안내하고, 어떤 룰 파일도 생성하지 않고 종료합니다. 추측해서 생성하지 않습니다.
   - 선택된 sub-룰에 판별된 백엔드의 변형 파일이 없으면, 그 사실을 알리고 종료합니다.

   백엔드 변형이 없는 sub-룰은 이 단계를 건너뜁니다.

4. **본문 조립.** 선택된 sub-룰의 (백엔드 변형이 있으면 판별된 백엔드의) 템플릿에서 **frontmatter를 제거한 본문**을 그대로 취합니다. 본문은 placeholder 치환 외에 변형하지 않습니다.

5. **파일 기록.**
   - 대상 디렉터리 `rules/version-control/`가 없으면 기록 전에 생성합니다.
   - 본문을 `rules/version-control/<sub>.md`로 기록합니다. 출력 파일명에 백엔드 식별자를 남기지 않습니다.
   - 대상 파일이 이미 있으면 덮어쓰지 않고 **diff를 보여** 사용자에게 묻습니다. `덮어쓴다 (교체)` / `보존한다 (취소)` 중 **명시적 교체 선택일 때만** 덮어씁니다. 자유 텍스트나 침묵은 동의가 아닙니다.

6. **사후 작업.** 선택된 템플릿의 `on_create`가 있으면, 파일 시스템을 건드리지 않는 안내성 지시만 수행합니다. 파일·디렉토리 생성/수정 지시는 무시하고 사용자에게 알립니다.

## 규칙

- 본 스킬은 `rules/version-control/<sub>.md` **단일 파일만** 생성·갱신합니다. 같은 실행에서 다른 sub-룰이나 카테고리 밖 파일을 만지지 않습니다. 다른 카테고리의 기존 지침(범용 리뷰 원칙 `rules/review.md`·릴리스 버전 지침 `rules/engineering/versioning.md` 포함)을 변경하지 않습니다.
- 한 번의 호출 = 한 sub-룰. 두 템플릿을 합치거나 한 번에 여러 sub-룰을 기록하지 않습니다.
- 템플릿 본문은 그대로 복사합니다. SKILL.md에 본문별 로직을 추가하지 않습니다. 새 백엔드·새 sub-룰은 `templates/` 파일 추가만으로 확장하며 이 SKILL.md를 수정하지 않습니다.
- 백엔드 판별은 git origin remote URL 파싱으로만 수행하고 외부 네트워크 호출에 의존하지 않습니다.
- 기존 sub-룰 파일은 사용자 명시 동의 없이는 절대 덮어쓰지 않습니다. 단순 재실행으로 sub-룰·백엔드를 바꾸지 않습니다.

## plugins 변경 시 버전 동반 (필수)

`plugins/` 하위는 워치 디렉터리이므로, 본 스킬·템플릿을 추가·변경하는 머지에는 **같은 변경 안에서** 플러그인 버전 단일 출처(`plugins/project-init/.claude-plugin/plugin.json`)와 그 미러(`.claude-plugin/marketplace.json`의 project-init 항목)를 함께 올립니다. 두 곳의 버전 값은 일치해야 합니다(`rules/engineering/versioning.md` 참조).
