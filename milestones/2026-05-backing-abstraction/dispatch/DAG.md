# DAG — 2026-05-backing-abstraction

`milestones/2026-05-backing-abstraction/prd/PRD.md`의 분해 결과. dispatch가 게이트 ① 승인 후 작성.

생성 시각: 2026-05-16T02:50Z

## 단위 목록

- child-a: constitution.md backing-neutral 어휘 재작성
  - 영향 파일: plugins/autopilot/skills/loop/references/constitution.md
  - verify: backing-specific terms grep (comment prefix·issue body·Project Status 등)이 backing-specific section 외부에서 0
  - 의존성: 없음
- child-b: SKILL.md 4개(spec·loop·prd·dispatch) backing-neutral 어휘 재작성
  - 영향 파일: plugins/autopilot/skills/spec/SKILL.md, plugins/autopilot/skills/loop/SKILL.md, plugins/autopilot/skills/prd/SKILL.md, plugins/autopilot/skills/dispatch/SKILL.md
  - verify: 4개 파일 backing-specific terms grep
  - 의존성: child-a (헌법 어휘 차용)
- child-c: loop.sh의 done·blocked 신호 검출·발행 매체 교체 + label name 자동 관리
  - 영향 파일: plugins/autopilot/skills/loop/references/loop.sh
  - verify: comment-based detect 코드 부재(last_prefix·prefix comment 검색 코드 없음) + 새 추상 헬퍼 함수 grep + label name 자동 생성·재사용 로직 확인
  - 의존성: child-a (헌법 어휘 차용)
- child-d: references 보조 .md(operational-guide·troubleshooting·status-format·agent-prompts) 잔존 표현 정리
  - 영향 파일: plugins/autopilot/skills/loop/references/operational-guide.md, plugins/autopilot/skills/loop/references/troubleshooting.md, plugins/autopilot/skills/loop/references/status-format.md, plugins/autopilot/skills/loop/references/agent-prompts.md
  - verify: 4개 파일 backing-specific terms grep
  - 의존성: child-a (헌법 어휘 차용)

## 의존성·wave 정렬

- wave 1 (정의 선행): [child-a]
- wave 2 (depends on wave 1, parallel-safe): [child-b, child-c, child-d]

## 메모

phase script들(pr-phase·rebase-phase·review-fix-phase·cleanup-phase)은 task storage 호출이 없고 git/PR/cleanup workflow에 한정되어 본 milestone scope 외로 판단해 child 단위에서 제외. 향후 별도 milestone에서 다룰 수 있다.

격리성 확보: wave 2의 3 child는 각각 다른 파일군(SKILL.md / loop.sh / 보조 .md)을 수정해 동시 실행 시 충돌 없음. wave 1의 child-a 산출물(헌법 본문에 정의된 추상 어휘)은 wave 2의 입력 컨텍스트로만 차용되고 파일 동시 수정은 일어나지 않는다.

self-referential 위험 대응: 각 child SPEC 작성 단계에서 `feedback_no_self_apply_during_spec` 메모리 룰 명시 — 현재 호출은 contract 선행 적용 금지. adapter 유혹 차단: 각 child SPEC의 비-목표에 "adapter 신설 금지" 명시.
