# validate 체크리스트

compile 1단계에서 전 항목을 적용한다. 하나라도 실패하면 산출물을 만들지 않고, 위반마다 `노드 id · 항목 · 수정 방법`을 보고한다.

## 1. 구조

- [ ] 최상위 필수 필드 존재: name, description, inputs, nodes
- [ ] 모든 노드에 `id`가 있고 파이프라인 내 유일
- [ ] 각 노드는 `skill` / `util` / `inline` 중 정확히 하나 — 단 유틸 노드의 설정 필드(foreach의 `skill:`·`items:`, transform의 `expr:` 등)는 판별자가 아니다: `util:`이 있으면 유틸 노드다
- [ ] `skill` 참조가 `.agents/skills/<이름>/SKILL.md`로 실재하고, frontmatter가 typed 계약(kind/inputs/outputs — `kind: pipeline`이 아니면 run도)을 만족
- [ ] `inline` 정의가 typed 계약의 kind/inputs/outputs/run을 갖춤 (`kind: pipeline` 인라인 금지)
- [ ] `util`이 7개 값(if, switch, foreach, while, merge, transform, human-gate) 중 하나이고 해당 유틸의 필수 필드를 갖춤 — if: cond/then · switch: cases · foreach: items + (skill 또는 inline) · while: (skill 또는 inline) + until + max_iterations · transform: expr · human-gate: message
- [ ] while의 `max_iterations`가 양의 정수(1 이상), `until`이 jq boolean 식이고 결정적(now·env 미사용). 상한이 100을 넘으면 경고하고 사용자 확인 — 반복 대상이 외부 프로세스면 그 횟수만큼 실행된다
- [ ] while의 `until`이 참조하는 최상위 필드가 반복 대상 노드의 `outputs` 계약에 실재 (오타 하나면 조건이 영영 거짓이 되어 상한까지 조용히 반복한다 — 2장의 `$id.last.<필드>` 검사와 같은 규칙)

## 2. 참조 무결성

- [ ] 모든 `$참조`가 해석 가능: `$pipeline.<입력>`은 inputs에, `$<노드id>.<출력>`은 그 노드의 outputs에 실재 (최상위 `outputs:` 매핑의 참조 포함). 유틸 노드의 출력 필드: foreach=`results`, while=`iterations`·`last`(`last` 하위는 반복 대상 노드의 outputs 계약으로 검사 — `$id.last.<필드>` 2단계 참조를 허용하고 그 필드 타입으로 일치를 본다), merge=`in`의 키, transform=`expr` 결과 객체의 최상위 키(정적 파싱), human-gate=`choice`
- [ ] `$item`은 foreach의 `in:` 안에서만 사용 (while은 회차 간 값 이월이 없어 자기 참조를 쓰지 않는다)
- [ ] `needs:`의 노드 id가 실재
- [ ] if/switch의 `then/else/run/default`에 나열된 id가 실재하고, 두 가지 이상에 중복되지 않음

## 3. 입력 충족과 타입

- [ ] 각 노드 인스턴스의 `in:`이 계약의 required 입력을 전부 매핑 (default 있는 필드는 생략 가능)
- [ ] `in:`에 계약의 inputs에 없는 필드가 없음
- [ ] 참조 연결의 타입 일치: `$a.x → b.in.y`에서 a.outputs.x.type == b.inputs.y.type (object↔array 혼용 금지, 리터럴은 값의 JSON 타입으로 판정)
- [ ] foreach의 `items:` 참조가 array 타입

## 4. 그래프

- [ ] 순환 없음 (참조 + needs로 만든 방향 그래프 기준 — `skill:`로 참조된 컴파일 파이프라인이 자기 자신을 다시 참조하는 자기 포함도 순환)
- [ ] 어디에서도 참조되지 않고 아무것도 참조하지 않는 고아 노드 없음 (경고 — 의도면 통과 가능하나 사용자 확인)
- [ ] 분기(then/else/cases) 밖의 노드가 스킵될 수 있는 노드의 출력을 무조건 참조하지 않음 — 참조하려면 그 노드도 같은 가지에 있거나 merge로 null 허용 합류

## 5. 실행 안전

- [ ] script/http 노드의 command·url에 미해석 `{{}}` 잔여 없음 (inputs에 선언 안 된 치환자)
- [ ] on_error 값이 fail | continue, retry가 0 이상 정수
- [ ] 시크릿 값이 정의에 하드코딩되지 않음 (Authorization 등은 입력 주입 권장 — 위반 시 경고)
- [ ] human-gate `message`의 `{{}}` 치환에 매핑되는 값이 스칼라(string/number/boolean) — 배열·객체 참조면 경고하고 transform으로 스칼라화 권고 (예: 건수는 `{count: [...] | length}` 경유)
