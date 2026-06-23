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
재사용하는 통합/리뷰/머지 엔진(`integration.sh`/`review-loop.sh`/`merge.sh`) 계약을 그대로 표면화한다.

| 동사 | 인자 | 내부 위임(github / direct) |
|---|---|---|
| `integrate` | `<spec> <run_dir> <key>` | `integration.sh integrate` / `integrate-direct` |
| `review` | `<run_dir> <key> <spec> [pr] [branch]` | `review-loop.sh round` / `run-direct` |
| `merge` | `<spec> <run_dir> <key> [pr]` | `merge.sh finish <...> [pr]` / `finish <...> "" 1` |

관리 동사: `host`(감지된 호스트 출력), `selftest`(라우팅 검증).

`merge` 통합 방식은 **백엔드 가용 여부로 갈린다**(`merge.sh finish` 내부 라우팅):
- **github/gitlab(백엔드 가용, PR/MR 존재)** → 호스트의 **PR 기반 서버사이드 머지**로만 통합한다.
  로컬 `git checkout <base>`+ff+push 를 **타지 않는다**(백엔드 가용 시 로컬 머지 금지). 따라서 기본
  브랜치가 다른 워크트리에 점유돼도 `already checked out` 으로 실패하지 않는다.
- **direct(origin/백엔드 미가용)** → PR 없이 로컬 `ff-only`(checkout+ff+push) 직접 머지.

두 경로 공통: PR 존재(forge)·승인(`reviewDecision==APPROVED` + 현재 head 미해결 `[blocking]` 0)·버전
범프 게이트를 머지 **전에** 적용하고, 직렬화 락·force 미사용을 유지한다. 서버사이드 머지 실패는 조용한
성공으로 보고하지 않고 `blocked` 로 종착한다.

`review`(github)는 `round`(=`rl_round`)를 호출해 반환코드(`0`=재작업 재푸시·`10`=에스컬레이션/라운드상한/핑퐁·
`20`=대기·`30`=approve)를 **그대로 표면화**한다. 단일 동기 드라이버(execute-task)가 이 코드로 리워크 진행/빠른
실패/승인 폴링을 분기하기 위함이다(`run` 은 코드를 `0` 으로 collapse 해 분기 불가). direct 는 PR 메타가 없어
기존 `run-direct`(동기 단발 리뷰)를 유지한다.

## 런타임 재사용

github/direct 구현은 통합/리뷰/머지 엔진(`<plugin>/forge/lib/`)을 **감싸 호출**한다(복제
금지, 엔진 .sh 는 그대로 둠). gitlab 구현은 v1 미구현 — 호출 시 명확한 안내 후 비-0 exit(조용한 실패 금지).
