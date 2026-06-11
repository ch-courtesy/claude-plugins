---
scope:
  include:
    - plugins/autopilot/skills/dispatch/references/integration.sh
    - plugins/autopilot/.claude-plugin/plugin.json
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# dispatch PR auto-review marker

## 무엇을 만들 것인가
dispatch 스킬이 forge 경로에서 **새로 생성하는** PR 의 제목과 본문에, 이 PR 이 사람이 직접 연 것이 아니라 dispatch 자동(적대) 리뷰를 거치는 자동 생성 PR 임을 식별하는 표시를 추가한다.

- 제목: 원래 제목 앞에 `🤖 [자동 리뷰] ` 접두 태그를 붙인 형태로 만든다.
- 본문: 기존 통합 문구(`dispatch 통합: 구현 완료, 승인 요청.`)를 유지한 채, 이 PR 이 dispatch 자동 적대 리뷰를 거친다는 설명 줄을 덧붙인다.

대상은 PR 을 **신규 생성하는 경로**뿐이다. 이미 열려 있는 같은 head 의 open PR 을 재사용하는 경로(생성 없이 기존 PR 번호만 반환)는 제목·본문을 바꾸지 않는다.

## 목적 (왜)
dispatch 가 만든 PR 은 사람이 연 PR 과 목록·알림에서 섞여 구분이 어렵다. 제목·본문에 자동 리뷰 표시를 달면, 리뷰어와 협업자가 "이 PR 은 dispatch 가 자동 생성했고 자동 적대 리뷰를 거치는 PR" 임을 한눈에 식별할 수 있다.

## 완료 조건
- dispatch 가 forge 경로에서 PR 을 **새로 생성할 때**, 생성에 사용되는 제목은 원래 제목 앞에 `🤖 [자동 리뷰] ` 접두 태그가 붙은 문자열이다.
- dispatch 가 forge 경로에서 PR 을 **새로 생성할 때**, 생성에 사용되는 본문은 기존 통합 문구를 포함하면서 동시에 자동 적대 리뷰를 거친다는 식별 문구(예: `자동 적대 리뷰` 를 포함하는 줄)를 함께 담는다.
- 이미 열려 있는 같은 head 의 open PR 이 발견되어 재사용될 때, 그 PR 의 제목과 본문에 대한 수정 호출은 일어나지 않는다(기존 동작 보존).
- plugins/ 워치 디렉터리를 변경하므로, 같은 변경 안에서 autopilot plugin.json 의 version 이 base(main) 대비 한 단계 올라가 있다(0.y.z 초기 개발 단계의 동작 추가이므로 MINOR 증가).
- integration.sh 의 selftest(`bash integration.sh selftest`)가 모두 통과하며, 그 안에 새 PR 생성 시 제목·본문에 자동 리뷰 표시가 들어갔음을 확인하는 단언이 존재한다.

## 범위
포함:
- `plugins/autopilot/skills/dispatch/references/integration.sh` 의 `in_ensure_pr` 신규 생성 경로(제목·본문 구성)와 그에 대한 selftest 단언.
- `plugins/autopilot/.claude-plugin/plugin.json` 의 version 범프.

비-목표 / 제외:
- in_ensure_pr 의 open PR 재사용(조기 반환) 경로 동작 변경.
- direct 서브모드(PR 을 만들지 않는 로컬 머지 경로)에 대한 표시 — PR 자체가 없으므로 대상 아님.
- 표시 문자열을 외부 주입 인터페이스로 노출하는 일반화(현재 주입 가능한 인터페이스 목록 확장).
- 제목·본문 외 PR 라벨·메타데이터 부여.
- GitHub Releases note(변경 기록) 작성 — 머지 절차의 책임이며 본 SPEC 범위 밖.

## 검증
이 SPEC 의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC 이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- 표시 형식은 제목 접두 `🤖 [자동 리뷰] ` + 원래 제목, 본문은 기존 문구 + 자동 적대 리뷰 식별 줄로 고정한다(인터뷰 확정 사항).
- forge CLI 호출 형태(`$FORGE_CMD pr create --head ... --base ... --title ... --body ...`)와 기존 주입 인터페이스(`FORGE_CMD` 등)는 유지한다 — 표시는 제목·본문 인자 값 구성만 바꾼다.
- 본문이 여러 줄이 되어도 단일 `--body` 인자로 전달한다(추가 forge 호출을 만들지 않는다).
- 버전 SoT 는 plugin.json 단일 출처다 — 다른 곳에 버전 문자열을 중복으로 적지 않는다.

## 위험
- 제목 접두 태그가 길어 PR 목록에서 원래 제목 식별을 방해할 수 있다 — 접두 태그를 짧게(`🤖 [자동 리뷰] `) 유지해 완화한다.
- 본문 다중 줄 구성 시 셸 따옴표/개행 처리 오류로 forge 호출이 깨질 수 있다 — selftest 의 mock forge 기록(PRLOG)으로 제목·본문 전달을 검증해 완화한다.
