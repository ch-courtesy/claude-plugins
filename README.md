# Claude Plugins Marketplace

Claude Code에서 사용하는 로컬 플러그인 마켓플레이스 저장소입니다. 공유 스킬과 자산은 `plugins/<name>/` 아래 한 벌로 유지하고, 런타임 매니페스트와 lifecycle hook 설정만 얇은 어댑터로 분리합니다.

## 제공 플러그인

- `thinktank` — 중앙 리서치를 바탕으로 다중 관점 숙의와 추적 가능한 브레인스토밍을 진행합니다.

## Claude Code

- marketplace: `.claude-plugin/marketplace.json`
- plugin manifest: `plugins/<name>/.claude-plugin/plugin.json`
