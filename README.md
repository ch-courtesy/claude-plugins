# Claude Plugins Marketplace

Claude Code에서 사용하는 로컬 플러그인 마켓플레이스 저장소입니다. 공유 스킬과 자산은 `plugins/<name>/` 아래 한 벌로 유지하고, 런타임 매니페스트와 lifecycle hook 설정만 얇은 어댑터로 분리합니다.

## 제공 플러그인

- `agent-kit` — 판단 전담 Advisor 에이전트가 Worker(호출 세션)를 감독하는 위임·검증 워크플로를 제공합니다.
- `explain-diff` — 방금 바뀐 코드를 초심자 눈높이 설명·퀴즈·상호작용 HTML 시각화로 이해시킵니다.
- `thinktank` — 중앙 리서치를 바탕으로 다중 관점 숙의와 추적 가능한 브레인스토밍을 진행합니다.

## Claude Code

- marketplace: `.claude-plugin/marketplace.json`
- plugin manifest: `plugins/<name>/.claude-plugin/plugin.json`
