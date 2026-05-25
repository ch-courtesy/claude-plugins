# PRD self-review (optimized)

PRD 작성·import 후 사용자 Q&A 없이 1회 검토한다. 부족한 항목은 인라인 수정하거나 `[NEEDS CLARIFICATION: <구체 질문>]` 마커로 남긴다.

## 5 checks

1. Placeholder: `{{...}}`, TBD, TODO, 빈 필수 섹션 없음.
2. Consistency: 문제, 목표, 성공 기준, 범위, 분해 힌트가 충돌하지 않음.
3. Decomposable scope: dispatch가 child SPEC으로 나눌 수 있을 만큼 범위가 명확하고 1차 후보가 1-8개로 보임.
4. Ambiguity: "개선", "빠르게", "적절히" 같은 표현은 판정 가능한 기준으로 바꾸거나 마커.
5. Marker handling: 남은 마커 수를 최종 안내에 반영하고, 마커가 있으면 dispatch start 차단.

PRD는 child SPEC의 EARS 세부화를 위한 상위 요구서이므로 EARS 강제는 하지 않는다.
