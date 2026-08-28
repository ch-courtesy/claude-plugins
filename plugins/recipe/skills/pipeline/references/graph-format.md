# graph.json 형식

정본 규칙은 pipecheck `check-graph`가 집행한다. 여기는 저작 지침이다.

## 골격

아래 골격은 형태 예시다 — 이름·배선 구성을 그대로 옮겨 쓰지 않는다(최상위 키·필드 구조는 저작 규칙대로 따른다).

```json
{
  "name": "review-and-fix",
  "in":  { "repo": { "shape": "text" } },
  "out": { "report": { "shape": "text" } },
  "nodes": [
    { "id": "scan", "kind": "node", "skill": "list-files", "const": { "pattern": "*.py" } },
    { "id": "review", "kind": "container", "rule": "items", "skill": "review-file",
      "split": ["path"], "expose": ["findings", "messages"], "const": { "focus": "security" } },
    { "id": "pick", "kind": "transform",
      "out": { "messages": { "expr": "zip(per_msg.flatten(), per_file.flatten()).filter(p, p.b.severity == 'high').map(p, p.a)" } } },
    { "id": "fix", "kind": "container", "rule": "condition", "skill": "fix-draft",
      "expose": ["draft"], "const": { "draft": "" },
      "until": "verdict == 'clean'", "max": 5, "carry": { "draft": "draft" } }
  ],
  "edges": [
    { "from": "graph.in.repo", "to": "scan.in.repo" },
    { "from": "scan.out.paths", "to": "review.in.path" },
    { "kind": "order", "from": "publish", "to": "cleanup" }
  ],
  "materials": [
    { "name": "list-files", "scope": "user", "contract": "sha256:...", "body": "sha256:..." }
  ]
}
```

## 저작 규칙

- 최상위 키는 여섯뿐 — `name`은 이름 규칙을 따르는 문자열, `in`·`out`은 포트 선언 객체, `nodes`·`edges`·`materials`는 배열. 같은 키를 두 번 적지 않는다. `in`·`out`의 각 값은 포트 선언 객체다. `materials` 항목은 네 키 — `name`은 이름 규칙을 따르는 문자열, `contract`·`body`는 문자열, `scope`는 `project`·`user`
- `kind`: `node`·`transform`·`container`. 엣지 `kind` 생략 = `data`
- 구성물(`transform`·컨테이너)은 자기 포트를 선언하지 않고 파생한다 — 컨테이너는 `split`(깊이 +1)·`expose`로, transform은 식에서. 노드는 구성물이 아니다 — 그 포트는 재료 계약 그대로다. 포트 이름 매핑은 없다 — 상류 포트 이름과 재료 포트 이름이 달라도 배선은 포트 참조로 하고, 계약 이름 자체를 바꾸고 싶으면 어댑터로 감싼다
- `split` 둘 이상이면 `combine`(zip·product·nested) 필수, 하나면 금지
- 조건 컨테이너: `until`(내부 출력만 참조, bool)·`max`(정수 1 이상) 필수, `carry`는 출력→입력(값 유일)
- data 엣지는 포트↔포트, order 엣지는 구성 요소↔구성 요소. 팬인은 깊이 1 이상 포트에만, 이어붙는 순서는 **엣지 선언 순서**, `aligned` 짝은 팬인·이중 배선 금지
- 분기는 transform 다중 출력 — 안 고른 갈래의 항목 컨테이너는 빈 배열을 받아 0회, 노드가 받으면 1회 돌아 빈 입력을 처리한다. 갈래마다 원 배열을 따로 거른다
- `nested`는 출력 축이 `split` 축과 그대로 대응(깊이 +len(split)), `product`는 한 줄로 평탄(깊이 +1 — 축 복원이 필요하면 nested). `carry`에 없는 입력 포트는 컨테이너 입력값을 유지하고, 조건 컨테이너 출력은 마지막 회차 값뿐이다(모으려면 누산 이월 — 항목 컨테이너는 회차 결과를 순서대로 모은다)
- transform 출력의 `aligned`만은 명시 선언한다 — `out.<포트>.aligned`에 자기 다른 출력 이름(§5.5의 유일한 명시 속성, 나머지는 식에서 파생)
- 상수(`const`)는 노드·컨테이너에만. 같은 포트에 상수+엣지 금지. transform에 주고 싶은 값은 식 안 리터럴
- 표현식은 CEL — transform·until 모든 표현식이 같은 규칙이다(`split`은 식이 아니라 입력 포트 이름 목록): `filter`·`map`·`exists`·`all` 매크로, `size`, `in`, 비교·논리·산술, 삼항(`c ? a : b`), 필드·인덱스 접근, 리스트·맵 리터럴, 그리고 호스트 함수 `zip(a,b)`(원소는 `{'a': a[i], 'b': b[i]}` 두 키 맵 — 두 길이가 다르면 오류)·`chunk(xs,n)`(마지막 묶음은 짧을 수 있다)·`first_or(xs,d)`와 메서드 `xs.flatten()`·`xs.join(sep)`만. 형변환·시간·문자열 함수 없음. bytes 리터럴·비문자열 키 맵 금지. 포트로 나가는 추론 결과 타입은 text·num·bool·json — int·uint·null_type 타입의 결과는 불가하고 수 리터럴은 `1.0`처럼 double로 쓴다(json 값 안의 중첩 정수·null은 무방)
- 모든 경계 입력은 data 엣지로 소비돼야 하고, 모든 구성 요소는 경계 출력에 기여하거나 order로 이어져야 한다 — 구성 요소가 하나뿐이면 경계 출력 기여·order 요건만 면제되고 경계 입력 소비 요건은 그대로다
- 자기 자신을 재료로 쓰지 못한다(전이 닫힘 포함)
- 안 쓰는 재료를 등재하지 않는다. `materials`의 해시는 `pipecheck hash`로 얻은 현재 값
