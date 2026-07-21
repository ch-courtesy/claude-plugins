# hook_checker 호출 계약 (단일 출처)

스킬(`create-hook`·`repair-hook`)이 훅 구조 표준의 결정적 검사기 `hook_checker.py`를 호출할 때의 공통 계약이다. 각 스킬은 이 문서를 참조하고 사본을 두지 않는다.

- **절대경로 고정.** `git rev-parse --show-toplevel`로 저장소 루트의 절대경로를 구하고, 검사기 경로와 평가 대상 훅 디렉터리 경로 모두 절대경로로 조합한다 — Bash 실행 시 현재 작업 디렉터리에 대한 가정을 하지 않으며, 상대경로(`../../` 등)는 Read로 단일 문서를 읽을 때만 쓰고 Bash 실행 인자에는 쓰지 않는다.
- **실행 형식.**

  ```
  python3 <repo_root>/plugins/project-init/shared/hook-standard/hook_checker.py <소비 프로젝트의 .claude/hooks 절대경로>
  ```

  settings 정합 검사는 인자로 받은 훅 디렉터리의 **부모**에서 `settings.json`·`settings.local.json`을 읽는다 — 별도 인자가 없다.

- **결과 해석.** 평가 자체가 성공하면 결함이 발견되어도 종료 코드 0과 함께 stdout JSON을 낸다 — 결함은 종료 코드가 아니라 JSON의 `grade`·`*_count`·`checks`(결정적 10항목, `check_type: "rule"`)에 담긴다. 각 항목의 `evidence`가 위반의 구체 근거(파일명·등록 경로)를 담는다. 종료 코드가 0이 아니면(경로 오류 등) 오류를 알리고 중단한다.
- **모델 판정 항목은 검사기 밖.** `standard.md`의 모델 판정 절 5항목은 이 JSON에 포함되지 않는다 — 스킬을 실행하는 에이전트가 스크립트를 읽고 채운다.
