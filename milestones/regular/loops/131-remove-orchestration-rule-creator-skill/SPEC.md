---
scope:
  include: ["plugins/project-init/skills/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: '[ ! -d plugins/project-init/skills/orchestration-rule-creator ] && ! grep -rq "orchestration-rule-creator" plugins/project-init/ && ! grep -q orchestration plugins/project-init/skills/bootstrap/SKILL.md && git diff --quiet main -- plugins/project-init/skills/context-rule-creator/ && [ "$(git diff main -- plugins/project-init/skills/engineering-rule-creator/ | grep ''^+[^+]'' | grep -c ''orchestration-rule-creator'')" = "0" ] && jq -e ''.name == "project-init"'' plugins/project-init/.claude-plugin/plugin.json > /dev/null'
ears_language: ko
---

# Remove orchestration-rule-creator skill

## 무엇을 만들 것인가
project-init 플러그인에서 `orchestration-rule-creator` 스킬을 자원 카탈로그에서 제거한다. 플러그인의 활성 카탈로그에 해당 스킬이 더 이상 나타나지 않고, 형제 스킬(`context-rule-creator`, `engineering-rule-creator`)의 호출 가능성·동작은 영향을 받지 않는다. bootstrap 흐름을 거치는 사용자에게 orchestration 카테고리 관련 자동 생성 경로·예시·언급이 일관되게 부재한 상태가 보장된다.

## 수용 기준 (EARS)
- **AC-1**: 제거 작업이 완료된 상태에서 `plugins/project-init/skills/`를 조회하면, 디렉터리 목록에 `orchestration-rule-creator`가 포함되지 않아야 한다.
- **AC-2**: 제거 작업이 완료된 상태에서 `plugins/project-init/` 하위에서 `orchestration-rule-creator` 문자열을 검색하면, 일치 건수가 0건이어야 한다.
- **AC-3**: 제거 작업이 완료된 상태에서 `plugins/project-init/skills/bootstrap/SKILL.md`를 검토하면, orchestration 카테고리가 형제 카테고리 예시·자동 생성 경로에서 언급되지 않아야 한다.
- **AC-4**: 제거 작업 중인 동안, `plugins/project-init/skills/context-rule-creator/` 디렉터리의 파일 내용은 변경되지 않아야 한다.
- **AC-5**: 제거 작업 중인 동안, `plugins/project-init/skills/engineering-rule-creator/` 디렉터리의 변경 사항은 `orchestration-rule-creator` 상호 참조 제거에만 국한되어야 한다.
- **AC-6**: 제거 작업이 완료된 상태에서 project-init 플러그인의 meta(plugin name·디렉터리 경로)를 조회하면, 변경 전 값과 동일해야 한다.

## 범위
포함:
- `plugins/project-init/skills/orchestration-rule-creator/` 디렉터리 전체(SKILL.md·references·기타 모든 자원) 삭제
- `plugins/project-init/skills/bootstrap/SKILL.md` 내 orchestration 카테고리 언급 제거·수정
- `plugins/project-init/skills/engineering-rule-creator/SKILL.md` 내 `orchestration-rule-creator` 상호 참조 제거
- 플러그인 메타에 명시적 skill 목록이 존재하면 그 항목 갱신

비-목표 / 제외:
- 다른 플러그인(autopilot·superpowers·context-mode 등) 수정
- `rules/`·`milestones/`·`CLAUDE.md` 수정
- context-rule-creator·engineering-rule-creator의 동작·디자인 변경 (`orchestration-rule-creator` 상호 참조 제거 외)
- project-init 플러그인의 버전 식별자 변경(version bump)
- 새로운 형제 스킬 추가·기존 카테고리 재정의

## 검증
이 명령이 0 exit으로 끝나야 합니다 (모든 AC를 단일 verify에서 자동 검증):

```bash
[ ! -d plugins/project-init/skills/orchestration-rule-creator ] && \
  ! grep -rq "orchestration-rule-creator" plugins/project-init/ && \
  ! grep -q orchestration plugins/project-init/skills/bootstrap/SKILL.md && \
  git diff --quiet main -- plugins/project-init/skills/context-rule-creator/ && \
  [ "$(git diff main -- plugins/project-init/skills/engineering-rule-creator/ | grep '^+[^+]' | grep -c 'orchestration-rule-creator')" = "0" ] && \
  jq -e '.name == "project-init"' plugins/project-init/.claude-plugin/plugin.json > /dev/null
```

각 명령의 AC 매핑:
- **AC-1**: `[ ! -d plugins/project-init/skills/orchestration-rule-creator ]`
- **AC-2**: `! grep -rq "orchestration-rule-creator" plugins/project-init/`
- **AC-3**: `! grep -q orchestration plugins/project-init/skills/bootstrap/SKILL.md`
- **AC-4**: `git diff --quiet main -- plugins/project-init/skills/context-rule-creator/`
- **AC-5**: engineering-rule-creator diff의 추가 라인(`^+[^+]`) 중 `orchestration-rule-creator` 문자열 포함 라인 0건 — 새로 추가하는 라인에 orchestration 참조를 도입하지 않음. 기존 라인을 재서술하면서 orchestration 참조만 빼는 부분 수정은 허용.
- **AC-6**: `plugin.json` 의 `.name`이 `"project-init"`로 유지

## 제약 (있을 때만)
- 형제 스킬(`context-rule-creator`, `engineering-rule-creator`)의 동작은 변경되지 않아야 한다. 이들 스킬의 호출 가능성·자동 실행 흐름·산출물 형식은 본 작업 후에도 동일해야 한다.
- project-init 플러그인의 기존 검증·테스트 명령(있다면)이 작업 후에도 그대로 통과해야 한다.
- project-init 플러그인의 디렉터리 식별자·plugin name·버전 식별자는 변경하지 않는다 — version bump는 본 task의 책임 외.

## 위험 (있을 때만)
- **R-1**: bootstrap SKILL.md 내 형제 카테고리 예시가 둘에서 하나로 줄면 자연어 문장이 어색해질 수 있다. 자연어 문장을 어색하지 않게 재구성한다.
- **R-2**: plugin marketplace 등록 메타가 skill 목록을 별도로 캐시할 가능성. 본 task 작업 후 grep으로 메타 일관성을 재확인한다.
- **R-3**: 다른 플러그인·외부 자원이 `orchestration-rule-creator`를 참조할 가능성. 본 task는 project-init 플러그인 내부만 정리하며, 외부 참조 정리는 별도 task로 분리한다.
