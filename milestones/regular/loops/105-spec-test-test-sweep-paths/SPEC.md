---
scope:
  include: ["plugins/autopilot/skills/spec/**", "tests/autopilot/test-spec-skill.sh"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-spec-skill.sh"
---

# spec 스킬에 test 코드 변경 감지·test_sweep_paths 자동 설정 절차 추가

## 무엇을 만들 것인가
spec 스킬 워크플로의 명확화 라운드에 "task scope가 test 코드 변경(rename·cleanup·삭제·내용 수정 등)을 포함하는지 자동 판단 → 포함 시 화이트리스트 경로 추출 → 사용자 단발 yes/no 확인 → SPEC frontmatter의 `test_sweep_paths` 필드에 기록" 절차를 추가한다. 판단 결과 "변경 없음"이면 새 prompt가 등장하지 않고 frontmatter에 `test_sweep_paths` 키를 추가하지 않는다. 자체 검토 단계는 이 절차가 누락되지 않도록 5축 체크에 검사 항목을 한 개 추가한다.

## 수용 기준 (EARS)
- **AC1 (Event-driven)**: 사용자가 spec 스킬을 호출해 명확화 라운드 마지막에 도달할 때, 시스템은 수집된 scope·의도로 task가 test 코드 변경(rename·cleanup·삭제·내용 수정 등)을 포함하는지 자동 판단한다.
- **AC2 (Optional)**: 자동 판단이 "test 변경 포함"으로 난 경우, 시스템은 sweep 화이트리스트 후보 경로를 추출해 사용자에게 단발 yes/no로 확인을 요청한다.
- **AC3 (Optional)**: 사용자가 "yes"로 응답한 경우, 시스템은 후보 경로를 SPEC frontmatter의 `test_sweep_paths` 필드에 기록한다.
- **AC4 (Unwanted/조건)**: 자동 판단이 "test 변경 없음"이면, 시스템은 명확화·승인 단계에 추가 prompt를 노출하지 않으며 SPEC frontmatter에 `test_sweep_paths` 키를 추가하지 않는다.
- **AC5 (Ubiquitous)**: 시스템은 spec 자체 검토(step 9) 5축 체크에 "task scope가 test 코드 변경을 포함하면 frontmatter의 `test_sweep_paths` 필드가 비어 있지 않다" 검사 항목을 포함한다.
- **AC6 (Ubiquitous)**: `bash tests/autopilot/test-spec-skill.sh`는 (a) test 변경 포함 SPEC 생성 시 `test_sweep_paths`가 frontmatter에 채워졌음을 검증하고 (b) test 변경 없는 SPEC 생성 시 새 prompt 미발동·frontmatter 키 부재를 검증하는 두 케이스를 포함해 0 exit으로 끝난다.

## 범위
포함:
- `plugins/autopilot/skills/spec/SKILL.md` — step 5 명확화 라운드 끝에 자동 판단·yes/no 단발 확인 절차 추가, step 8 SPEC.md 치환 룰에 frontmatter `test_sweep_paths` 키 처리 명세 추가.
- `plugins/autopilot/skills/spec/references/spec-template.md` — `{{test_sweep_paths}}` placeholder 정의·고정 frontmatter active 영역 위치 결정. 기존 commented `# test_sweep_paths:`·`# test_paths:` 예시 블록은 보존.
- `plugins/autopilot/skills/spec/references/self-review.md` — 5축 체크 항목에 "scope에 test 코드 변경 포함 시 `test_sweep_paths` 필드가 비어 있지 않다" 검사 추가.
- `tests/autopilot/test-spec-skill.sh` — (a) test 변경 포함 SPEC 생성 케이스, (b) test 변경 없는 SPEC 생성 케이스 두 케이스 추가.

비-목표 / 제외:
- `test_paths` 필드 자동 채움 — 본 SPEC은 `test_sweep_paths`에 한정.
- loop 스킬·tester·tester-runner의 테스트 약화 게이트 로직 변경.
- 기존 SPEC들의 retroactive 갱신·migration.
- self-referential — 본 SPEC를 작성하는 *현 호출*에 새 contract를 선행 적용 (메모리 `feedback_no_self_apply_during_spec`).
- spec-template.md의 기존 commented `# test_paths:`·`# test_sweep_paths:` 예시 블록 교체·삭제 (문서적 가치 유지를 위해 보존).

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash tests/autopilot/test-spec-skill.sh
```

## 제약 (있을 때만)
- spec 스킬은 self-referential. `feedback_no_self_apply_during_spec` 메모리 규약에 따라 본 SPEC를 작성하는 *현 호출*에는 새 contract를 선행 적용하지 않으며, 새 동작은 본 SPEC이 default 브랜치에 merge된 후의 다음 spec 호출부터 적용된다.
- `spec-template.md`의 기존 commented `# test_sweep_paths:`·`# test_paths:` 예시 블록은 문서적 가치 유지를 위해 보존한다. 새 placeholder는 commented 블록과 별도로 frontmatter active 영역에 정의한다.
- 모델의 "test 변경 포함" 자동 판단은 휴리스틱이므로 위양성·위음성 가능. 사용자 단발 yes/no 확인이 안전망 역할을 한다.
- 검증 명령 `bash tests/autopilot/test-spec-skill.sh`는 spec 워크플로의 interactive 입력을 mock·fixture로 자동화하거나, SKILL.md·template·self-review.md의 구조적 점검(grep)으로 대체해야 한다 — 실제 spec 호출은 `AskUserQuestion` 의존이라 bash 환경에서 자동화 불가.

## 위험 (있을 때만)
- **모델 위양성** (실제 test 변경 없는데 prompt 발동): 사용자 단발 yes/no에서 거부로 처리. 마찰 추가되나 단일 질문이라 미미.
- **모델 위음성** (실제 test 변경 있는데 prompt 누락): self-review 5축 체크가 catch. 그러나 self-review도 LLM 휴리스틱이라 완전 보장 아님.
- **spec-template.md placeholder 치환·YAML 파싱 충돌**: 빈 값 시 출력 형태(`[]` 또는 키 생략)에 따라 yq 파싱 실패 가능. 기존 commented 예시와 충돌 없도록 frontmatter active 영역 위치 결정 필요.
- **dogfooding fixture 난이도**: spec 워크플로가 AskUserQuestion 의존이라 실제 호출 자동화 곤란. 정적 grep 교차로 fallback 가능하나 runtime 검증력 약화.
