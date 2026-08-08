# 유틸 노드 시맨틱 (v1: 5종)

유틸 노드는 `util:` 필드로 선언하며 별도 타입 파일이 없다. 공통 속성(retry/timeout/on_error)은 동일하게 적용된다(단 human-gate에는 retry 무의미).

## if / switch — 분기

```yaml
- id: check
  util: if
  in: {count: $fetch.total}
  cond: '.count > 0'          # jq boolean 식, in으로 매핑된 객체에 적용
  then: [each, combine]       # 참일 때만 실행할 노드 id
  else: [notify-empty]        # 거짓일 때 (생략 가능)
```

```yaml
- id: route
  util: switch
  in: {level: $triage.severity}
  cases:
    - {when: '.level == "critical"', run: [page-oncall]}
    - {when: '.level == "warning"', run: [file-issue]}
  default: [log-only]         # 생략 가능
```

- 선택되지 않은 가지의 노드는 `skipped`로 기록하고 실행하지 않는다. 스킵된 노드의 출력을 참조하는 하류 노드도 연쇄 스킵된다.
- `then`/`run`에 나열되는 id는 같은 파이프라인의 노드여야 하며, 두 가지 이상에 겹쳐 나열할 수 없다.
- switch의 cases는 위에서부터 첫 매치 하나만 실행한다.

## foreach — 배열 순회 (map)

```yaml
- id: each
  util: foreach
  items: $fetch.issues        # 배열 참조
  skill: summarize            # 항목마다 실행할 typed 스킬 (또는 inline: 정의)
  in: {text: $item.body}      # $item = 현재 항목
  outputs: → results          # 고정: {results: array} — 항목별 출력 객체의 배열, 입력 순서 보존
```

- v1은 노드 **하나**를 map한다. 여러 단계를 순회하려면 그 단계들을 파이프라인으로 묶어 컴파일한 뒤 그 `kind: pipeline` 스킬을 `skill:`로 참조한다.
- 항목 하나가 실패하면 노드의 on_error를 따른다: `fail`이면 전체 중단, `continue`면 해당 항목 결과를 `{error: ...}`로 기록하고 계속.
- 항목 실행 기록은 `runs/<run-id>/<노드id>/<인덱스>.json`에 남긴다.

## merge — 팬인 합류

```yaml
- id: merged
  util: merge
  in: {issues: $fetch.issues, notes: $collect.notes}
```

- 여러 상류의 출력을 기다렸다가 `in`의 키를 그대로 가진 객체 하나를 출력한다 (`outputs` = in과 동일 키).
- 상류 중 skipped가 있으면 해당 키를 null로 채운다. 재성형이 필요하면 merge 대신 transform을 쓴다.

## transform — 데이터 재성형

```yaml
- id: combine
  util: transform
  in: {items: $each.results}
  expr: '{summaries: [.items[].summary]}'   # jq 식
```

- `in`으로 매핑된 객체에 `expr`(jq)를 적용한 결과가 출력 객체다. 결과는 JSON 객체여야 한다.
- 실행은 결정적이어야 한다 — expr 안에서 외부 상태(now, env)를 쓰지 않는다.

## human-gate — 사용자 승인 대기

```yaml
- id: gate
  util: human-gate
  message: "{{count}}건 발행할까요?"   # $참조 대신 in으로 받은 값을 {{}}로 치환
  in: {count: $combine.total}
  options: [발행, 보류]               # 생략 시 승인/거부
  outputs: → {choice: string}
```

- 현재 런타임의 구조화된 사용자 질문 기능(없으면 간결한 직접 질문)으로 message와 options를 제시한다. `{{}}` 치환 값은 스칼라만 — 배열·객체는 transform으로 스칼라화(건수 등) 후 매핑한다.
- 첫 번째 옵션(또는 승인) 외 선택 시: 파이프라인을 `aborted`로 중단하되 상태를 보존한다 — `resume <run-id>`로 게이트부터 재개 가능.
- 하류에서 `$gate.choice`로 선택값을 쓸 수 있다.
