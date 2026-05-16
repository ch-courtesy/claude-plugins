# autopilot 설계·드라이버의 backing-neutral 어휘 + native signal 매체 교체

**Milestone**: 2026-05-backing-abstraction

## 문제

현 autopilot은 task의 backing system(=구체적 task storage·workflow 백엔드. 본 프로젝트의 경우 GitHub Issue + Project)에 강결합되어 있다. 두 측면에서 문제가 나타난다.

첫째, 설계 문서 차원: 헌법(`constitution.md`)·SKILL.md·`references/*.md`의 곳곳에서 "task issue body", "[done] prefix comment", "Project Status field" 같은 backing-specific 표현이 직접 노출된다. 이로 인해 같은 추상 동작(예: "완료 신호 표시")이 매체 이름으로 산재해 기술되고, 향후 다른 backing을 채택할 가능성을 검토하기 전부터 한 backing의 어휘에 갇혀 있다.

둘째, 신호 검출 차원: 워커가 완료 시 발행하는 `[done]` prefix comment를 드라이버(`loop.sh`)가 안정적으로 검출하지 못한다. 0.2.1 헌법은 신호 매체를 comment prefix로 정의했지만 `loop.sh`는 워크트리의 `$WT/DONE` 파일을 체크하는 구 컨벤션 잔존 코드를 사용한다. 그 결과 워커가 매 이터마다 `[done]` comment를 발행하며 수렴해 있어도 드라이버는 이를 모르고 이터 상한(예: 30회)까지 회전하다 자동 `[blocked]` comment로 에스컬레이션된다. 같은 매체에서 발행·검출이 일치하지 않는 한, 이 부정합은 향후 다른 매체로 옮기더라도 반복될 위험이 있다.

두 측면은 한 뿌리에서 나온 증상이다 — 설계와 구현이 backing의 구체 어휘를 같은 자리에서 다루지 않아 매체 변경이 산발적으로 일어나고, 결국 사용자가 매번 부정합을 추적해 고쳐야 한다.

## 목표·비전

스킬 패키지 내 모든 설계 문서(헌법·SKILL.md·`references/*.md`)와 드라이버 코드(`loop.sh`·`pr-phase.sh`·`rebase-phase.sh`·`review-fix-phase.sh`·`cleanup-phase.sh`)가 task backing system을 **backing-neutral 추상 어휘**로 일관 기술한다. 그 추상에서 정의된 동작 — 예: "task에 label 추가", "task의 label 검색", "task status를 X로 전이" — 은 현 GitHub 구현 위에서 그대로 수행된다.

이 milestone은 추상 어휘 layer를 도입하되 **adapter 인터페이스를 신설하거나 다른 backing 구현을 추가하지 않는다**. 단일 GitHub 구현 위에 어휘 layer만 얹어 향후 다른 backing 검토 시 분기 지점을 명확히 한다.

신호 매체 차원에서는 완료 신호를 GitHub label(예: `loop:done`)로, 정지 신호를 GitHub Project Status field 전이(예: `Blocked`)로 단일화한다. 인간 가독·로그를 위한 `[done]`·`[blocked]` prefix comment는 양쪽 모두 함께 발행하되 드라이버 검출 키는 label·status에 단일 의존한다.

## 성공 기준

- 헌법·SKILL.md·`references/*.md`의 텍스트가 backing-neutral 어휘로 일관 기술되어, backing-specific section(예: 헌법의 "GitHub 구현 절" 같은 명시 영역) 외부에서는 "comment prefix", "gh issue body" 같은 구체 표현이 노출되지 않는다.
- `loop.sh`의 done 신호 검출이 GitHub label 검색(예: `loop:done`)으로 동작하고, blocked 신호 검출이 GitHub Project Status field(예: `Blocked`)로 동작한다. 두 신호 모두 가독·로그용 comment 발행은 유지하되 검출 키는 label·status에 단일 의존한다.
- 기존 `[done]`·`[blocked]` prefix comment 히스토리는 마이그레이션 없이 보존된다 — 본 milestone 이전에 발행된 comment는 그대로 남고, 본 milestone 이후 발행되는 신호부터만 새 매체로 전환된다.
- adapter 인터페이스·다른 backing 구현·`rules/context.md` 변경·산출물(SPEC.md·PRD.md·issue body 등) 자동 마이그레이션은 본 milestone에서 일어나지 않는다 (각 child SPEC도 동일).
- 자율 loop이 이 milestone의 child task를 처리할 때, 워커의 완료 발행과 드라이버의 검출이 일치해 이터 상한 도달 없이 정상 종료한다 — 본 milestone이 해결한 부정합이 child task 실행 자체에서 재현되지 않음을 입증.

## 범위

포함:

- `plugins/autopilot/skills/<skill>/SKILL.md` (spec·loop·prd·dispatch) 4개의 backing-neutral 어휘 재작성
- `plugins/autopilot/skills/loop/references/constitution.md`의 backing-neutral 어휘 재작성 — 특히 §11(이터간 컨텍스트 운영) 및 §5(정지)·§3.4(완료 판정)
- `plugins/autopilot/skills/loop/references/{loop,pr-phase,rebase-phase,review-fix-phase,cleanup-phase}.sh`의 backing 호출 식별·추상 헬퍼로 묶기 + done 신호 검출(comment 검색 → label 검색)·blocked 신호 검출(comment 검색 → Project Status field 조회) 교체
- 새 label name 고정 정의(예: `loop:done`)와 부재 시 자동 생성·재사용 로직
- `plugins/autopilot/skills/loop/references/{handoff,notes,plan,runlog,escalation}-template.md` 등 보조 문서에서 backing-specific 표현 정리 (없으면 무변경)

비-목표 / 제외:

- adapter/interface 신설 — 추상 어휘 layer는 텍스트 차원과 헬퍼 함수명 차원에서만 적용. 다중 구현을 분기하는 dispatcher는 만들지 않는다
- 다른 backing 구현(파일 기반·Linear·Jira 등) 추가
- `rules/context.md` 변경 — 본 프로젝트는 의도적으로 GitHub Project+Issue를 구체화로 채택했으므로 본 milestone의 어휘 추상화 대상에서 명시 제외
- 스킬 산출물(SPEC.md·PRD.md·issue body·기존 prefix comment 히스토리) 자동 마이그레이션
- `gh` CLI 의존 자체 제거 — 현 구현이 `gh`를 사용하는 사실 자체는 유지

## 제약

- 기존 `[done]`·`[blocked]` prefix comment 히스토리는 건들지 않음 — 소급 마이그레이션 없음. 본 milestone 이전 issue의 자동 완료 감지는 포기한다.
- done = label, blocked = Project Status. 양쪽 모두 가독·로그용 comment 발행은 유지하되 드라이버 검출 키는 label·status에 단일 의존한다.
- label name (예: `loop:done`)은 프로젝트 수준에서 고정하고, 드라이버가 부재 시 자동 생성·재사용한다. 사용자가 별도 입력하지 않아도 작동.
- Project Status field 명칭(예: `Blocked`)은 의존하되 변경 시 단일 위치에서 갱신 가능하도록 한 모듈에 집중.
- `feedback_no_self_apply_during_spec` 메모리 룰에 따라, 본 milestone의 어느 child SPEC도 *자신의 호출* 중 새 contract를 자신의 산출물에 선행 적용하지 않는다 — 새 동작은 다음 spec/loop 호출부터 적용된다.

## 위험

- **self-referential**: autopilot 자체를 소재로 child task를 돌리면 spec·loop이 자기 구현을 수정한다. 각 child SPEC에 `feedback_no_self_apply_during_spec`·`feedback_self_referential_verification` 메모리 룰을 명시해, 검증은 verify·worktree source만 보고 runtime artifact 직접 검사를 금지한다. 각 child loop의 자기 구현 호출 함정 차단.
- **adapter 유혹**: child 작업 중 "adapter 인터페이스를 만드는 게 깔끔해" 유혹으로 범위가 부풀려질 위험. PRD·child SPEC 각각에 "adapter 신설 금지" 비-목표를 명시. 코드 차원의 추상화는 헬퍼 함수명·매개변수 수준에서만 허용하고 다중 구현을 분기하는 dispatcher·인터페이스 객체는 만들지 않는다.

## 분해 힌트

(없음 — dispatch에 맡김)
