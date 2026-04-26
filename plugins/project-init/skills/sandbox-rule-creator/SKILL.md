---
name: sandbox-rule-creator
description: 현재 프로젝트에 맞는 샌드박스·격리 지침을 `rules/sandbox.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 격리 환경 지침을 새로 만들고 싶어 할 때.
---

# sandbox-rule-creator

현재 프로젝트에 맞는 샌드박스·격리 지침 문서를 `rules/sandbox.md`에 생성·갱신합니다.

## 생성 절차

1. **프로젝트 스캔** — 격리 관련 맥락을 파악합니다.
   - 컨테이너 설정(`Dockerfile`, `docker-compose.yml`, `devcontainer.json`).
   - 가상환경·lock 파일(`.venv/`, `poetry.lock`, `pnpm-lock.yaml`).
   - `git worktree` 사용 이력, CI 격리 설정.
2. **내용 구성**
   - 같은 디렉토리의 `sandbox.md` 전체를 기본 내용으로 사용합니다.
   - 프로젝트의 컨테이너 이미지·devcontainer 진입 절차·CI 격리 방식을 "## 이 프로젝트의 세부 지침"에 추가합니다.
3. **파일 기록**
   - 대상: `rules/sandbox.md`
   - 상위 디렉토리 부재 시 함께 생성.
   - 이미 존재하면 덮어쓰지 않고 diff 후 사용자에게 확인.
