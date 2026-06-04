---
scope:
  include:
    - plugins/autopilot/skills/fsd/**
    - plugins/autopilot/skills/spec/SKILL.md
    - plugins/autopilot/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  exclude:
    - rules/**
    - CLAUDE.md
    - plugins/autopilot/skills/dispatch/**
    - plugins/autopilot/skills/review/**
    - plugins/autopilot/skills/loop/**
ears_language: ko
---

# fsd: 리뷰·머지를 dispatch에 완전위임 + 완전자율운행

## 무엇을 만들 것인가

`fsd`가 자체로 들고 있던 **forge 통합·리뷰·머지·승인-대기 기계를 전부 걷어내고**, 리뷰·머지 책임을 `dispatch`의 통합 모드(기본 활성)에 **완전위임**한다. fsd는 SPEC 작성(spec)·task 등록(intake)·구현 위임(start=dispatch start)·상태 드레인(poll)만 책임지며, 구현 완료 SPEC의 통합(PR)·리뷰·머지는 `dispatch start`가 자기 통합 파이프라인 안에서 수행한다.

동시에 fsd를 **완전자율운행**으로 만든다 — 파이프라인에서 사람 개입/외부 승인 대기 지점을 제거한다. fsd가 위임하는 dispatch는 **direct 서브모드**(분리 승인 신원 없이 ff-only 자율 직접 머지)로 돌아 task가 done까지 사람 손 없이 전진한다. 기존 poll의 "미승인 PR → 외부 승인 대기 no-op" 게이트는 제거된다.

또한 fsd가 자연어 의도 진입 모드에서 spec 스킬을 호출할 수 있도록 **spec 스킬 호출 권한을 보장**하고, **fsd가 spec을 호출하는 맥락에서는 spec의 step-7 옵트인 핸드오프 프롬프트("구현까지 자동 진행할까요?")가 뜨지 않도록** 한다 — fsd는 항상 자율이라 진행 결정을 소유하므로 그 확인은 중복이다. **별도의 신호 인자(`--autonomous` 등)는 두지 않는다** — 같은 오케스트레이터가 fsd→spec를 연달아 실행하므로 호출 맥락만으로 억제가 성립한다. spec은 자율 오케스트레이터 호출 맥락에서 step-7 사용자 대면 프롬프트를 생략하되 **dispatch를 직접 호출하지 않고 SPEC 경로만 반환**한다 — dispatch 기동은 fsd의 `start`가 단독으로 하여 같은 SPEC에 dispatch가 이중 기동되지 않는다(명확화 인터뷰·미해결 마커 가드·최종 SPEC 산출은 그대로 유지 — 품질 게이트는 보존). 사람 단독 호출(문서-only 검토 경로)이면 기존 프롬프트를 유지한다.

구체 변경:

- fsd의 자체 forge/머지 레이어(`forge.sh`·`merge.sh`)와 `merge` 서브커맨드, poll의 자체 통합·승인-대기 배선을 제거한다.
- `start`는 `dispatch start`(통합 모드 ON)에 위임하며 `--no-integrate`를 붙이지 않는다 — dispatch가 implement→통합→(direct)머지를 소유한다.
- `poll`은 dispatch의 **공개 인터페이스**(`dispatch status`/`watch`)로 run 상태만 드레인해 모든 SPEC이 머지 종착에 도달하면 task를 `done`으로 전이한다. 자체 PR 생성·리뷰·승인-조회·머지를 하지 않으며 외부 승인 대기 no-op도 없다.
- fsd는 분리 승인 신원(`APPROVER`)을 설정하지 않아 dispatch가 direct 서브모드로 자율 머지하게 한다.
- `operational-guide.md`에서 approver 신원 분리·승인 게이트 서술을 제거하고, 무인 토큰 스코프 최소화·자율 실행기 자식 권한 격리·폴링 주기만 남긴다.

## 목적 (왜)

리뷰·머지 책임이 `dispatch`(통합 모드 기본 활성)와 `fsd`(자체 forge.sh/merge.sh/poll 승인-대기)에 **이중으로** 존재해, fsd가 위임한 `dispatch start`가 이미 통합·머지를 수행하는데도 fsd poll이 같은 일을 다시 시도하는 중복·충돌 구조였다. 리뷰·머지를 dispatch 한 곳에 모으고 fsd를 얇은 task 오케스트레이터로 줄여 중복을 없앤다. 아울러 사용자 개입/외부 승인 대기 지점을 제거해 fsd를 무인 완전자율 파이프라인으로 만든다.

## 완료 조건

1. 항상 `plugins/autopilot/skills/fsd/references/merge.sh`와 `plugins/autopilot/skills/fsd/references/forge.sh` 파일이 존재하지 않는다(fsd 자체 머지·forge 레이어 제거).
2. 항상 `fsd.sh`에 `merge` 서브커맨드 라우팅(`merge) cmd_merge ...`)·`cmd_merge` 함수·usage의 `merge` 줄이 없다.
3. 항상 `plugins/autopilot/skills/fsd/` 아래 어떤 파일에도 `POLL_FORGE_CMD`, `POLL_MERGE_CMD`, `cmd_merge`, `외부 승인 대기`, `approval`, `APPROVER` 문자열이 남지 않는다.
4. `fsd start`(=`cmd_start`)는 SPEC(들)을 `dispatch start`에 위임하며 `--no-integrate` 플래그를 전달하지 않는다(dispatch 통합 모드가 켜진 채 위임된다).
5. `poll`의 `poll_task`는 진행 중 task에 대해 dispatch의 공개 인터페이스(`dispatch status`)로 per-SPEC state만 관측하며, 자체 PR 생성·리뷰·승인 조회·머지를 호출하지 않는다. dispatch의 종착 상태(`done|failed|skipped`)로 task를 전이한다 — 비종착(`pending|running|integrating` 등)이 하나라도 남으면 상태 불변(같은 상태 재드레인 멱등), 전부 종착이며 전부 `done`이면 task `done`, 전부 종착이나 일부 `failed`/`skipped`면 task `dispatch-failed`(운영자가 실패를 감지·재시작할 수 있게 한다 — 실패 run이 `dispatched`에 영구 정체하지 않는다). 미승인 PR을 기다리는 "외부 승인 대기" 분기는 없다.
6. `poll`/start 경로 어디에도 사람 개입을 요구하거나 외부 승인을 기다리며 멈추는 지점이 없다 — 진행 중 task는 dispatch가 종착(머지/실패/skip)시킬 때까지 자율 전진하며, 사람 입력을 차단 조건으로 두지 않는다.
7. `fsd/SKILL.md`의 `allowed-tools`에 `Skill`이 포함되어 fsd가 `spec`·`dispatch` 스킬을 호출할 수 있다. SKILL.md 본문은 자연어 의도 진입 모드에서 `Skill(skill: "spec", ...)`로 SPEC을 산출함을 명시한다.
7a. fsd가 자연어 의도 진입 모드에서 spec을 호출할 때 **별도의 자율 모드 인자(`--autonomous` 등)를 전달하지 않는다** — `fsd/SKILL.md`는 fsd가 항상 자율이므로 호출 맥락만으로 spec의 step-7 프롬프트가 생략됨을 명시한다.
7b. `spec/SKILL.md`는 **자율 오케스트레이터(`autopilot:fsd` 등)가 호출하는 맥락에서** step-7 옵트인 핸드오프 프롬프트("구현까지 자동 진행할까요?")를 **생략**함을 명시한다(별도 인자 불필요). 이 맥락에서 **spec은 `autopilot:dispatch`를 직접 호출하지 않고 산출된 SPEC 경로만 오케스트레이터에 넘긴다** — dispatch 기동은 오케스트레이터(fsd의 `start`)가 단독으로 하여, spec의 handoff와 오케스트레이터의 start가 같은 SPEC에 dispatch를 **이중 기동하지 않는다**. 명확화 인터뷰·미해결 마커 가드·최종 SPEC 산출은 그대로 수행한다(미해결 마커가 남으면 자율 맥락이어도 경로를 넘기지 않고 `--resume`를 안내). 사람 단독 호출(문서-only 검토 경로)이면 기존 step-7 핸드오프 프롬프트·동의 시 dispatch 호출 동작을 유지한다(하위 호환). 어느 문서에도 `--autonomous` 같은 신호 인자가 남지 않는다.
7d. fsd 자연어 진입 경로에서 dispatch는 **fsd의 `start`만** 기동한다(spec은 경로 반환만) — 같은 SPEC에 중복 dispatch run/머지가 발생하지 않는다.
7c. 항상 `spec/SKILL.md` 외 `skills/spec/` 의 다른 파일(references 등)은 변경되지 않는다.
8. `fsd/SKILL.md`·`fsd.sh` usage·`plugin.json`·`marketplace.json`의 fsd 서브커맨드 집합과 설명에 `merge`가 없고 `intake·start·poll`(및 status/list/stop)만 남으며, 리뷰·머지를 dispatch가 소유함과 fsd가 완전자율(외부 승인 대기 없음)임을 반영한다.
9. `operational-guide.md`에 approver 신원 분리(`APPROVER`≠`REVIEW_BOT`)·self-approve 무효화·승인 게이트·"승인된 PR만 머지" 서술이 남지 않고, 무인 토큰 스코프 최소화·자율 실행기 자식 권한 격리(머지·base push 권한 미상속)·폴링 주기 안내는 보존된다. 완전자율 direct 머지 모델과 정합한다.
10. `fsd/SKILL.md`·`operational-guide.md`·`forge-integration.md`에 리뷰·머지·통합을 fsd가 수행한다는 서술이 남지 않고, 그 책임이 `dispatch`(통합 모드)에 있음을 가리킨다.
11. `bash plugins/autopilot/skills/fsd/references/fsd.sh selftest`가 ALL PASS 한다(merge 제거·start 통합위임 회귀 가드 포함).
12. `bash plugins/autopilot/skills/fsd/references/poll.sh selftest`가 ALL PASS 하고, "비종착 남음 → 전진 없음·상태 불변", "전부 종착·전부 done → task done 전이", "전부 종착·일부 failed/skipped → task dispatch-failed 전이" 케이스를 포함하며 외부 승인 대기 케이스는 포함하지 않는다.
13. 남는 셸 스크립트(`fsd.sh`·`poll.sh`·`lib-state.sh`)가 `bash -n` 문법 검사를 통과한다. `lib-state.sh`에 제거된 forge/머지/승인 전용 헬퍼가 있으면 함께 제거되고 잔여 참조가 없다.
14. `plugins/autopilot/.claude-plugin/plugin.json`과 `.claude-plugin/marketplace.json`의 autopilot 설명에서 fsd 괄호가 `(intake·start·poll)`이고 리뷰·머지를 dispatch가 소유함과 정합하며, 두 파일의 autopilot version이 `0.24.0`이다. 두 파일 모두 `jq .`로 유효하다.
15. 항상 `dispatch`·`review`·`loop` 스킬 디렉토리는 변경되지 않고, `spec` 스킬은 `SKILL.md`(step-7 핸드오프 억제 규약)만 변경되며 그 외 `skills/spec/` 파일은 무손상이다(dispatch 통합·리뷰·머지 무손상).

## 범위

포함:
- `plugins/autopilot/skills/fsd/references/merge.sh`·`forge.sh` 삭제
- `fsd.sh`: `merge` 서브커맨드·`cmd_merge`·usage 줄 제거, start의 dispatch 통합위임 보존(--no-integrate 미전달)
- `poll.sh`: 자체 forge/머지/승인-대기 배선 제거, dispatch 공개 인터페이스 상태 드레인으로 재작성, 외부 승인 대기 no-op 제거, selftest 갱신
- `lib-state.sh`: 제거된 레이어 전용 헬퍼·잔여 참조 정리(필요 시)
- `fsd/SKILL.md`: 서브커맨드 집합·진입 모드·불변식·description 갱신(merge 제거, dispatch 위임·완전자율 명시), allowed-tools의 `Skill` 보장, spec을 별도 인자 없이 호출하되 fsd 맥락에서 step-7 프롬프트가 생략됨을 명시
- `spec/SKILL.md`: 자율 오케스트레이터 호출 맥락에서 step-7 옵트인 핸드오프 프롬프트 생략 규약 추가(별도 인자 불필요, 사람 단독 호출이면 기존 동작 유지)
- `operational-guide.md`: approver 분리·승인 게이트 절 제거, 토큰 스코프·자식 권한 격리·폴링 주기 보존
- `forge-integration.md`: 리뷰·머지·통합 책임이 dispatch에 있음으로 정합
- `plugin.json`(단일 출처)·`marketplace.json`(미러): fsd 괄호·설명·version 0.24.0 갱신

비-목표 / 제외:
- `dispatch`(`skills/dispatch/`) 통합·리뷰·머지 로직 변경 — **보존**(fsd는 dispatch 공개 인터페이스만 소비)
- `autopilot:review` 스킬(`skills/review/`)·`loop` 스킬 변경, 그리고 `spec` 스킬의 `SKILL.md` 외 변경(references 등) — `spec/SKILL.md`의 핸드오프 억제 규약만 변경
- `rules/**`·`CLAUDE.md` 변경
- dispatch의 forge 서브모드(APPROVER 사용) 자체 제거 — dispatch는 그대로 두고, fsd가 APPROVER를 설정하지 않아 direct 서브모드로 위임할 뿐이다
- task backend(이슈/Project) 연동 신규 구현

## 검증

이 SPEC의 인수 바는 위 **완료 조건**이다. 검증 진입 명령은 프로젝트 규칙(`rules/`)이 단일 출처다.

## 제약

- `SKILL.md` 편집은 `superpowers:writing-skills` 관례를 따른다.
- 셸 스크립트는 bash 3.2+ 호환을 유지한다.
- fsd는 `.fsd/` 디렉토리 밖 경로를 만들지 않고, dispatch·loop·spec의 정의 파일을 수정하지 않으며 공개 서브커맨드(`dispatch start|status|watch|stop`, `Skill(spec)`)만 소비한다.
- 구현 위임·상태 드레인은 dispatch의 공개 인터페이스로만 하고 dispatch 내부 신호 파일·run 디렉토리·워크트리를 직접 들여다보지 않는다.
- `plugin.json`(단일 출처)·`marketplace.json`(미러) 버전·설명을 함께 `0.24.0`으로 올린다([[dispatch-plugins-version-bump-at-integration]]). 버전 범프는 `rules/engineering/versioning.md`를 따른다.
- force push·rebase·force merge를 쓰지 않는다(머지는 dispatch가 ff-only로 수행).

## 위험

- 완전자율 direct 머지는 외부 승인 게이트 없이 main에 머지한다 — 의도된 동작(사용자 결정: 완전자율·개입 없음). 안전망은 dispatch의 ff-only·버전 범프 게이트·loop BLOCKED 신호이며 fsd는 이를 우회하지 않는다. 완료 조건 5·6이 이를 고정한다.
- fsd 자체 forge/머지 제거 후 dispatch가 머지를 수행하지 못하는 환경(forge 미구성·direct 불가)에서는 task가 done에 이르지 못할 수 있다 — 이때 dispatch run의 SPEC이 `failed`/`skipped`로 종착하면 poll이 task를 `dispatch-failed`로 전이해 운영자가 실패를 감지·재시작할 수 있고(완료 조건 5), 아직 비종착이면 멱등 재드레인하며 상태를 유지한다. dispatch direct 서브모드는 forge 없이도 ff-only 직접 머지하므로 일반 환경에서 자율 종착한다.
- dispatch는 보존하지만 fsd가 그 동작에 의존하므로, 완료 조건 15(dispatch 무손상)와 11·12 selftest로 회귀를 가드한다.
