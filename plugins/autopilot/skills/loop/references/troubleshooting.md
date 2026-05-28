# ESCALATION troubleshooting (optimized)

차단은 `.loop/signals/BLOCKED` 파일(첫 줄 `category:`)로 신호된다. 차단 해제의 정식 절차는 원인 보정 후 `.loop/signals/BLOCKED` 파일을 삭제하고 재시작하는 것이다.

## category 별 처리

### config-gap

도구 미설치·자격증명·env var 누락. missing item 확인 → 환경 조정 → `.loop/signals/BLOCKED` 삭제 → 재시작.

### spec-gap

모호한 수용 기준·verify 부적합·scope 미흡, 또는 1회차 플랜 형성 불가("스펙 강화 필요"). 필요한 결정 확인 → 스펙 보정 → `.loop/signals/BLOCKED` 삭제 → 재시작.

### architecture-gap

현재 구조로 해결 불가. 본 실행 정지, 별도 architecture 작업 수행, 이후 스펙 scope 조정 또는 cleanup 후 새 실행.

### environment-gap

API rate limit·네트워크·외부 서비스 장애. 일시 문제면 대기 후 재시작, 영구 문제면 mock/test double 또는 스펙 조정.

### gate-violation

driver의 객관 게이트 위반 자동 정지. 최근 이터 로그로 원인 파악 후 스펙(scope·verify) 조정 또는 노트에 메모.

### other

차단 본문을 읽고 사람이 판단.

## halt 후 stash

driver halt 시 미커밋 변경은 자동 stash될 수 있다. 작업 공간에서 `git stash list`, 필요 시 `git stash pop`.
