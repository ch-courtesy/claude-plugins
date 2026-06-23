# flow

**무엇** — 내장 dynamic Workflow(멀티에이전트 오케스트레이션) 도구가 막힌 환경에서도 임의 `depends_on` DAG를
스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달로 실행하는 독립 오케스트레이터 하니스.
Python 표준 라이브러리만 쓴다(외부 패키지·네트워크 없음).

**언제** — 내장 Workflow 도구가 미가용인 환경에서 DAG 오케스트레이션이 필요할 때. 다른 스킬이
strong-parallel 불가 환경의 폴백으로 프로그램적으로 호출할 수도 있다.

**호출** — `Skill(skill="flow", args="<subcommand> [<args>]")` (subcommand: `run`/`selftest`/`deps`).

상세(subcommand 계약·engine API·워크플로 정의 작성법·예시)는 **`SKILL.md`가 단일 출처**다. 이 README는
입구 요약이며 그 내용을 복제하지 않는다.
