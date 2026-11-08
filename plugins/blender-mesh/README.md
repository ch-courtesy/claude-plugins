# blender-mesh

원화(정면·측면·후면 턴어라운드)에서 출발해 Blender로 캐릭터와 소품을 사람이 하듯 한 단계씩 만들고,
단계마다 고정된 기준으로 채점하며 반복하는 스킬 모음입니다.

모델링 → 리깅 → UV → 텍스처 → 애니메이션 → 소품 충돌 → GLB 내보내기 → Unreal 검사

## 설치

```
/plugin install blender-mesh --marketplace ch-courtesy/claude-plugins
```

## 필요한 것

- Blender 5.2 (헤드리스로 실행, `mesh.py`가 찾습니다)
- Python 3과 Pillow (`py -3` 또는 `python3`)
- 선택: Unreal Engine 5.8 (`engine_unreal` 단계)

## 시작

- 절차: `box-modeling`, 단계와 기준: `stage-gate`, 실행 도구: `mesh-session`
- 기준값은 `stage-gate/assets/gates.json`에 있고, 바뀐 이력은 같은 파일의 `_changes`에 남아 있습니다.
- 회귀 시험: `mesh-session/scripts/mesh.py selftest`
- 예제 계획·리그·동작 사양: `box-modeling/references/`

## 검증

처음 보는 원화 네 쌍(캐릭터와 소품)으로 눈가림 시험을 했고, 4차 시험에서 캐릭터와 소품이 스킬 수정 없이
모든 게이트를 통과했습니다. 게이트가 재지 못하는 것(모양의 매력, 몸끼리의 충돌, 소품과 바닥 등)은
그림을 사람이 직접 봐야 합니다. 각 SKILL.md의 "알아 두실 점"과 한계를 먼저 읽으세요.
