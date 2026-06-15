# ESCALATION troubleshooting

차단 신호는 `.loop/signals/BLOCKED`(첫 줄 `category:`). 차단 해제 정식 절차는 본문의 원인을 보정한 뒤 BLOCKED 파일을 삭제하고 재시작. category 값과 의미는 `references/constitution.md §작업 매체` SoT.

## category 별 운영 조치

- **config-gap**: 도구 미설치·자격증명·env var 누락 — 환경 조정 후 재시작.
- **spec-gap**: 모호한 수용 기준·verify 부적합·scope 미흡, 또는 1회차 플랜 형성 불가("스펙 강화 필요") — 스펙 보정 후 재시작.
- **architecture-gap**: 현재 구조로 해결 불가 — 본 실행 정지, 별도 architecture 작업 수행 후 스펙 scope 조정 또는 cleanup 후 새 실행.
- **environment-gap**: API rate limit·네트워크·외부 서비스 장애 — 일시 문제면 대기 후 재시작, 영구 문제면 mock/test double 또는 스펙 조정.
- **other**: BLOCKED 본문 직접 판단.

## driver halt 처리

driver 가 객관 게이트 위반·worker 비정상 exit streak 등으로 halt 하면 BLOCKED 신호는 만들지 않는다 — stderr 메시지 + 미커밋 변경 자동 stash + exit 1. 진단:
- 최근 이터 로그(`.loop/iterations/<n>.log`)에서 원인 파악.
- 작업 공간에서 `git stash list`, 필요 시 `git stash pop`.
- 스펙(scope·verify) 조정 또는 노트(`.loop/notes.md`)에 메모 후 재시작.
