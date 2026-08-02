# /advisor 스킬 설계 스펙 (agent-kit 플러그인)

날짜: 2026-08-01
상태: 사용자 리뷰 대기

## 개요

호출 세션(Worker)이 판단 전담 서브에이전트(Advisor)를 생성해, 요구사항 분석·작업 분해·설계 결정·작업 브리프 작성·결과 검증·커밋 승인을 위임받는 스킬. Advisor는 판단에 집중하고 구현 노동은 Worker가 수행한다. 역할 역전 구조: 메인 세션이 Worker, 서브에이전트가 Advisor다.

새 플러그인 **agent-kit**(`plugins/agent-kit`)의 첫 스킬로 추가한다. agent-kit은 향후 workflow 계열 등 에이전트 유틸 스킬을 담는 그릇이다.

## 확정된 결정

| 결정 | 선택 |
|---|---|
| 배포 형태 | 새 플러그인 `plugins/agent-kit` 0.1.0, 마켓플레이스 등록 |
| Advisor 수명주기 | 지속 서브에이전트 1개 + SendMessage 왕복 루프 |
| 초기 컨텍스트 | 하이브리드 — Worker가 아는 것을 스폰 프롬프트에 패키징, Advisor가 부족분만 직접 탐색 |
| Advisor 도구 | Read, Grep, Glob, Bash + Edit, Write (프롬프트 규율로 "사소한 마무리"만 수정 허용) |
| 커밋 흐름 | Advisor 승인 → Worker가 커밋 실행(사용자가 커밋을 요청한 세션에서만) → 보고문 릴레이 |
| 수정 루프 상한 | REVISE 3라운드 초과 시 사용자 에스컬레이션 |
| 에이전트 정의 | 플러그인 `agents/advisor.md` 커스텀 에이전트 (선언적 도구 제한, model 상속) |
| 기록 영속화 | 없음 — 대화 왕복만. 세션 파일 만들지 않음 |
| 트리거 | 수동 위주. description에 명확한 트리거 문구만("advisor", "감독 받으며 구현", "검증 위임") |

## 아키텍처·프로토콜

```
Worker(호출 세션) ──/advisor <과제>──▶ Advisor(지속 서브에이전트)
       ◀── BRIEF / QUESTION / SKIP ──
       ── 구현 후 완료 보고 (SendMessage) ──▶
       ◀── APPROVED / REVISE / ESCALATE ──
```

1. **호출.** Worker가 `/advisor <과제>` 호출. 사용자 요청 원문, 이미 파악한 탐색 결과, 제약을 스폰 프롬프트에 패키징해 Advisor를 생성한다.
2. **분석 턴.** Advisor는 요구사항을 분석하고 부족한 컨텍스트를 직접 탐색한 뒤 셋 중 하나를 반환한다.
   - **BRIEF** — 자기완결적 작업 브리프: 목표, 파일 경로, 프로젝트 컨벤션, 알려진 함정, 완료 기준(통과해야 할 테스트). Worker가 재탐색하지 않아도 되게 작성한다.
   - **QUESTION** — 사용자 확인이 필요한 모호성. Worker가 사용자에게 릴레이하고 답변을 가공 없이 SendMessage로 회신한다.
   - **SKIP** — 위임 오버헤드가 더 큰 사소한 작업. Worker가 직접 처리하고 Advisor 루프는 종료한다.
3. **구현.** Worker가 브리프대로 구현하고 테스트를 실행한 뒤, 변경 파일 목록·요약·테스트 결과를 SendMessage로 보고한다.
4. **검증 턴.** Advisor는 완료 보고를 그대로 믿지 않는다. `git diff`를 직접 확인하고 테스트를 직접 실행한 뒤 판정한다.
   - **APPROVED** — 승인. 커밋 메시지와 사용자 보고문을 함께 반환한다.
   - **REVISE** — 수정 브리프로 재위임. 라운드 카운트를 올린다. 사소한 결함은 Advisor가 직접 수정한 뒤 승인해도 된다.
   - **ESCALATE** — REVISE 3라운드 초과 시 상황 요약과 선택지를 반환. Worker가 사용자에게 질문한다.
5. **커밋.** Advisor 승인 + 사용자가 커밋을 요청한 세션일 때만 Worker가 커밋을 실행한다. 보고문은 Worker가 사용자에게 릴레이한다.
6. **턴제.** Advisor 검증 턴 동안 Worker는 파일을 수정하지 않는다(동시 작성자 방지). Advisor의 직접 수정은 검증 턴 안에서만 일어난다.

## 컴포넌트

```
plugins/agent-kit/
  .claude-plugin/plugin.json    # name: agent-kit, version: 0.1.0
  skills/advisor/SKILL.md       # Worker 측 프로토콜
  agents/advisor.md             # Advisor 시스템 프롬프트 + 도구 제한
```

`.claude-plugin/marketplace.json`에 agent-kit 항목을 등록한다. `plugins/` 변경이므로 버전 규칙(rules/engineering/versioning.md)에 따라 같은 머지 안에서 SoT(plugin.json 0.1.0 신설, 마켓플레이스 metadata.version 증가)를 갱신한다.

### agents/advisor.md 골자

- 역할: 판단 전담. 요구사항 분석, 작업 분해, 설계 결정, 브리프 작성, 검증, 커밋 승인. 구현 노동 금지.
- 도구: Read, Grep, Glob, Bash, Edit, Write. model 오버라이드 없음(상속).
- 브리프 템플릿: 목표 / 대상 파일 경로 / 컨벤션 / 함정 / 완료 기준(통과 테스트 명령).
- 검증 규율: 보고를 믿지 않는다. diff·테스트 직접 실행 후 판정. 근거는 관찰된 증거로 말한다.
- 수정 허용 범위: 사소한 마무리(오타, 누락 개행, 한두 줄)만. 그 외는 REVISE 브리프로 재위임.
- 출력 형식: 모든 턴의 첫 줄에 상태 태그(`BRIEF` / `QUESTION` / `SKIP` / `APPROVED` / `REVISE` / `ESCALATE`)를 명시한다.
- 라운드 관리: REVISE 카운트를 스스로 추적, 3라운드 초과 시 ESCALATE.

### skills/advisor/SKILL.md 골자

- 트리거: 수동 호출 위주. description은 "advisor", "감독 받으며 구현", "검증 위임" 등 명확한 문구만 포함.
- Worker 규율:
  - 스폰 프롬프트에 사용자 요청 원문·파악한 컨텍스트·제약을 패키징한다.
  - 브리프를 준수해 구현하고, 완료 보고는 정해진 형식(변경 파일, 요약, 테스트 결과)으로 보낸다.
  - QUESTION은 사용자에게 그대로 릴레이하고 답변을 가공 없이 회신한다.
  - APPROVED의 보고문을 사용자에게 릴레이한다. 커밋은 사용자가 요청한 경우에만 실행한다.
  - Advisor 검증 턴 동안 파일을 수정하지 않는다.

## 에러·엣지 처리

- **Advisor 소실·SendMessage 실패**: 지금까지의 결정·라운드 카운트를 요약해 재스폰하고 루프를 이어간다.
- **동시 작성자**: 턴제로 방지. Advisor Edit는 검증 턴 내 사소한 마무리로 한정.
- **릴레이 무가공**: QUESTION·사용자 답변·최종 보고문은 Worker가 요약·왜곡 없이 전달한다.
- **커밋 정책 충돌**: 사용자가 커밋을 요청하지 않은 세션에서는 APPROVED여도 커밋하지 않고 승인 사실만 보고한다.

## 테스트

repo 컨벤션(`tests/<plugin>/`)에 따라 `tests/agent-kit/test-advisor-skill.sh` 셸 테스트를 추가한다. 구조 검증만 수행한다:

- plugin.json 존재·유효 JSON·필수 필드(name, version).
- SKILL.md frontmatter(name, description) 및 필수 섹션 존재.
- agents/advisor.md frontmatter 및 상태 태그 6종 정의 존재.
- marketplace.json에 agent-kit 등록 및 source 경로 유효.

## 범위 밖 (YAGNI)

- 세션 파일·기록 영속화.
- Orca 오케스트레이션 연동.
- workflow 계열 추가 스킬(후속 작업).
- 자동 정리 훅·CI 연동.
