---
name: major-unknown-key
description: "frontmatter에 허용되지 않은 키를 넣어 S-ALLOWED-KEYS MAJOR를 유발하는 픽스처 — 검사기가 허용 외 키를 잡는지 확인할 때 사용한다."
allowed-tools:
  - Read
tags: not-an-allowed-key
---

# major-unknown-key

이 픽스처의 frontmatter에는 허용되지 않은 `tags` 키가 있다. BLOCKER는 없고
S-ALLOWED-KEYS MAJOR 하나만 발생하므로 등급은 A가 되어야 한다.
