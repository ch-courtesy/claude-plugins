# 표준 시나리오 픽스처: forum-scenario-01

## 시나리오 메타데이터
- fixture-id: forum-scenario-01
- skill: forum
- version: 1.2.0
- created-at: 2026-08-01
- purpose: core-fact·independent-sources·park-recondition·elimination-reason 마커 정량 측정 재현용 표준 입력

## 시나리오 설명

이 픽스처는 forum 스킬 1.2.0 정량 게이트 검증을 위한 표준 입력 시나리오다.
측정 세션을 재현할 때 이 파일의 브리프와 제약 조건을 그대로 사용한다.

## 브리프 (측정 세션 입력)

**주제**: B2B SaaS 제품의 신규 사용자 온보딩 이탈률 개선 아이디어 발굴

배경:
- 현재 온보딩 완료율: 34% (업계 평균 52%)
- 최초 로그인 후 7일 이내 이탈: 58%
- 현재 온보딩 방식: 이메일 시퀀스 7단계 + 인앱 툴팁 3개
- 주요 이탈 지점: 3단계 (데이터 연동 설정, 28% 이탈)

## 제약 조건 (측정 세션 입력)

- 개발 예산: 3인월 이하
- 출시 일정: 6주 이내
- 기술 스택: React + Node.js (변경 불가)
- 고객 세그먼트: 중소기업 IT 담당자 (비개발자 다수)

## 측정 목표 마커

이 시나리오로 구동된 forum 세션은 다음 구조화 마커를 생성해야 한다:

- `core-fact: ...` — 최소 1개, 핵심 사실(채택·탈락을 좌우하는 근거)
- `independent-sources: N` — N ≥ 2, 독립 출처 수 (정수)
- `park-recondition: ...` — status:parked 아이디어에 필수
- `elimination-reason: ...` — status:eliminated 아이디어에 필수
