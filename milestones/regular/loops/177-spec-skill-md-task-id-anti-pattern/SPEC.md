---
scope:
  include: ["plugins/autopilot/skills/spec/SKILL.md"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "test \"$(grep -cF 'task-id 는 항상 task 생성 호출의 응답값을 그대로 사용한다 — 추측·예측·작명 금지' plugins/autopilot/skills/spec/SKILL.md)\" -eq 2"
ears_language: ko
---

# spec SKILL.md — task-id 추측 금지 anti-pattern 룰 명시

## 무엇을 만들 것인가

spec 스킬의 SKILL.md 본문에서 task-id 생성·교체와 관련된 두 위치 — step 2 (task 상태 정합 4갈래 분기 (a)) 와 §1.2 사전 명확화 라운드 요약 — 에 "task-id 는 항상 task 생성 호출의 응답값을 그대로 사용한다 — 추측·예측·작명 금지" 라는 부정 명령을 한 줄씩 명시한다.

배경: 현행 SKILL.md 본문은 "새 task 생성·task-id 교체"·"task 생성 단계에서 결정" 같은 긍정 기술만 두고 부정 명령은 두지 않는다. 그 결과, 호출 모델이 로컬 `milestones/regular/loops/` 디렉토리에 보이는 기존 숫자 패턴(예: 65/69/71/72/73/75/78/79)에서 다음 번호를 추측·예측하는 경향이 반복 관측된다. id 발급의 강제 진술은 `references/task-state-alignment.md` 의 "task 생성 호출 시점엔 아직 발급되지 않은 값" 절에 보존돼 있으나, SKILL.md 본문만 훑는 경로에서는 그 attractor 가 노출되지 않아 효과가 부족하다. 본 변경의 목적은 SKILL.md 본문만 읽고도 "id 는 외부 응답값" 이라는 강제 규칙이 즉시 보이도록 만드는 것이다.

## 수용 기준 (EARS)

- **AC1** (Ubiquitous): SKILL.md step 2 의 4갈래 분기 (a) 설명에 "⚠ task-id 는 항상 task 생성 호출의 응답값을 그대로 사용한다 — 추측·예측·작명 금지" 부정 명령이 한 줄로 포함된다.
- **AC2** (Ubiquitous): SKILL.md §1.2 사전 명확화 라운드 요약에 동일 부정 명령이 한 줄로 포함된다.
- **AC3** (Ubiquitous): 두 위치의 한 줄은 정확히 동일한 문자열이다 (오타·표현 분기 없음).
- **AC4** (Unwanted): SKILL.md 외부 — 특히 `plugins/autopilot/skills/spec/references/` 하위 어느 파일에도 동일 문구가 중복으로 출현하지 않는다. 단일 source of truth 는 SKILL.md 본문 두 위치이며, 강제 진술 자체의 source 는 `task-state-alignment.md` 기존 위치 그대로 유지.

## 범위

포함:

- `plugins/autopilot/skills/spec/SKILL.md` — step 2 의 4갈래 분기 (a) 설명 줄 옆에 anti-pattern 한 줄 추가, §1.2 요약의 "단일 task → 프로젝트 태스크 트래커 컨벤션으로 task 생성" 문구 옆에 동일 anti-pattern 한 줄 추가

비-목표 / 제외:

- `references/task-state-alignment.md` — 기존 강제 진술("task 생성 호출 시점엔 아직 발급되지 않은 값") 유지, 변경 없음
- 다른 스킬(`loop`·`dispatch`·`prd`) — 영향 없음
- §8.2 sync trigger 의 placeholder 2줄 검증 가드와 §1.2.1 의 "프로젝트 지침 본문 구조" 사이의 별개 불일치 — 본 SPEC 의 단일 anti-pattern 추가로 가려질 수 있으나 해소는 별개 SPEC 책임
- spec 호출 흐름·라우팅·검증·step 순서 변경 — 본 SPEC 은 docs 두 줄 추가에 한정

## 검증

frontmatter `verify` 명령이 0 exit 으로 끝나야 합니다 (count 기반 — AC1+AC2+AC3 통합 검증):

```bash
test "$(grep -cF 'task-id 는 항상 task 생성 호출의 응답값을 그대로 사용한다 — 추측·예측·작명 금지' plugins/autopilot/skills/spec/SKILL.md)" -eq 2
```

추가로 다음 보조 검사들이 PR 리뷰 시점에 검증된다 (자동 verify 외 — AC1·AC2 위치 분포 + AC4 중복 부재):

```bash
# AC1: step 2 영역 (### 2. task 상태 정합 ~ ### 3. 컨텍스트 탐색 사이) 에 1회 이상
awk '/^### 2\. task 상태 정합/,/^### 3\. 컨텍스트 탐색/' plugins/autopilot/skills/spec/SKILL.md \
  | grep -cF 'task-id 는 항상 task 생성 호출의 응답값을 그대로 사용한다 — 추측·예측·작명 금지'

# AC2: §1.2 영역 (#### 1.2 사전 명확화 라운드 ~ ### 2. task 상태 정합 사이) 에 1회 이상
awk '/^#### 1\.2 사전 명확화 라운드/,/^### 2\. task 상태 정합/' plugins/autopilot/skills/spec/SKILL.md \
  | grep -cF 'task-id 는 항상 task 생성 호출의 응답값을 그대로 사용한다 — 추측·예측·작명 금지'

# AC4: references/ 하위에 동일 문구 부재 (0 이어야 함)
grep -rcF 'task-id 는 항상 task 생성 호출의 응답값을 그대로 사용한다 — 추측·예측·작명 금지' \
  plugins/autopilot/skills/spec/references/ 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}'
```

## 제약

- self-referential 변경: `feedback_no_self_apply_during_spec` 메모리 노트에 따라 본 SPEC 의 새 룰은 현재 spec 호출에 선행 적용되지 않는다 — 새 동작은 본 SPEC 이 default 브랜치에 merge 된 후의 다음 spec 호출부터.
- 두 위치의 한 줄은 정확히 동일한 문자열이어야 한다 (AC3) — 후속 편집 시 표현 분기 방지.
- 추가는 SKILL.md 본문에 한정 — `references/` 하위는 손대지 않으며, 강제 진술의 단일 출처는 기존 `task-state-alignment.md` 위치 유지.

## 위험

- SKILL.md 가 점점 길어지면 부정 명령들이 묻혀 동일 attractor 가 재발할 수 있음 — 향후 SKILL.md 구조 개편 시 "anti-pattern 모음" 섹션 신설 검토 (본 SPEC 범위 외).
- §8.2 fence 가드(placeholder 2줄 정합 검증) 와 §1.2.1 의 "프로젝트 태스크 관련 지침 본문 구조" 사이의 별개 불일치가 본 SPEC 변경으로 가려질 수 있음 — 향후 별개 SPEC 으로 추적 권장.
- "⚠" 이모지 사용이 다른 SKILL.md 컨벤션과 어긋날 가능성. 현행 SKILL.md 본문에 이모지 사용 사례가 거의 없어 false-positive 패턴 매칭 위험은 낮지만, 후속 grep 자동화·렌더링에서 인코딩 이슈가 생기면 표현을 재검토 (본 SPEC 범위 내 수정 가능).
