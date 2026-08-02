# agent-kit /advisor 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Context:** 승인·커밋된 스펙 `docs/superpowers/specs/2026-08-01-advisor-design.md` 구현. 호출 세션(Worker)이 판단 전담 서브에이전트(Advisor)를 생성해 브리프 작성·결과 검증·커밋 승인을 위임받는 역할 역전 구조. 새 플러그인 **agent-kit** 0.1.0의 첫 스킬.

**Goal:** `plugins/agent-kit` 플러그인(스킬 `/advisor` + 에이전트 `advisor`)을 마켓플레이스에 등록하고 구조 검증 테스트로 계약을 고정한다.

**Architecture:** 스킬(SKILL.md)은 Worker 측 프로토콜만, 에이전트(agents/advisor.md)는 Advisor 판단 규율만 담당. 상태 태그 6종(BRIEF/QUESTION/SKIP/APPROVED/REVISE/ESCALATE)이 두 파일을 잇는 인터페이스. 셸 테스트가 계약 문구를 grep으로 고정.

**Tech Stack:** Claude Code 플러그인 (마크다운 스킬·에이전트, JSON 매니페스트), bash 구조 테스트.

## Global Constraints

- 산문은 한국어, repo 기존 문체를 따른다 (thinktank·explain-diff 참조).
- `plugins/` 워치 디렉토리 변경 → 같은 머지에서 SoT 갱신: 신규 `plugin.json` 0.1.0 + `marketplace.json` metadata.version `0.3.0` → `0.4.0` (rules/engineering/versioning.md).
- CHANGELOG.md·README.md 갱신 — explain-diff 추가 커밋(4b832f6) 패턴 준수.
- 커밋 메시지는 한국어 conventional (`feat:`, `test:`), merge commit 방식, force push 금지.
- 스펙의 결정 사항 변경 금지 (docs/superpowers/specs/2026-08-01-advisor-design.md의 확정 결정 표).
- 계획 문서 자체도 repo 컨벤션에 따라 `docs/superpowers/plans/2026-08-02-agent-kit-advisor.md`로 저장·커밋한다 (Task 0).

---

### Task 0: 계획 문서 저장

**Files:**
- Create: `docs/superpowers/plans/2026-08-02-agent-kit-advisor.md` (이 계획 파일 내용 그대로)

- [ ] **Step 1: 이 계획 내용을 위 경로에 저장**
- [ ] **Step 2: 커밋**

```bash
git add docs/superpowers/plans/2026-08-02-agent-kit-advisor.md
git commit -m "docs: agent-kit /advisor 구현 계획 추가"
```

---

### Task 1: 플러그인 매니페스트 + 마켓플레이스 등록

**Files:**
- Create: `plugins/agent-kit/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Produces: 플러그인 이름 `agent-kit`(후속 태스크의 에이전트 참조 `agent-kit:advisor`의 접두), 버전 `0.1.0`(Task 4 테스트의 릴리스 핀).

- [ ] **Step 1: plugin.json 작성**

```json
{
  "name": "agent-kit",
  "version": "0.1.0",
  "description": "에이전트 협업 유틸 모음 — 판단 전담 Advisor가 Worker를 감독하는 위임·검증 워크플로 제공",
  "author": {
    "name": "예의상",
    "email": "ch.courtesy@gmail.com"
  },
  "license": "MIT",
  "keywords": ["advisor", "delegation", "verification", "supervision", "agents", "workflow"]
}
```

- [ ] **Step 2: marketplace.json 갱신**

`metadata.version`을 `"0.3.0"` → `"0.4.0"`으로 올리고, `plugins` 배열 끝에 추가:

```json
{
  "name": "agent-kit",
  "source": "./plugins/agent-kit",
  "description": "판단 전담 Advisor 에이전트가 Worker(호출 세션)를 감독하는 위임·검증 워크플로",
  "version": "0.1.0",
  "category": "productivity",
  "tags": ["advisor", "delegation", "verification", "supervision", "agents", "workflow"]
}
```

- [ ] **Step 3: JSON 유효성 검증**

```bash
python3 -c 'import json; print(json.load(open("plugins/agent-kit/.claude-plugin/plugin.json"))["name"])'
python3 -c 'import json; m=json.load(open(".claude-plugin/marketplace.json")); print(m["metadata"]["version"], next(p["version"] for p in m["plugins"] if p["name"]=="agent-kit"))'
```
Expected: `agent-kit` / `0.4.0 0.1.0`

- [ ] **Step 4: 커밋**

```bash
git add plugins/agent-kit/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat: agent-kit 플러그인 매니페스트 추가·마켓플레이스 등록 (0.3.0→0.4.0)"
```

---

### Task 2: Advisor 에이전트 정의

**Files:**
- Create: `plugins/agent-kit/agents/advisor.md`

**Interfaces:**
- Consumes: 플러그인 이름 `agent-kit` (Task 1).
- Produces: 상태 태그 6종 문자열 `BRIEF`/`QUESTION`/`SKIP`/`APPROVED`/`REVISE`/`ESCALATE`, 브리프 필드(목표/대상 파일/컨벤션/함정/완료 기준), REVISE 라운드 표기 `라운드 N/3` — Task 3 SKILL.md와 Task 4 테스트가 이 문자열에 의존.

- [ ] **Step 1: agents/advisor.md 작성** (전문 그대로)

````markdown
---
name: advisor
description: >
  판단 전담 감독 에이전트. /advisor 스킬이 생성하며, 요구사항 분석, 작업 분해,
  설계 결정, 작업 브리프 작성, 결과 검증(diff·테스트 직접 실행), 커밋 승인을
  담당한다. 구현 노동은 Worker(호출 세션)에게 위임한다.
tools: [Read, Grep, Glob, Bash, Edit, Write]
---

너는 Advisor다. 판단에 집중하고, 구현 노동은 Worker(너를 생성한 호출 세션)에게 위임하라.

## 출력 계약

모든 응답의 첫 줄은 상태 태그 하나다: `BRIEF` / `QUESTION` / `SKIP` / `APPROVED` / `REVISE` / `ESCALATE`. 태그 아래에 그 상태의 본문을 쓴다. 상태 태그 없는 응답은 계약 위반이다.

## 분석 턴 (첫 응답)

스폰 프롬프트로 과제와 Worker가 파악한 컨텍스트를 받는다. 요구사항을 분석하고, 부족한 컨텍스트만 Read/Grep/Glob/Bash로 직접 탐색한 뒤 셋 중 하나로 응답한다.

- `SKIP` — 한두 줄 수정처럼 위임 오버헤드가 구현 비용보다 큰 작업. Worker가 직접 처리하도록 근거와 함께 즉시 종료한다.
- `QUESTION` — 사용자 확인 없이는 진행할 수 없는 모호성. 질문 목록을 쓴다. Worker가 사용자에게 릴레이하고 답변을 회신하면 분석을 재개한다.
- `BRIEF` — 작업 브리프. Worker가 재탐색하지 않도록 자기완결적으로 쓴다:
  - **목표**: 검증 가능한 성공 기준
  - **대상 파일**: 정확한 경로 (필요 시 라인 범위)
  - **컨벤션**: 따라야 할 프로젝트 규약·기존 패턴
  - **함정**: 알려진 주의점
  - **완료 기준**: 통과해야 할 테스트·검증 명령 (정확한 명령줄)

## 검증 턴 (완료 보고 수신 시)

Worker의 완료 보고를 그대로 믿지 마라. 직접 확인한다.

1. `git diff`로 실제 변경을 직접 확인한다 (보고와 대조).
2. 브리프의 완료 기준 명령(테스트 등)을 직접 실행한다.
3. 판정한다:
   - `APPROVED` — 완료 기준 충족. 커밋 메시지 초안과 사용자 보고문을 함께 반환한다.
   - `REVISE` — 미충족. 무엇이 왜 실패했는지 관찰된 증거와 수정 브리프를 쓴다. 본문에 라운드를 명시한다 (예: `라운드 2/3`).
   - `ESCALATE` — REVISE 3라운드를 초과했거나 브리프 자체가 잘못됐다고 판단될 때. 상황 요약, 시도 이력, 사용자에게 제시할 선택지를 쓴다.

직접 수정은 사소한 마무리(오타, 누락 개행, 한두 줄)에만 허용된다. 그 이상은 반드시 REVISE로 재위임한다. 직접 수정했다면 무엇을 왜 고쳤는지 판정 본문에 명시한다.

## 금지

- 구현 노동(기능 코드·테스트 코드 작성)을 직접 하지 않는다. Edit/Write는 사소한 마무리 전용이다.
- 커밋·푸시를 직접 실행하지 않는다. 커밋은 승인 후 Worker의 몫이다.
- 사용자와 직접 대화할 수 없다. 사용자 입력이 필요하면 QUESTION 또는 ESCALATE로 Worker에게 릴레이를 맡긴다.
````

- [ ] **Step 2: 계약 문구 확인**

```bash
for tag in BRIEF QUESTION SKIP APPROVED REVISE ESCALATE; do grep -q "$tag" plugins/agent-kit/agents/advisor.md || echo "누락: $tag"; done
grep -qF 'tools: [Read, Grep, Glob, Bash, Edit, Write]' plugins/agent-kit/agents/advisor.md && echo OK
```
Expected: 누락 출력 없음, `OK`

- [ ] **Step 3: 커밋**

```bash
git add plugins/agent-kit/agents/advisor.md
git commit -m "feat: agent-kit advisor 에이전트 정의 — 판단 전담·상태 태그 출력 계약"
```

---

### Task 3: /advisor 스킬 (Worker 측 프로토콜)

**Files:**
- Create: `plugins/agent-kit/skills/advisor/SKILL.md`

**Interfaces:**
- Consumes: 에이전트 참조 `agent-kit:advisor` (Task 1·2), 상태 태그 6종 (Task 2).
- Produces: 완료 보고 형식(변경 파일 목록/변경 요약/완료 기준 실행 결과) — Task 4 테스트가 문구에 의존.

- [ ] **Step 1: SKILL.md 작성** (전문 그대로)

````markdown
---
name: advisor
description: "구현 작업을 판단 전담 Advisor 에이전트의 감독 아래 수행할 때 사용. 사용자가 'advisor', '감독 받으며 구현', '검증 위임'을 요청할 때 활성화. 호출 세션은 Worker로서 구현을 담당하고, Advisor가 요구사항 분석·작업 브리프·결과 검증·커밋 승인을 담당한다."
---

# advisor

호출 세션(너)은 **Worker**다. 판단 전담 **Advisor** 서브에이전트를 생성해 감독 아래 구현한다. Advisor가 브리프 작성·결과 검증·커밋 승인을 소유하고, Worker는 구현 노동과 사용자 릴레이를 소유한다.

## 호출

`/advisor <과제>` — 과제가 없으면 현재 대화에서 사용자가 요청한 작업을 과제로 삼는다.

## 워크플로

1. **컨텍스트 패키징 + 스폰.** Agent 도구로 Advisor를 생성한다 (`subagent_type: "agent-kit:advisor"`, 동기 실행). 스폰 프롬프트에 담는다:
   - 사용자 요청 원문 (가공 없이)
   - Worker가 이미 파악한 컨텍스트: 파일 경로, 프로젝트 컨벤션, 탐색 결과, 제약
   - 알려진 완료 기준 (테스트 명령 등)
2. **첫 응답 처리.** 응답 첫 줄의 상태 태그로 분기한다.
   - `BRIEF` → 3으로.
   - `QUESTION` → 질문을 가공 없이 사용자에게 전달(구조화 질문 기능이 있으면 그것으로 묻는다), 답변을 가공 없이 SendMessage로 회신. 다시 2.
   - `SKIP` → Advisor 루프 종료. Worker가 직접 처리하고 사용자에게 결과를 보고한다.
3. **구현.** 브리프대로 구현하고 완료 기준 명령을 실행한다. 브리프 범위를 벗어난 판단이 필요해지면 임의로 정하지 말고 SendMessage로 Advisor에게 묻는다.
4. **완료 보고.** SendMessage로 Advisor에게 보고한다: 변경 파일 목록, 변경 요약, 완료 기준 실행 결과(명령과 출력 요지). 판정이 올 때까지 파일을 수정하지 않는다 (Advisor 검증 턴 — 동시 작성자 방지. Advisor의 사소한 마무리 수정과 충돌하지 않기 위함).
5. **판정 처리.**
   - `APPROVED` → 6으로.
   - `REVISE` → 수정 브리프대로 다시 구현. 3–4를 반복한다.
   - `ESCALATE` → 상황 요약과 선택지를 가공 없이 사용자에게 전달하고, 사용자 결정을 Advisor에 회신하거나 지시대로 종료한다.
6. **커밋·보고.** 사용자가 이 세션에서 커밋을 요청했을 때만 Advisor의 커밋 메시지로 커밋을 실행한다. 요청하지 않았으면 승인 사실만 보고한다. Advisor의 사용자 보고문을 가공 없이 전달한다.

## Worker 규율

- QUESTION·ESCALATE·최종 보고문은 요약·왜곡 없이 그대로 릴레이한다.
- Advisor 검증 턴 동안 파일을 수정하지 않는다.
- Advisor가 소실되거나 SendMessage가 실패하면, 지금까지의 결정·라운드 카운트를 요약해 새 Advisor를 스폰하고 루프를 이어간다.
- 브리프 준수가 원칙이다. 브리프와 사용자 지시가 충돌하면 사용자 지시가 우선하며, 충돌 사실을 Advisor에게 알린다.
````

- [ ] **Step 2: 계약 문구 확인**

```bash
for tag in BRIEF QUESTION SKIP APPROVED REVISE ESCALATE; do grep -q "$tag" plugins/agent-kit/skills/advisor/SKILL.md || echo "누락: $tag"; done
grep -qF 'agent-kit:advisor' plugins/agent-kit/skills/advisor/SKILL.md && grep -qF 'SendMessage' plugins/agent-kit/skills/advisor/SKILL.md && echo OK
```
Expected: 누락 출력 없음, `OK`

- [ ] **Step 3: 커밋**

```bash
git add plugins/agent-kit/skills/advisor/SKILL.md
git commit -m "feat: /advisor 스킬 추가 — Worker 측 위임·검증·릴레이 프로토콜"
```

---

### Task 4: 구조 검증 테스트

**Files:**
- Create: `tests/agent-kit/test-advisor-skill.sh` (실행 권한 필요)

**Interfaces:**
- Consumes: Task 1–3의 모든 계약 문자열. 릴리스 핀 `0.1.0`.

- [ ] **Step 1: 테스트 작성** (전문 그대로; `tests/thinktank/test-brainstorm-skill.sh` 스타일 준수)

````bash
#!/usr/bin/env bash
# agent-kit advisor 스킬 패키지와 프로토콜 계약 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/agent-kit"
SKILL_MD="$PLUGIN_DIR/skills/advisor/SKILL.md"
AGENT_MD="$PLUGIN_DIR/agents/advisor.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

echo "=== TEST 1: 패키지 구조 ==="
for file in "$PLUGIN_JSON" "$SKILL_MD" "$AGENT_MD"; do
  [[ -f "$file" ]] || fail "필수 파일 부재: $file"
done
ok "필수 파일 존재"

echo ""
echo "=== TEST 2: 매니페스트와 버전 ==="
PLUGIN_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$PLUGIN_JSON")"
[[ "$PLUGIN_NAME" == "agent-kit" ]] || fail "플러그인 이름 불일치: $PLUGIN_NAME"
PLUGIN_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN_JSON")"
MARKET_VERSION="$(python3 -c 'import json,sys; print(next(p["version"] for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="agent-kit"))' "$MARKETPLACE")"
[[ -n "$PLUGIN_VERSION" && "$PLUGIN_VERSION" == "$MARKET_VERSION" ]] \
  || fail "플러그인/마켓플레이스 버전 불일치: plugin.json=$PLUGIN_VERSION marketplace=$MARKET_VERSION"
# 버전 범프 회귀 가드: 릴리스 시 이 핀도 함께 올린다
EXPECTED_VERSION="0.1.0"
[[ "$PLUGIN_VERSION" == "$EXPECTED_VERSION" ]] \
  || fail "플러그인 버전이 현재 릴리스 핀과 다름: plugin.json=$PLUGIN_VERSION expected=$EXPECTED_VERSION (릴리스 시 핀 갱신)"
SOURCE_PATH="$(python3 -c 'import json,sys; print(next(p["source"] for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="agent-kit"))' "$MARKETPLACE")"
[[ "$SOURCE_PATH" == "./plugins/agent-kit" ]] || fail "마켓플레이스 source 경로 불일치: $SOURCE_PATH"
ok "매니페스트·버전 동기·릴리스 핀 ($PLUGIN_VERSION)"

echo ""
echo "=== TEST 3: 상태 태그 계약 ==="
for tag in BRIEF QUESTION SKIP APPROVED REVISE ESCALATE; do
  grep -q "$tag" "$AGENT_MD" || fail "에이전트 상태 태그 누락: $tag"
  grep -q "$tag" "$SKILL_MD" || fail "스킬 상태 태그 누락: $tag"
done
grep -qE '첫 줄.*상태 태그|상태 태그.*첫 줄' "$AGENT_MD" \
  || fail "첫 줄 상태 태그 출력 계약 누락"
ok "상태 태그 6종 양쪽 존재 + 첫 줄 출력 계약"

echo ""
echo "=== TEST 4: Advisor 판단 규율 ==="
grep -qF 'tools: [Read, Grep, Glob, Bash, Edit, Write]' "$AGENT_MD" \
  || fail "에이전트 도구 선언 불일치"
grep -qE '그대로 믿지 마라|믿지 않는다' "$AGENT_MD" \
  || fail "완료 보고 불신 계약 누락"
grep -qF 'git diff' "$AGENT_MD" \
  || fail "diff 직접 확인 계약 누락"
grep -qE '직접 실행' "$AGENT_MD" \
  || fail "완료 기준 직접 실행 계약 누락"
grep -qF '사소한 마무리' "$AGENT_MD" \
  || fail "직접 수정 허용 범위 계약 누락"
grep -qE '3라운드|라운드 2/3' "$AGENT_MD" \
  || fail "REVISE 3라운드 상한 누락"
grep -qE '커밋.*Worker의 몫|커밋.*직접 실행하지 않는다' "$AGENT_MD" \
  || fail "커밋 비실행 계약 누락"
grep -qE '자기완결' "$AGENT_MD" \
  || fail "자기완결 브리프 규범 누락"
for field in '목표' '대상 파일' '컨벤션' '함정' '완료 기준'; do
  grep -q "$field" "$AGENT_MD" || fail "브리프 필드 누락: $field"
done
ok "판단 규율·브리프 템플릿 계약"

echo ""
echo "=== TEST 5: Worker 프로토콜 ==="
grep -qF 'agent-kit:advisor' "$SKILL_MD" \
  || fail "에이전트 참조(agent-kit:advisor) 누락"
grep -qF 'SendMessage' "$SKILL_MD" \
  || fail "SendMessage 루프 계약 누락"
grep -qE '가공 없이' "$SKILL_MD" \
  || fail "무가공 릴레이 계약 누락"
grep -qE '파일을 수정하지 않는다' "$SKILL_MD" \
  || fail "검증 턴 턴제(수정 금지) 계약 누락"
grep -qE '커밋을 요청했을 때만' "$SKILL_MD" \
  || fail "사용자 커밋 요청 조건 누락"
grep -qE '새 Advisor를 스폰' "$SKILL_MD" \
  || fail "소실 시 재스폰 계약 누락"
for item in '변경 파일 목록' '변경 요약' '완료 기준 실행 결과'; do
  grep -qF "$item" "$SKILL_MD" || fail "완료 보고 형식 누락: $item"
done
ok "Worker 프로토콜 계약"

echo ""
echo "=== 모든 advisor 스킬 테스트 통과 ==="
````

- [ ] **Step 2: 실행 권한 부여 후 실행**

```bash
chmod +x tests/agent-kit/test-advisor-skill.sh
tests/agent-kit/test-advisor-skill.sh
```
Expected: `=== 모든 advisor 스킬 테스트 통과 ===` (exit 0)

- [ ] **Step 3: 기존 테스트 회귀 확인**

```bash
tests/thinktank/test-brainstorm-skill.sh >/dev/null && echo brainstorm-OK
```
Expected: `brainstorm-OK`

- [ ] **Step 4: 커밋**

```bash
git add tests/agent-kit/test-advisor-skill.sh
git commit -m "test: agent-kit advisor 구조·계약 검증 테스트 추가"
```

---

### Task 5: CHANGELOG·README 갱신

**Files:**
- Modify: `CHANGELOG.md` (헤더 설명문 바로 아래, `## explain-diff 0.1.0` 위에 삽입)
- Modify: `README.md` (플러그인 목록에 한 줄 추가 — explain-diff 항목 형식 준수)

- [ ] **Step 1: CHANGELOG 항목 추가**

```markdown
## agent-kit 0.1.0

### 새 기능
- **advisor 스킬** — 호출 세션(Worker)이 판단 전담 Advisor 서브에이전트를 생성해 감독 아래 구현하는 역할 역전 워크플로. Advisor는 요구사항 분석·작업 브리프 작성·결과 검증(diff·테스트 직접 실행)·커밋 승인을 소유하고, 구현 노동은 Worker가 수행한다. 상태 태그 6종(BRIEF/QUESTION/SKIP/APPROVED/REVISE/ESCALATE) 프로토콜, REVISE 3라운드 초과 시 사용자 에스컬레이션, 커밋은 사용자가 요청한 세션에서만 실행.
```

- [ ] **Step 2: README 플러그인 목록에 agent-kit 한 줄 추가** (기존 explain-diff 줄 형식을 보고 동일하게)

- [ ] **Step 3: 커밋**

```bash
git add CHANGELOG.md README.md
git commit -m "docs: agent-kit 0.1.0 CHANGELOG·README 갱신"
```

---

## 검증 (end-to-end)

1. `tests/agent-kit/test-advisor-skill.sh` → exit 0, 전체 통과 출력.
2. `tests/thinktank/test-brainstorm-skill.sh` → 회귀 없음.
3. `python3 -c 'import json; json.load(open(".claude-plugin/marketplace.json"))'` → 유효 JSON.
4. 수동 스모크(선택): `/reload-plugins` 후 새 세션에서 `/advisor` 호출 → 스킬 인식·Advisor 스폰·BRIEF 반환 확인.

## Self-Review 결과

- 스펙 커버리지: 확정 결정 9건 전부 태스크에 반영 (배포 형태·수명주기·하이브리드 컨텍스트·도구·커밋 흐름·3라운드·에이전트 정의·무영속·트리거 → Task 1–3 본문, Task 4 테스트 고정). 스펙의 "범위 밖" 항목은 계획에도 없음.
- placeholder: 없음 (모든 파일 전문 포함).
- 문자열 일관성: 상태 태그 6종, `agent-kit:advisor`, `사소한 마무리`, 완료 보고 3요소 — Task 2/3 본문과 Task 4 grep 패턴 대조 완료.
