---
scope:
  include: ["plugins/autopilot/skills/loop/**", "tests/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: '! grep -RnE ''(PLAN|NOTES|HANDOFF|RUN_LOG|ESCALATION)\.md'' plugins/autopilot/skills/loop/references/ plugins/autopilot/skills/loop/agents/ plugins/autopilot/skills/loop/SKILL.md plugins/autopilot/skills/loop/templates/ 2>/dev/null'
ears_language: ko
test_sweep_paths:
  - "tests/autopilot/test-loop-sh.sh"
---

# Loop 메타 파일 5종을 Task 코멘트로 이전

## 무엇을 만들 것인가
자율 루프(autopilot loop)의 이터간 메타(`PLAN`·`NOTES`·`HANDOFF`·`RUN_LOG`·`ESCALATION`) 저장소를 워크트리 파일에서 GitHub Issue의 body 계획 섹션·comments로 이전한다. 장기 계획 상태는 issue body 계획 섹션에 두고 매 이터 갱신한다. 이터 단위의 흐름·교훈·핵심·정지 사유는 comments에 적절한 prefix(`[handoff]`·`[notes]`·`[blocked]`·`[done]`)를 달아 append한다. 정지·종료 신호는 task의 Project Status와 특수 prefix comment로 교체한다. 결과적으로 루프 수행 중 워크트리에는 5종 메타 파일이 생성·갱신·커밋되지 않는다.

## 수용 기준 (EARS)
1. 시스템은 loop의 PLAN·NOTES·HANDOFF·RUN_LOG·ESCALATION 메타 정보를 GitHub Issue body 또는 comments에만 저장한다.
2. 이터가 종료될 때, 시스템은 그 이터의 진행 흐름·인계 메모를 task issue의 1개 이상 comment로 append한다.
3. 이터의 계획(목표·배경·제안·검증 계획·DoD)이 갱신될 때, 시스템은 task issue body의 계획 섹션을 동일한 내용으로 갱신한다.
4. task가 Project Status=Blocked인 동안, 시스템은 그 task에 대해 다음 이터를 시작하지 않는다.
5. 이터가 진행 불가 상황을 보고할 때, 시스템은 task의 Project Status를 Blocked로 전이하고 사유를 `[blocked]` prefix comment로 작성한다.
6. 이터가 task 완료를 선언할 때, 시스템은 `[done]` prefix comment를 작성하고 loop을 정상 종료한다.
7. 워크트리에 PLAN.md·NOTES.md·HANDOFF.md·RUN_LOG.md·ESCALATION.md 중 하나라도 생성·갱신되면, 검증은 실패한다.
8. 드라이버 `--watch` 모드가 정지 task의 Status가 Blocked에서 벗어남을 감지할 때, 시스템은 다음 이터를 자동 재개한다.

## 범위
포함:
- `plugins/autopilot/skills/loop/` 안의 다음 영역: 드라이버 스크립트(`loop.sh`)·헌법(`constitution.md`)·운영 가이드(`operational-guide.md`)·에이전트 정의(`agents/*`)·템플릿(`templates/*`)·`SKILL.md`. 구체적으로 메타 파일 생성·읽기·종료 신호·`--watch` polling 경로를 모두 교체한다.
- `tests/` 안의 관련 회귀·단위 테스트.

비-목표 / 제외:
- 마이그레이션·구식 메타 파일 변환 도구는 만들지 않는다. 진행 중인 loop·아카이브된 메타 파일의 데이터 보전은 본 SPEC의 책임이 아니다.
- 다른 자율 워크플로(`autopilot:dispatch`·`autopilot:prd`·`autopilot:spec`)의 동작은 변경하지 않는다.
- `rules/context.md`는 이미 매핑 규안을 명시하므로 재작성하지 않는다 (본 SPEC은 그 규안의 구현).
- 정지·종료 신호 외 다른 신호 파일(예: 비-loop 워크플로의 `DONE` 사용처)은 손대지 않는다.

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
! grep -RnE '(PLAN|NOTES|HANDOFF|RUN_LOG|ESCALATION)\.md' plugins/autopilot/skills/loop/references/ plugins/autopilot/skills/loop/agents/ plugins/autopilot/skills/loop/SKILL.md plugins/autopilot/skills/loop/templates/ 2>/dev/null
```

## 제약 (있을 때만)
- **self-referential 검증 제약**: 본 SPEC을 수행하는 드라이버 자체가 자신의 행동 규약을 바꾸므로, 검증은 `verify` 명령의 0 exit과 정적 grep으로만 수행한다. runtime loop 실행에 의존하는 검증(테스트 loop을 돌려 실제 메타 파일이 더 이상 생성되지 않는지 동적으로 확인)은 금지한다.
- `rules/context.md`의 "GitHub Project + Issue" 컨벤션을 단일 출처로 사용한다. 본 SPEC은 그 규안을 구현하며, 매핑 정의를 재정의하지 않는다.
- task-id ↔ issue 매핑은 issue number 직접 사용 또는 `gh issue list --search`를 따른다 (`rules/context.md` 컨벤션과 동일).
- `[handoff]`·`[notes]`·`[blocked]`·`[done]` prefix는 comment 본문 컨벤션이며 GitHub 라벨이 아니다. 별도 셋업 없이 본문 첫 줄 prefix로 식별한다.

## 위험 (있을 때만)
- `gh` CLI rate limit·외부 호출 일시 실패가 이터 진행 자체를 막을 수 있다 (이전엔 파일 쓰기만 해서 항상 성공). 재시도·backoff 설계가 필요하다.
- task issue body 계획 섹션의 동시 편집 충돌(외부 사용자가 UI·CLI로 동시 수정) 가능. last-writer-wins 가정 — 매 이터 갱신 직전 최신 본문을 다시 읽어 머지하는 식의 보호가 필요할 수 있다.
- `[done]`·`[blocked]` prefix는 본문 컨벤션이므로 외부에서도 추가 가능 — 위변조 외부 제약은 없다 (이전 `DONE` 파일도 동일한 신뢰 모델).
- self-referential: 본 SPEC 수행 도중 워커가 자신의 driver(`loop.sh`·`constitution.md`)를 갱신해 다음 이터의 동작이 변할 수 있다. 한 이터에서 contract을 전환한 뒤 다음 이터가 두 모드 사이 어디에 있는지 모호해질 수 있어, 변경을 한 이터에 묶거나 다음 이터부터 새 contract만 적용되는 단방향 마이그레이션 순서 설계가 필요하다.
