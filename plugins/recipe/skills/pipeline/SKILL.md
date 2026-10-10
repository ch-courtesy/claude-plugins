---
name: pipeline
description: 여러 단계 작업을 graph.json 그래프로 설계해 실행 가능한 워크플로 스킬로 컴파일할 때 사용. 신호 — 여러 스킬을 이어 붙이기, 워크플로 스킬 만들기, 그래프·transform 수정, 재컴파일, verify-materials 실패. CI(GitHub Actions 등)·외부 오케스트레이터 설정에는 쓰지 않는다.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
  - Skill
---

# pipeline — 그래프 생산

사용자가 원하는 워크플로를 그래프(`graph.json`)로 설계하고, 재료를 재사용하거나 만들어, 실행 가능한 워크플로 스킬로 컴파일한다. 구조 판정은 전부 `pipecheck`에 위임한다 — 직접 판정하지 않는다.

`/skill`·`/pipeline`은 같은 플러그인의 `skill`·`pipeline` 스킬이다 — 런타임에 따라 `recipe:skill`처럼 플러그인 접두가 붙는다.

**번호 표기** — 본문과 references의 절 번호는 설계 스펙 번호다. 이렇게 읽는다:
- 7.1 = 아래 절차 체크리스트(1~7단계). "7.1의 2~5"는 그 2~5단계, 7.1-5는 5단계(검사)
- 7.4 = [references/failure.md](references/failure.md)(실패 보고 형식·전이)
- 7.5 = [references/approval.md](references/approval.md)(승인 화면·전이 표)
- 7.6 = [references/diagram.md](references/diagram.md)(그림 문법)
- 7.7 = 승인 화면의 워크플로 자신의 이름·위치·설명 확정(approval.md "최상위 확정")과 그 뒤의 [references/compile.md](references/compile.md)
- 8 재검사 = 승인 화면의 수정 요청 뒤 도는 `check-graph` 재검사
- 9 = 컴파일된 워크플로의 실행 지시서([references/runner.md](references/runner.md)), 9.1 = 그 절차 1의 `verify-materials` 대조
- 5.2·5.5·5.7 = [references/graph-format.md](references/graph-format.md)의 골격 예제·transform `aligned`·`combine` 규칙, 5.8 = `pipecheck hash`의 해시 정규형(이름이 본문 해시에 든다)
- 6.1.1 = `/skill`의 초안 확정(이름 충돌 세 선택지), 6.1.1-2 = 그 계약 초안, "6.1.1의 3" = `/skill`의 본문 쓰기, 6.1.4 = `/skill` 승인 순서 2(설치·위치 변경), 6.4 = `/skill`의 검증 루프(재작성 3회)

## 판정 도구

판정 도구 명령은 프로젝트 루트에서 실행한다.

```bash
OS=$(uname -s | tr A-Z a-z); EXT=""
case "$OS" in mingw*|msys*|cygwin*) OS=windows; EXT=".exe" ;; esac  # Windows Git Bash 는 uname -s 가 MINGW64_NT-… 등
BIN="<이 SKILL.md가 있는 디렉터리>/../../tools/pipecheck/dist/pipecheck-$OS-$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')$EXT"
```

- 그래프 검사: `"$BIN" check-graph -file <임시 위치>/<이름>/graph.json -project .claude/skills -user ~/.claude/skills -self-name <이름> -self-scope <scope> -overlay <임시 위치>` — `-overlay`는 임시 위치 루트다: 승인 전 신규·수정 재료를 설치본보다 먼저 찾게 한다
- 표현식 단건: `echo '{"expr":"...","in":{...}}' | "$BIN" check-expr` — transform·until 식을 초안·수정할 때 그 식만 먼저 확인하고, 불통과면 그 출력대로 식을 고쳐 다시 확인한다. 3회 안에 못 고치면 불통과 출력과 의도를 구조화된 사용자 질문 기능으로 묻고, 답대로 고쳐 다시 확인한다 — 그래도 불통과면 같은 문답을 반복한다. 물리면 최초 패스 중에는 실행을 그만두는 처리와 같고, 승인 화면의 수정 요청이 촉발한 재검사 중에는 그 수정을 되돌리고 화면을 유지한다
- 해시·파급: `/skill`과 같은 `hash`·`ripple`

출력은 한 줄 JSON, 불통과는 exit 1. exit 2는 호출 오류 — 명령을 고쳐 같은 호출을 다시 부르는 연속 시도를 3회까지 하고, 그래도 exit 2면 그 출력과 시도한 명령을 보고하고 오류로 끝낸다. 통과하거나 다른 호출로 넘어가면 시도 횟수는 남지 않는다. 바이너리가 없으면 `<이 SKILL.md가 있는 디렉터리>/../../tools/pipecheck/build.sh`를 먼저 실행해 만든다 — 파일 시각은 설치·체크아웃 때 새로 찍혀 소스 변경 판단에 쓰지 않는다(pipecheck 소스를 고친 쪽이 커밋 전에 build.sh 로 dist 를 갱신한다). 빌드가 실패하면 그 출력을 보고한다 — 승인 화면이 열려 있으면 그 화면으로 돌아가고, 아니면 실행을 끝낸다.

## 절차 체크리스트 (§7.1)

```
- [ ] 1. 워크플로 서술 받기
- [ ] 2. 그래프로 분해 (references/decompose.md)
- [ ] 3. 노드마다 재료 탐색·확보 (references/candidates.md)
- [ ] 4. 경계 포트·배선 확정
- [ ] 5. check-graph 검사 (실패 처리는 references/failure.md)
- [ ] 6. 그림 + 승인 화면 (references/diagram.md, references/approval.md)
- [ ] 7. 컴파일·설치 (references/compile.md)
```

앞 단계가 확정되기 전에 다음 단계 산출물을 만들지 않는다. 작업 공간은 임시 위치(`mktemp -d`) — 산출물은 스킬·워크플로 구분 없이 `<임시 위치>/<이름>/`에 놓고, 워크플로는 그 안에 `graph.json`·`SKILL.md`를 둔다. 산출물의 이름·위치가 바뀌거나 같은 이름이 둘 이상 얽히면 [references/rename.md](references/rename.md)를 따른다 — 이 실행의 그래프·어댑터가 기록한 이름과 해시를 함께 고쳐야 하고, 같은 실행에 동명 산출물은 하나여야 한다. 승인 전에는 아무것도 설치하지 않는다. 사용자가 실행 전체를 그만두면 어느 단계든 임시 위치를 지우고 진행 상태를 보고하며 끝낸다 — 승인 화면의 수정 요청·문답 취소는 전이 표대로 화면을 유지한다. 오류로 끝나는 모든 경로도 같다 — 단독 실행이면 임시 위치를 지우고, 위임·재귀 호출이면 실패를 상위에 반환하며 임시 위치는 상위가 지운다.

## 1. 서술

무엇을 입력으로 받아 무엇을 내는 워크플로인지, 중간에 어떤 판단·반복이 있는지 받는다. 워크플로 이름·설치 위치 초안도 여기서 정한다(위치 초안은 `project`) — 임시 디렉터리와 검사의 `-self-name`·`-self-scope`에 쓰기 위해서다. 이름 규칙은 재료와 같고, 확정은 승인 화면의 7.7이 한다.

**기존 워크플로 수정·재컴파일이면 진입이 다르다**: 대상 워크플로(name+scope)를 지정받아 `graph.json`을 초안으로 읽는다 — 이 실행의 임시 위치에 그 워크플로의 것이 있으면 그것, 없으면 설치본을 `<임시 위치>/<이름>/graph.json`으로 복사해 그것을 작업본으로 쓴다. 같은 이름 유지가 수정이며 충돌이 아니고, 이름을 바꾸는 경우는 7.7 규칙(두 선택지 — 다른 이름/변경 취소)을 따른다. 진입 뒤 도는 범위는 세 갈래다:
- 사용자가 직접 부른 최상위 수정 — 무엇을 어떻게 바꿀지 서술을 함께 받고 2~7 전부를 돈다
- 상위 `/pipeline`이 분해·수정 중에 부른 재귀 호출 — 1~5만. 신규 하위면 1의 서술과 이름·위치 초안을 상위가 분해에서 정해 넘기고, 기존 하위의 수정이면 위 진입 규칙대로 초안 `graph.json`을 읽는다 — 이 진입 정보(서술·이름·위치 초안)는 어느 쪽도 사용자에게 다시 묻지 않는다. 승인·컴파일·설치는 최상위가 한다
- `/skill`이 넘긴 "그 자리 재컴파일"(파급 문답의 예 답) — 구성 변경 없이 바뀐 재료의 `materials` 항목을 갱신하고 — 이름·위치가 바뀐 재료면 `name`·`scope`와 노드·컨테이너의 `skill` 참조도 새 값으로 — 승인이 `/skill` 화면에 이미 합쳐져 있으므로 5(check-graph)와 7(컴파일·설치)만 돈다. 5가 불통과면 재료·배선을 고치지 않고 그 보고를 부른 `/skill`에 실패로 반환한다 — 복구는 `/skill` 승인 절차가 맡는다. `/skill`이 수정 스킬을 이미 설치한 뒤 부르므로 그 산출물은 다시 옮기지 않고, 이 재컴파일이 낡게 하는 어댑터의 연쇄 재기록과 후속 문답은 부른 `/skill`의 승인 절차가 맡는다 — 이 경로는 보고만 한다. 임시 위치도 부른 `/skill`이 넘긴 것을 쓴다 — 새로 만들지 않고, 지우지도 않는다

## 2. 분해

[references/decompose.md](references/decompose.md)의 기준으로 노드·transform·컨테이너를 가른다. 값 가공은 transform 식으로, 도구 실행·판단은 노드로, 반복은 컨테이너로.

## 3. 재료

[references/candidates.md](references/candidates.md)의 절차로 노드마다 후보를 찾는다. 맞는 것이 없으면 `/skill`을 불러 이 실행의 임시 위치를 넘겨 그 안에 만든다 — `/skill`은 검증까지만 수행하고 승인은 이 화면에 합쳐진다.

**분해 결과가 그래프인 단계도 먼저 candidates.md의 절차로 재사용·감쌀 후보를 찾고, 맞는 것이 없으면 `/pipeline`을 재귀로 불러 하위 워크플로를 같은 임시 위치에 만든다** — 하위 호출은 1~5단계만 돌고 자기 승인·설치·컴파일을 갖지 않는다. 하위 호출이 끝나면 — 신규 생성이든 기존 하위의 수정이든 — `graph.json` 곁에 경계 계약(`node:` 블록)을 담은 `SKILL.md`를 임시 위치에 생성한다 — 상위 검사의 `-overlay`가 하위 계약을 해소하기 위해서다. 본문 세 절은 최상위의 7 컴파일이 완성한다. 승인·컴파일·설치는 전부 최상위가 한다. 이 실행에서 만드는 중인 워크플로 — 최상위와 중간 전부, `name`+`scope`로 판정 — 를 하위에서 다시 만들려 하면 재료 이름·설치 위치·실행 경로를 보고하며 오류로 끝낸다.

## 4. 배선

경계 포트를 정하고 data·order 엣지를 적는다. 형식·규칙은 [references/graph-format.md](references/graph-format.md).

## 5. 검사

`check-graph`를 돌린다. 실패 처리·보고 형식은 [references/failure.md](references/failure.md) — 어긋난 재료를 바꾸거나 배선을 고치고 다시 돈다. `/skill` 위임 재컴파일이면 고치지 않고 부른 `/skill`에 실패로 반환한다.

## 6. 승인

그림([references/diagram.md](references/diagram.md))과 승인 화면([references/approval.md](references/approval.md))을 보여주고 3택+자유 서술로 받는다. 수정 요청 해석·전이는 approval.md의 표가 정한다.

## 7. 컴파일·설치

승인되면 [references/compile.md](references/compile.md)대로 — 하위 워크플로부터, 전이 닫힘의 산출물 전부를 설치하고, 실패하면 전부 되돌린다. `/skill` 위임 재컴파일이면 자기 산출물만 되돌리고 실패를 부른 `/skill`에 반환한다.
