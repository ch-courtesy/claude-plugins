---
scope:
  include: ["plugins/autopilot/skills/spec/**", "tests/autopilot/test-spec-skill.sh"]
  exclude:
    - rules/**
    - .loops/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-spec-skill.sh"
---

# autopilot:spec step 1 검증 실패 분기 라우팅

## 무엇을 만들 것인가
`autopilot:spec` 스킬의 사전 검사 단계에서 task-id 검증이 실패할 때 즉시 종료하는 대신, 사용자에게 의도를 분류하는 라우팅 옵션을 제시한다. 트리거 범위는 task-id 형식 규칙 위반 전체와 자연어 문장으로 보이는 입력. 옵션은 (a) 올바른 task-id 재입력 후 검증 재시도, (b) 사전 명확화 라운드 진입, (c) 종료이다.

(b)의 "사전 명확화 라운드"는 새 phase가 아니라 spec의 기존 step 4 명확화 라운드를 task-id 확보 *전* 단계로 앞당겨 적용한 것이다. 동일한 AskUserQuestion 메커니즘으로 문제·목표·범위·제약을 수집한다. 수렴 결과가 단일 task 규모면 프로젝트의 태스크 관련 지침에 따라 task를 생성해 task-id를 확보한 뒤 spec의 컨텍스트 탐색(step 2)부터 그 task-id로 재개한다. 수렴 결과가 다수 task로 분해될 마일스톤 규모면 PRD 작성 스킬 호출 여부를 AskUserQuestion으로 묻고 명시적 승인 시 invoke한다.

산출 파일은 단일 경로의 SPEC.md 또는 마일스톤 경로의 PRD.md 하나뿐이다. 스킬·시스템 설계 의도 라우팅은 본 변경 범위 밖이며 별도 task로 분리한다.

## 수용 기준 (EARS)
1. `spec`이 step 1 검증 규칙에 어긋나는 task-id로 호출되면, 시스템은 (a) task-id 재입력, (b) 사전 명확화 라운드 진입, (c) 종료 중 최소 세 옵션을 포함한 AskUserQuestion을 제시해야 한다.
2. `spec`이 공백을 포함하거나 task-id가 아닌 자연어 문장으로 보이는 인자로 호출되면, 시스템은 이를 검증 실패로 취급하고 같은 라우팅 AskUserQuestion을 제시해야 한다.
3. 사용자가 (a)를 선택하면, 시스템은 새 task-id를 받아 step 1 검증을 재실행하고 통과 시 정상 spec 흐름으로 복귀해야 한다.
4. 사용자가 (b)를 선택하면, 시스템은 spec의 기존 step 4 명확화 라운드 메커니즘을 task-id 확보 전 단계로 적용해 한 번에 한 AskUserQuestion으로 문제·목표·범위·제약을 수집해야 한다.
5. (b) 라운드 결과가 단일 task 규모로 수렴하면, 시스템은 프로젝트의 태스크 관련 지침에 따라 task를 생성해 task-id를 확보하고 spec의 컨텍스트 탐색 단계(step 2)부터 그 task-id로 재개해야 한다.
6. (b) 라운드 결과가 다수 task로 분해될 마일스톤 규모로 수렴하면, 시스템은 PRD 작성 스킬 호출 여부를 묻는 AskUserQuestion을 제시하고 사용자의 명시적 승인이 있을 때만 PRD 스킬을 invoke해야 한다.
7. 사용자가 (c)를 선택하거나 라우팅·라운드 AskUserQuestion에 응답 없이 종료하면, 시스템은 SPEC.md를 작성하지 않고 종료해야 한다.
8. 시스템은 "다음 단계: Skill(...)" 형식의 자유 텍스트 안내를 출력해서는 안 되며, 후속 스킬 호출은 항상 AskUserQuestion 확인을 거쳐야 한다.
9. `tests/autopilot/test-spec-skill.sh`가 실행되면, 시스템은 spec SKILL.md가 검증 실패 라우팅 옵션 (a)/(b)/(c), 사전 명확화 라운드(step 4 앞당김) 적용 규칙, 단일 task→프로젝트 태스크 관련 지침 따른 생성 경로, 마일스톤→PRD 경로, AskUserQuestion 기반 스킬 체인 규칙을 모두 명시함을 검증하는 assertion을 통과해야 한다.
10. 사용자가 사전 명확화 라운드 중 명시적으로 취소하면, 시스템은 task를 생성하지 않고 어떠한 산출물도 남기지 않고 종료해야 한다.

## 범위
포함:
- `plugins/autopilot/skills/spec/` 디렉터리 (SKILL.md 갱신, 필요 시 의도 탐색 관련 모듈 추가)
- `tests/autopilot/test-spec-skill.sh` 신규 작성

비-목표 / 제외:
- prd·loop·dispatch 스킬 본문 수정
- 별도 brainstorming 전용 스킬 생성 (후속 task)
- spec 워크플로 1~9단계 중 검증 실패 분기 외 기존 흐름 변경
- CLAUDE.md, `rules/*` 갱신
- 외부 도구(`gh` CLI 등) 자체의 동작 변경 — 프로젝트의 태스크 관련 지침이 정의한 기존 절차를 사용만 함

## 검증
이 명령이 0 exit으로 끝나야 합니다:
bash tests/autopilot/test-spec-skill.sh

## 제약 (있을 때만)
- 사전 명확화 라운드는 spec의 기존 step 4 메커니즘(한 번에 한 AskUserQuestion, 4문항 이내)을 task-id 확보 전 단계로 앞당겨 재사용한다. 별도 phase·신규 모듈을 만들지 않고, 같은 인터랙션 규칙을 그대로 적용한다.
- 위 앞당김 적용 설계는 `superpowers:brainstorming`을 포함해 같은 목적의 외부·내부 도구를 우선 리서치·벤치마크한 결과를 근거로 한다. 자체 개념을 처음부터 만들지 않는다.
- 모든 결정·확인·옵션 제시는 `AskUserQuestion`으로 한다. CLAUDE.md의 "자유 텍스트 끝에 질문 종결구 다는 방식 금지" 룰을 그대로 적용한다.
- spec SKILL.md 본문은 WHAT/HOW 방어선을 유지한다.
- 단일 task 수렴 시 task 생성은 프로젝트의 태스크 관련 지침이 정의한 issue body 구조(목표·배경·제안·검증 계획·DoD 등)를 따른다. 본 SPEC이 그 구조를 재정의하지 않는다.
- 후속 스킬 호출(예: PRD)을 "다음 단계: Skill(...)" 자유 텍스트로 안내하지 않는다 — 항상 AskUserQuestion 확인 후 invoke.

## 위험 (있을 때만)
- spec의 책임 범위가 "task-id를 받아 SPEC 작성"에서 "사전 명확화 + task 생성/마일스톤 라우팅"으로 확장된다. step 4 메커니즘을 재사용해 코드 중복은 피하지만 단일 책임 원칙이 약해질 수 있으며, 향후 별도 스킬 분리 가능성을 SKILL.md 본문에 후속 task 메모로 남긴다.
- 자연어 입력 감지 휴리스틱은 위양성·위음성이 가능하다. 검증 실패 분류 후에도 사용자가 (a) 재입력으로 즉시 복구할 수 있어야 한다.
- (b) → 단일 task 경로의 task 생성은 외부 도구(`gh` CLI, GitHub Project 접근)에 의존한다. 실패 시 사용자에게 명시적으로 알리고 부분 산출물을 남기지 않고 안전하게 종료한다.
- (b) 라운드의 종료 조건이 모호하면 무한 Q&A 위험. 매 라운드 사용자 측 "충분" 종결 옵션을 AskUserQuestion에 포함한다.
- (b) → 마일스톤 경로에서 PRD 스킬은 `milestone-id`를 요구한다. spec은 PRD 스킬을 invoke하기 전 사용자에게 milestone-id를 받아 인자로 전달할 책임이 있다.
- 사전 명확화 라운드는 task-id가 없는 상태에서 진행되므로 합의된 산출(문제·목표·범위·제약)을 단일 task 수렴 후 step 2 이후 단계의 섹션 초안으로 손실 없이 이어 사용해야 한다.
