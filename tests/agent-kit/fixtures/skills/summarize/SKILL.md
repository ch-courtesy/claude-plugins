---
name: summarize
description: "텍스트를 지정 단어 수 이내로 요약할 때 사용."
kind: llm
inputs:
  text: {type: string, required: true}
  max_words: {type: number, default: 100}
outputs:
  summary: {type: string}
run:
  prompt: |
    다음 텍스트를 {{max_words}} 단어 이내로 요약하고
    {"summary": "..."} 형태의 JSON만 출력하라: {{text}}
---

# summarize

llm typed 스킬 표준 픽스처.

## 실행

1. inputs 스키마대로 `text`(필수), `max_words`(기본 100)를 수집한다.
2. run.prompt에 입력을 치환해 수행한다.
3. outputs 스키마를 만족하는 JSON(`{"summary": "..."}`)으로 결과를 보고한다.
