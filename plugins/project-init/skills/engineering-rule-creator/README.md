# engineering-rule-creator

엔지니어링 카테고리의 sub-룰 디스패처 스킬. 호출마다 `templates/` 의 한 템플릿을
`rules/engineering/<sub>.md` 한 파일로 생성·갱신한다.

## 무엇 (What)

- 입력: `templates/*.md` (옵션·입력·사후 작업을 frontmatter로 선언한 sub-룰 템플릿).
- 출력: `rules/engineering/<sub>.md` 단일 파일 (`<sub>` = 템플릿 파일명 − 확장자).
- 공개 계약: 한 번의 호출 = 한 sub-룰. 기존 파일은 사용자 명시 동의 없이 덮어쓰지 않는다.

## 언제 (When)

project-init 초기화 흐름에서 엔지니어링 카테고리 지침을 만들 때, 또는 사용자가
릴리스 버전 규약(versioning)·버전업 강제·changelog 정책 등 엔지니어링 sub-룰을
새로 작성·갱신하려 할 때. (정확한 트리거 표현은 `SKILL.md` frontmatter `description`.)

## 어떻게 호출 (How)

Claude 스킬로 활성화된다 — 자연어 트리거가 `description` 과 매칭되면 실행된다.
절차·입력 파싱·치환 규칙의 단일 출처는 `SKILL.md` 본문이며, 결정적 작업은
`references/` 스크립트로 고정되어 있다.

## 포인터

- 절차·옵션·입력·사후 작업 규칙: [`SKILL.md`](./SKILL.md)
- 결정적 작업 스크립트: [`references/`](./references/)
  - `scan_templates.py` — 템플릿 frontmatter 파싱 → 정규화 후보 JSON.
  - `list_target_dirs.py` — target depth1 디렉토리 후보 산출.
  - `render_rule.py` — frontmatter 제거 + placeholder 치환 + bullet 렌더.
- sub-룰 템플릿: [`templates/`](./templates/)
