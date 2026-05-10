# autopilot `spec` 스킬 설계

작성일: 2026-05-10
대상 플러그인: `autopilot`
관련 결정: 기존 `loop prepare` 서브커맨드 완전 제거, 신규 최상위 스킬 `spec`으로 대체

## 배경

autopilot의 `loop` 스킬은 자율 코딩 루프(랄프 루프)를 운영하며, 입력으로 `.loops/<task-id>/SPEC.md` 한 개 파일을 받습니다. SPEC이 다운스트림 자율 loop의 *유일한* 계약이므로, SPEC의 품질이 loop의 성공·실패를 결정합니다.

현재 `loop prepare` 서브커맨드는 두 라운드 6문항 폼으로 SPEC을 생성합니다 — 빠르고 균일하지만 다음의 한계가 있습니다.

- **고정 질문은 탐색하지 않음**: 폼이 묻지 않는 이슈는 SPEC에 안 박힘. loop이 도중에 발견하면 자율 운영 모드에서 해결 불가
- **모호성을 못 잡음**: "수용 기준"이 자유 텍스트라 verify 명령으로 검증 가능한지 보장 안 됨
- **의사결정 단계 부재**: 다중 서브시스템 task가 분해 없이 단일 SPEC으로 들어가 loop이 thrash

**리서치 결과** (Spec-Kit, Kiro, BMAD, superpowers:brainstorming, Cline 등 8개 도구 벤치마크): 다운스트림이 자율 loop인 우리 환경에는 *구조화된 대화* 아키타입이 1순위 적합. 추가로 Spec-Kit의 비용 거의 0인 강성 장치(`[NEEDS CLARIFICATION]` 마커, WHAT/HOW 방어선, EARS 포맷, Independent-Test 규칙) 차용.

**의도된 결과**: 사용자가 task 아이디어를 자유롭게 말하고, 스킬이 한 질문씩 명확화하며, 합의된 SPEC을 섹션별로 승인받아 작성. 결과물은 loop이 도중 질문 없이 완수할 수 있는 자기완결적 SPEC.

## 목표 / 비-목표

**목표**:
- `loop prepare`를 대체하는 대화형 SPEC 생성 스킬 신설
- SPEC 품질을 강성 장치 4종으로 보강 (마커, WHAT/HOW, EARS, Independent-Test)
- 미해결 항목이 있는 SPEC으로 loop이 시작하지 않도록 게이트
- loop 자율성 보존 — SPEC은 BEHAVIOR만 명세, 테스트 구조·구현 디테일은 loop이 결정

**비-목표**:
- 다중 파일 산출물 (Spec-Kit·Kiro 패턴 미차용 — SPEC.md 한 파일 유지)
- prepare의 빠른 경로 유지 / deprecation alias (완전 제거)
- 페르소나 연극·다단계 의식 (autopilot은 단일 사용자 도구)
- 테스트 코드·파일·이름 사전 명세 (loop 자율성 침해)

## 아키텍처 & 파일 배치

```
plugins/autopilot/
├── .claude-plugin/plugin.json          # 변경 없음
└── skills/
    ├── loop/
    │   ├── SKILL.md                    # prepare 항목 제거, 워크플로 안내 갱신
    │   └── references/
    │       ├── prepare.md  ←── 삭제
    │       ├── spec-template.md  ←── 신규 spec 스킬로 이동
    │       └── (나머지 그대로)
    └── spec/                           # ★ 신규 ★
        ├── SKILL.md
        └── references/
            ├── spec-template.md        # WHAT/HOW + EARS 슬롯 반영
            ├── ears-patterns.md        # 5개 EARS 패턴 사례
            ├── self-review.md          # 자체 검토 체크리스트
            └── decomposition-gate.md   # 다중 서브시스템 감지 가이드
```

호출: `Skill(skill: "spec", args: "<task-id>")` → 대화 → `.loops/<task-id>/SPEC.md` 산출 → 사용자 안내 `Skill(skill: "loop", args: "start <task-id>")`.

재진입: `Skill(skill: "spec", args: "<task-id> --resume")` — 기존 SPEC.md의 `[NEEDS CLARIFICATION]` 마커만 해결하는 모드.

## 스킬 대화 흐름

`spec` 스킬은 호출 시 다음 9단계를 TodoWrite로 등록·실행합니다.

| # | 단계 | 산출물 / 검사 |
|---|---|---|
| 1 | 사전 검사 | task-id 형식 검증 (path traversal 금지), `.loops/<id>/` 존재 시 abort + 3옵션 안내 |
| 2 | 컨텍스트 탐색 | `git log -5`, `tree -L 2`, `cat CLAUDE.md`, `ls rules/`, 테스트 디렉터리 컨벤션 자동 감지 |
| 3 | 범위 분해 게이트 | 다중 독립 서브시스템 감지 시 분해 제안 → 첫 서브만 본 흐름. 단일이면 통과 |
| 4 | 명확화 라운드 | 한 질문씩 (목적·제약·성공 기준), 가능하면 `AskUserQuestion` 멀티초이스 |
| 5 | 접근법 비교 (조건부) | 비-자명 task만 2-3 접근법 + 트레이드오프 + 추천. 자명하면 생략 |
| 6 | 섹션별 SPEC 제시·승인 | 제목 → What → Acceptance(EARS) → Scope → Verify → Constraints → Risks. 각 섹션 후 `AskUserQuestion`으로 확인 |
| 7 | SPEC.md 작성 | `.loops/<task-id>/SPEC.md` 기록. 미해결은 `[NEEDS CLARIFICATION: ...]` 박힌 채 |
| 8 | 자체 검토 | `references/self-review.md` 4항목 + EARS fail-가능성 1항목. 인라인 수정만, 재루프 없음 |
| 9 | 사용자 최종 검토 | SPEC.md 경로 안내 + 검토 요청. 변경 시 6/7번 재진입. 승인 시 `loop start <task-id>` 안내 |

핵심 디자인 결정:
- **5단계는 조건부**: 자명한 task에 매번 접근법 비교 강요하면 의식 부담
- **6단계는 무조건 섹션별**: 한 번에 통째 제시하면 "lgtm 러버스탬프" 패턴 발생
- **자체 검토는 인라인만**: 발견 즉시 고치고 진행, 재루프 없음 (superpowers:brainstorming 그대로)

## SPEC 스키마 변경

기존 `spec-template.md`를 다음과 같이 확장:

```markdown
---
scope:
  include: [src/**, tests/**]
  exclude: [rules/**, .loops/**, CLAUDE.md]
verify: "<0 exit이면 검증 통과>"
# test_paths (선택)
---

# {{task_title}}

## 무엇을 만들 것인가  (WHAT/HOW 방어선 — 기술 스택·파일 경로·라이브러리·클래스명 금지)
{{task_description}}

## 수용 기준 (EARS)
- A1: When <트리거>, the system shall <응답>
- A2: While <상태>, the system shall <지속 응답>
- A3: If <불가용/오류>, then the system shall <복구·거부>
- (Ubiquitous: "The system shall ..." / Optional: "Where <조건>, the system shall ...")

## 범위
포함: {{scope_in}}
비-목표: {{scope_out}}

## 검증
이 명령이 0 exit으로 끝나야 합니다:
{{verify_command}}

## 제약 (있을 때만)  ← 기술 스택·호환성·테스트 스타일 가이드
{{constraints}}

## 위험 (있을 때만)  ← dead-end·금지 영역·과거 실패
{{risks}}
```

**달라진 점**:
1. **수용 기준이 EARS 포맷 강제**: 자체 검토 단계가 5개 EARS 패턴 중 하나에 안 맞으면 자동 변환 시도 → 거절 시 `[NEEDS CLARIFICATION]` 마커
2. **WHAT/HOW 방어선 명시 룰**: "무엇을 만들 것인가" 섹션에 기술 스택·파일 경로 등장 시 자체 검토에서 잡힘 → Constraints로 이동 권유
3. **`[NEEDS CLARIFICATION: <구체 질문>]` 마커**: SPEC 어디든 박을 수 있음. 자체·사용자 검토 모두 잔존 마커 0개 보장
4. **"Tests to write" 섹션 없음**: EARS가 곧 테스트 계약 — loop 자율성 보존
5. **레퍼런스 4종 추가**: ears-patterns / self-review / decomposition-gate / spec-template

## loop 측 통합 변경

### 1. `prepare` 서브커맨드 완전 제거
- `loop SKILL.md`의 서브커맨드 목록에서 prepare 삭제
- `references/prepare.md` 삭제
- `references/spec-template.md`은 spec 스킬로 이동
- `loop.sh`의 서브커맨드 dispatch에서 `prepare` 케이스는 *help-text 스텁만* 남김 (실제 prepare 동작 0): *"prepare는 spec 스킬로 이전됨. `Skill(skill: \"spec\", args: \"<task-id>\")` 사용"* 출력 후 exit. 백워드 호환 alias가 아니라 친숙한 오류 메시지 — 다음 메이저 버전에서 케이스 자체 제거 가능

### 2. `loop start`에 `[NEEDS CLARIFICATION]` 차단 게이트
시작 직전 SPEC.md 로드 후, lock 획득 *전*:
```bash
if grep -q '\[NEEDS CLARIFICATION' .loops/$TASK_ID/SPEC.md; then
  echo "ERR: SPEC.md has unresolved [NEEDS CLARIFICATION] markers."
  echo "     Run: Skill(skill: \"spec\", args: \"$TASK_ID --resume\")"
  exit 2
fi
```
구현 위치: `loop.sh`의 `start` 함수.

### 3. spec 스킬 재진입 모드 (`--resume`)
- 기존 `.loops/<task-id>/SPEC.md` 존재 시 호출 (없으면 일반 abort)
- 잔존 마커 0개일 경우: "해결할 마커 없음. SPEC.md 그대로 사용 가능" 안내 후 exit 0
- 잔존 마커 1개 이상일 경우: 마커 위치 스캔 → 해당 섹션부터 대화 재개 (전체 처음부터 안 묻고 미해결만)
- 작성 단계에서 마커 자리 치환 후 SPEC.md 재기록

### 4. `loop SKILL.md` 안내 문구 갱신
- "워크플로 개요"의 *"먼저 prepare로 SPEC 작성"* → *"먼저 spec 스킬로 SPEC 작성"*
- 다른 서브커맨드(start/status/stop/list/cleanup/logs)는 그대로

### 5. 후방 호환 없음
사용자가 "완전 제거" 결정. deprecation alias·플래그 없음.

## 엣지 케이스 & 실패 모드

| 시나리오 | 처리 |
|---|---|
| EARS를 안 따른 자유 텍스트 수용 기준 | 자체 검토에서 자동 변환 시도 (`AskUserQuestion`) → 거절 시 `[NEEDS CLARIFICATION]` 마커 |
| 범위 분해 게이트 위양성 (실제 단일) | 사용자가 "분해 안 함" 선택 시 강제 안 함. SPEC Risks에 한 줄 노트 |
| 위음성 (실제 다중인데 못 잡음) | 자체 검토 scope check가 2차 방어. 그래도 놓치면 loop thrash → 정상 escalation |
| 큰 모노레포 컨텍스트 탐색 부담 | 단계 2를 `git log -5` / `tree -L 2` / `cat CLAUDE.md` / `ls rules/`로 한정. 더 깊이 필요 시 단계 4에서 사용자에게 영역 질의 |
| `.loops/<task-id>/` 이미 존재 | abort + 3옵션 (다른 task-id / `--resume` / 백업 후 새로) |
| 사용자 도중 종료 (Ctrl-C) | 단계 7 이전: 산출물 0, 디렉터리 미생성. 단계 7 이후: SPEC.md 잔존 → 다음 호출 시 `--resume` 회복 |
| `loop start`가 SPEC 파싱 실패 | 마커 검사를 frontmatter 파싱 *이전*에 단순 grep으로 — 깨진 SPEC도 마커 검출은 동작 |
| 동시 spec 호출 (같은 task-id) | spec 스킬은 lock 안 잡음. 디렉터리 존재 검사가 자연 직렬화 — 두 번째는 abort |

## 검증

이 설계가 의도한 결과를 내는지 검증할 방법:

1. **Happy path E2E**: 빈 task-id로 `Skill(spec, "test-feature-1")` 호출 → 9단계 진행 → 마커 없는 SPEC.md 생성 → `Skill(loop, "start test-feature-1")` 정상 시작
2. **마커 차단 테스트**: 일부러 `[NEEDS CLARIFICATION]` 박은 SPEC으로 `loop start` → exit 2 + 안내 출력 확인
3. **재진입 테스트**: 마커 잔존 SPEC에 `Skill(spec, "test-feature-1 --resume")` → 마커 있는 섹션만 묻고 나머지 안 건드림 확인
4. **EARS 변환 테스트**: 자유 텍스트 수용 기준 입력 → 자동 변환 제안 → 사용자 승인 시 EARS로 작성 확인
5. **분해 게이트 테스트**: 다중 서브시스템 task ("로그인·결제·메일링 모두") → 분해 제안 표시 확인
6. **prepare 제거 테스트**: `Skill(loop, "prepare foo")` → 안내 메시지 출력, SPEC.md 미생성 확인
7. **WHAT/HOW 방어선 테스트**: "무엇을 만들 것인가"에 "FastAPI로 구현" 같은 기술 스택 등장 → 자체 검토에서 Constraints 이동 권유 확인

## 구현 순서 (대략)

상세 plan은 writing-plans 스킬이 작성. 대략의 단계:
1. 새 `skills/spec/` 디렉터리·SKILL.md·references 4종 작성
2. `spec-template.md`을 loop에서 spec으로 이동·확장
3. `loop.sh`의 start 함수에 마커 차단 게이트 추가
4. `loop SKILL.md`에서 prepare 항목 삭제, 안내 문구 갱신
5. `loop/references/prepare.md` 삭제
6. `--resume` 모드 구현
7. 검증 시나리오 1-7 수동·자동 테스트
