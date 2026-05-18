---
scope:
  include: ["plugins/autopilot/skills/spec/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "grep -E '^request_review:[[:space:]]*true' plugins/autopilot/skills/spec/references/spec-template.md && bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh"
---

# Spec template: request_review on by default

## 무엇을 만들 것인가

spec 스킬의 SPEC 템플릿이 새로 생성되는 SPEC.md frontmatter에 `request_review` 키를 기본값 `true`로 명시한다. 이전 동작 — 키 자체가 주석 처리된 채 노출되어 사용자가 의도적으로 해제해야 활성화되던 — 을 뒤집어, 새 SPEC은 default로 PR 자동 리뷰·머지 루프(`review-fix-phase` + auto-merge + cleanup)에 진입한다. 사용자가 자동 흐름을 끄려면 SPEC frontmatter에 `request_review: false`를 명시적으로 적는다. 본 변경은 새로 생성되는 SPEC에만 적용되며, 이미 작성된 기존 SPEC들과 loop 스크립트의 fallback 동작은 그대로 둔다.

## 수용 기준 (EARS)

- **AC1** (Event-driven): spec 스킬이 새 SPEC.md를 작성할 때, 시스템은 frontmatter에 `request_review: true`를 명시적 키로 박는다.
- **AC2** (Optional): 사용자가 SPEC frontmatter를 `request_review: false`로 변경한 경우, loop은 review-fix·auto-merge·cleanup 흐름에 진입하지 않는다.
- **AC3** (Ubiquitous): 본 변경 이전에 생성된 기존 SPEC.md 파일들은 frontmatter가 그대로 보존되며 행동이 변경되지 않는다.
- **AC4** (Ubiquitous): loop 스크립트의 yq fallback 표현(키 부재 시 `false`)은 변경되지 않으며, 명시 안 한 SPEC은 이전과 동일하게 비활성으로 처리된다.

## 범위

포함:

- `plugins/autopilot/skills/spec/references/spec-template.md` — frontmatter `request_review: true` 주석 해제·명시 + 안내 주석 갱신 (default 의미 변경 반영)

비-목표 / 제외:

- `plugins/autopilot/skills/loop/references/loop.sh` — yq fallback 변경 안 함
- `plugins/autopilot/skills/loop/SKILL.md` 안내 갱신 (별도 SPEC)
- `plugins/autopilot/skills/spec/SKILL.md` 안내 갱신 (별도 SPEC)
- 기존 `milestones/.../SPEC.md` retroactive 변경 — 보존
- 이미 명시적 `request_review: true`를 가진 선례 SPEC들 — 그대로 (변경될 입장 아님)

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
grep -E '^request_review:[[:space:]]*true' plugins/autopilot/skills/spec/references/spec-template.md && \
bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh
```

- grep 0 exit → template frontmatter에 명시적 `request_review: true` 존재 (AC1)
- contract verifier 0 exit → spec↔loop 계약 파괴 없음 (AC3·AC4 근거)

## 제약

- 변경은 `spec-template.md` 단일 파일 — 다른 스크립트·문서는 손대지 않음.
- spec 스킬 step 8은 template을 readout·placeholder 치환만 수행하므로 frontmatter 키 추가만으로 새 SPEC에 자동 반영.
- `loop.sh`의 yq fallback(`// false`) 그대로 — 명시 안 한 SPEC은 비활성 유지.
- bash 4 · yq 기존 가정 동일.

## 위험

- spec SKILL.md·loop SKILL.md 안내 ("`request_review: true` 지정된 task만 진입")가 stale이 됨 — 별도 SPEC으로 갱신 권장.
- 사용자가 새 SPEC을 무의식 생성해도 default로 review-fix 루프가 진행·auto-merge 대기 — 단 자동 머지 트리거는 명시적 신호(승인·`/done`·합격·통과)이 필요해 무의도 머지 확률 낮음.
- 이미 명시 `request_review: true`를 가진 기존 SPEC들과 default true의 동작은 동일 — 충돌 없음.
- 본 SPEC 자체의 SPEC.md가 main에 ff-merge·push되는 시점에 새 default가 적용될 수 있음 (self-referential — spec 자체도 그 시점부터 새 default 템플릿 사용).
