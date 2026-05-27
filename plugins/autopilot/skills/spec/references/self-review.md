# SPEC self-review (optimized)

SPEC 작성 후 사용자 Q&A 없이 1회 자체 검토한다. 발견 사항은 인라인 수정하거나 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 남긴다.

## 5 checks

1. Placeholder: `{{...}}`, TBD, TODO, 빈 섹션 없음.
2. Consistency: 제목, WHAT, acceptance, scope, verify가 서로 충돌하지 않음.
3. Scope: `scope.include`가 필요한 변경을 포함하고 `scope.exclude`와 충돌하지 않음. 분해 발행(N개)이면 각 문서의 `depends_on`이 실제 선행 단위 slug를 가리키고, 단일 발행이면 `depends_on` 줄이 없어야 한다.
4. Ambiguity: 두 가지로 해석 가능한 요구는 구체 질문 마커로 남김.
5. EARS fail-가능성: 각 acceptance가 관찰 가능하고 독립 테스트 가능하며 구현 방법을 강제하지 않음.

마커가 남으면 loop start가 차단되므로 최종 안내에서 `--resume`을 알려야 한다.
