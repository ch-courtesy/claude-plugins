---
name: genre-rubric
description: 수필·설명문·논설문·리뷰·단편·장편·웹소설 원고를 그 장르의 10항목 0·1·2점 표로 외부 LLM 에이전트 CLI(codex·claude·agy 중 글쓴 모델과 다른 회사)가 독립 채점한다. 항목마다 본문 근거 문장과 수정 행동을 붙이고, 적용 불가 항목은 분모에서 빼며, 없는 출처·지어낸 경험·설정 충돌 같은 결함은 총점과 따로 먼저 고치게 한다. 원고 채점, 장르 채점표, 퇴고 전 진단에 사용
node:
  in:
    post_path: { shape: text }
    genre: { shape: text, values: [essay, explainer, argument, review, short-story, novel, webnovel] }
    brief_path: { shape: text, list: 1, required: false }
    reviewer: { shape: text, values: [codex, claude, agy] }
  out:
    score: { shape: json }
    findings: { shape: json, list: 1, required: false }
---

# 장르별 독립 채점

## 입력

- `post_path`: UTF-8 원고 경로다. 없으면 오류로 끝낸다.
- `genre`: `essay`, `explainer`, `argument`, `review`, `short-story`, `novel`, `webnovel` 중 주 장르다. 혼합 글은 결론에 맞는 주 장르를 고르고 보조 장르 항목은 별도 진단으로 둔다.
- `brief_path`: 선택 입력인 원소 0~1개 배열이다. 독자·창작 의도·자료와 확인 범위가 있으면 전달하라. 의도에 맞는 이탈을 자동 감점하지 마라.
- `reviewer`: `codex`, `claude`, `agy` 중 글쓴 모델과 다른 회사 모델을 고른다. CLI 이름만 보지 말고 실제 모델 제공 회사를 확인하라. 다른 회사 모델이나 `recipe:oneshot`이 없으면 독립 채점 불가로 보고하고 자기 채점으로 대체하지 마라.

## 실행

1. 원고가 있는 프로젝트의 `.tmp/` 아래 실행마다 고유 디렉터리를 만들고 `prompt.txt`, `auto.json`, `stdout.txt`, `stderr.txt`, `result.json`을 둬라. 프롬프트는 BOM 없는 UTF-8로 써라.
2. 채점 전에 `python <이 스킬>/scripts/auto_checks.py <post_path> --sequence-limit 3`을 실행해 JSON을 `auto.json`에 보관하라. `--sequence-limit`은 같은 종결 형태 연속 후보의 기준이며 점수 기준이 아니다. 검사 실패를 ‘이상 없음’으로 처리하지 마라.
3. `references/rubric-<genre>.md` 본문 전체, 원고 전체, brief와 필요한 자료, 기계 검사 JSON을 아래 프롬프트에 붙여라. 외부 채점자는 글쓴 세션의 결론이나 이미 찾은 문제를 공유받지 않는다.
4. 설치된 `recipe:oneshot`을 읽고 래퍼를 실행하라. 예: `bash <oneshot>/references/oneshot.sh --mode read --prompt-file <실행 디렉터리>/prompt.txt <reviewer>`. 원고 프로젝트에서 실행하고 stdout·stderr를 분리해 보관하라. 모델·effort는 CLI 기본값을 쓴다. 종료 코드 0 또는 3은 stdout 검증으로 진행하고 그 밖은 실행 실패로 처리하라.
5. stdout에서 JSON 객체를 추출해 아래 형식·항목 누락·중복·점수 범위·인용 실재·분모·합계를 검증하라. 점수는 외부 채점자의 것을 유지하고 합산만 호출자가 다시 계산하라.
6. 실행 또는 형식 검증 실패면 오류 목록만 프롬프트 끝에 추가해 전체 채점을 한 번 다시 요청하라. 두 번째도 실패하면 `total: null`과 실패 원인·로그 경로를 반환하라. 성공한 점수를 임의로 만들지 마라. 실패 로그는 남기고 성공 시 필요한 결과를 반환한 뒤 실행 디렉터리만 정리하라.

`agy`는 프롬프트 첫 줄에 ‘셸 명령 도구를 쓰지 마라. 파일 보기 도구와 아래 원문만 써라’를 추가하라. Windows 명령줄 길이를 넘으면 다른 회사 조건을 만족하는 채점자로 바꿔라. 원고를 잘라서 채점하지 마라.

## 프롬프트 템플릿

````text
너는 해당 장르의 시니어 편집자다. 글을 수정하지 말고 아래 원문과 기준으로 독립 채점하라.
읽을 파일은 모두 UTF-8이다. 파일 읽기가 막히면 아래 붙인 원문을 사용하라.
원고 경로: <post_path>
주 장르: <genre>
창작 의도·매체 규칙·자료와 확인 범위: <brief 및 자료, 없으면 미제공>

채점표 전체:
<references/rubric-genre.md 본문 전체>

기계 검사 JSON:
<auto.json 전체>

각 주 장르 항목을 0·1·2점으로 채점하라. 기계 검사는 후보이며 점수가 아니다.
각 항목에 실제 원문 인용, 판단 이유, 최소 수정 행동, 추가 확인 사항을 붙여라.
적용 불가는 score=null로 두고 reason에 이유를 써라. 단순 누락·자료 부족은 적용 불가가 아니다.
의도에 맞는 이탈은 자동 감점하지 마라. AI 작성 여부를 추정하지 마라.
미확인 사실을 오류로 단정하지 말고 needs_check에 남겨라.
없는 출처·인용·통계, 제공 안 된 경험 창작, 중심 사실 오류, 결론을 뒤집는 반대 증거 누락,
확정 설정 중대 충돌, 제한 시점 핵심 정보 누출, 결말 근거 부재는 blockers로 따로 보고하라.
합격선·합격 판정을 만들지 마라. JSON 객체 하나만 출력하라.
형식:
{"genre":"<genre>","items":[{"item":"<채점표 항목명>","score":0,"evidence":"<원문 문장>","reason":"<이유>","fix":"<수정 행동>","needs_check":[]}],"applicable_total":20,"total":0,"blockers":[]}
blockers의 각 항목: {"item":"<결함 종류>","evidence":"<문제 문장·자료 위치>","reason":"<충돌 근거>","fix":"<최소 수정안>","needs_check":[]}
근거 문장이 없는 누락 항목은 evidence=""로 두고 reason에 누락 범위를 적어라.
적용 불가도 items에 유지하되 분모에서는 빼라. needs_check는 문자열 배열이다.
보조 장르 진단이 필요하면 별도 auxiliary_items 배열에 같은 형식으로 쓰고 주 장르 합계에 더하지 마라.

<<<POST
<원고 파일 내용 전체>
POST>>>
````

## 채점 검증과 출력

주 장르 채점표의 10항목이 한 번씩 있어야 한다. `score`는 정수 0·1·2 또는 적용 불가의 `null`이다. `evidence` 인용이 원고에 실제로 있는지 확인하라. 인용 없는 누락 판단은 `reason`의 대상 범위로 검증하라. 알려진 자료가 없으면 경험 창작이나 출처 부재를 곧바로 확정하지 말고 추가 확인으로 남겨라.

`applicable_total = 2 × score가 null이 아닌 항목 수`, `total = 적용 항목 점수 합`이다. 모두 적용되면 20점 만점이다. 모두 적용 불가면 분모 0과 판단 불가를 명시하라. 환산해 20점으로 부풀리지 마라. 합격선은 없으며 구조·비율·점수는 검증된 표준이 아니다.

- `score`: `{genre, items, applicable_total, total, blockers}`와 reviewer·기계 검사 결과를 반환하라.
- `findings`: 1점 이하 항목과 blockers를 근거·이유·수정 행동과 함께 반환하라. blockers는 총점으로 상쇄하지 않으며 점수와 무관하게 ‘고칠 것’으로 먼저 제시하라.
- 확인 못 한 자료·정책은 `needs_check`로 남겨라. 기계 후보의 부호 짝·작업 표시·서술체 혼용·종결 반복·사물 높임은 문맥을 읽고 판정하며 자동 교체하지 마라.
