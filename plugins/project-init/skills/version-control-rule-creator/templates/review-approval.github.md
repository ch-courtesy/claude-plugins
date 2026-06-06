---
sub_rule: review-approval
backend: github
label: 변경 제안 심사·승인 (GitHub)
description: GitHub Pull Request의 승인 상태·스레드 해소·필수 체크·소유권 경계·머지 방식·Draft 규율을 백엔드 용어로 정의합니다.
inputs:
  - name: merge_method
    multi_select: false
    header: "머지 방식"
    question: "리뷰가 끝난 PR을 머지할 때 이 프로젝트가 쓰는 방식을 하나 고르세요."
    options:
      - label: "저장소 설정을 따름"
        default: true
        description: "방식을 룰로 못 박지 않고 GitHub 저장소에 설정된 머지 방식을 그대로 따릅니다. 안전한 기본값입니다."
        value: |-
          - 이 저장소가 정한 머지 방식(merge commit / squash / rebase)을 따릅니다. 방식이 명시돼 있지 않으면 임의로 바꾸지 말고 저장소 관례·설정을 따릅니다.
      - label: "merge commit"
        description: "PR마다 머지 커밋을 만들어 토픽 브랜치 history를 base에 보존합니다."
        value: |-
          - 이 저장소의 머지 방식은 **merge commit**입니다. PR을 머지할 때 머지 커밋을 만들어 토픽 브랜치 history를 base 브랜치에 보존합니다. squash·rebase 방식으로 바꿔 머지하지 않습니다.
      - label: "squash"
        description: "PR의 커밋들을 하나로 합쳐 base에 단일 커밋으로 올립니다(선형 history)."
        value: |-
          - 이 저장소의 머지 방식은 **squash**입니다. PR을 머지할 때 커밋들을 하나로 합쳐(squash) base 브랜치에 단일 커밋으로 올립니다. merge commit·rebase 방식으로 바꿔 머지하지 않습니다.
      - label: "rebase"
        description: "PR 커밋들을 base 위에 rebase해 머지 커밋 없이 올립니다."
        value: |-
          - 이 저장소의 머지 방식은 **rebase**입니다. PR을 머지할 때 커밋들을 base 브랜치 위에 rebase해 머지 커밋 없이 올립니다. merge commit·squash 방식으로 바꿔 머지하지 않습니다.
---

# 변경 제안 심사·승인 지침 — GitHub

이 프로젝트의 호스팅 백엔드는 **GitHub**입니다. 변경 제안(change proposal)은 GitHub의 **Pull Request(PR)**로 표현됩니다. 본 지침은 PR을 심사·승인할 때 GitHub의 심사·승인 모델을 어떻게 적용하는지 정의합니다.

> 본 지침은 범용 리뷰 원칙(`rules/review.md`)을 **대체하지 않습니다.** 무엇을 어떻게 리뷰할지(판정 전 사실 확정, 구속 기준 우선, 위험도 비례 정밀도, 검증, 발견 보고 등)는 그 9원칙을 그대로 따르고, 본 지침은 그 위에 **GitHub 백엔드 특화 심사·승인 규율**을 더합니다. 릴리스 버전 번호 지침(`rules/engineering/versioning.md`)과도 별개입니다.

## 심사 단위

- 심사·승인의 단위는 하나의 **Pull Request**입니다. 한 PR은 하나의 응집된 변경 제안을 담으며, 심사·승인·머지는 PR 단위로 판단합니다.
- PR 설명에는 변경의 의도·범위·검증 방법이 드러나야 하고, 심사자는 그 범위를 기준선(base 브랜치) 대비 diff로 확정한 뒤 판정합니다.

## 승인 상태의 의미

GitHub 리뷰는 세 가지 상태로 제출되며, 각 상태의 의미를 다음과 같이 구속합니다.

- **Comment** — 승인도 거부도 아닌 의견. 머지 가부를 결정하지 않습니다. 질문·제안·관찰을 남길 때 씁니다.
- **Approve** — 변경 제안을 머지해도 좋다는 명시적 동의. 심사자가 diff를 실제로 확인하고 구속 기준(정확성·계약·보안·발견성)을 만족했다고 판단했을 때만 제출합니다. "보기엔 괜찮다"는 Approve의 근거가 아닙니다.
- **Request changes** — 머지 전 반드시 해소해야 할 차단 의견. 이 상태가 살아 있는 동안 변경 제안은 머지 대상이 아닙니다. 지적한 본인이 재확인 후 해제하는 것이 원칙입니다.

## 대화 스레드 해소

- 리뷰 코멘트 스레드는 **해소(resolve)** 되어야 머지 준비가 끝납니다. 지적이 코드·설명으로 실제 반영됐는지 확인한 뒤 해소하며, "고쳤다"는 말만으로 해소하지 않습니다.
- 미해소 스레드가 남아 있으면 머지하지 않습니다. 후속으로 분리할 항목은 별도 이슈로 떼어 명시적으로 기록한 뒤에만 스레드를 닫습니다.

## 필수 상태 체크

- base 브랜치에 설정된 **필수 상태 체크(required status checks)** 가 모두 통과(green)해야 머지할 수 있습니다. 체크 실패·미완료 상태로 머지하지 않습니다.
- 필수 체크는 자동 검증의 단일 신호이되 충분 조건이 아닙니다 — 체크가 덮지 못하는 영역(산문 계약·UX·행동 규율)은 사람이 수동으로 심사합니다(`rules/review.md` 5원칙).

## 소유권 경계

- 변경이 닿는 경로에 코드 소유권 규칙(CODEOWNERS 등)이 걸려 있으면, **그 경로의 소유자 승인**이 머지의 필요 조건입니다. 소유 경계를 우회해 머지하지 않습니다.
- 자기 자신이 만든 변경 제안을 스스로 승인해 경계를 무력화하지 않습니다.

## 머지 방식

{{merge_method}}

- 머지 직전 base 브랜치와의 충돌이 해소됐는지, 필수 체크가 최신 커밋 기준으로 green인지 확인합니다.

## Draft 상태

- 아직 심사를 요청할 단계가 아닌 변경 제안은 **Draft PR**로 둡니다. Draft는 "심사 받을 준비가 되지 않음"의 명시 신호이므로, Draft 상태의 PR에는 승인을 제출하지 않고 머지하지 않습니다.
- 심사 준비가 끝나면 Draft를 해제(Ready for review)한 뒤에 승인 절차를 시작합니다.
