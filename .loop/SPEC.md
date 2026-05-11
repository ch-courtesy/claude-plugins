---
scope:
  include: ["plugins/autopilot/skills/loop/**", "plugins/autopilot/skills/dispatch/**", "plugins/autopilot/skills/spec/**", "tests/autopilot/**"]
  exclude:
    - rules/**
    - .loops/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-loop-sh.sh && bash tests/autopilot/test-dispatch-skill.sh && bash tests/autopilot/test-dispatch-integration.sh && bash tests/autopilot/test-skill-install.sh"
test_sweep_paths:
  - "tests/autopilot/**"
---

# autopilot: 워크트리·lock·SPEC을 milestones/<m>/loops/<c>/ 안으로 통합 (.loops/ 제거)

## 무엇을 만들 것인가
autopilot이 생성하는 작업별 런타임 산출물(워크트리, lock 파일, SPEC 파일, 메타 파일)을 모두 메인 레포 내부 nested 단일 트리(`milestones/<m>/loops/<c>/`) 안에 통합한다. 외부 sibling 디렉터리(`<project>-loops/`)와 별도 `.loops/` 디렉터리를 더 이상 사용하지 않으며, 한 task의 모든 산출물은 IDE에서 같은 부모 디렉터리 아래로 보인다. 단일 task는 normalize 과정에서 `<m>=regular`로 정규화되므로 경로 분기가 사라진다. 새 위치들이 git에 의해 무시되도록 첫 호출 setup이 `.gitignore`를 자동으로 정렬한다. 자율 loop의 정리 절차는 새 nested 워크트리 경로 밖을 절대 건드리지 않도록 path guard를 갖춘다. dispatch 스킬의 sentinel 감시와 spec 스킬의 SPEC 저장도 같은 정책을 따른다.

## 수용 기준 (EARS)
1. autopilot이 자율 task의 워크트리를 생성하면, 시스템은 `milestones/<m>/loops/<c>/.worktree/` 경로에 워크트리를 만들어야 한다 (단일 task의 경우 `<m>=regular`로 정규화).
2. autopilot이 자율 task의 lock 파일을 잡으면, 시스템은 해당 lock을 `milestones/<m>/loops/<c>/.lock`에 두어야 하며, 이전 `.loops/locks/<sanitized>.lock` 경로는 더 이상 생성·참조하지 않아야 한다.
3. spec 스킬이 SPEC.md를 기록하면, 시스템은 `milestones/<m>/loops/<c>/SPEC.md` 경로에 저장해야 하며, `.loops/<task-id>/SPEC.md`에는 새로 기록하지 않아야 한다.
4. autopilot의 첫 호출 setup이 실행되면, 시스템은 `.gitignore`에 `milestones/**/loops/**/.worktree/`와 `milestones/**/loops/**/.lock` 패턴이 없으면 추가하고, 기존 `.loops/locks/` 라인이 있으면 제거한 뒤, 변경분을 단일 chore commit으로 기록해야 한다.
5. 자율 task의 cleanup이 호출되면, 시스템은 새 nested 워크트리 디렉터리만 제거 대상으로 인식하고, 메인 레포의 다른 영역(워크트리 경로 prefix 밖)을 건드리지 않아야 한다.
6. dispatch 스킬이 wave 내 child loop의 sentinel을 감시하는 동안, 시스템은 `DONE`·`.loop/ESCALATION.md` 파일을 새 nested 워크트리 경로 안에서 찾아야 한다.
7. 시스템은 constitution과 운영 문서(loop SKILL.md·operational-guide.md·troubleshooting.md·dispatch SKILL.md·spec SKILL.md 등)의 `.loops/` 관련 문구·예시를 새 nested 정책에 맞게 갱신해야 한다.
8. 만약 `.gitignore` 갱신이 실패하면(쓰기 불가·commit 실패 등), 시스템은 워크트리·lock 생성을 중단하고 사유를 표준 오류로 보고한 뒤 0이 아닌 exit 코드로 종료해야 한다.

## 범위
포함:
- `plugins/autopilot/skills/loop/references/loop.sh` — `compute_paths`의 `WT`를 `milestones/<m>/loops/<c>/.worktree/`로, `LOCK_DIR`/`LOCK_FILE`을 `milestones/<m>/loops/<c>/.lock`으로, 첫 호출 setup의 `.gitignore` 자동 관리(워크트리·lock 패턴 추가 + 기존 `.loops/locks/` 라인 제거 + 단일 chore commit), `cmd_cleanup`에 워크트리 경로 prefix path guard 추가
- `plugins/autopilot/skills/loop/references/constitution.md` — §2 워크트리 위치 가정 문구를 새 nested 정책에 맞게 갱신
- `plugins/autopilot/skills/loop/SKILL.md`, `plugins/autopilot/skills/loop/references/operational-guide.md`, `plugins/autopilot/skills/loop/references/troubleshooting.md` — `.loops/`·외부 sibling 관련 문구·예시·디렉터리 다이어그램 갱신
- `plugins/autopilot/skills/dispatch/references/dispatch.sh`, `plugins/autopilot/skills/dispatch/SKILL.md` — `LOCK_DIR` 새 경로, sentinel 폴링 경로(`DONE`·`.loop/ESCALATION.md`)를 새 nested 워크트리 기준
- `plugins/autopilot/skills/spec/SKILL.md` — SPEC 저장 경로, 일반 모드 사전 검사 경로, `--resume` 경로, 단계 7 mkdir, 단계 9 안내 문구를 `milestones/<m>/loops/<c>/`로 갱신
- `plugins/autopilot/skills/spec/references/spec-template.md` — frontmatter `scope.exclude`의 `.loops/**` 라인을 새 정책에 맞게 갱신/제거
- `tests/autopilot/test-loop-sh.sh`, `test-dispatch-skill.sh`, `test-dispatch-integration.sh`, `test-skill-install.sh` — 워크트리·lock·SPEC 경로 케이스, `.gitignore` 자동 관리 케이스(TEST 34/35 계열) 갱신

비-목표 / 제외:
- 기존 `.loops/`에 남아있는 콘텐츠(in-flight SPEC, stale lock, 빈 디렉터리)의 자동 이동·정리 — 사용자가 수동 처리
- 기존 외부 sibling 워크트리(`<project>-loops/`) 자동 마이그레이션·도움말 — 코드에서 감지·처리 안 함
- `docs/superpowers/specs/2026-05-11-autopilot-prd-dispatch-design.md` §6 sentinel 경로 갱신 — 별 PR로 분리
- `.loops/` 디렉터리 자체의 자동 제거 — 사용자가 정리 시점·방식 결정

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```bash
bash tests/autopilot/test-loop-sh.sh && bash tests/autopilot/test-dispatch-skill.sh && bash tests/autopilot/test-dispatch-integration.sh && bash tests/autopilot/test-skill-install.sh
```

## 제약
- 셸 스크립트는 bash (POSIX sh 비호환 기능 사용 가능). macOS Darwin과 Linux 모두에서 작동해야 한다.
- `compute_paths`는 `PROJECT_ROOT` 설정 이후에 호출되는 기존 가정을 유지한다.
- `normalize_task_id`의 `regular/` prefix 정책을 유지한다. 워크트리·lock·SPEC 경로 모두 같은 정규화 결과를 사용해야 한다.
- `.gitignore` 자동 commit은 사용자의 staged·unstaged 변경과 commit 단위를 침범하지 않도록, `.gitignore` 단일 파일만 staging한 뒤 단독 chore commit으로 격리한다.
- lock 파일이 child 디렉터리 안(`milestones/<m>/loops/<c>/.lock`)에 위치하므로 `cmd_cleanup`이 child 디렉터리를 archival·삭제할 때 lock도 함께 정리된다. 활성 lock 보유 task에 대한 cleanup은 기존대로 stop·release 절차 통과를 가정한다.
- 기존 외부 sibling 경로(`<project>-loops/`)와 기존 `.loops/` 내용은 코드에서 감지하지 않으며 자동 처리하지 않는다.
- `.gitignore` 자동 관리는 `git check-ignore`로 효과만 검사하지 않고, 라인 텍스트 단위로도 정확히 확인·삽입·삭제한다(기존 `.loops/locks/` 라인 제거가 필요하므로).

## 위험
- `cmd_cleanup`의 path guard가 약하면 변수 누락 시 메인 레포 손상 위험. mitigation: 워크트리 경로를 `realpath`로 절대화한 뒤 `PROJECT_ROOT` 하위 prefix 검사, 빈 변수·심볼릭 링크·`.` 가드를 명시. 테스트로 path guard 시나리오를 추가한다.
- `.gitignore` auto-commit이 사용자의 in-flight 변경과 commit 단위가 섞이면 변경 추적이 오염된다. mitigation: `.gitignore` 단독 파일·단독 commit, commit 직전 staged 상태 검사.
- `dispatch.sh`와 `loop.sh`의 경로 계산이 어긋나면 `watch_wave`가 영구 idle 상태로 빠진다. mitigation: 같은 알고리즘 또는 공유 helper로 일원화, 통합 테스트로 cross-validation.
- IDE 인덱싱은 `.gitignore`와 무관하게 워크트리를 스캔할 수 있다. git 도구 일관성은 확보되지만 IDE 설정은 사용자 환경별 — mitigation 범위 밖.
- 기존 `.loops/locks/`에 stale lock 또는 in-flight SPEC이 남아 있을 수 있고, 새 코드는 이를 감지하지 않는다. mitigation: `troubleshooting.md`에 `.loops/` 정리 가이드를 추가한다 — 사용자가 `loop stop`·수동 mv·rm으로 처리.
- spec 스킬의 SPEC 저장 경로가 바뀌면 외부 도구·문서가 `.loops/<task-id>/SPEC.md`를 가정한 채 호출될 수 있다. mitigation: spec `SKILL.md` 모든 사례·안내를 새 경로로 갱신, 자체 검토 단계에서 `.loops/` 잔존 문구를 잡는다.
