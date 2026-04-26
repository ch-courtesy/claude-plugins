# 지침을 플러그인 생성기 스킬로 전환 (계획)

**상태**: 완료 (2026-04-23)
**작성일**: 2026-04-23 (최초) / 2026-04-23 방향 재조정

## 확정된 방향

- **구조**: 각 지침을 플러그인 내부의 **생성기 스킬**로 구현.
  - 경로: `plugins/project-init/skills/<scope>-rule-creator/SKILL.md`
  - 역할: 스킬 자체가 "지침 파일을 프로젝트에 맞게 생성"하는 생성기.
- **출력 위치**: `rules/<category>.md` (일반 markdown 문서).
- **`bootstrap` 스킬** (네임스페이스: `project-init:bootstrap`): 오케스트레이터. `CLAUDE.md` 생성 + 사용자가 선택한 카테고리의 생성기 호출. 카테고리 목록은 런타임에 형제 `*-rule-creator`에서 도출.
- **`domain` 카테고리**: 메타 지침만 `rules/domain.md`로 생성. 주제별 내용은 `rules/domain/` 하위에 수동 작성(자동 생성하지 않음).

## 배경 / 의사결정 흐름

초기 안은 "템플릿을 프로젝트 루트의 `.claude/skills/`로 복사"하는 방식이었으나, 사용자가 의도한 것은 **플러그인 내부에 지침 생성기 스킬**을 두는 구조였음. 생성기 스킬은 프로젝트 컨텍스트를 스캔해 맞춤 지침을 `rules/`에 작성함.

## 적용된 변경

- `plugins/project-init/skills/` 아래에 11개 생성기 스킬 디렉토리 추가:
  - `filesystem-rule-creator/`, `git-rule-creator/`, `bash-rule-creator/`, `sandbox-rule-creator/`, `meta-rule-creator/`, `search-rule-creator/`, `context-rule-creator/`, `autonomous-loop-rule-creator/`, `domain-rule-creator/`, `engineering-rule-creator/`, `security-rule-creator/`
  - 각 디렉토리에 `SKILL.md` 하나씩. 구조:
    - frontmatter: 생성기용 `name`/`description`
    - 상단: "생성 절차"(프로젝트 스캔 → 내용 구성 → 파일 기록)
    - 구분선 이후: 베이스 지침 본문(원래 템플릿 내용)
- 기존 `plugins/project-init/skills/project-init/templates/` 디렉토리 삭제.
- `plugins/project-init/skills/bootstrap/SKILL.md`를 오케스트레이터로 재작성 (초기 경로는 `skills/project-init/`이었으나 네임스페이스 중복 해소를 위해 `bootstrap`으로 리네임 — 2026-04-25, 검증 §1 참조):
  - 자신이 만드는 파일은 `CLAUDE.md` 하나.
  - 지침 파일(`rules/<category>.md`) 생성은 각 형제 생성기 스킬에 위임.
  - 카테고리 목록은 런타임에 형제 `*-rule-creator`에서 도출 (하드코딩 없음).

## 파일 구조 (최종)

```
plugins/project-init/
├── .claude-plugin/plugin.json
└── skills/
    ├── bootstrap/SKILL.md                        # 오케스트레이터
    ├── filesystem-rule-creator/SKILL.md            # 생성기
    ├── git-rule-creator/SKILL.md
    ├── bash-rule-creator/SKILL.md
    ├── sandbox-rule-creator/SKILL.md
    ├── meta-rule-creator/SKILL.md
    ├── search-rule-creator/SKILL.md
    ├── context-rule-creator/SKILL.md
    ├── autonomous-loop-rule-creator/SKILL.md
    ├── domain-rule-creator/SKILL.md
    ├── engineering-rule-creator/SKILL.md
    └── security-rule-creator/SKILL.md
```

## 검증 (2026-04-25)

### 수행한 테스트 및 조치

1. **플러그인 설치 경로** — `/plugin marketplace add` → `/plugin install` → `/reload-plugins` 흐름 통과.
   - 발견: 플러그인명과 오케스트레이터 스킬명이 동일(`project-init:project-init`)하여 네임스페이스 중복.
   - 조치: 오케스트레이터 스킬을 `bootstrap`으로 리네임 (네임스페이스 `project-init:bootstrap`).

2. **명시적 의도로 트리거** — "새 프로젝트 초기화해줘" 입력 시 `project-init:bootstrap` 호출. 통과.

3. **모호한 입력의 선제 제안** — "안녕?" 같은 일반 인사에는 bootstrap 제안 없음.
   - 판정: description 기반 활성화의 구조적 한계. 현재는 수용. 결정적 트리거가 필요해지면 `SessionStart` 훅 도입 검토 (미구현).

4. **기존 초기화 흔적 처리 UX** — `CLAUDE.md` + 일부 `rules/*.md`가 있는 상태에서 실행.
   - 관찰: Claude가 3옵션(`남은 카테고리 중 선택해서 추가` / `전부 다시 검토` / `중단`)으로 `AskUserQuestion` 발행.
   - 조치: 1단계 스펙에 3옵션을 명시적으로 고정 (Claude 즉흥 해석에서 결정적 동작으로).

5. **"남은 카테고리 중 선택해서 추가" 옵션 동작** — 초기에는 남은 집합을 전부 자동 호출.
   - 조치: 3단계의 선택 플로우(`전체 생성` / `일부만 선택`)를 남은 집합에 적용하도록 스펙 수정.

6. **`AskUserQuestion` 스키마 위반 (`Invalid tool parameters`)** — 5개 옵션을 한 `multiSelect` 질문에 올림 → `options.maxItems: 4` 위반.
   - 조치: 3단계 문구 강화 — "각 `multiSelect` 질문에 최대 4개, 초과 시 반드시 여러 질문으로 분할. 한 호출당 최대 4질문(16옵션), 초과 시 여러 호출로 분할".

7. **남은 집합이 비어 있을 때** — 11개 `rules/*.md`가 이미 모두 존재.
   - 관찰: 옵션 1 "남은 카테고리 중 선택해서 추가"가 `실행할 작업 없음` 상태로 그대로 노출.
   - 조치: 남은 집합이 비면 2옵션(`중단 (Recommended)` / `전부 다시 검토`)로 축소하도록 스펙 수정.

8. **생성기 스킬 개별 호출 격리성** — 사용자 지시로 특정 생성기만 호출 시 해당 파일만 갱신하고 다른 파일은 건드리지 않는지. 통과 (예: "bash 지침 만들어줘" → `bash-rule-creator`만 발동).

9. **`domain` 카테고리 범위** — 메타 지침만 `rules/domain.md`에 생성하고 `rules/domain/` 하위 주제별 파일은 자동 생성하지 않는지. 통과.

10. **기존 파일 덮어쓰기 방지 (diff 확인 절차)** — 기존 `rules/<category>.md`와 스킬 기본 내용의 차이를 diff로 보여준 뒤 사용자 확인을 받는지. 통과 (예: `bash-rule-creator`가 기존 파일의 변경점을 `+`/`-` 포맷으로 출력 후 확인 프롬프트 발행).

## 남은 고민 (운영 중 정리)

_(없음)_
