# 프레이밍 템플릿

세션 책임자는 한 번에 한 주제씩 인터뷰하고 확정·가정·미확정을 구분한다. 후보 평가 기준은 일반적인 매력도가 아니라 **의뢰자 가치**에서 도출한다.

## 인터뷰 질문

1. 어떤 상황을 바꾸거나 어떤 기회를 탐색하려는가?
2. 누구에게 어떤 의뢰자 가치 또는 사용자 가치를 만들어야 하는가?
3. 좋은 결과가 보일 때 관찰 가능한 성공 신호는 무엇인가?
4. 탐색 범위와 제외 범위는 무엇인가?
5. 반드시 지킬 제약과 금지 영역은 무엇인가?
6. 기존 시도, 이미 기각한 접근, 활용 가능한 자산은 무엇인가?
7. 지금 가장 불확실하지만 영향이 큰 가정은 무엇인가?

## 브리프 섹션 규격

세션 파일(`.brainstorm/<session-id>.md`)의 브리프 섹션에 다음 필드를 기록한다.

```markdown
- session-id:
- requester:
- problem-or-opportunity:
- target:
- requester-value:
- how-might-we:
- scope:
- out-of-scope:
- constraints:
- existing-attempts:
- assumptions:
- success-signals:
- evaluation-criteria:
- frame-status: draft | approved
```

`how-might-we`는 해결책을 미리 고정하지 않는 열린 질문이어야 한다. 평가 기준은 의뢰자 가치와 성공 신호에 직접 연결하고, 서로 충돌하는 기준은 우선순위 또는 trade-off로 표시한다.
