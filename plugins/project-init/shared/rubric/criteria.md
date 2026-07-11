# 스킬 품질 루브릭 30항목 (단일 출처)

토스 기술블로그 '스킬 품질 루브릭' 6개 섹션 30개 항목을 verbatim으로 따른다.
`create-skill`(작성 단계 자가점검)과 `repair-skill`(기존 스킬 평가·수정)이 모두 이 문서를
단일 출처로 참조한다 — 각자 사본을 두지 않는다.

검사는 둘로 나뉜다:
- **규칙 17항목** — 정규식·카운트·syntax로 결정적으로 판정한다. `rule_checker.py`로
  검사한다 — `repair-skill`은 평가 단계에서, `create-skill`은 파일 작성 후 규칙 검사
  단계에서 실행한다.
- **모델 13항목** — 의미적 판정이라 에이전트가 이 문서 기준으로 직접 판정한다.

## 등급 기준

| 조건 | 등급 |
|------|------|
| BLOCKER ≥ 1 | F |
| BLOCKER 0, MAJOR 0 | S |
| BLOCKER 0, MAJOR 1–2 | A |
| BLOCKER 0, MAJOR 3–4 | B |
| BLOCKER 0, MAJOR 5+ | C |

MINOR 개수는 등급을 가르지 않으나 개선 대상이다.

---

## 1. 규칙 항목 (17)

규칙 항목은 정규식·카운트·syntax 검사로 결정적으로 판정한다.

### 1-1. 구조 (8항목)

- [ ] **S-YAML** `BLOCKER` — YAML frontmatter 파싱 가능
  첫 줄 `---` / 닫는 `---` / 유효한 YAML 구문.

- [ ] **S-NAME-FORMAT** `BLOCKER` — name이 kebab-case이고 64자 이하
  정규식 `^[a-z][a-z0-9]*(-[a-z0-9]+)*$` 충족.

- [ ] **S-NAME-FOLDER** `BLOCKER` — name과 폴더명 일치
  `name: foo-bar`이면 폴더 이름도 `foo-bar`.

- [ ] **S-DESC-LEN** `BLOCKER` — description이 1자 이상 1024자 이하
  description 키 자체가 없거나 빈 문자열이면 FAIL.

- [ ] **S-NO-XML** `BLOCKER` — 본문에 대문자 XML 태그 없음
  `<SOMETHING>`, `</SOMETHING>` 등 대문자로 시작하는 XML 류 태그 금지.
  소문자 HTML(`<br>`, `<code>` 등)은 허용.

- [ ] **S-ALLOWED-KEYS** `MAJOR` — frontmatter에 허용 키만 사용
  허용 키: `name`, `description`, `allowed-tools`, `argument-hint`.
  그 외 키가 있으면 FAIL.

- [ ] **S-RESERVED** `MAJOR` — name에 예약어(`claude`/`anthropic`) 없음
  대소문자 무관 검사.

- [ ] **S-README** `MINOR` — 같은 폴더에 `README.md` 존재

### 1-2. 트리거 (2항목)

- [ ] **T-BODY-ONLY** `BLOCKER` — Body-only 안티패턴 없음
  시점 정보(언제 쓰는가)가 description에도 있어야 한다.
  본문에만 있고 description에 없으면 FAIL.
  판정 키워드: `use`, `when`, `whenever`, `before`, `after`, `during`, `trigger`,
  `사용`, `활성화`, `요청`, `할 때`, `때`, `시작` 등.

- [ ] **T-ARG-HINT** `MINOR` — `$ARGUMENTS` 사용 시 `argument-hint` 키 존재
  본문에 `$ARGUMENTS` 또는 `{{ args }}`가 없으면 자동 통과.

### 1-3. 콘텐츠 (1항목)

- [ ] **C-LENGTH** `MINOR` — 본문 500줄 이하
  frontmatter를 제외한 본문 기준.

### 1-4. 리소스 (4항목)

- [ ] **R-TOC** `MINOR` — 100줄 이상 `references/` 문서에 목차(H1~H3 헤더 3개+) 존재

- [ ] **R-SYNTAX** `MAJOR` — `references/`의 `.py`·`.sh` 스크립트 syntax 유효
  스크립트가 없으면 자동 통과.

- [ ] **R-SCRIPTPATH** `MINOR` — 스크립트 경로가 본문에 명시됨
  스크립트가 없으면 자동 통과.

- [ ] **R-PLACEHOLDER** `MINOR` — 본문에 `[TODO]`, `[PLACEHOLDER]`, `FIXME`, `{{ ... }}` 잔재 없음

### 1-5. 안전성 (2항목)

- [ ] **SEC-SECRET** `BLOCKER` — 본문·스크립트에 평문 secret 없음
  `password=`, `api_key=`, `token=` 뒤에 8자 이상 평문 값이 오면 FAIL.

- [ ] **SEC-DESTRUCTIVE** `BLOCKER` — allowed-tools에 파괴적 도구 없음
  `rm -rf`, `git push --force`, `DROP TABLE`, `mkfs`, `dd if=` 등 금지.

---

## 2. 모델 항목 (13)

모델 항목은 에이전트가 의미적으로 판정한다. 확신이 없으면 보수적으로 FAIL.

### 2-1. 타당성 (3항목)

- [ ] **V-REPEAT** `MAJOR` — 반복되는 워크플로우인가
  PASS: 여러 번·여러 상황에서 다시 쓰일 절차(예: "PR 리뷰", "SPEC 작성").
  FAIL: 일회성 작업이거나 한 번 쓰고 버릴 내용.

- [ ] **V-GENERIC** `MAJOR` — 범용성 (특정 프로젝트 한정이 아님)
  PASS: 다른 저장소·맥락에도 적용 가능한 일반 절차.
  FAIL: 이 저장소의 특정 파일 경로·내부 사정에만 묶여 재사용 불가.

- [ ] **V-IRREPLACEABLE** `MAJOR` — 대체 불가능성
  PASS: 에이전트 기본 능력만으로 일관되게 수행하기 어려운 고유 절차·지식을 더한다.
  FAIL: "코드를 읽어라", "테스트를 실행하라" 수준의 기본 능력 재기술.

### 2-2. 트리거 (4항목)

- [ ] **T-WHATWHEN** `MAJOR` — description에 WHAT + WHEN 모두 포함
  PASS: "무엇을 하는가(WHAT)"와 "언제 쓰는가(WHEN)"가 모두 있다.
  FAIL: 기능 설명만 있고 호출 시점이 없거나, 반대로 시점만 있고 기능이 모호.

- [ ] **T-KEYWORDS** `MAJOR` — 트리거 키워드 충분
  PASS: 사용자가 실제로 쓸 법한 표현·동의어가 description에 충분히 담겨 매칭이 잘 된다.
  FAIL: 키워드가 빈약해 관련 요청에도 호출이 안 잡힐 위험.

- [ ] **T-SEMANTIC** `MAJOR` — description과 본문 의미 일치
  PASS: description이 약속한 동작과 본문이 실제로 시키는 동작이 일치.
  FAIL: description은 A를 한다는데 본문은 B를 시킨다(과장·불일치).

- [ ] **T-SCOPE** `MAJOR` — 트리거 범위가 과도하지 않음
  PASS: 적절히 좁아 무관한 요청까지 빨아들이지 않는다.
  FAIL: "어떤 작업이든", "항상" 류로 과도하게 넓어 오발동 위험.
  (진입점 성격의 라우팅 스킬은 의도적으로 넓을 수 있으니 맥락을 본다.)

### 2-3. 콘텐츠 (2항목)

- [ ] **C-SPECIFIC** `MINOR` — 구체성
  PASS: 수치·코드·임계값·"왜(Why)"·구체 시나리오가 있다.
  FAIL: "Redis는 인메모리 DB입니다" 같은 일반론·교과서 서술.

- [ ] **C-ORG** `MAJOR` — 조직 고유성
  PASS: 일반 상식이 아니라 이 조직·프로젝트의 내부 운영 규칙·관례·결정을 담는다.
  FAIL: 어디서나 찾을 수 있는 일반 베스트프랙티스만 나열.

### 2-4. 리소스 (4항목)

- [ ] **R-SPLIT** `MAJOR` — 본문/참고 분리
  PASS: 핵심 절차는 SKILL.md 본문에, 상세·레퍼런스는 `references/`에 분리.
  FAIL: 모든 상세를 본문에 욱여넣어 본문이 비대하거나, 반대로 본문이 비고 전부 참고로 빠짐.

- [ ] **R-LINKWHEN** `MINOR` — references 읽는 시점 명시
  PASS: "X를 할 때 `references/y.md`를 읽어라"처럼 언제 읽는지 본문이 지시.
  FAIL: references 파일은 있는데 언제 읽어야 하는지 본문이 말하지 않음.

- [ ] **R-NESTED** `MAJOR` — 중첩 참조 없음
  PASS: 참조 깊이가 얕다 (본문 → references 1단계).
  FAIL: A가 B를 읽으라 하고 B가 다시 C를 읽으라 하는 A→B→C 연쇄.

- [ ] **R-SCRIPTIFY** `MAJOR` — 실수 가능한 작업의 스크립트화
  PASS: 손으로 하면 틀리기 쉬운 결정적 작업(파싱·계산·정해진 명령열)은
  `references/` 스크립트로 고정. 결정적 작업이 없으면 자동 통과.
  FAIL: 매번 에이전트가 즉흥으로 재현해야 하는, 틀리기 쉬운 절차를 산문으로만 남김.
