# rule_checker 호출 계약 (단일 출처)

스킬(`create-skill`·`repair-skill`)이 규칙 17항목 결정적 검사기 `rule_checker.py`를 호출할 때의 공통 계약이다. 각 스킬은 이 문서를 참조하고 사본을 두지 않는다.

- **절대경로 고정.** `git rev-parse --show-toplevel`로 저장소 루트의 절대경로를 구하고, 검사기 경로와 평가 대상 SKILL.md 경로 모두 그 루트 기준 절대경로로 조합한다 — Bash 실행 시 현재 작업 디렉터리가 스킬 폴더라는 가정을 하지 않으며, 상대경로(`../../` 등)는 Read로 단일 문서를 읽을 때만 쓰고 Bash 실행 인자에는 쓰지 않는다.
- **실행 형식.**

  ```
  python3 <repo_root>/plugins/project-init/shared/rubric/rule_checker.py <SKILL.md 절대경로 | all [repo_root]>
  ```

- **결과 해석.** 평가 자체가 성공하면 결함이 발견되어도 종료 코드 0과 함께 stdout JSON을 낸다 — 결함은 종료 코드가 아니라 JSON의 `grade`·`*_count`·`results[].checks`(규칙 17항목, `check_type: "rule"`)에 담긴다. 종료 코드가 0이 아니면(경로 오류 등) 오류를 알리고 중단한다.
