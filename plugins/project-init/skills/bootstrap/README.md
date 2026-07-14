# bootstrap

새 프로젝트의 공통 `AGENTS.md`와 선택한 벤더 골격(Claude Code·Codex)을 누락분만 설치하는 `project-init` 오케스트레이터 스킬 — `rules/` 카테고리 지침 생성은 형제 `*-rule-creator`에 위임한다.

- **언제** — 새 프로젝트 초기화·세팅·셋업·환경 구성 요청, 또는 공통 지침·벤더 골격 누락 프로젝트(정확한 트리거는 `SKILL.md` description).
- **호출** — 트리거 감지 시 자동 활성화. 별도 서브커맨드·인자 없음.

진행 순서·규칙은 [`SKILL.md`](./SKILL.md), 조립 베이스·벤더 골격·선택 자산은 `../../shared/bootstrap/`, 계약 테스트는 [`tests/`](./tests/) 참조 — 이 문서는 폴더 진입점용 요약이며 본문을 복제하지 않는다.
