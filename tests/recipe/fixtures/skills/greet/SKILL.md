---
name: greet
description: "이름을 받아 인사말을 만들 때 사용."
kind: script
inputs:
  name: {type: string, required: true}
outputs:
  greeting: {type: string}
run:
  command: "jq -c '{greeting: (\"hello, \" + .name)}'"
  input: stdin-json
  output: stdout-json
---

# greet

결정적 script typed 스킬 표준 픽스처 — skill test·E2E 스모크용.

## 실행

1. inputs 스키마대로 `name`을 수집한다.
2. 입력 JSON을 stdin으로 `jq -c '{greeting: ("hello, " + .name)}'`에 전달한다.
3. stdout JSON을 outputs 스키마(`{"greeting": "..."}`)와 대조해 보고한다.
