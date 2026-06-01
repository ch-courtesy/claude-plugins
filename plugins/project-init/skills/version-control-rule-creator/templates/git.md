---
sub_rule: git
label: git 계열 공통 지침 (force push 정책)
description: git 계열 백엔드(GitHub·GitLab 등) 공통으로 적용되는 version-control 지침. 첫 항목으로 force push 정책을 담습니다.
inputs:
  - name: force_push_policy
    header: "force push"
    question: "이 프로젝트에서 force push(history 재작성 push)를 허용하시겠습니까? (기본값: 금지)"
    options:
      - label: "금지 (Recommended)"
        description: "공유 브랜치 history를 보호합니다. 협업 프로젝트의 안전한 기본값입니다."
        value: |-
          ## force push 금지

          공유 브랜치(기본 브랜치 및 다른 사람이 받아 가는 브랜치)에 대한 **force push**(`git push --force` / `--force-with-lease`, history 재작성 push)를 **금지**합니다.

          - 이미 푸시되어 공유된 commit은 history를 재작성해 덮어쓰지 않습니다. 잘못된 commit은 새 commit(revert·수정)으로 바로잡습니다.
          - force push는 다른 사람이 받아 간 history를 무효화해 작업 손실·충돌을 일으키므로, 공유 브랜치에서는 예외 없이 막습니다.
          - 아직 공유되지 않은 본인 전용 토픽 브랜치의 정리(rebase 후 force push)가 불가피하면, 그 브랜치가 공유되지 않았음을 확인한 경우에만 허용하며 공유 브랜치에는 적용하지 않습니다.
          - 호스팅의 브랜치 보호(protected branch) 설정으로 기본 브랜치 force push를 차단하는 것을 권장합니다.
      - label: "허용"
        description: "force push를 정책상 막지 않습니다. 브랜치 보호는 호스팅 설정에 위임합니다."
        value: ""
---

# git 계열 공통 지침

이 프로젝트의 호스팅 백엔드는 **git 계열**(GitHub·GitLab 등)입니다. 본 지침은 호스팅 백엔드(GitHub/GitLab)와 무관하게 git 계열 전체에 공통으로 적용되는 version-control 규율을 정의합니다. 백엔드 특화 심사·승인 규율은 별도 sub-룰(`rules/version-control/review-approval.md`)이 담습니다.

{{force_push_policy}}
