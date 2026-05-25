# task state alignment (optimized)

spec step 2는 사전 검사 통과 직후 일반·`--resume` 두 모드에서 실행한다. 목적은 외부 task를 설계 상태로 맞추고 spec/loop가 같은 task-id를 쓰게 하는 것이다.

구체 백엔드(GitHub Issue/Project, 상태 필드, 라벨, CLI)는 target `rules/context.md`가 단일 출처다.

## 분기

- (a) task 부재: 새 task 생성, 상태를 설계 상태로 설정, task-id를 반환된 ID로 교체, 사전 검사 재적용.
- (b) task가 설계 상태/In Design: 변경 없이 진행.
- (c) task가 설계 이전/Backlog: 설계 상태로 전이.
- (d) task가 설계 이후/In Progress/Review/Done: 새 task 생성 후 task-id 교체. (a)와 동일.

task-id는 생성 호출의 응답값만 사용한다. 추측·예측·작명 금지.

## 새 task 생성

title은 `AskUserQuestion`으로 한 줄 수집하고, 비어 있으면 task-id fallback. body는 고정 2줄 placeholder:

```text
spec 워크플로우 step 2에서 자동 생성. 본문은 SPEC.md 작성·승인 후 갱신될 예정.
SPEC: milestones/<m>/loops/<new-task-id>/SPEC.md
```

`<m>`은 create 호출 전 치환한다. `<new-task-id>`는 create가 반환한 issue number로 `gh issue edit --body-file`을 통해 치환한다.

조회·생성·edit·상태 전이 호출 실패는 abort. loop start 때 설계 상태에서 진행 상태로 바꾸는 것은 본 단계 책임이 아니다.
