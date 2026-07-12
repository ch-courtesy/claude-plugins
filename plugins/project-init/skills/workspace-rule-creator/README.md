# workspace-rule-creator

작업공간 위생 카테고리의 sub-룰 디스패처 스킬. 호출마다 `templates/` 의 한 템플릿을
`rules/workspace/<sub>.md` 한 파일로 생성·갱신한다.

## 무엇 (What)

- 입력: `templates/*.md` (옵션·입력·사후 작업을 frontmatter로 선언한 sub-룰 템플릿).
- 출력: `rules/workspace/<sub>.md` 단일 파일 (`<sub>` = 템플릿 파일명 − 확장자).
- 공개 계약: 한 번의 호출 = 한 sub-룰. 기존 파일은 사용자 명시 동의 없이 덮어쓰지 않는다.

## 언제 (When)

project-init 초기화 흐름에서 작업공간 위생 카테고리 지침을 만들 때, 또는 사용자가
임시 파일·빌드 산출물·스크래치 데이터 등 작업공간 위생(workspace hygiene) sub-룰을
새로 작성·갱신하려 할 때. (정확한 트리거 표현은 `SKILL.md` frontmatter `description`.)

## 어떻게 호출 (How)

Claude 스킬로 활성화된다 — 자연어 트리거가 `description` 과 매칭되면 실행된다.
절차·입력 파싱·치환 규칙의 단일 출처는 공유 프로토콜
`../../shared/rule-creator/protocol.md`이고, `SKILL.md`에는 이 스킬 고유
사항(메뉴-우선 정적 입력 계약·temp_path 기본값 등)만 남는다.

## 포인터

- 고유 사항(대상 디렉터리·메뉴-우선 계약·temp_path): [`SKILL.md`](./SKILL.md)
- 공유 절차·결정적 스크립트: [`../../shared/rule-creator/`](../../shared/rule-creator/)
- 스킬 고유 스크립트: [`references/`](./references/)
  - `normalize_path.py` — temp_path 입력값 후행 `/` 정규화 + 빈 값 기본값 적용.
- sub-룰 템플릿: [`templates/`](./templates/)
