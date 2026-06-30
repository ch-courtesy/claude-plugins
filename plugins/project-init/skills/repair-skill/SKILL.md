---
name: repair-skill
description: 기존 SKILL.md를 `shared/rubric` 30항목(규칙 17 + 모델 13) 기준으로 직접 평가해 등급과 BLOCKER·MAJOR 지적을 산출하고, 사용자 승인을 받은 항목만 직접 수정한 뒤 재평가까지 끝낸다. 사용자가 기존 스킬의 품질 점검·진단·수정·보수·고치기·리페어를 요청하거나 BLOCKER·MAJOR 해소가 필요할 때 활성화된다. 호출 `Skill(skill="repair-skill", args="<SKILL.md 경로 | all>")`.
allowed-tools:
  - Read
  - Edit
  - AskUserQuestion
  - Bash(python3 *rule_checker.py*:*)
  - Bash(git rev-parse:*)
---

# repair-skill

기존 SKILL.md를 평가하고, 사용자 승인을 받은 BLOCKER·MAJOR 항목만 직접 수정한 뒤
재평가로 결과를 확인한다. 루브릭 30항목 기준의 단일 출처는
`../../shared/rubric/criteria.md`다 — 이 스킬은 자체 사본을 두지 않는다.

## 절차

### 1. 입력 해석과 절대경로 확정

`args`로 평가 대상을 받는다. `git rev-parse --show-toplevel`로 저장소 루트의
절대경로를 먼저 구하고, `<repo_root>/plugins/project-init/shared/rubric/`를
검사기·기준 문서의 절대경로로 고정한다 — Bash 실행 시 현재 작업 디렉터리가
이 스킬 폴더라는 가정을 하지 않는다(상대경로 `../../`는 Read로 단일 문서를
읽을 때만 쓰고, Bash 실행 인자에는 쓰지 않는다).
- 단일 경로가 오면 그 SKILL.md 하나만 평가한다.
- `all`이면 저장소 전체 SKILL.md를 대상으로 한다(`skill-rubric` 플러그인의
  `rubric` 스킬과 동일한 `all` 관례 — 호출이나 결과 의존 없이 의미만 일치시킨다).

### 2. 규칙 검사 실행 (결정적 17항목)

1단계에서 구한 저장소 루트 절대경로를 사용해 다음을 실행하고 stdout의 JSON을
수집한다.

```
python3 <repo_root>/plugins/project-init/shared/rubric/rule_checker.py <SKILL.md 경로 | all [repo_root]>
```

`results[].checks`에 규칙 17항목이 `check_type: "rule"`로 담긴다. 평가 자체가
성공하면 종료 코드 0과 함께 JSON을 낸다 — 발견된 결함은 종료 코드가 아니라
JSON의 `grade`·`*_count`에 담기므로, 결함이 있는 스킬을 평가해도 0으로 끝나며
다음 단계로 진행한다. 종료 코드가 0이 아니면(경로 오류 등) 오류를 알리고 중단한다.

### 3. 모델 검사 (의미적 13항목)

`../../shared/rubric/criteria.md`의 "2. 모델 항목" 절을 읽고, 평가 대상
SKILL.md(필요하면 `references/`까지)를 직접 읽어 13개 모델 항목을 판정한다.
확신이 없으면 보수적으로 FAIL한다. `all` 모드에서는 스킬마다 2–3단계를
순차로 반복한다.

### 4. 병합·등급

스킬별로 규칙 17 + 모델 13 결과를 합쳐 등급을 매긴다(`criteria.md`의 등급표
그대로): BLOCKER 1개 이상이면 F, 아니면 MAJOR 개수로 S/A/B/C를 가른다. MINOR는
등급을 가르지 않으나 보고에는 포함한다.

### 5. 분기 — 통과 vs 수정 필요

- **BLOCKER 0건, MAJOR 0건**이면 수정 작업 없이 통과 사실(등급·MINOR 목록)만
  보고하고 종료한다.
- BLOCKER 또는 MAJOR가 하나라도 있으면 6단계로 진행한다.

### 6. 수정안 도출과 승인

BLOCKER·MAJOR 항목마다 그 evidence에 대응하는 구체적 수정 내용을 도출하고,
적용 전 변경 diff(현재 내용 → 수정안)를 사용자에게 제시한다. 구조화된 사용자
질문 기능으로 적용 여부 승인을 받는다 — 기능을 쓸 수 없는 환경에서만 간결한
직접 질문으로 대체한다. MINOR 항목은 참고용으로만 함께 보고하고 수정안을
만들지 않는다(자동 수정 대상 아님).

`all` 모드에서는 스킬마다 독립적으로 diff를 제시하고 개별 승인을 받는다 — 한
스킬의 승인이 다른 스킬에 적용되지 않는다.

### 7. 적용

사용자가 승인한 항목만 해당 SKILL.md(및 필요한 references)에 `Edit`으로
직접 반영한다. 거부된 항목은 수정하지 않고 그대로 둔다.

### 8. 재평가와 보고

변경을 반영한 대상에 대해 2–4단계를 다시 실행해 BLOCKER·MAJOR 해소 여부를
확인한다. 갱신된 등급, 해소된 항목, 잔존 지적(거부되었거나 재평가에서도 남은
BLOCKER·MAJOR, 그리고 MINOR 전체)을 보고한다. 잔존 지적은 보고만 하고 같은
이터에서 추가로 반복 수정하지 않는다(무한 루프 방지).

## 규칙

- 사용자에게 승인을 요청할 때는 현재 런타임의 구조화된 사용자 질문 기능을
  우선 사용한다. 기능을 쓸 수 없으면 동일 내용을 간결한 직접 질문으로
  대체한다.
- 기존 파일은 diff 제시 후 명시적 승인이 있을 때만 수정한다. 사용자가 거부하면
  해당 항목은 미해결로만 보고하고 수정하지 않는다.
- 루브릭 30항목 기준과 평가 스크립트의 단일 출처는 `../../shared/rubric/`다.
  다른 플러그인(`skill-rubric` 등)을 호출하거나 그 결과에 런타임 의존하지 않는다.
- 모든 대상의 BLOCKER·MAJOR가 0건이면 수정 없이 통과만 보고한다.

## references

| 파일 | 용도 | 읽는 시점 |
|------|------|-----------|
| `../../shared/rubric/criteria.md` | 루브릭 30항목 기준 (단일 출처) | 3·4단계 — 모델 검사·등급 |
| `../../shared/rubric/rule_checker.py` | 규칙 17항목 결정적 검사기 | 2단계 — 규칙 검사 실행 |
