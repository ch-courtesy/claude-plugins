# GitHub Issues + Projects로 작업 관리하기 (계획)

**상태**: 미착수 (나중에 진행 예정)
**작성일**: 2026-04-23

## 목표

여러 계획·작업을 꾸준히 추적하고, 이후 세션의 Claude도 이전 논의를 이어갈 수 있도록 **영구 저장소**를 마련한다. 대화 메모리나 로컬 markdown만으로는 다수 항목의 상태 추적·검색·연결(커밋/PR)이 어렵다.

## 핵심 원칙

- **계획 본문은 Issue body에.** 설계 문서·결정 근거·미해결 질문 등 장문 markdown은 Issue가 담는다. 버전·diff·인라인 편집·코멘트 스레드 모두 Issue가 우월.
- **Project는 인덱스 / 상태 트래커.** 카드 필드에는 메타데이터(상태·우선순위·영역)만. 본문은 넣지 않는다.
- **Claude가 꺼내 쓸 수 있어야 의미가 있다.** `gh` CLI로 조회 가능한 위치·네이밍 규약을 reference 메모리에 기록.

## 초기 세팅 단계

1. **전제 조건 확인**
   - 이 레포(`claude-plugins`)에 GitHub 원격이 연결되어 있는지 (`git remote -v`).
   - 없으면 리모트 생성 및 푸시부터.

2. **Project 생성**
   - 이름 예시: `Plugin Roadmap`
   - 타입: Repository 단위 Project (또는 User/Org 단위 — 팀 범위에 따라)

3. **필드 구성**
   - `Status`: Backlog / In Design / In Progress / Done
   - `Area`: plugin / skill / infra / docs
   - (선택) `Priority`: P0 / P1 / P2

4. **Issue 템플릿 추가** (`.github/ISSUE_TEMPLATE/plan.md`)
   - 섹션: 목표 / 배경 / 제안 / 미해결 질문 / 검증 계획
   - 설계 계획과 버그 리포트를 구분하고 싶다면 템플릿 2종.

5. **첫 아이템 등록**
   - 현재 논의 중인 "project-init 템플릿 → 프로젝트 스킬 전환" 계획을 Issue로 작성해 Project에 추가.
   - Status=In Design, Area=skill.

6. **레이블 정리**
   - `type:plan`, `type:bug`, `type:feature` 등 최소한의 레이블 체계.

## Claude 접근 경로

Reference 메모리에 아래를 기록한다 (세팅 완료 후):

- 계획·작업은 `<owner>/<repo>` GitHub Project "Plugin Roadmap"에서 추적.
- Issue 조회: `gh issue list --label type:plan`
- Project 조회: `gh project item-list <project-number> --owner <owner>`
- 본 파일(`docs/plans/github-issues-workflow.md`)은 워크플로 자체의 설계 문서로 유지.

## 미해결 질문 (진행 전 결정)

1. Project 스코프: 이 레포 전용? 아니면 User/Org 레벨에서 여러 레포 아우름?
2. 계획(plan)과 실행 태스크(task)를 별 Issue로 분리할지, 한 Issue 안 체크박스로 다룰지?
3. Claude가 Issue를 **자동 업데이트**할 수 있게 할지(코멘트·상태 전환), 읽기 전용으로만 쓸지?
4. `docs/plans/` 로컬 문서와 Issue 간 관계: Issue가 정본이고 로컬은 제거? 아니면 로컬 문서 링크를 Issue에 거는 이중 구조?

## 다음 단계

이 계획을 실제로 진행할 때는:
- 위 "초기 세팅 단계" 1번부터 순서대로.
- 세팅 완료 후 reference 메모리 업데이트.
- 기존 논의 중인 계획들(예: 스킬 전환)을 Issue로 이관.
