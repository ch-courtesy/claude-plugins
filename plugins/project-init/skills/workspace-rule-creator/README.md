# workspace-rule-creator

작업공간 위생 카테고리의 sub-룰 디스패처 스킬 — 호출마다 `templates/`의 한 템플릿을 `rules/workspace/<sub>.md` 한 파일로 생성·갱신한다.

- **언제** — project-init 초기화 흐름, 또는 사용자가 임시 파일·빌드 산출물·스크래치 데이터 등 작업공간 위생(workspace hygiene) sub-룰을 작성·갱신하려 할 때(정확한 트리거는 `SKILL.md` description).
- **호출** — 자연어 트리거가 description과 매칭되면 자동 활성화.

고유 사항(대상 디렉터리·메뉴-우선 계약·temp_path)은 [`SKILL.md`](./SKILL.md), 공유 절차·결정적 스크립트는 [`../../shared/rule-creator/`](../../shared/rule-creator/), 스킬 고유 스크립트(`normalize_path.py` — temp_path 정규화)는 [`references/`](./references/), sub-룰 템플릿은 [`templates/`](./templates/) 참조.
