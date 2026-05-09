# 작업 계획

마일스톤별 정의·검증·영향·위험을 추적. 진전이 있을 때마다 모델이 갱신.
**첫 이터의 모델이 SPEC.md를 분석해 마일스톤 초안을 작성**한다 (이 템플릿을 그대로 두면 안 됨).

## 마일스톤

### M1: <한 줄 제목>
- **정의**: <이 마일스톤이 만족되는 조건. 가능하면 검증 가능한 형태>
- **검증**: <어떻게 확인하는지 — 특정 테스트·관찰·verify 명령의 부분>
- **영향 영역**: <대략적 파일/디렉토리. 처음엔 "TBD" 가능>
- (선택) **위험**: <이 마일스톤 특화 dead-end·함정. SPEC.md의 전체 risks와 별개>
- [ ] 완료

### M2: <한 줄 제목>
- **정의**: ...
- **검증**: ...
- **영향 영역**: ...
- (선택) **위험**: ...
- [ ] 완료

(필요한 만큼 추가)

## 의존 관계 (마일스톤 다수일 때만)

- 순차: M1 → M2 → M3
- 병렬: M1·M2 (독립), M3 (M1·M2 후)

## 완료 판정 (헌법 §3.4·§3.5)

다음을 모두 만족하면 워크트리 루트에 `DONE` 작성:

- [ ] 모든 마일스톤 체크
- [ ] 4-Level Verifier (헌법 §3.4) 통과 — Existence·Substantive·Wired·Runtime
- [ ] Self-Review 4축 (헌법 §3.5) 통과 — Completeness·Quality·Discipline·Testing
- [ ] verify 명령 0 exit
- [ ] 자기 분류 누적에 `fix:symptom` 연속 없음

## fix:symptom 발생 시 (자체 교정)

이번 이터를 `fix:symptom`으로 commit한 경우, 종료 전 본 PLAN.md를 재검토:
- 영향받은 마일스톤의 정의·검증이 여전히 유효한가?
- 영향 영역이 잘못 추정됐는가?
- 새로 발견된 dead-end를 위험 섹션에 추가
- 마일스톤이 너무 커서 분할이 필요한가?
- 의존 순서를 재배치해야 하는가?

재검토 결과별 처리 (헌법 §3.3 표 참조):

| 판단 | commit 처리 | PLAN 처리 |
|---|---|---|
| 우회 패치 수용 | 유지 | NOTES.md에 workaround·재조사 필요 명시 |
| 마일스톤 재정밀 | 유지 | 마일스톤 정의·검증 엄밀화 |
| 잘못된 가정, HEAD 1개로 처리 가능 | `git revert HEAD` | 영향 마일스톤·위험 갱신 |
| 다중 commit 영향 또는 광범위 재구성 필요 | revert 안 함 → ESCALATION (`architecture-gap`) | 사람 결정 대기 |

revert는 HEAD 단일 commit에 한정. 다중 commit 영향은 ESCALATION으로 (헌법 §3.3 마지막 단락).

revert 시 message: `chore: revert <짧은 SHA> — fix:symptom 자체 교정 (사유)`. 드라이버 streak 검사는 `^fix:symptom`만 grep하므로 `chore:` prefix는 streak에 포함 안 됨.

자체 교정으로 다음 이터의 가정 오류를 차단. 이 단계 없이 fix:symptom이 누적되면 §4.2 조기 정지 (streak)로 강제 정지된다.
