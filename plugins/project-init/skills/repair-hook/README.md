# repair-hook

소비 프로젝트의 기존 `.claude/hooks/`를 `../../shared/hook-standard/` 15항목(검사기 10 + 모델 5) 기준으로 평가하고, 승인된 BLOCKER·MAJOR 항목만 직접 수정한 뒤 재평가하는 `project-init` 스킬.

- **언제** — 기존 훅의 품질 점검·진단·수정·보수·표준화 요청, 또는 훅 BLOCKER·MAJOR 해소가 필요할 때(정확한 트리거는 `SKILL.md` description). 평가-전용 모드도 지원한다.
- **호출** — `Skill(skill="repair-hook", args="[<훅 디렉터리 경로>]")`. 생략하면 기본값 `.claude/hooks/`.

절차·규칙은 [`SKILL.md`](./SKILL.md), 표준 기준은 [`../../shared/hook-standard/standard.md`](../../shared/hook-standard/standard.md), 검사기는 [`../../shared/hook-standard/hook_checker.py`](../../shared/hook-standard/hook_checker.py) 참조 — 이 문서는 폴더 진입점용 요약이며 본문을 복제하지 않는다.
