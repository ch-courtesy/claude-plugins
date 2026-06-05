---
name: context-rule-creator
description: 현재 프로젝트에 맞는 컨텍스트 관리 지침을 컨텍스트 카테고리 디렉터리 아래 두 sub-룰 파일(`rules/context/task-model.md`·`rules/context/task-ops.md`)로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 컨텍스트 지침을 새로 만들고 싶어 할 때.
---

# context-rule-creator

선택한 컨텍스트 백엔드의 지침을 **백엔드 결합도**를 기준으로 둘로 갈라, 컨텍스트 카테고리 디렉터리 아래 두 sub-룰 파일로 기록합니다.

- `rules/context/task-model.md` — 태스크 속성을 선택된 백엔드에 매핑·적용하는 **백엔드 결합** 내용.
- `rules/context/task-ops.md` — 백엔드와 무관한 **운영 규율·절차** 전반(태스크 우선 원칙, 작업 시작 신호, 상태 전이 책임, 운영 단계 규칙, append-only 기록 규율 등).

출력 파일명은 `task-model`·`task-ops`로 **고정**입니다(템플릿 파일명·백엔드명에서 파생하지 않습니다). 디렉터리 구조라 향후 다른 컨텍스트 sub-룰이 같은 카테고리 아래 공존할 수 있습니다.

## 템플릿 레이아웃

공통 템플릿 디렉터리 `../../../shared/context-rule-creator/templates/` 아래:

- `../../../shared/context-rule-creator/templates/<backend>/task-model.md` — 백엔드별 task-model 본문. 이 파일의 frontmatter가 백엔드 선택 메타데이터입니다.
- `../../../shared/context-rule-creator/templates/task-ops.md` — 모든 백엔드가 공유하는 백엔드 무관 task-ops 본문(frontmatter 없음).

`<backend>`는 백엔드 id(예: `filesystem`, `github-project`)이며 상호배타적 단일 선택지입니다. 새 백엔드를 추가하려면 공통 템플릿 디렉터리 `../../../shared/context-rule-creator/templates/` 아래에 `task-model.md`를 담은 새 디렉터리를 두면 되고, 이 SKILL.md는 변경하지 않습니다.

## 생성 절차

1. **백엔드 열거.** 공통 템플릿 디렉터리 `../../../shared/context-rule-creator/templates/` 아래에서 `task-model.md`를 가진 서브디렉터리만 백엔드 후보로 삼습니다. 디렉터리명이 백엔드 id입니다. 공유 본문 `../../../shared/context-rule-creator/templates/task-ops.md`도 읽어 둡니다. 다른 경로는 탐색하지 않습니다.

2. **frontmatter 파싱.** 각 백엔드의 `task-model.md` frontmatter를 읽습니다.
   - `label` 필수, 옵션 라벨입니다.
   - `description` 선택, 옵션 설명입니다.
   - `recommended: true` 선택, 라벨에 `(Recommended)`를 붙이고 맨 앞으로 둡니다. 하나만 허용합니다.
   - `inputs` 선택, `name`, `header`, `question`, `options[{label, description, value?}]`를 가진 정적 placeholder 입력입니다.
   - `on_create` 선택, 파일 기록 후 수행할 지시입니다.

   `task-model.md`가 없거나 `label`이 없는 디렉터리는 후보에서 제외하고 사용자에게 알립니다.

3. **백엔드 선택 (상호배타 단일).** 후보가 하나면 자동 선택하고, 둘 이상이면 `request_user_input` single-select로 묻습니다. 한 번의 실행에서 **정확히 하나**의 백엔드만 기록합니다. 단순 재실행으로 백엔드를 바꾸지 않습니다.

4. **정적 입력 수집.** 선택된 백엔드 `task-model.md`에 `inputs`가 있으면 순서대로 묻습니다. 값은 `value` 또는 `label`을 사용하고, "Other"도 허용합니다. 수집된 값만 `{{name}}`에 치환하고 누락·빈 값은 placeholder를 보존합니다.

5. **상태 구성 수집 (두 단계로 분리).** 아래 ①②를 **각각 별도 질문**으로 수집합니다. 한 질문에 묶지 않습니다. 각 단계에서 응답 누락·빈 값이면 해당 placeholder를 보존합니다(정적 입력과 동일 규약). 전이 순서는 사용자에게 따로 묻지 않습니다 — 순서가 정해진 라이프사이클 이벤트들의 목표 상태로부터 스킬이 자동으로 구성합니다(6단계 참조).

   - **① 상태 집합** — 사용할 태스크 상태들이 무엇인지 묻습니다. 기본 후보 예시: `backlog`, `in_design`, `in_progress`, `blocked`, `review`, `done`, `cancelled`. 다중 선택 + "Other"를 허용합니다. 수집값 → `{{state_set}}`.
   - **② 이벤트별 목표 상태** — 아래 **고정 이벤트 카탈로그**(작업 워크플로 라이프사이클 이벤트)의 각 이벤트에 대해 "어느 상태로 전이할지"만 묻습니다. ①과 **분리된** 별도 단계입니다. 이벤트 자체는 사용자가 서술하지 않습니다 — 사용자는 각 이벤트의 목표 상태만 ①에서 고른 집합 중에서 지정합니다. 카탈로그는 진행 순서대로 나열되며, 맨 앞 "태스크 최초 등록"(아직 진행되지 않은 초기 상태)부터 묻습니다.

     | 라이프사이클 이벤트 (고정) | placeholder |
     |---|---|
     | 태스크 최초 등록 (아직 진행되지 않은 초기 상태) | `{{event_initial}}` |
     | 계획/스펙 문서 생성 | `{{event_plan_doc}}` |
     | 구현 시작 | `{{event_impl_start}}` |
     | 리뷰 요청 (검증/리뷰에 진입한 상태) | `{{event_review_start}}` |
     | 머지/완료 | `{{event_merge_done}}` |
     | 차단 발견 | `{{event_blocked}}` |
     | 차단 해제 | `{{event_unblocked}}` |

   ①의 상태 집합은 task-model의 상태 집합·백엔드 매핑(`{{state_set}}`)에 반영됩니다. ②의 이벤트별 목표 상태는 task-ops의 전이 이벤트·운영 규칙에 반영되고, 그중 on-path 이벤트들의 목표 상태는 기본 흐름(전이 순서) 자동 구성에도 쓰입니다.

6. **본문 조립.** 두 산출물 본문을 조립합니다.
   - task-model 본문: 선택된 백엔드 `task-model.md`의 frontmatter를 제거한 본문에 4·5단계 수집값을 치환합니다.
   - task-ops 본문: 공유 `../../../shared/context-rule-creator/templates/task-ops.md` 본문에 5단계 수집값을 치환합니다.
   - "기본 흐름:" 줄의 `{{transition_order}}`는 사용자 입력이 아니라, 순서가 정해진 on-path 이벤트들의 목표 상태(`{{event_initial}}` → `{{event_plan_doc}}` → `{{event_impl_start}}` → `{{event_review_start}}` → `{{event_merge_done}}`)를 종합해 자동으로 채웁니다. 차단·해제 같은 off-path 이벤트는 기본 흐름에 포함하지 않습니다. on-path 이벤트의 목표 상태가 누락되면 그 자리는 placeholder를 보존합니다.
   - 수집되지 않은 값의 `{{...}}` placeholder는 그대로 보존합니다.

7. **기록 전 확인 게이트.** 조립된 두 본문(task-model·task-ops)을 사용자에게 보여 주고, 이 내용으로 기록해도 되는지 **확인을 받습니다**. 신규 파일·기존 파일 모두에 적용하며, 이는 8단계의 기존 파일 덮어쓰기 diff 확인과 별개입니다. 확인 없이는 기록하지 않습니다.

8. **파일 기록.**
   - 대상 디렉터리 `rules/context/`가 없으면 기록 전에 생성합니다. (평면 파일 `rules/context.md`와 디렉터리 `rules/context/`는 경로가 달라 공존 가능하므로 디렉터리 생성 자체는 실패하지 않습니다.)
   - **레거시 산출물 처리.** 이전 버전 스킬의 평면 파일 `rules/context.md`가 있으면, 이 파일이 새 분할 구조(`rules/context/task-model.md`·`task-ops.md`)로 대체됨을 사용자에게 알리고 제거 여부를 확인합니다. 둘 다 남으면 컨텍스트 지침이 중복 적용되므로 정리를 권장하되, 사용자의 명시적 동의 없이는 삭제하지 않습니다.
   - `rules/context/task-model.md`와 `rules/context/task-ops.md`를 함께 기록합니다.
   - 각 대상 파일이 이미 있으면 덮어쓰지 않고 diff를 보여 사용자에게 확인합니다. 명시적 확인 없이는 덮어쓰지 않습니다.

9. **사후 작업.** 선택된 백엔드의 `on_create`가 있으면 그대로 수행합니다.

## 규칙

- 템플릿 본문은 placeholder 치환 외에는 그대로 복사합니다. SKILL.md에 본문별 로직을 추가하지 않습니다.
- 한 번의 호출 = 한 백엔드의 task-model·task-ops 한 쌍. 두 백엔드를 합치거나 누적하지 않습니다.
- 대화형 입력 확장은 태스크 상태 집합·이벤트별 목표 상태에 한정합니다(전이 순서는 입력받지 않고 on-path 이벤트의 목표 상태로부터 자동 구성). 그 밖의 지침 항목은 대화형 입력으로 일반화하지 않습니다.
- 사용자의 명시적 요청이 있을 때만 기존 sub-룰 파일 덮어쓰기를 검토합니다. 단순 재실행으로 백엔드를 바꾸지 않습니다.
