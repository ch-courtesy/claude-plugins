---
name: story-ledger
description: 장편·웹소설처럼 여러 세션에 걸쳐 쓰는 긴 이야기의 장부(설정집, 인물표, 인물별 지식, 시간선, 회차 요약, 장면 카드, 복선)를 TOML로 만들고 갱신하며, 스크립트로 ID 중복·날짜 역전·죽은 인물 재등장·소유 중복·방치 복선·분량 미달을 검사한다. 확정 사실·계획·인물의 믿음을 나눠 기록한다. 소설 설정 관리, 연속성 점검, 장부 갱신, 설정 바꾼 뒤 영향 찾기에 사용
node:
  in:
    ledger_dir: { shape: text }
    action: { shape: text, values: [init, update, check, impact] }
    patch: { shape: text, list: 1, required: false }
  out:
    report: { shape: json }
---

# 이야기 장부

<!-- 뼈대(W-429). 본문은 W-430에서 DESIGN.md 4.4 기준으로 채운다. -->

## 장부 파일
<!-- references/schema.md: bible, characters, knowledge, timeline, episodes/E###, scenes/E###-S##, foreshadow. 모든 사실에 status = confirmed | planned | belief -->

## init
<!-- 기획 카드에서 첫 장부를 만든다. 계획은 planned로만 -->

## update
<!-- fiction-draft의 장부 갱신안을 채택 본문 근거(회차/장면/문단)와 함께 반영. 폐기 초안 사실 금지 -->

## check
<!-- scripts/ledger_check.py 실행(기계 검사 6종) + 모델 점검 질문(설명 없는 정보 획득, 말투 변화, 능력 예외, 동기 급변, 같은 깨달음 반복): 문제 문장·충돌 근거·최소 수정안. '이상 없음'에도 장부 해시를 남긴다 -->

## impact
<!-- 설정을 바꿀 때 그 ID를 참조하는 장면·복선·요약을 찾아 이미 공개한 사실과 미공개 계획을 나눠 보고 -->
