# forge 어댑터 계약 (플러그인 자체 단일 출처)

execute-task 의 review→머지 단계가 **origin 호스트**에 따라 PR/MR/로컬 리뷰를 고르도록 하는 어댑터다.
판정 기준은 forge CLI 가용성이 아니라 **`git remote get-url origin`** 결과다. **이 문서가 플러그인 자체 단일
출처**다 — `rules/` 지침이나 다른 스킬을 참조하지 않는다.

## origin 판정 규칙

```
origin url 없음            → direct  (로컬 review + ff-only 직접 머지)
*github.com*              → github  (PR, gh)
*gitlab*                 → gitlab  (MR, glab — v1 미구현 확장점)
그 외 호스트              → direct  (안전 폴백)
```

## 동사 (3개)

각 동사는 origin 호스트별 구현(`github.sh`/`gitlab.sh`/`direct.sh`)으로 라우팅된다. 출력·반환코드는 내부에서
재사용하는 dispatch 워커 헬퍼(`integration.sh`/`review-loop.sh`/`merge.sh`) 계약을 그대로 표면화한다.

| 동사 | 인자 | 내부 위임(github / direct) |
|---|---|---|
| `integrate` | `<spec> <run_dir> <key>` | `integration.sh integrate` / `integrate-direct` |
| `review` | `<run_dir> <key> <spec> [pr] [branch]` | `review-loop.sh run` / `run-direct` |
| `merge` | `<spec> <run_dir> <key> [pr]` | `merge.sh finish <...> [pr]` / `finish <...> "" 1` |

관리 동사: `host`(감지된 호스트 출력), `selftest`(라우팅 검증).

## 런타임 재사용

github/direct 구현은 기존 dispatch 워커 헬퍼(`<plugin>/skills/dispatch/references/`)를 **감싸 호출**한다(복제
금지, 엔진 .sh 는 그대로 둠). gitlab 구현은 v1 미구현 — 호출 시 명확한 안내 후 비-0 exit(조용한 실패 금지).
