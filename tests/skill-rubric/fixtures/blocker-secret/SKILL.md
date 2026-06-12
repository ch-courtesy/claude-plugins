---
name: blocker-secret
description: "본문에 평문 시크릿을 넣어 SEC-SECRET BLOCKER를 유발하는 픽스처 — 검사기가 하드코딩된 비밀을 잡는지 확인할 때 사용한다."
allowed-tools:
  - Read
---

# blocker-secret

이 픽스처는 본문에 하드코딩된 시크릿을 포함한다.

```
api_key = "abcd1234efgh5678ijkl"
```

이 평문 시크릿 때문에 SEC-SECRET BLOCKER가 발생하고 등급이 F가 되어야 한다.
