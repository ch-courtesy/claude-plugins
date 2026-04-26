---
name: git-rule-creator
description: 현재 프로젝트에 맞는 Git 지침을 `rules/git.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 Git 지침을 새로 만들고 싶어 할 때.
---

# git-rule-creator

현재 프로젝트에 맞는 Git 지침 문서를 `rules/git.md`에 생성·갱신합니다.

## 생성 절차

1. **프로젝트 스캔** — Git 관련 맥락을 파악합니다.
   - 원격 설정(`git remote -v`), 기본 브랜치(`main` / `master` / 기타).
   - `.gitignore`, `.gitattributes`, `.github/` 워크플로.
   - 기존 `git log` 메시지 스타일(있는 경우) — 커밋 컨벤션 힌트.
   - PR 템플릿(`.github/PULL_REQUEST_TEMPLATE.md`) 존재 여부.
2. **내용 구성**
   - 같은 디렉토리의 `git.md` 전체를 기본 내용으로 사용합니다.
   - 스캔 결과 기반으로 프로젝트 고유의 브랜치 규칙·커밋 스타일·PR 절차를 "## 이 프로젝트의 세부 지침" 섹션으로 추가합니다.
3. **파일 기록**
   - 대상: `rules/git.md`
   - 상위 디렉토리 부재 시 함께 생성.
   - 이미 존재하면 덮어쓰지 않고 diff 후 사용자에게 확인.
