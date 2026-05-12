# 다음 이터에게 (HANDOFF)

## 직전 이터: 1

## 이번에 무엇을 했는가
- M1: `plugins/autopilot/skills/spec/SKILL.md` 단계 9 재작성 — 자유 텍스트 "다음 단계 안내" 출력을 제거하고 `AskUserQuestion`으로 3옵션 명시적 결정 입력으로 전환 (① 지금 loop start 호출 [Recommended, 즉시 sibling Skill 호출] / ② SPEC만 확정 / ③ 변경).
- M2: `plugins/autopilot/skills/loop/SKILL.md` start 서브커맨드에 `--no-monitor` 플래그 추가 + "자동 Monitor 가설 (기본 동작)" 섹션 추가. 권장 기본값(`persistent: true`, `timeout_ms: 3600000`, 필터 정규식) 명시. `--no-monitor`는 SKILL.md 차원 옵션이라 loop.sh로 미전달, 셸 드라이버 무변경 명시.
- verify fresh 통과: `bash tests/autopilot/test-loop-sh.sh` 54건 모두 OK + 3개 grep 마커 모두 hit.

## 무엇이 막혔거나 막힐 수 있는가
- 막힌 것 없음. loop.sh 셸 드라이버 무변경 — 기존 회귀 테스트 보존 (SPEC 명시).
- 잠재 위험: spec 단계 9에서 자동 연계 호출 시 사용자 의도 어긋날 가능성은 라벨 "지금 loop start 호출"로 명확히 한정.

## 다음 단계 추천
- 작업 완료. `DONE` 작성 후 종료.

## 의심점 (있을 때만 — DONE_WITH_CONCERNS 신호)

(self-review 4축 모두 통과 — 의심점 없음)
