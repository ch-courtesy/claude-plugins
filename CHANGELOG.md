# Changelog

이 저장소의 **사용자 가시(behavior-changing) 변경**을 기록합니다. 버전의 단일 출처(SoT)는 각 플러그인의 `plugin.json`이며(`rules/engineering/versioning.md`), 본 파일은 변경이 머지될 때마다 누적합니다. 분류: 새 기능 / 변경(호환) / 변경(깨짐) / 버그 수정 / 보안.

## project-init 0.21.0

### 새 기능
- **Codex 완전 동등성 확장** — 저장소 Codex marketplace를 추가하고 기존 plugin-bundled SessionStart hook을 Claude/Codex가 함께 사용하며, 두 런타임이 같은 공유 스킬·템플릿·rules index 구현을 사용하도록 런타임별 차이를 얇은 어댑터로 격리했다.

### 변경(호환)
- **런타임 중립 질문 계약** — 공통 스킬 절차 본문에서 직접 런타임 도구명 의존을 제거하고, 구조화 질문 기능이 없는 표면에서는 동일 선택지를 간결한 직접 질문으로 제시하되 스킬별 명시적 누락 응답 계약은 보존하도록 명시했다.

## autopilot 0.47.0

### 새 기능
- **`spec` 명확화 인터뷰에 옵트인 "시각 컴패니언" 추가** — 화면·레이아웃·구조처럼 글보다 그림으로 볼 때 더 잘 판단되는 질문에서, 사용자에게 경량 정적 시각 미리보기(터미널 텍스트 도식 또는 임시 디렉토리의 정적 파일)를 곁들여 인터뷰 판단을 돕는다. 시각적 주제가 예상될 때 단독 메시지로 1회 제안하고, 켜진 동안에도 질문별로 "글보다 그림이 나은가"를 판단해 도움이 되는 질문에서만 시각물을 보여준다. 라이브 서버·WebSocket·브라우저 클릭 수집은 쓰지 않으며, 사용자의 최종 선택은 기존 명확화 질문으로 받아 SPEC 확정 텍스트에 캡처하고 시각물은 인터뷰 종료 시 폐기한다(권위 산출물은 SPEC.md뿐, 외부 상태 무생성 계약 보존). 사람 대화 경로 한정 — 자율 오케스트레이터·헤드리스 맥락에선 제안하지 않는다. SKILL.md는 계약만 담고 메커니즘은 `references/visual-companion.md` 한 곳에 둔다.

## autopilot 0.42.0

### 변경(호환)
- **`dispatch` fan-out 드라이버를 단일 `flow` 드라이버로 통합** — 기존 세 드라이버(`strong-parallel`=내장 dynamic Workflow / `background` / `foreground-batch`)와 자동 감지·override·안전 강등 사슬·`DRIVER` sticky 마커를 제거하고, 준비된 SPEC의 스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달을 `flow` 스킬의 공개 계약으로 구동한다. 워커는 flow의 서브프로세스 에이전트(`wf.agent`+`SubprocessAgentCaller`, 벤더 중립)로 spawn한다. Claude Code 전용 내장 Workflow 의존을 제거해 다양한 벤더에서 동작하고 환경 의존 복잡도를 없앤다. `start` 인터페이스는 불변. `python3` 3.9+ 미가용 시 폴백 없이 hard-abort. 운영자 노브 `DISPATCH_DRIVER`·`DISPATCH_NO_STRONG_PARALLEL`·`DISPATCH_NO_BACKGROUND`는 더 이상 동작을 가르지 않으며 `driver`/`status`는 항상 `flow`를 보고한다.

## skill-rubric 0.1.0

### 새 기능
- **`skill-rubric` 플러그인 추가** — 토스 기술블로그 '스킬 품질 루브릭' 6개 섹션 30개 항목(규칙 17 + 모델 13)으로 SKILL.md를 평가해 등급(S/A/B/C/F)과 지적 목록을 산출하는 `rubric` 스킬. 결정적 17항목은 Python 검사기(`rule_checker.py`)가 정규식·카운트·syntax 검사로 판정하고(frontmatter YAML 파싱·유효성은 `yq`(mikefarah)에 위임), 의미적 13항목은 스킬을 실행하는 에이전트가 판정한다. `Skill(skill="rubric", args="<SKILL.md 경로 | all>")`로 단일·전체 평가, 마크다운 리포트 + JSON 산출. 루브릭은 verbatim 적용(본문 XML 태그 = BLOCKER).

## autopilot 0.41.0

### 새 기능
- **`autopilot:flow` 스킬 추가** — Workflow Replica 하니스(Python 표준 라이브러리만으로 동작하는 독립 DAG 오케스트레이터)의 진입점. 내장 dynamic Workflow 도구가 미가용인 환경에서도 임의 `depends_on` DAG를 스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달로 실행한다. CLI 러너(`flow run <정의.py>` / `flow selftest` / `flow deps`), 기계 판독 JSON 출력.
