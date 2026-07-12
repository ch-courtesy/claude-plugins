---
name: blocker-secret
description: 규칙 검사기 blocker-secret 픽스처 — 본문에 평문 시크릿이 있어 SEC-SECRET이 FAIL해야 할 때 사용한다.
allowed-tools:
  - Read
---

# blocker-secret

이 픽스처는 본문에 하드코딩된 시크릿을 포함한다.

```
api_key = "abcd1234efgh5678ijkl"
```

이 평문 시크릿 때문에 SEC-SECRET BLOCKER가 발생하고 등급이 F가 되어야 한다.
