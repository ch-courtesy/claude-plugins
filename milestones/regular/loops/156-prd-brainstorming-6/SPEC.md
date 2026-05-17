---
scope:
  include:
    - "plugins/autopilot/skills/prd/**"
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; F=plugins/autopilot/skills/prd/SKILL.md; grep -qE \"(기본 ON|기본 활성화|무조건|mandatory)\" \"$F\"; grep -qE \"milestone.*(단위|적정성|fit)\" \"$F\"; grep -q \"YAGNI\" \"$F\"; grep -qE \"(단순|simple).*9단계|9단계.*스킵|스킵.*9단계\" \"$F\"; grep -qE \"(brownfield|동행 개선)\" \"$F\"; grep -q \"visual companion\" \"$F\"'"
ears_language: ko
---

# PRD 스킬에 brainstorming 탐색 규율 흡수 (6개 갭)

## 무엇을 만들 것인가

`autopilot:prd` 스킬에 `superpowers:brainstorming` 스킬이 갖고 있는 6가지 "탐색 규율" 게이트를 흡수해, PRD 호출만으로 milestone-level 탐색이 완결되도록 한다. 별도 brainstorming 호출 없이도 PRD가 충분히 깊게 의도·범위를 추궁한다.

흡수 대상 6개 갭:

1. **접근법 비교 기본 ON** — 현재 접근법 비교 단계가 "비-자명한 설계 결정 포함 시" 조건부 OPT-IN인 것을 뒤집어, **기본 활성화**(mandatory)로 만든다. 정말 trivial할 때만 명시적 OPT-OUT 사유와 함께 생략을 허용한다.

2. **milestone 단위 적정성 검사** — 명확화 라운드 직후 신설 단계에서 "이 milestone이 단일 PRD로 결착 가능한가, 아니면 더 쪼개야 하는가"를 1회 판정한다. 분해가 필요하다고 판정되면 사용자에게 milestone 분해를 제안하고 PRD 작성을 중단한다.

3. **YAGNI 강제 통과** — 목표·범위 섹션 합의 직후, 합의된 각 항목에 "정말 필요한가, 빼도 되는가"를 1회 강제 검토한다. 모든 항목을 한 번씩 거치는 게이트이며 우회 불가.

4. **"이건 너무 단순하다" 안티패턴 가드** — 본 스킬 본문에 "어떤 milestone도 9단계를 스킵하지 않는다"는 원칙을 명시 문구로 박는다. 별도 게이트 없이 텍스트 가드만으로 운영한다 — 모델이 "이건 작은 milestone이라 step X 생략" 합리화를 만들지 못하게 한다.

5. **Brownfield 통합 소프트 질문** — 컨텍스트 탐색 단계에서 "건드릴 코드에 동행 개선이 필요한가?"를 1회 선택 질문한다. 답변에 따라 범위 섹션에 자동 반영하되, 강제하지 않는다.

6. **Visual companion 입구** — 컨텍스트 탐색 직후 신설 단계로 visual companion offer 입구를 둔다. brainstorming의 visual-companion 메커니즘을 동일하게 복제해, UX·시각 콘텐츠가 무거운 milestone에 한해 사용자가 선택적으로 활성화할 수 있게 한다.

**흡수 *비*-대상** (의도적 제외): brainstorming의 architecture·components·data flow·testing 섹션 제시 — backing-neutral 추상화를 깨므로 PRD에 포함하지 않는다. 이런 설계 깊이는 `autopilot:dispatch` → `autopilot:spec` → `autopilot:loop`이 child SPEC에서 EARS로 정밀화할 영역이다.

## 수용 기준 (EARS)

- **AC1** (Ubiquitous): 시스템은 PRD SKILL.md의 접근법 비교 단계 설명에 `기본 ON`·`기본 활성화`·`무조건`·`mandatory` 중 하나의 문구와 OPT-OUT 조건을 함께 포함한다.

- **AC2** (Ubiquitous): 시스템은 PRD SKILL.md에 `milestone 단위`·`milestone 적정성`·`milestone-fit` 중 하나의 표현으로 식별되는 검사 단계를, 명확화 라운드 직후 위치에 둔다.

- **AC3** (Ubiquitous): 시스템은 PRD SKILL.md의 섹션 합의 단계에 `YAGNI` 키워드와 함께 강제 통과 의미의 문구(`강제`·`1회`·`각 항목` 중 하나 이상)를 둔다.

- **AC4** (Ubiquitous): 시스템은 PRD SKILL.md 본문에 "어떤 milestone도 9단계를 스킵하지 않는다" 의미의 anti-pattern 가드 문구를 둔다 — 정규식상 `(단순|simple).*9단계` 또는 `9단계.*스킵` 또는 `스킵.*9단계` 중 하나로 매칭된다.

- **AC5** (Ubiquitous): 시스템은 PRD SKILL.md의 컨텍스트 탐색 단계에 `brownfield` 또는 `동행 개선` 의미의 1회 선택 질문을 명시한다.

- **AC6** (Ubiquitous): 시스템은 PRD SKILL.md에 `visual companion` offer 입구 단계를 두고, brainstorming 스킬의 visual-companion 가이드를 참조하거나 동등 내용으로 포함한다.

## 범위

포함:
- `plugins/autopilot/skills/prd/SKILL.md` 갱신 — 6개 갭에 해당하는 단계·문구 추가
- 필요 시 `plugins/autopilot/skills/prd/references/` 하위 신규/참조 가이드 추가 (예: visual-companion 안내 파일 또는 brainstorming의 가이드 인용 링크)
- PRD 스킬 frontmatter `description` 갱신 — 탐색 규율 흡수 사실을 한 줄로 반영

비-목표 / 제외:
- `superpowers:brainstorming` 스킬 자체 수정·삭제 (기존 사용자 흐름 유지)
- `autopilot:dispatch`·`autopilot:spec`·`autopilot:loop` 등 sibling 스킬 변경
- PRD에 architecture·components·data flow·testing 등 *설계 깊이* 섹션 추가 (backing-neutral 추상화 위반)
- 기존 작성된 PRD.md 파일들의 마이그레이션·재작성
- 9단계 → N단계로의 전체 재번호화 (필요한 단계 신설은 `step N.5` 형식으로 삽입)

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```
bash -c 'set -e; F=plugins/autopilot/skills/prd/SKILL.md; \
  grep -qE "(기본 ON|기본 활성화|무조건|mandatory)" "$F"; \
  grep -qE "milestone.*(단위|적정성|fit)" "$F"; \
  grep -q "YAGNI" "$F"; \
  grep -qE "(단순|simple).*9단계|9단계.*스킵|스킵.*9단계" "$F"; \
  grep -qE "(brownfield|동행 개선)" "$F"; \
  grep -q "visual companion" "$F"'
```

## 제약 (있을 때만)

- **Backing-neutral 추상화 유지**: PRD는 백엔드(GitHub Issues 등) 구체 어휘를 직접 쓰지 않는다. 6개 갭 흡수가 이 추상화를 깨면 안 된다. 백엔드 매핑이 필요한 항목은 `rules/context.md` 참조로 위임한다.

- **Self-referential 적용 금지**: 본 SPEC가 정의하는 PRD 갱신 contract를 본 SPEC의 작성·검토 단계에서 PRD 스킬 본문에 미리 적용하지 않는다. PRD는 본 SPEC를 입력받은 별도 loop 호출에서만 갱신된다.

- **dispatch 분해 호환성**: 갭 #2(milestone 단위 적정성 검사)가 dispatch의 PRD→child SPEC 분해 단계와 *사용자 인터랙션이 중복되지 않게* 한다. PRD의 milestone-fit은 "현재 milestone-id가 단일 PRD로 결착 가능한가" 한 질문으로 좁히고, child SPEC 단위 분해는 dispatch가 담당한다.

- **frontmatter 호환**: PRD 스킬 frontmatter 갱신은 description 한 줄에 한정한다. 기존 `name` 등 다른 필드는 건드리지 않는다.

## 위험 (있을 때만)

- **갭 #6 visual companion 무게**: 본 레포는 주로 CLI/skill 변경이라 visual companion 효용이 낮다. "기능은 있으나 거의 안 쓰이는" 데드기능 위험. 향후 사용 빈도가 낮으면 후행 SPEC에서 간소화·제거 가능성 열어둠.

- **갭 #2 milestone-fit과 dispatch 중복 경험**: PRD에서 한 번, dispatch에서 또 분해 — 사용자가 "같은 질문 두 번" 느낌을 받을 수 있다. PRD의 milestone-fit은 *PRD 자체 결착 가능성*만 보고, dispatch의 분해는 *child SPEC 단위*만 본다는 책임 분리를 본문에 명시해야 한다.

- **검증 keyword 매칭 취약성**: grep 기반 verify는 키워드 존재만 보므로 의미상 약한 문구로도 통과 가능하다. EARS AC가 "있으면 PASS" 수준이라 실제 행동 변화를 보장하지 못한다. 보완: 본 SPEC loop 완료 후 fixture milestone 1건으로 실제 PRD 호출을 돌려 6개 갭이 모두 살아 있는지 수동 확인.

- **brainstorming 진화 동기화**: brainstorming 스킬이 향후 자체 진화하면 PRD가 흡수한 6갭이 stale해질 수 있다. 본 SPEC는 1회 흡수만 책임 — 지속 동기화는 별도 운영 책임 영역.
