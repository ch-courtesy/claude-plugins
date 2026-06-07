# autopilot:review — lens dispatch briefs

한 작업의 변경(diff)을 리뷰할 때 워커가 **4개의 lens 서브에이전트를 병렬·독립**으로 dispatch 하는 brief. 각 lens 는 서로의 결론을 **보지 못한다**(합의 투표 아님). 각 lens 는 자기 관점의 **발견(findings)만 보고**하고, 판정·중복 제거·신뢰도 게이팅·최종 verdict 는 **결정적 중재 게이트(`review.sh`)**가 한다.

> 적대 렌즈(contrarian·minimalist·constraint-auditor)가 필요할 때 그 정의는 `plugins/autopilot/skills/spec/references/personas.md`(단일 출처)를 **참조**한다 — 여기서 복제하지 않는다.

## 공통 출력 계약 (모든 lens)

각 lens 는 `references/output-schema.json` 의 `findings[]` 항목 형식으로만 보고한다. **결정·승인·차단은 하지 않는다** — 발견만 낸다.

각 finding 은 4증거를 **모두** 갖춰야 하며, 하나라도 빠지면 finding 을 만들지 않는다(중재 게이트가 어차피 제외):

1. **변경 위치 링크** — `file` + `line`(변경된 diff 라인의 양수). null 금지.
2. **실패/위험 경로 설명** — `body`. 실제로 무엇이 어떻게 깨지는지.
3. **파일·라인 인용** — 근거가 변경 라인 밖이면 `body` 첫 줄에 `실제 위치: <file>:<line>`.
4. **실행 가능한 제안** — `suggestion`. 수정자가 바로 행동 가능.

추가 필드:
- `confidence_score` (0–100). 80 미만이면 보고하지 말 것(게이트가 제외).
- `severity`: `blocking`(merge 전 필수: correctness·security·data loss·clear regression) / `non_blocking` / `question`.
- `adoption` 힌트(`must_adopt`/`defer`/`wont_adopt`): 선택. **안전경계 발견(보안·데이터 손실·계약·범위·권한)은 중재 게이트가 `must_adopt` 로 고정**하므로 힌트를 무시하고 강등하지 않는다.
- `review_perspective`: 자기 lens 태그(아래).

lens 는 `fingerprint`·`duplicate_of` 를 **직접 만들지 않는다** — 중재 게이트가 파일+관점+정규화 제목으로 결정론적으로 부여한다.

## 입력 (워커가 각 lens 에 paste)

- 작업 식별자, 변경 diff(또는 잘림 표시), 변경 파일 목록.
- SPEC 수용기준(lens① 필수), 관련 비변경 파일(필요 시), 기존 리뷰 스레드 요약.
- diff 가 잘렸거나 필수 컨텍스트를 못 읽으면 lens 는 `context_incomplete` 를 보고하고 추정으로 finding 을 만들지 않는다(중재 게이트가 `unavailable` 로 판정, 절대 approve 안 함).

## lens① — SPEC 수용기준 준수 (`review_perspective: spec_compliance`)

용도: 변경이 SPEC 의 각 수용기준을 실제로 충족하는지 독립 검증.

```text
이 변경이 SPEC 수용기준을 충족하는지 검증하라. 다른 관점 결론은 보지 않는다.

## 수용기준
[SPEC 의 완료 조건 전체를 paste]

## 변경
[diff + 변경 파일]

## 임무
각 수용기준에 대해: 대응 변경이 존재하고(Existence), stub/mock/TODO 가 아니며(Substantive),
실제 호출처에 연결됐는지(Wired) 확인하라. 충족된 기준 id 를 verified_criteria 로 보고하라.
미충족·부분충족은 blocking finding 으로 보고하라.

## 출력
findings[] (spec_compliance) + verified_criteria[] (충족 확인된 수용기준 id) + context_incomplete(bool).
발견만 보고한다. verdict·승인·차단을 결정하지 마라.
```

## lens② — 정확성·보안 (`review_perspective: bug`)

용도: 변경 hunk 자체의 명확한 correctness/security/reliability 버그.

```text
변경 hunk 에서 명확한 correctness·security·reliability 버그만 찾아라. 스타일·취향·네이밍·포맷은 무시.

## 변경
[diff + 필요한 호출부/스키마/설정만]

## 임무
실제 실패 경로가 설명 가능한 버그만 보고. 근거 없는 성능 추측·범위 밖 기존 문제·
linter/typechecker 가 잡을 문제는 보고하지 마라. 보안·데이터 손실·계약 위반은 blocking.

## 출력
findings[] (bug). 4증거 + confidence_score>=80 만. 발견만 보고. 판정 금지.
```

## lens③ — 회귀·역사적 맥락 (`review_perspective: history`)

용도: git blame·주변 commit·과거 PR 맥락으로 현재 변경이 기존 의도를 깨는지.

```text
이 변경이 기존 의도·이전 결정을 깨는지 역사적 맥락으로 검증하라.

## 변경
[diff + 관련 이력(blame/이전 PR 요약)]

## 임무
과거에 의도적으로 만든 동작·계약·불변식을 현재 변경이 회귀시키는지 보고.
"중복처럼 보인다"가 load-bearing 강화를 제거할 근거가 되지 않음에 유의.

## 출력
findings[] (history). 발견만 보고. 판정 금지.
```

## lens④ — 저장소 가이드라인 준수 (`review_perspective: guideline`)

용도: `CLAUDE.md`·`rules/`·워크플로 문서 등 명시적 지침과 변경의 충돌.

```text
변경이 저장소 명시 지침(CLAUDE.md·AGENTS.md·rules/·워크플로 문서)과 충돌하는지 확인하라.

## 변경
[diff + 적용되는 규칙 발췌]

## 임무
지침을 구체적으로 짚어 충돌을 보고(어느 규칙·어느 라인). 막연한 불안 금지.
권한·scope·테스트·완료조건 같은 안전 경계 위반은 blocking.

## 출력
findings[] (guideline). 발견만 보고. 판정 금지.
```

## 중재 게이트 (워커가 lens 출력을 병합 후 결정적 처리)

워커는 4 lens 출력을 하나의 `{findings, verified_criteria, context_incomplete}` JSON 으로 병합해
`review.sh` 의 `REVIEW_LENS_CMD` 로 주입한다. 중재 게이트는:

- finding 별 fingerprint(파일+관점+정규화 제목, 라인 무관) 부여.
- evidence/신뢰도(>=80) 게이트로 부적격 finding 제외.
- 기존 스레드 fingerprint 와 중복 제거(skipped_duplicates).
- blocking 발견을 `rules/change-adoption.md` 3분류(must_adopt/defer/wont_adopt)로 재작업 브리프 작성,
  안전경계는 must_adopt 고정.
- 수용기준 커버리지(total/verified/unverified) 산출, 미검증 잔존 시 approve 금지.
- 단일 `pipeline_verdict`(approve/request_changes/unavailable) 산출.

**완료·차단·머지 결정은 이 스킬이 하지 않는다** — 판정은 머신리더블 산출물일 뿐, 게이트 결정은 오케스트레이터·머지 규칙의 책임이다.
