# engineering-rule-creator

엔지니어링 카테고리의 sub-룰 디스패처 스킬 — 호출마다 `templates/`의 한 템플릿을 `rules/engineering/<sub>.md` 한 파일로 생성·갱신한다.

- **언제** — project-init 초기화 흐름, 또는 사용자가 릴리스 버전 규약(versioning)·버전업 강제 등 엔지니어링 sub-룰을 작성·갱신하려 할 때(정확한 트리거는 `SKILL.md` description).
- **호출** — 자연어 트리거가 description과 매칭되면 자동 활성화.

고유 사항(대상 디렉터리·빈 목록 문구)은 [`SKILL.md`](./SKILL.md), 공유 절차·결정적 스크립트는 [`../../shared/rule-creator/`](../../shared/rule-creator/), sub-룰 템플릿은 [`templates/`](./templates/) 참조.
