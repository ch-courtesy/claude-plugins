# repair-skill

기존 SKILL.md를 `../../shared/rubric/` 30항목(규칙 17 + 모델 13) 기준으로 평가하고, 승인된 BLOCKER·MAJOR 항목만 직접 수정한 뒤 재평가하는 `project-init` 스킬.

- **언제** — 기존 스킬의 품질 점검·진단·수정·보수·리페어 요청, 또는 BLOCKER·MAJOR 해소가 필요할 때(정확한 트리거는 `SKILL.md` description).
- **호출** — `Skill(skill="repair-skill", args="<SKILL.md 경로 | all>")`. `all`이면 저장소 전체 SKILL.md를 스킬마다 독립적으로 평가·승인한다.

절차·규칙은 [`SKILL.md`](./SKILL.md), 루브릭 기준은 [`../../shared/rubric/criteria.md`](../../shared/rubric/criteria.md), 검사기는 [`../../shared/rubric/rule_checker.py`](../../shared/rubric/rule_checker.py) 참조 — 이 문서는 폴더 진입점용 요약이며 본문을 복제하지 않는다.
