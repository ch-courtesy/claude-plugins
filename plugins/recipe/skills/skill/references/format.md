# 산출물 형식

스킬 하나 = 디렉터리 하나. `<이름>/SKILL.md`(어댑터·일반 스킬), 워크플로는 `graph.json`이 함께 있다. `graph.json`은 /pipeline이 만든다 — 이 스킬에서 만들지 않는다.

## 이름 규칙

스킬 이름은 한 글자 이상, 소문자·숫자·밑줄·하이픈만, 숫자로 시작하지 않고, 255자 이하. 설치 경로가 이름에서 나온다.

## 프론트매터

키는 `name`·`description`·`node`·`wraps`(어댑터만) 넷뿐이다. 같은 키를 두 번 적지 않는다.

```markdown
---
name: review-file
description: 파일 하나를 리뷰하고 발견 사항을 낸다
node:
  in:
    path:  { shape: text }
    focus: { shape: text }
  out:
    findings: { shape: json, list: 1, required: false }
    messages: { shape: text, list: 1, required: false, aligned: findings }
    verdict:  { shape: text, values: [clean, needs_fix] }
---

## 입력
- `path` — 이 파일을 읽어 리뷰 대상으로 삼는다
- `focus` — 리뷰 관점. 배선하는 쪽이 상수나 상류 값으로 반드시 준다

## 실행
`path`가 가리키는 파일이 없으면 오류로 끝낸다 — 경로 실재 확인은 그 값을 쓰는 이 노드의 몫이다.
(그 밖은 구체적 절차. CLI면 명령과 인자를, API면 엔드포인트를,
 MCP 도구면 도구 이름과 파라미터를 명시한다.)

## 출력
- `findings` — 발견 사항 배열. 각 항목은 severity·line·message를 갖는다
- `messages` — 각 발견 사항의 message만 뽑은 배열. `findings`와 같은 순서다
- `verdict` — `clean` 또는 `needs_fix`
```

## 계약(`node:`) 규칙

- `node:`의 키는 `in`·`out` 둘뿐. 포트 객체의 필드는 `shape`·`list`·`required`·`values`·`aligned`뿐
- `shape`: `text`·`num`·`bool`·`json` 4종. `list`: 0 이상 정수(기본 0). `required`: 불리언(기본 true)
- 포트 이름: 한 글자 이상, 소문자·숫자·밑줄만, 숫자로 시작하지 않음
- `required: false`와 `aligned`는 깊이(`list`) 1 이상 포트에만
- `values`는 `shape: text` 포트에만 — 원소 하나 이상, 비어 있지 않은 서로 다른 문자열
- `aligned`는 같은 방향의 실재 포트를 가리키고 순환하지 않는다. 짝은 `required`·깊이가 같다
- 출력 포트 0개는 적법하다 — 그런 노드는 순서 엣지로만 연결된다

## 본문 세 절 규칙

표제는 `## 입력`·`## 실행`·`## 출력` 그대로, 이 순서로, 다른 `## ` 절 없이. 절 경계 판정은 원시 `## ` 시작 줄이다 — 코드 펜스 안이라도 `## `로 시작하는 줄을 본문에 두지 않는다.

입력·출력 절은 계약의 포트를 **전부** `- `이름` — 설명` 항목으로 나열한다. 계약에 없는 포트를 나열하지 않고, 설명을 비워 두지 않는다.

## 어댑터 프론트매터

```yaml
wraps: { name: review-file, scope: project, contract: "sha256:...", body: "sha256:..." }
```

`contract`·`body`는 원본의 현재 해시(`pipecheck hash`)를 적는다.
