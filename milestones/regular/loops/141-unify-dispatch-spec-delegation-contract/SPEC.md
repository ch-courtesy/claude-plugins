---
scope:
  include: ["plugins/autopilot/skills/spec/**", "plugins/autopilot/skills/dispatch/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; spec=plugins/autopilot/skills/spec/SKILL.md; dispatch=plugins/autopilot/skills/dispatch/SKILL.md; grep -qE -- \"--milestone <m>\" \"$spec\"; grep -qE \"슬래시.*거부|args.*슬래시\" \"$spec\"; grep -qE \"기본 milestone|default milestone\" \"$spec\"; grep -qE \"dispatch.*위임|위임.*dispatch\" \"$spec\"; grep -qE \"자율 루프.*자동|자동.*루프\" \"$spec\"; grep -qE \"세 옵션|3옵션\" \"$spec\"; grep -qE -- \"--milestone <m> <자연어\" \"$dispatch\"; ! grep -qE \"args.*\\\"<m>/<c>\\\"\" \"$dispatch\"; grep -qE \"스냅샷.*차이|디렉토리.*스냅샷\" \"$dispatch\"'"
# ears_language: ko (default)
---

# unify dispatch spec delegation contract

## 무엇을 만들 것인가

`autopilot:dispatch` 가 `autopilot:spec` 을 위임 호출할 때의 contract 를 단일화한다. dispatch 는 child task 식별자를 알 필요가 없으며 spec 이 task 생성·명세 작성·설계 브랜치 준비·후속 자율 루프 시작까지 단일 호출에서 완수한다.

spec 은 milestone 을 별도 인자로만 받는다 — args 본문에는 task 식별자 또는 자연어 task 설명만 들어가고, milestone 은 항상 명시적인 플래그로 명시한다. 플래그가 없으면 프로젝트 기본 milestone (`regular`) 으로 적용된다. args 본문 안 슬래시는 거부된다 — 한 정보는 한 위치.

dispatch 의 위임 호출은 task 식별자 대신 처리할 task 의 자연어 설명·milestone 만 넘긴다. milestone 은 명시 플래그로, 자연어 설명은 그 뒤 본문으로 전달된다. 이를 받은 spec 은 호출자가 dispatch 임을 인식해 최종 사용자 확인 단계를 생략하고 자율 루프를 바로 시작한다. 사용자가 spec 을 직접 호출한 경우에는 기존의 최종 확인 단계·세 옵션 (loop start · SPEC 만 확정 · 변경) 이 그대로 유지된다.

dispatch 는 위임 전후 설계 산출물 저장소의 스냅샷 차이로 child 의 명세 경로를 식별하며 task 식별자 자체는 참조하지 않는다.

## 수용 기준 (EARS)

AC1 (Event-driven): 사용자가 spec 을 단일 식별자만으로 호출할 때, 시스템은 milestone 을 프로젝트 기본 milestone 으로 적용한다.

AC2 (Event-driven): 사용자가 spec 을 `--milestone <m>` 인자와 함께 호출할 때, 시스템은 `<m>` 을 milestone 으로 적용한다.

AC3 (Unwanted): 사용자가 spec 을 슬래시 포함 args (플래그 부분 제외 본문) 로 호출하면, 시스템은 이를 거부한다.

AC4 (Event-driven): spec args 의 플래그 제외 남은 값이 task 식별자 패턴이면 시스템은 그 값을 기존 task 식별자로 해석한다.

AC5 (Event-driven): spec args 의 플래그 제외 남은 값이 task 식별자 패턴이 아닌 자연어이면 시스템은 그 값을 task 생성 입력으로 처리한다.

AC6 (Event-driven): dispatch 가 spec 을 위임 호출할 때, 시스템은 단일 args 문자열로 `--milestone <m> <자연어 task 설명>` 형식만 전달한다.

AC7 (State-driven): dispatch 가 위임 호출한 경우, spec 은 task 생성·명세 작성·설계 브랜치 준비·자율 루프 시작까지 단일 호출에서 완수한다.

AC8 (Optional): 사용자가 spec 을 직접 호출한 경우, 시스템은 최종 확인 단계의 세 옵션 (loop start · SPEC 만 확정 · 변경) 을 제시한다.

AC9 (Ubiquitous): dispatch 는 child task 식별자를 보유하지 않고 명세 경로 스냅샷 차이로 child 명세 경로만 식별한다.

AC10 (Ubiquitous, 메타): 본 SPEC 호출 흐름은 이전 컨벤션으로 완료되며 새 contract 는 본 SPEC 다음 호출부터 적용된다 (self-referential 보호).

## 범위

포함:
- spec 스킬 명세 명확화 (`--milestone` 플래그 · 슬래시 args 거부 · 단일 본문 값 해석 · dispatch 위임 모드 분기 · 자율 루프 자동 시작 · 사용자 직접 호출 세 옵션 유지)
- dispatch 스킬 명세 명확화 (spec 위임 구체 형식 · child 식별자 미보유 · 명세 경로 스냅샷 차이 기반 child 식별)

비-목표 / 제외:
- 자율 루프 스킬·구동 스크립트 수정
- PRD 스킬 명세 수정
- 기존 설계 산출물 저장소 하위 마이그레이션
- dispatch 의 wave 처리·게이트·sentinel watch 로직 자체
- spec slug 컨벤션·feat 브랜치 명명 규칙 변경
- 다른 플러그인의 인자 컨벤션
- 본 SPEC 호출 흐름 자체 (AC10)

## 검증

이 명령이 0 exit 으로 끝나야 합니다:

```
bash -c 'set -e
spec=plugins/autopilot/skills/spec/SKILL.md
dispatch=plugins/autopilot/skills/dispatch/SKILL.md

# spec: --milestone 플래그 명시
grep -qE -- "--milestone <m>" "$spec"
# spec: 슬래시 args 본문 거부 명시
grep -qE "슬래시.*거부|args.*슬래시" "$spec"
# spec: default milestone 적용 명시 (regular 라는 단어 자체는 흔하므로 "기본 milestone" 결합으로 좁힘)
grep -qE "기본 milestone|default milestone" "$spec"
# spec: dispatch 위임 모드 분기 명시
grep -qE "dispatch.*위임|위임.*dispatch" "$spec"
# spec: 자율 루프 자동 시작 명시
grep -qE "자율 루프.*자동|자동.*루프" "$spec"
# spec: step 10 세 옵션 유지 (사용자 직접 호출 — "세 옵션"·"3옵션" 표현으로 좁힘)
grep -qE "세 옵션|3옵션" "$spec"

# dispatch: 새 위임 형식
grep -qE -- "--milestone <m> <자연어" "$dispatch"
# dispatch: 기존 <m>/<c> 형식 제거
! grep -qE "args.*\"<m>/<c>\"" "$dispatch"
# dispatch: 스냅샷 차이 기반 child 식별
grep -qE "스냅샷.*차이|디렉토리.*스냅샷" "$dispatch"'
```

## 제약

- 변경 대상은 spec 스킬·dispatch 스킬 명세 문서 둘 뿐. 자율 루프 구동 스크립트·다른 플러그인·기존 산출물은 변경하지 않는다.
- EARS 작성 언어: ko (프로젝트 기본).
- 검증은 정적 grep 기반 (실행 가능 코드가 아닌 문서 변경).
- 본 SPEC 호출 흐름은 self-referential 이므로 이전 컨벤션으로 완료되어야 한다 (AC10). 워커는 본 SPEC 가 정의하는 새 contract 를 본 SPEC 의 호출 경로·브랜치 결정에 미리 적용하지 않는다.
- 사용자가 합의한 항목 안에 해당하지 않는 컨벤션 변경은 권한 초과.

## 위험

- self-referential 위험: 본 SPEC 가 spec 스킬 자체를 재정의. 본 호출 경로·브랜치는 이전 컨벤션으로 이미 결정되어 있으므로 워커는 변경이 적용되지 않는 명세 파일만 수정해야 한다 (memory `feedback_no_self_apply_during_spec`).
- 기존 호출자: 이전 컨벤션 (슬래시 자동 해석·예전 위임 형식 등) 을 쓰던 진입점이 있으면 깨진다. 워커는 수정 전 grep 으로 호출처를 확인하고 영향 범위를 NOTES.md 에 기록해야 한다.
- dispatch 위임 모드의 자동 loop start 실패 처리·롤백은 본 SPEC 범위 밖. 본 SPEC 는 contract 만 정의하며, 운영 실패 처리는 별도 task 로 다루는 것을 권장.
- task 식별자 vs 자연어 구분 휴리스틱 모호성. 워커는 현 spec step 1 의 기존 자연어 감지 휴리스틱 (물음표·따옴표·문장 부호 다중·길이 ≥ 40자 등) 을 그대로 우선 적용하고, 모호한 경계 사례는 NOTES.md 에 기록 후 사용자 결정을 따른다.
