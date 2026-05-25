# EARS patterns (optimized)

SPEC 수용 기준은 가능하면 EARS로 쓴다. frontmatter `ears_language`: `ko`(default), `en`, `hybrid`.

## 5 patterns

- Ubiquitous: 항상 성립. `The system shall ...` / `시스템은 ...해야 한다`
- Event-driven: 이벤트 발생 시. `When <event>, the system shall ...`
- State-driven: 상태 동안. `While <state>, the system shall ...`
- Unwanted behavior: 예외/오류 시. `If <condition>, the system shall ...`
- Optional feature: 기능 활성화 시. `Where <feature>, the system shall ...`

## 작성 규칙

- 각 기준은 관찰 가능한 결과와 검증 방법을 포함한다.
- 구현 방법, 파일명, 클래스명, 라이브러리명은 피한다. WHAT/HOW 방어선 유지.
- 하나의 기준에는 하나의 검증 가능한 요구만 둔다.
- 모호한 단어("적절히", "빠르게", "잘")는 수치·상태·출력으로 바꾼다.
- 독립 테스트 가능해야 한다.

## 언어 모드

- `ko`: 한국어 EARS. 키워드는 자연스럽게 번역.
- `en`: 영어 EARS.
- `hybrid`: EARS trigger는 영어, 설명은 한국어 허용.

사용자에게 언어를 다시 묻지 말고 frontmatter 값을 따른다.
