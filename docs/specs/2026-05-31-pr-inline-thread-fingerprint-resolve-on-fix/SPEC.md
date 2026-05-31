---
scope:
  include:
    - .github/workflows/claude-review.yml
    - .github/workflows/codex-review.yml
    - .github/prompts/claude-pr-review.ko.md
    - .github/prompts/codex-pr-review.ko.md
    - .github/prompts/codex-pr-review.schema.json
    - tests/claude/test-claude-review-workflow.sh
    - tests/codex/test-codex-review-workflow.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# PR 리뷰 inline thread fingerprint 단위 resolve-on-fix 전환

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
PR 리뷰 워크플로가 verdict에 의존해 두던 "조잡한 게이트" 두 곳을 걷어내고, self inline thread
resolve를 finding 단위로 복구한다.

### (1) self inline thread resolve 복구
워크플로는 자신이 과거에 단 inline review thread를, 최신 리뷰에서 그 finding이 해결됐다고 판단되면
자동으로 resolved 상태로 전환한다. 이 동작은 과거 agentic 리뷰(모델이 직접 기존 thread를 조회·판단해
thread 단위로 resolve)에서는 작동했으나, 구조화 JSON 리뷰로 전환되며 회귀했다. 현재 리뷰 출력 schema에는
모델이 "어떤 thread가 해결됐는지" 내리는 판단을 담는 자리(resolved_threads: 각 항목에 fingerprint·reason)가
있지만, 워크플로는 이 판단을 전혀 소비하지 않는다. 또한 게시되는 inline thread에는 finding의 fingerprint가
담기지 않아 모델의 판단을 thread로 매핑할 길이 없다. 그 결과 resolve는 verdict가 approve(현재 라운드
finding 0건)일 때에만 일괄로만 일어나, finding이 하나라도 남으면 이미 해결된 thread조차 미해결로 남는다.

이를 finding 단위(fingerprint 기준)로 복구한다. ① 게시되는 inline thread는 자신을 만든 finding의
fingerprint를 self-식별 마커에 담는다. ② 모델은 기존 봇 self thread의 마커 fingerprint를 근거로,
현재 변경에서 해결됐다고 판단한 thread의 fingerprint를 resolved_threads에 기록한다. ③ 워크플로는
verdict와 무관하게 매 리뷰 실행에서, 모델이 resolved_threads로 지목한 self thread를 1차로 resolve하고,
거기에 없더라도 이번 라운드 findings의 fingerprint 집합에 더 이상 없는 self thread를 fallback으로
resolve한다. 여전히 보고되는 fingerprint의 thread는 그대로 둔다. 기존 approve 전용 일괄 resolve 게이트는
제거한다.

### (2) REQUEST_CHANGES 리뷰 상태 폐지
같은 조잡한 게이트 문제가 REQUEST_CHANGES 경로에도 있다 — 워크플로가 blocking finding에 대해 공식
REQUEST_CHANGES review를 제출하고, 그 뒤 최신 verdict가 approve일 때에만 옛 CHANGES_REQUESTED를
dismiss한다. 비-blocking finding이 남아 verdict가 comment로 떨어지면 변경요청 사유가 이미 해소됐는데도
옛 CHANGES_REQUESTED가 stuck된다.

이를 근본적으로 없앤다. 워크플로는 어떤 verdict에서도 REQUEST_CHANGES review event를 제출하지 않는다
(공식 review event는 APPROVE 또는 COMMENT만). blocking finding은 이미 inline-only 정책에 따라 inline
코멘트로 표면화되므로 별도의 review 상태가 필요 없다. REQUEST_CHANGES를 만들지 않으므로 거둘 대상도
없어, dismiss-on-approve 로직은 제거한다. request_changes는 리뷰 출력 verdict 어휘(프롬프트 지시·스키마
enum·워크플로 verdict 검증)에서도 제거해 모델이 산출하지 않도록 한다.

동일 동작을 Claude·Codex 두 워크플로(및 두 프롬프트·공용 스키마)에 적용하고 회귀 가드를 둔다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->
1. When 워크플로가 finding을 inline review 코멘트로 게시할 때, 시스템은 그 finding의 fingerprint를
   코멘트 본문의 self-식별 마커에 포함해야 한다.
2. 시스템은 모델에게, 기존 봇 self inline thread의 마커 fingerprint를 근거로 현재 변경에서 해결된
   thread의 fingerprint를 리뷰 출력의 resolved_threads에 기록하도록 지시해야 한다.
3. When 리뷰 출력의 resolved_threads에 어떤 fingerprint가 포함되고 그 fingerprint를 마커에 담은
   봇 작성 미해결 self thread가 존재할 때, 시스템은 verdict 값과 무관하게 그 thread를 resolved
   상태로 전환해야 한다.
4. When 봇 작성 미해결 self thread의 마커 fingerprint가 resolved_threads에도 없고 이번 라운드
   findings의 fingerprint 집합에도 없을 때, 시스템은 그 thread를 resolved 상태로 전환해야 한다.
5. While 봇 작성 self thread의 마커 fingerprint가 이번 라운드 findings 집합에 포함되고
   resolved_threads에는 없는 동안, 시스템은 그 thread를 resolve하지 않아야 한다.
6. 시스템은 self inline thread resolve 평가를 verdict=approve 조건 안에 가두지 않고 매 리뷰 실행에서
   수행해야 한다.
7. If self inline thread의 마커에서 추출 가능한 fingerprint가 없으면, 시스템은 그 thread를 finding
   단위 resolve 대상에서 제외하고 상태를 변경하지 않아야 한다.
8. 시스템은 봇이 작성하지 않은 thread를 resolve하지 않아야 하며, 이미 resolved 상태인 thread의 상태를
   다시 변경하지 않아야 한다.
9. If GraphQL API가 봇 작성자 login을 REST 형식(접미사 `[bot]` 포함)과 다른 형식으로 반환하더라도,
   시스템은 해당 thread를 자신이 작성한 thread로 식별해야 한다.
10. 시스템은 어떤 verdict에서도 REQUEST_CHANGES review event를 제출하지 않아야 하며, 공식 review event는
    APPROVE 또는 COMMENT로만 제출해야 한다.
11. While blocking finding이 존재하는 동안, 시스템은 그 finding을 inline review 코멘트로 표면화해야 하며,
    REQUEST_CHANGES review 상태로 표현하지 않아야 한다.
12. 시스템은 리뷰 출력 verdict 어휘에서 request_changes를 제거해(프롬프트 지시·스키마 enum·워크플로 verdict
    검증 모두), 모델이 request_changes verdict를 산출하거나 워크플로가 이를 유효 verdict로 받아들이지
    않도록 해야 한다.
13. 시스템은 이전 CHANGES_REQUESTED self review를 dismiss하는 로직을 포함하지 않아야 한다.
14. 시스템은 기존 리뷰 멱등성 검사의 REST 기반 봇 식별 동작을 변경 없이 유지해야 한다.
15. 시스템은 Claude·Codex 두 리뷰 워크플로(두 리뷰 프롬프트·공용 스키마 포함)에서 동일한 finding 단위
    self thread resolve 동작과 동일한 REQUEST_CHANGES 폐지를 제공해야 한다.
16. 시스템은 두 워크플로 테스트 스위트에, (a) resolve 평가가 verdict=approve 게이트 안에만 존재하면 실패,
    (b) 게시 마커에 finding fingerprint가 담기지 않으면 실패, (c) resolved_threads를 소비해 thread를
    resolve하는 경로가 없으면 실패, (d) fingerprint-부재 fallback resolve 경로가 없으면 실패,
    (e) REQUEST_CHANGES event를 제출하는 분기가 존재하면 실패, (f) verdict 검증/어휘에 request_changes가
    남아 있으면 실패, (g) dismiss-on-approve(CHANGES_REQUESTED dismiss) 로직이 존재하면 실패하는 회귀
    가드를 포함해야 한다.

## 범위
포함:
- 두 워크플로의 inline 코멘트 게시 마커에 finding fingerprint 운반
- 두 워크플로의 self inline thread resolve 경로를 verdict 게이트 밖으로 분리하고, resolved_threads 소비(1차)
  + fingerprint-부재 fallback(2차) 기준으로 전환
- 두 리뷰 프롬프트에 기존 self thread의 마커 fingerprint를 근거로 resolved_threads를 채우라는 지시 추가
- 두 워크플로에서 REQUEST_CHANGES review event 제출 분기와 dismiss-on-approve 로직 제거(event는 APPROVE/COMMENT만)
- request_changes를 verdict 어휘에서 제거: 두 프롬프트 지시, 공용 스키마 verdict enum, 두 워크플로의 verdict 검증
- 두 워크플로 테스트의 resolve·마커·REQUEST_CHANGES 폐지 관련 회귀 가드 갱신

비-목표 / 제외:
- 미수정(여전히 보고되는) finding thread에 후속 reply·재게시(설계 Phase3 reply)
- 동일 finding 재지적 시 중복 inline thread 생성 방지(dedup) — 기존 동작 유지
- resolved → unresolved 되돌리기(re-open) 등 추가 thread lifecycle
- approve 제출 조건(may_approve·findings 0건·diff 미truncate)과 managed issue comment 게시·supersede 로직 — 변경 없이 유지
- automation_safety.may_request_changes 필드 자체의 스키마 삭제 — 미사용으로 남기되 이번 범위에서 제거하지 않음
- resolved_threads/unresolved_threads 필드 정의 — 이미 존재하며 그대로 사용

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다.
검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- self thread 식별의 1차 기준은 코멘트 본문에 심은 self-식별 마커이며, 봇 login 비교는 `[bot]` 접미사
  유무 차이에 강건해야 한다(기존 botLoginGql 정규화 유지).
- fingerprint는 리뷰 출력 schema의 `finding.fingerprint` 값을 그대로 사용한다.
- fingerprint는 기존 self-식별 마커를 확장하는 방식으로 운반하며, 확장된 마커는 기존 self-식별 검사가
  계속 성립하도록 기존 마커 부분문자열을 보존해야 한다(별도 마커 라인 신설이 아님).
- resolve는 resolved_threads 소비를 1차 기준으로, fingerprint-부재 매칭을 2차(fallback) 기준으로 둔다.
- resolve 대상은 항상 봇이 작성한 self thread로 한정한다(타 리뷰어 thread 불가침).
- 공식 review event는 APPROVE 또는 COMMENT로만 제출한다 — REQUEST_CHANGES 제출 분기와 dismiss-on-approve
  블록은 제거한다.
- approve 제출 조건(may_approve·findings 0건·diff 미truncate)과 approve 전용 managed comment 게시는 유지한다.
- Claude·Codex 두 워크플로와 두 프롬프트, 공용 스키마에 동일하게 적용한다.

## 위험
- (fallback 경로 한정·수용된 trade-off) incremental·thread 컨텍스트 모드에서는 모델이 증분 diff만 보므로
  "fingerprint가 이번 findings에 없음"이 "해결됨"을 보장하지 않는다 — 이전 라운드 finding을 단지 다시
  보지 않은 경우에도 fallback 경로가 그 thread를 resolve할 수 있다(오해소). resolved_threads 1차 경로는
  모델의 명시적 판단이라 이 위험이 없으나, fallback은 컨텍스트 모드 가드 없이 동작한다. 완화: full 모드
  초기 리뷰는 전체 findings를 보므로 위험이 낮고, 오해소된 thread는 다음 라운드 재지적 시 새 thread로
  다시 표면화된다.
- REQUEST_CHANGES 폐지로 봇이 PR을 공식 review 상태로 "차단"하지 않는다 — blocking 이슈가 inline 코멘트로만
  표면화되므로, 머지 차단을 봇의 CHANGES_REQUESTED 상태에 의존하던 흐름이 있으면 영향이 있다. 완화: 본래
  워크플로 토큰은 self-approve도 강제력이 약했고 inline-only 정책상 blocking은 inline으로 항상 보이며,
  머지 게이팅은 branch protection·사람 리뷰가 단일 출처여야 한다(봇 review 상태에 의존하지 않음).
- 모델이 resolved_threads에 실제 self thread와 매칭되지 않는(또는 잘못된) fingerprint를 넣을 위험 —
  resolve는 self-owned + 마커 fingerprint 정확 매칭에만 적용하고, 매칭되지 않는 fingerprint는 무시하여
  완화한다(AC3·AC8).
- fingerprint가 라운드 간 안정적이지 않으면(동일 이슈에 다른 fingerprint 부여) 매칭이 어긋나 오해소 또는
  미해소가 발생한다 — fingerprint 생성 규칙의 안정성에 의존한다.
- 마커 형식 확장이 기존 self-식별 매칭과 어긋나면 식별이 실패한다 — 확장은 기존 마커 부분문자열을 보존해야
  하며 AC1·AC9·테스트 회귀 가드로 보호한다. 마커에 fingerprint가 없는 레거시 thread는 AC7로 resolve 대상에서 제외한다.
