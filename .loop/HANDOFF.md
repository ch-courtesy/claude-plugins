# 다음 이터에게 (HANDOFF)

## 직전 이터: 1

## 이번에 무엇을 했는가
- `tests/autopilot/test-spec-skill.sh` 신규 작성 (TDD RED) — SKILL.md가 검증 실패 라우팅 (a)/(b)/(c), 사전 명확화 라운드(step 4 앞당김), 단일 task→프로젝트 태스크 관련 지침, 마일스톤→PRD(AskUserQuestion 승인), AskUserQuestion 기반 스킬 체인 규칙, 취소 시 산출물 미생성 안전 종료를 모두 명시함을 검증하는 8 테스트 그룹·23 assertion.
- 의도한 이유(섹션 부재)로 RED 확인.
- `plugins/autopilot/skills/spec/SKILL.md` step 1에 §1.1 검증 실패 라우팅 / §1.2 사전 명확화 라운드(§1.2.1 단일 task 경로 / §1.2.2 마일스톤 경로 / §1.2.3 후속 task 메모) 추가 (GREEN).
- `bash tests/autopilot/test-spec-skill.sh` 0 exit 확인.

## 무엇이 막혔거나 막힐 수 있는가
- 워크트리 초기 setup이 CLAUDE.md를 worker 헌법으로 치환해 `git status`에 modified로 노출됨. 이번 이터에서 CLAUDE.md는 손대지 않았으며 커밋 스테이징에서도 제외. 드라이버 scope 검사가 staged 기준이면 영향 없음, 워크트리 기준이면 driver 룰 자체 이슈로 분류.
- spec 책임 범위가 약간 확장됨 — §1.2.3에 별도 의도-탐색 스킬 분리 후속 task 메모 남김.

## 다음 단계 추천
- (해당 없음 — 본 task는 수용 기준 10항 모두 충족, 4-Level Verifier 통과, DONE 작성 예정.)
