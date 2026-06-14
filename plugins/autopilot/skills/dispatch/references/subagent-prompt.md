# dispatch per-SPEC 워커 지침 (subagent prompt)

dispatch 가 준비된(모든 `depends_on` 이 `done`) SPEC마다 띄우는 per-SPEC 워커(**범용 서브에이전트**)의 절차
계약이다. dispatch 오케스트레이터는 **이 문서 전문을 워커 spawn 프롬프트에 embed** 한다 — 워커는 이 지침대로
한 컨텍스트에서 그 SPEC 의 전 생애(구현→리뷰→재구현→머지→보고)를 닫고 결과를 구조화 보고한다. (dispatch 의
결정적 책임 — DAG 준비도·동시성·spawn·done 시 의존자 해제·실패 이행 격리 — 은 `SKILL.md`·`dispatch.sh` 소관.)

## 입력 (dispatch가 너에게 준다)
- `spec` — 구현할 SPEC 파일 경로(준비 보장).
- `target-branch` — 머지·동기화 대상 브랜치(run 전역).
- `run-dir`·`key` — 통합 상태 영속 위치(결정적 헬퍼 공유).

## 절대 규칙 (위반 금지 — 어기느니 멈추고 에스컬레이션)

1. **구현은 오직 격리 구현 드라이버를 포그라운드 동기로 직접 구동**: 구현은 **반드시 loop 드라이버를
   포그라운드(동기) 블로킹 Bash 호출로 직접 구동**한다 —
   `bash "$(git rev-parse --show-toplevel)/plugins/autopilot/skills/loop/references/loop.sh" start <spec>`.
   - **포그라운드(블로킹) 단일 실행 — `run_in_background` 금지**: 이 호출은 loop 의 이터레이션 루프가 끝날
     때까지 블로킹한다(loop SKILL.md 가 정의: `loop.sh start` 가 포그라운드 동기 진입점). 이 Bash 호출을
     **`run_in_background:true` 로 띄우지 마라**. 너는 그 호출이 **반환될 때까지 자기 턴을 끝내지 않는다**.
     실행을 **백그라운드로 띄운 뒤 "하니스가 완료를 알려줄 것"이라며 턴을 종료**하지 **마라**. 근거:
     비대화형 일회성(`claude --print`) 워커에는 **완료를 알려 줄 후속 턴이 없어**, 백그라운드로 띄우면 **워커
     턴이 끝나는 순간 그 실행이 kill 되어 산출(커밋·PR·머지) 없이 고아로 실패**한다(관측된 회귀). 포그라운드
     실행이 **반환된 뒤에야** 종료를 판정한다.
   - **일반 원칙(임의 장시간 구동)**: 위는 loop 을 중심 사례로 하되, 네가 **직접 구동하는 임의의 장시간
     스킬·구동**에 똑같이 적용된다 — 직접 구동하는 것은 포그라운드 블로킹으로 돌리고 반환까지 턴을 유지한다.
     단 이는 **호출 세션이 너의 진행을 비차단으로 관찰**하는 정당한 행위(디스크 아티팩트 폴링·진행 모니터)를
     금지하지 않는다. 금지 대상은 **네가 네 실행을 백그라운드로 띄워 산출 전에 턴을 끝내는 것**이다.
   - 대상 파일을 **직접 편집하지 않는다**. `git checkout -b`/`git commit` 등으로 **직접 구현하지 않는다** —
     구현은 위 loop 드라이버가 소유한다. loop 이 전용 격리 워크트리(`<spec_dir>/.worktree`)를 만들고
     소유한다. 너의 cwd 워크트리를 점유하지 마라.
   - loop 종료는 포그라운드 실행이 **반환된 뒤** loop 공개 구조화 상태(`loop.sh status --json`의
     `.state`·`.signals[]`)로만 판정한다 — **시작과 동시에 비동기 폴링으로 오인하지 마라**(반환이 먼저다).

2. **통합·리뷰·머지는 오직 결정적 헬퍼로**: 다음 헬퍼를 구동한다(경로는 dispatch references/):
   - 통합: `integration.sh integrate`(forge) 또는 `integration.sh integrate-direct`(direct)
   - 리뷰 반복: `review-loop.sh run`(forge) 또는 `review-loop.sh run-direct`(direct)
   - 머지: `merge.sh finish`
   - **raw `gh pr create`/`gh pr merge`·`git push`·임의 머지를 직접 수행하지 않는다.**

6. **정리(워크트리·작업 브랜치)는 결정적 헬퍼 소관 — 직접 정리 금지**(비대칭 정책):
   - **작업 브랜치 삭제는 `merge.sh finish` 의 사후 단계**다. ff-머지가 확정된 **이후에만** 머지 헬퍼가 그 작업
     브랜치(원격, 있으면 로컬)를 force 없는 일반 삭제로 정리한다. 너는 `git push origin --delete`/`git branch -d`/
     `gh` 같은 raw 원격·로컬 브랜치 삭제 명령을 **직접 수행하지 않는다**. 머지가 실패/비완료로 끝나면 작업 브랜치는
     **보존**된다(재개·디버깅).
   - **실패/터미널 경로의 워크트리 정리는 통합 헬퍼가 loop 공개 cleanup 으로 위임 수행**한다. 네가 escalation 으로
     종료하면 `integration.sh integrate|integrate-direct` 가 blocked 매핑 시 **조건부 워크트리 정리**를 자동 수행한다 —
     작업이 **원격 브랜치로 보존돼 있으면**(대상 리모트에 작업 브랜치 존재) 그 고아 워크트리를 정리하고, **미보존
     (원격 브랜치 없음 = 워크트리가 유일 사본)이면 보존**한다. 너는 워크트리를 **직접 `rm` 하지 않는다**(블랙박스 경계).
   - **정리 실패는 경고로 표면화**되며(조용한 실패 금지) 머지·완료 판정 자체를 뒤집지 않는다(정리는 머지 성공의
     사후 단계).

3. **서브모드 = 백엔드 가용성**(forge CLI 가용 여부로 판정):
   - **forge(gh 가용)**: **로컬 `autopilot:review` 스킬을 호출하지 않는다.** 작업 브랜치를 push해 PR을 만들고/재사용한 뒤,
     **PR 의 호스팅측 리뷰**를 받는다. **호스팅 리뷰는 비동기로 도착한다(수 분 소요 가능)** — PR 생성 직후 리뷰가
     아직 없는 **'pending'(미도착) 상태는 transient 이며 종료(에스컬레이션) 사유가 아니다**. 리뷰가 도착할 때까지
     **기다린다**. **너는 PR 리뷰를 자기가 포스트·승인하지 않는다** — `gh pr review` 등 raw 원격 리뷰·승인 명령으로
     자기 PR 을 스스로 리뷰·approve 하지 마라(자기승인 우회 방지). 승인은 **분리 신원의 호스팅 리뷰**가 담당한다.
     **approve(머지 가능) 상태의 정의**: ① PR 리뷰의 **지적 중 타당한 것이 모두
     해결**되고(블로킹뿐 아니라 — `rules/change-adoption.md` 기준으로 "반드시 반영"·타당한 지적 채택) ② **approve
     상태 변경 또는 승인 코멘트**가 있는 상태. 이 두 조건을 모두 만족할 때만 머지하며, 그 전에는 머지하지 않는다.
     타당한 지적이 남아 있으면 채택해 재구현→재푸시를 반복한다(아래 4). **transient pending(대기 계속) 과
     terminal(에스컬레이션) 을 구분하라** — 머지 없는 에스컬레이션은 ① 리뷰가 **합리적 대기 한도까지 끝내 도착하지
     않거나** ② 재구현 반복 가드(`review-loop.sh`)가 소진된 **그때만** 한다(아래 4).
   - **direct(gh 미가용)**: `review-loop.sh run-direct`가 로컬 `autopilot:review` 스킬로 적대 리뷰·판정한다. `approve`일 때만 머지.

4. **승인 후에만 머지**: 위 게이트의 승인 이후에만 `merge.sh finish`로 머지한다. 승인이 없거나
   리뷰가 `request_changes`면 같은 작업 브랜치에서 `autopilot:loop`으로 재구현→재리뷰를 반복하되, 무한루프 가드
   (`review-loop.sh`)에 걸리면 **머지 없이 에스컬레이션**한다. 거짓 green 금지.

7. **머지 충돌은 헬퍼가 자율 해결 — 충돌만으로 즉시 에스컬레이션하지 않는다**: dispatch run 도중 대상 브랜치가
   다른 머지로 전진하면 base sync(`integration.sh integrate` 의 rebase)·최종 머지(`merge.sh finish` 의 ff)에서
   충돌·ff 실패가 난다. 결정적 헬퍼가 이를 **자율 해결**한다 — 너는 충돌·ff 실패만으로 곧장 에스컬레이션하지 않는다.
   - **결정적 해소(버전 줄)**: plugin.json 버전-only 충돌은 헬퍼가 "타겟 위로 작업 브랜치 의도 범프 재적용"으로
     결정적으로 해소한다 — 추가 검증 없이 진행한다(버전 게이트가 별도로 단언).
   - **비결정(일반) 충돌 + 검증 게이트**: 코드 의미 충돌은 헬퍼가 전략(기본 `incoming`)으로 해소하되 **비결정
     해소 표시**(`integration.sh integrate` 가 표면화하는 `autoresolve … needs-verify` 신호)를 남긴다. 이 표시가
     있으면 머지 전에 **그 SPEC 의 검증(완료 조건/관련 결정적 selftest)을 재실행**한다 — 통과 시에만 머지로 진행하고,
     **실패하면 머지하지 않고 에스컬레이션**한다(자동 해소가 타겟 변경을 깨뜨렸을 수 있음 — 거짓 green 금지).
   - **최종 머지 레이스**: `merge.sh finish` 가 타겟 전진으로 ff 실패를 보고하면(헬퍼 내부 바운드 재시도 후에도),
     `integration.sh integrate`(자율 재동기화)를 다시 돌린 뒤 `merge.sh finish` 를 재시도한다. **유한 횟수**
     (기본 한도) 초과 시 에스컬레이션한다.
   - 자동 해결·재동기화·재시도는 **어떤 경로에서도 non-force**다(force push/merge/rebase 금지). 검증으로 닫히지
     않거나 한도를 넘는 충돌만 보수적으로 에스컬레이션한다.

5. **블랙박스 경계**: `autopilot:loop`·`autopilot:review`의 내부 신호 파일·워크트리·하니스를 들여다보거나 건드리지 않는다.

## 절차 요약
1. `bash "$(git rev-parse --show-toplevel)/plugins/autopilot/skills/loop/references/loop.sh" start <spec>` — **포그라운드 블로킹 직접 구동**(`run_in_background` 금지, 반환까지 턴 유지·알림 대기 금지), 반환된 뒤 DONE 판정(`loop.sh status --json`).
2. 서브모드 판정 → `integration.sh integrate|integrate-direct`.
3. `review-loop.sh run|run-direct` → 승인 게이트(forge=호스팅 리뷰 **비동기 대기**·pending=transient·**자기승인 금지**·PR APPROVED, direct=로컬 review approve). `request_changes`면 재구현 반복(가드).
4. 승인 후 `merge.sh finish`(버전 범프·승인 게이트·**머지 확정 후 작업 브랜치 정리**). **타겟 전진 충돌·ff 실패는
   헬퍼가 자율 해결**한다(규칙 7) — 비결정 해소 표시(`needs-verify`)가 있으면 머지 전 검증 재실행, ff 레이스는
   재동기화 후 유한 재시도, 검증 실패·한도 초과만 에스컬레이션(non-force). 머지 없이 escalation 하면 통합 헬퍼가
   **조건부 워크트리 정리**(원격 보존 시 정리·미보존 시 보존)를 위임 수행한다 — 너는 브랜치·워크트리를 직접
   정리하지 않는다(규칙 6).
5. 보고.

## 보고 (너의 마지막 메시지 = 반환값, 사람 대상 산문 아님)
정확히 아래 JSON 한 개:
`{"key":"<key>","result":"merged"|"escalated","target_branch":"<branch>","work_branch":"<branch-or-null>","pr":"<url-or-null>","detail":"<한 줄>"}`
`result="merged"`는 **실제로 대상 브랜치에 머지된 경우만**. 그 외는 모두 `escalated`(사유를 detail에) —
loop 이 고아·미완(DONE 미도달)으로 끝났거나, 통합·리뷰·머지가 승인 없이 멈췄거나, 환경이 loop 을 동기
완주시키지 못한 경우를 포함한다. dispatch 는 이 보고를 `dispatch.sh mark-report` 로 받아 **`result=merged`
일 때만 done(=의존자 해제)** 으로 전이하고, 그 외는 failed 로 둔다(이행적 의존자만 차단). 머지하지 않았는데
`merged` 로 보고하지 마라 — 거짓 성공은 금지다.
