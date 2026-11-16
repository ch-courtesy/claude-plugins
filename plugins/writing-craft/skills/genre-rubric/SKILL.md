---
name: genre-rubric
description: 수필·설명문·논설문·리뷰·단편·장편·웹소설 원고를 그 장르의 10항목 0·1·2점 표로 외부 LLM 에이전트 CLI(codex·claude·agy 중 글쓴 모델과 다른 회사)가 독립 채점한다. 항목마다 본문 근거 문장과 수정 행동을 붙이고, 적용 불가 항목은 분모에서 빼며, 없는 출처·지어낸 경험·설정 충돌 같은 결함은 총점과 따로 먼저 고치게 한다. 원고 채점, 장르 채점표, 퇴고 전 진단에 사용
node:
  in:
    post_path: { shape: text }
    genre: { shape: text, values: [essay, explainer, argument, review, short-story, novel, webnovel] }
    brief_path: { shape: text, list: 1, required: false }
    reviewer: { shape: text, values: [codex, claude, agy] }
  out:
    score: { shape: json }
    findings: { shape: json, list: 1, required: false }
---

# 장르별 채점

<!-- 뼈대(W-429). 본문은 W-430에서 DESIGN.md 4.3 기준으로, blog-craft post-rubric의 실행 절차(recipe:oneshot, 임시 디렉터리, 프롬프트 틀, JSON 검증)를 따라 채운다. -->

## 입력
<!-- genre는 주 장르. 혼합 글은 결론에 맞는 장르. brief_path는 창작 의도 — 의도와 맞는 이탈은 감점하지 않는다 -->

## 실행
<!-- 1 auto_checks.py로 기계 후보 2 references/rubric-<genre>.md 본문 전체를 프롬프트에 붙여 외부 모델 채점 3 JSON 검증 -->

## 채점 규칙
<!-- 항목: 점수 / 근거(문장 인용) / 판단 이유 / 수정 행동 / 추가 확인. 적용 불가는 이유 쓰고 분모 제외. AI 사용 여부 추정 금지. 합격선 없음(보정 전) -->

## 총점으로 상쇄하지 않는 결함
<!-- 없는 출처·인용·통계 / 제공 안 된 경험 창작 / 중심 설명을 무너뜨리는 사실 오류 / 결론을 뒤집는 반대 증거 누락 / 확정 설정 중대 충돌 / 제한 시점 핵심 정보 누출 / 결말 근거 부재 -->

## 출력
<!-- score: {genre, items[], applicable_total, total, blockers[]}, findings: 1점 이하 항목과 blockers -->
