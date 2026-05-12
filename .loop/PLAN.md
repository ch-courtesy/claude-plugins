# 작업 계획

`autopilot:spec` step 1 검증 실패 시 abort 대신 라우팅 제시. SPEC.md 수용 기준 10항·EARS 1~10 모두 만족 필요.

## 마일스톤

### M1: test-spec-skill.sh 작성 (RED)
- **정의**: `tests/autopilot/test-spec-skill.sh`가 신규 작성되고, 현재 SKILL.md 상태에서는 의도한 이유로 실패한다.
- **검증**: `bash tests/autopilot/test-spec-skill.sh` 실행 시 SKILL.md에 새 라우팅 섹션 없음으로 인한 실패 (existence assertion fail).
- **영향 영역**: `tests/autopilot/test-spec-skill.sh` (신규)
- **위험**: 기존 SKILL.md 항목과 grep 충돌 가능 — 새로 추가될 키워드는 기존 본문에 부재함을 사전 확인.
- [x] 완료 (iter1: TEST 1에서 의도한 fail 확인)

### M2: SKILL.md 검증 실패 라우팅 섹션 추가 (GREEN)
- **정의**: spec SKILL.md step 1에 검증 실패 라우팅 (a/b/c) + 사전 명확화 라운드(step 4 앞당김) + 단일 task 경로(프로젝트 태스크 관련 지침) + 마일스톤 경로(PRD invoke, AskUserQuestion 승인) + 명시적 취소 시 안전 종료 절이 명시된다.
- **검증**: `bash tests/autopilot/test-spec-skill.sh` 0 exit.
- **영향 영역**: `plugins/autopilot/skills/spec/SKILL.md`
- **위험**: 책임 범위 확장으로 단일 책임 약화. SKILL.md 본문 §1.2.3에 후속 분리 task 메모 남김으로 위험 명시.
- [x] 완료 (iter1: 23 assertion 모두 통과)

## 의존 관계

- 순차: M1 → M2

## 완료 판정 (헌법 §3.4·§3.5)

- [x] 모든 마일스톤 체크
- [x] 4-Level Verifier — Existence·Substantive·Wired·Runtime
- [x] Self-Review 4축 — Completeness·Quality·Discipline·Testing
- [x] verify 명령 0 exit (`bash tests/autopilot/test-spec-skill.sh`)
- [x] `fix:symptom` 누적 없음 (M1=test, M2=feat)
