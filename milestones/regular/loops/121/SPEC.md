---
scope:
  include: ["plugins/project-init/skills/engineering-rule-creator/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "test -f plugins/project-init/skills/engineering-rule-creator/SKILL.md && test -f plugins/project-init/skills/engineering-rule-creator/templates/versioning.md && grep -q SemVer plugins/project-init/skills/engineering-rule-creator/templates/versioning.md && grep -q CalVer plugins/project-init/skills/engineering-rule-creator/templates/versioning.md && grep -q ZeroVer plugins/project-init/skills/engineering-rule-creator/templates/versioning.md && grep -q '자유' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md && grep -qE 'SoT|source_of_truth|단일 출처' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md && grep -qiE 'changelog|변경 기록' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md && grep -qiE 'watch|워치' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md && grep -qE '기본 브랜치|default branch|머지' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md && grep -q node_modules plugins/project-init/skills/engineering-rule-creator/SKILL.md && grep -qE 'maxdepth 1|depth=1|최상위' plugins/project-init/skills/engineering-rule-creator/SKILL.md && grep -qE '단일 파일|단일파일' plugins/project-init/skills/engineering-rule-creator/SKILL.md && grep -qE '덮어쓰' plugins/project-init/skills/engineering-rule-creator/SKILL.md"
ears_language: ko
request_review: true
---

# engineering-rule-creator/versioning 재설계 — 정책 조합·워치 디렉토리·머지 강제 버전업

## 무엇을 만들 것인가

engineering-rule-creator 스킬을 재설계해, 새 프로젝트 초기화 흐름에서 사용자에게 더 풍부한
버전 관리 입력을 받아 더 강한 단일 버전 관리 룰 문서를 산출하게 한다.

사용자에게 묻는 핵심 입력은 다음 네 가지다:

1. **버전 정책**: 사전 정의된 표준 후보(SemVer · CalVer · ZeroVer) 중 하나를 단일 선택하거나,
   "자유 입력" 탈출구로 프로젝트 고유의 정책을 자유 텍스트로 정의한다.
2. **버전의 단일 출처 (SoT)**: 버전 값이 어디에 기록되는가 (예: 패키지 매니페스트 · git tag · 전용 파일).
3. **변경 기록 위치 (Changelog)**: 변경 로그를 어디에 누적하는가.
4. **워치 디렉토리**: 변경이 발생하면 *반드시* 버전이 올라가야 하는 디렉토리 목록.
   skill은 자동으로 후보를 제시하고, 사용자가 multi-select로 고르거나 자유 입력으로
   추가할 수 있다.

산출되는 룰 문서는 위 네 입력을 본문으로 가지며, 추가로 다음 고정 강제 문구를
반드시 포함한다:

> "기본 브랜치(예: main)에 머지될 때, 워치 디렉토리에 변경이 있었다면
>  반드시 그 머지 안에서 버전이 올라가야 한다."

세부 위반 대응(차단·경고·hotfix 등)은 프로젝트가 별도로 정한다. 본 룰은 강제
규칙 자체만을 명세하며, 자동 감지 메커니즘(CI · git hook · PR check)은 본 task의
범위 밖이다.

## 수용 기준 (EARS)

1. (Event-driven) 사용자가 engineering-rule-creator 스킬을 호출하면,
   시스템은 버전 정책 후보(SemVer · CalVer · ZeroVer · 자유 입력) single-select
   질문을 가장 먼저 제시한다.

2. (Event-driven) 사용자가 정책 단계에서 "자유 입력"을 선택하면,
   시스템은 자유 텍스트 입력을 받아 그 값을 산출 룰 본문의 정책
   필드에 그대로 기록한다.

3. (Ubiquitous) 시스템은 버전의 단일 출처(SoT)를 묻는 질문을 사용자에게
   제시한다.

4. (Ubiquitous) 시스템은 변경 기록(Changelog) 위치를 묻는 질문을 사용자에게
   제시한다.

5. (Event-driven) 사용자가 워치 디렉토리 입력 단계에 진입하면,
   시스템은 target 프로젝트 루트의 depth=1 디렉토리 중
   `.*` · `node_modules` · `dist` · `build` · `target`을 제외한 목록을
   자동 후보로 제시한다.

6. (Optional) 사용자에게 자유 입력 탈출구가 제공되면, 사용자는
   자동 후보 외의 디렉토리·글로브 패턴을 워치 목록에 추가할 수 있다.

7. (Ubiquitous) 산출된 `rules/engineering/versioning.md`는 다음 고정 문구를
   본문에 포함한다 — "기본 브랜치에 머지될 때, 워치 디렉토리에
   변경이 있었다면 반드시 그 머지 안에서 버전이 올라가야 한다."

8. (Unwanted) target에 `rules/engineering/versioning.md`가 이미 존재하고
   사용자의 명시적 덮어쓰기 동의가 없으면, 시스템은 기존 파일을
   보존하고 덮어쓰지 않는다.

9. (State-driven) 본 스킬이 실행 중인 동안, 시스템은 target 프로젝트의
   `rules/engineering/versioning.md` 외 다른 파일을 만지지 않는다.

## 범위

포함:
- `plugins/project-init/skills/engineering-rule-creator/SKILL.md` 갱신 —
  자동 워치 후보 탐색(depth=1, exclude `.*`·`node_modules`·`dist`·`build`·`target`),
  정책 단계 자유 입력 탈출구 처리, 워치 디렉토리 자유 입력 처리
  등 확장된 입력 수집 흐름 문서화.
- `plugins/project-init/skills/engineering-rule-creator/templates/versioning.md` 완전 재설계 —
  inputs(정책·SoT·changelog·워치 디렉토리) + 본문 섹션 + 고정 머지
  강제 문구.

비-목표 / 제외:
- 다른 engineering sub-룰(testing · linting · dependency · security 등).
- 자동 감지 메커니즘 (CI · git hook · PR check · GitHub Action 설치/생성).
- target 프로젝트의 실제 `rules/engineering/versioning.md` 산출과 그 검증 —
  본 task는 메타 skill·템플릿 갱신만 담당.
- 형제 스킬 갱신(context-rule-creator · orchestration-rule-creator).
- bootstrap SKILL.md 위임 흐름 — #102에서 이미 통합 완료.
- 이 저장소 자체의 `rules/`·`milestones/`·`CLAUDE.md` (default exclude).

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```bash
test -f plugins/project-init/skills/engineering-rule-creator/SKILL.md \
 && test -f plugins/project-init/skills/engineering-rule-creator/templates/versioning.md \
 && grep -q SemVer  plugins/project-init/skills/engineering-rule-creator/templates/versioning.md \
 && grep -q CalVer  plugins/project-init/skills/engineering-rule-creator/templates/versioning.md \
 && grep -q ZeroVer plugins/project-init/skills/engineering-rule-creator/templates/versioning.md \
 && grep -q '자유' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md \
 && grep -qE 'SoT|source_of_truth|단일 출처' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md \
 && grep -qiE 'changelog|변경 기록' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md \
 && grep -qiE 'watch|워치' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md \
 && grep -qE '기본 브랜치|default branch|머지' plugins/project-init/skills/engineering-rule-creator/templates/versioning.md \
 && grep -q node_modules plugins/project-init/skills/engineering-rule-creator/SKILL.md \
 && grep -qE 'maxdepth 1|depth=1|최상위' plugins/project-init/skills/engineering-rule-creator/SKILL.md \
 && grep -qE '단일 파일|단일파일' plugins/project-init/skills/engineering-rule-creator/SKILL.md \
 && grep -qE '덮어쓰' plugins/project-init/skills/engineering-rule-creator/SKILL.md
```

## 제약
- 구현 장소: 이 저장소의 `plugins/project-init/skills/engineering-rule-creator/`.
  아티팩트 = SKILL.md (디스패처) + templates/versioning.md (템플릿).
- 타 파일은 만지지 않는다. 특히 형제 스킬·bootstrap·이 레포의 `rules/`·`milestones/`.
- 기존 #102 템플릿 구조는 완전 재설계 허용 (사용자 합의).
- 정책 후보 최소 세트: SemVer / CalVer / ZeroVer / 자유 입력.
- 워치 자동 후보 규칙: depth=1, exclude `.*` · `node_modules` · `dist` · `build` · `target`.
- 워치 탐색 도구: POSIX find/ls 기반 (gitignore 존중 불필요).

## 위험
- **자기참조 검증 금지**: 본 task는 다른 스킬을 갱신하므로 워커의 driver
  자체를 만지지 않는다 (feedback_self_referential_verification 원칙).
  verify 명령은 정적 grep으로만 구성한다 — skill의 런타임 실행 결과를
  궁극 증거로 삼지 않는다.
- **YAML frontmatter 자동 접근 한계**: 자유 입력 탈출구·자동 워치 후보는
  템플릿 inputs frontmatter만으론 표현하기 부족할 수 있다. 필요 시
  SKILL.md 자연어 절차에 명시해 LLM이 동적으로 처리하게 한다.
- **덮어쓰기 함정**: target에 기존 versioning.md가 있을 때 동의 없이
  덮어쓰면 사용자의 기존 규칙이 손실된다 (#102에서 동일 함정).
