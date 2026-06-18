# Claude & Codex Plugins Marketplace

Claude Code와 Codex에서 함께 사용하는 로컬 플러그인 마켓플레이스 저장소입니다. 공유 스킬과 자산은 `plugins/<name>/` 아래 한 벌로 유지하고, 런타임별 매니페스트와 lifecycle hook 설정만 얇은 어댑터로 분리합니다.

## Claude Code

- marketplace: `.claude-plugin/marketplace.json`
- plugin manifest: `plugins/<name>/.claude-plugin/plugin.json`

## Codex

- marketplace: `.agents/plugins/marketplace.json`
- plugin manifest: `plugins/<name>/.codex-plugin/plugin.json`

저장소 marketplace를 Codex에 등록하고 `project-init`을 설치합니다:

```bash
codex plugin marketplace add .
```

설치 후 Codex를 다시 시작하고 `/plugins`에서 `project-init`을 설치·활성화합니다. `project-init`의 SessionStart hook을 처음 사용하거나 hook 정의가 바뀌면 `/hooks`에서 내용을 검토하고 신뢰한 뒤 새 thread를 시작합니다. Hook을 신뢰하지 않은 상태에서도 스킬은 사용할 수 있지만 `rules/` 인덱스 자동 주입은 건너뜁니다.
