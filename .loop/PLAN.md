# 작업 계획

SPEC: spec 단계 9 결정 분리 + loop start 자동 Monitor 가설

## 마일스톤

### M1: spec/SKILL.md 단계 9 — 자유 텍스트 안내 → AskUserQuestion 결정 입력
- **정의**: 단계 9가 SPEC.md 경로 안내 후 `AskUserQuestion`으로 3옵션(① 지금 loop start 호출 ② SPEC만 확정 ③ 변경)을 받는 형태로 재작성. ①을 선택 시 즉시 `Skill(skill: "loop", args: "start <m>/<c>")` 호출. 옵션 라벨에 "지금 loop start 호출"이 명시되어 verify의 `grep -q 'loop start 호출'` 통과.
- **검증**: `grep -q 'loop start 호출' plugins/autopilot/skills/spec/SKILL.md` 0 exit + 본문에 "AskUserQuestion", "명시적 결정 입력" 또는 동등 의미가 명시.
- **영향 영역**: `plugins/autopilot/skills/spec/SKILL.md` 단계 9 절차 (현 L106-110 부근)
- **위험**: SPEC 제약 — 자유 텍스트 끝 질문 종결구 금지. 옵션 라벨에서 "지금 loop start 호출"임을 명확히. spec→loop 자동 연계 시 추가 모니터 결정 질문 없이 loop 기본 동작 적용 (모니터 가설 포함).
- [x] 완료

### M2: loop/SKILL.md start — `--no-monitor` 플래그 + 자동 Monitor 가설
- **정의**: start 서브커맨드 시그니처에 `--no-monitor` 추가. 본문에 자동 Monitor 가설 섹션 작성 — `--no-monitor` 미지정 시 백그라운드 실행 직후 `Monitor` 도구로 핵심 이벤트(이터 시작·종료, halt, escalation, done 등) 자동 알림. 권장 기본값(`persistent: true`, `timeout_ms: 3600000`, 필터 정규식) 명시. `--no-monitor`는 SKILL.md 차원 옵션으로 모델이 args 파싱 시 분리·소비하고 `loop.sh`로 전달 안 함 (셸 드라이버 변경 없음).
- **검증**: `grep -q 'Monitor' plugins/autopilot/skills/loop/SKILL.md` + `grep -q -- '--no-monitor' plugins/autopilot/skills/loop/SKILL.md` 둘 다 0 exit. `bash tests/autopilot/test-loop-sh.sh` 회귀 통과.
- **영향 영역**: `plugins/autopilot/skills/loop/SKILL.md` start 섹션 (현 L30-41 부근)
- **위험**: SPEC 제약 — `loop.sh` 미변경. 사용자가 직접 셸 드라이버 호출하면 `--no-monitor` 효력 없음을 본문에 명시. Monitor 알림 노이즈 → 필터 정규식으로 완화.
- [x] 완료

## 의존 관계

- M1·M2 독립 (각각 다른 SKILL.md 파일). 한 이터레이션에 같이 처리 가능.

## 완료 판정 (헌법 §3.4·§3.5)

다음을 모두 만족하면 워크트리 루트에 `DONE` 작성:

- [ ] M1·M2 모두 체크
- [ ] 4-Level Verifier (헌법 §3.4) 통과 — Existence·Substantive·Wired·Runtime
- [ ] Self-Review 4축 (헌법 §3.5) 통과 — Completeness·Quality·Discipline·Testing
- [ ] verify 명령 0 exit (`bash tests/autopilot/test-loop-sh.sh && grep -q 'loop start 호출' ... && grep -q 'Monitor' ... && grep -q -- '--no-monitor' ...`)
- [ ] 자기 분류 누적에 `fix:symptom` 연속 없음

## fix:symptom 발생 시 (자체 교정)

(헌법 §3.3 표 — 보존)
