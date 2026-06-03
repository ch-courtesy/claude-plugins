# task 상태 정합 지침

SPEC 문서가 가리키는 작업을 외부 task 백엔드(GitHub Issue/Project 등)와 같은 상태로 맞추는 절차입니다. spec 스킬은 더 이상 task를 만들거나 상태를 맞추지 않으므로(SPEC 문서만 산출), 이 책임은 **구현 스킬·오케스트레이터(loop/dispatch) 또는 호출자**가 집니다.

구체 백엔드(GitHub Issue/Project, 상태 필드, 라벨, CLI)와 **태스크 내용(설계 문서 본문) 동기화 절차**는 `rules/context.md`가 단일 출처입니다. 본 문서는 백엔드 무관한 정합 분기만 정의합니다.

## 책임 소재 (no-task-no-work)

`rules/context.md`의 태스크 우선 원칙(no-task-no-work)은 그대로 유효합니다. SPEC 문서를 받아 실제 작업(`Edit`/`Write`/`commit`/외부 상태 변경)을 시작하는 주체는 작업 시작 신호 발생 시 관련 task가 존재하는지 먼저 확인하고, 없으면 아래 분기로 task를 설계 상태에 맞춘 뒤 진행합니다. spec이 task를 만들지 않으므로 이 확인은 구현 단계로 이동했습니다 — 공백을 두지 않습니다.

## 정합 분기

작업 대상 task의 현재 상태에 따라 4갈래로 분기합니다.

- (a) task 부재: 새 task 생성, 상태를 설계 상태로 설정, 이후 그 task-id를 사용.
- (b) task가 설계 상태/In Design: 변경 없이 진행.
- (c) task가 설계 이전/Backlog: 설계 상태로 전이.
- (d) task가 설계 이후/In Progress/Review/Done: 새 task 생성 후 새 task-id를 사용. (a)와 동일.

task-id는 생성 호출의 응답값만 사용합니다. 추측·예측·작명은 금지합니다.

## 새 task 생성

title은 한 줄로 수집하고, 비어 있으면 의미 있는 fallback(예: slug)을 씁니다. body는 최소한 목표·SPEC 문서 링크를 담습니다. 백엔드별 body 구조·필드 매핑은 `rules/context.md`를 따릅니다.

조회·생성·edit·상태 전이 호출 실패는 abort합니다. 설계 상태에서 진행 상태로 바꾸는 전이(실제 작업 착수 시점)는 본 단계가 아니라 구현 흐름의 책임입니다.
