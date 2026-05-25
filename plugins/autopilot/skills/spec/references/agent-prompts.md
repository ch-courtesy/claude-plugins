# spec subagent briefs (optimized)

spec 10-step에서 선택적으로 Agent에 위임할 수 있는 역할 2종. 공통 원칙: 결정·합성은 메인, 중첩 dispatch 금지, SPEC 작성·마커 삽입·patch 생성은 메인 책임.

## spec-context-explorer

언제: step 3 컨텍스트 탐색이 부족할 때. 권장 신호: `rules/`가 많고 적용 룰 불명, 기존 SPEC 선례 다수, multi-component 영향, 자연어 의도만 있음.

임무: read-only로 관련 룰, 기존 SPEC, 코드 영역, 컨벤션·금기, 권고를 수집한다. SPEC을 작성하거나 범위를 확장/축소하지 않는다.

응답:

```text
## 관련 룰
- [file:line] <룰> — 적용 사유

## 관련 기존 SPEC
- [path] <요약> — 유사/차이

## 관련 코드 영역
- [path] <역할>

## 컨벤션·금기
- [출처] <내용>

## 권고
- <메인이 고려할 점>
```

## spec-self-reviewer

언제: step 9 자체 검토 보강. 권장 신호: SPEC 100줄 초과, `[NEEDS CLARIFICATION]` 2개 이상, 사용자 요청.

임무: 작성된 SPEC 초안을 `self-review.md` 5축으로 독립 검토하고 발견만 보고한다. 수정·마커 삽입 금지.

심각도: Critical=loop이 막히거나 verify 불가능, Important=진행 가능하나 의도 이탈 위험, Minor=표현/polish.

응답:

```text
## 5축 검토 결과
- placeholder 잔존: N
- 모순: N
- 범위: N
- 모호성: N
- EARS fail-가능성: N

## 발견 사항
### Critical
- [위치] <문제> — <이유>
### Important
### Minor

## 판정
- 진행 가능: 예 | 마커 추가 후 가능 | 재작성 필요
- 근거: ...
```

## 호출 패턴

```text
Agent({
  description: "<짧은 요약>",
  subagent_type: "general-purpose",
  prompt: <위 양식 + 필요한 파일 경로/본문/응답 형식>
})
```

brief는 자기완결이어야 한다. subagent는 메인 컨텍스트를 보지 못한다.
