---
name: filesystem-rule-creator
description: 현재 프로젝트에 맞는 파일시스템 지침을 `rules/filesystem.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 파일시스템 지침을 새로 만들고 싶어 할 때.
---

# filesystem-rule-creator

현재 프로젝트에 맞는 파일시스템 지침 문서를 `rules/filesystem.md`에 생성·갱신합니다.

## 생성 절차

1. **프로젝트 스캔** — 파일 구성 맥락을 파악합니다.
   - `.gitignore` 항목, 빌드 산출물 디렉토리(`dist/`, `build/`, `target/`), 의존성 디렉토리(`node_modules/`, `.venv/`).
   - `.env*` 계열 파일, 예시 파일(`.env.example`), 잠금 파일(`package-lock.json`, `poetry.lock` 등).
   - 사용자별 설정 파일(`.idea/`, `.vscode/`, `~/` 참조 경로).
2. **내용 구성**
   - 같은 디렉토리의 `filesystem.md` 전체를 기본 내용으로 사용합니다.
   - 스캔에서 드러난 프로젝트 특화 위치(예: 특정 산출물 경로, 프로젝트 고유 `.gitignore` 항목)를 "## 이 프로젝트의 세부 지침" 섹션으로 본문 맨 아래에 추가합니다.
3. **파일 기록**
   - 대상: `rules/filesystem.md`
   - 상위 디렉토리가 없으면 함께 생성합니다.
   - 이미 존재하면 덮어쓰지 않고 diff 후 사용자에게 확인합니다.
