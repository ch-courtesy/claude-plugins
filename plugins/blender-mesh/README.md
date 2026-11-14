# blender-mesh

원화(정면·측면·후면 턴어라운드)에서 출발해 Blender로 캐릭터와 소품을 사람이 하듯 한 단계씩 만들고,
단계마다 고정된 기준으로 채점하며 반복하는 스킬 모음입니다.

모델링 → 리깅 → UV → 텍스처 → 애니메이션 → 소품 충돌 → GLB 내보내기 → Unreal 검사

0.2.0부터 게임 액션을 다룹니다: 무기를 주먹에 쥔 한 번 실행 공격(연타·돌진·회전·도약), 타격 측정(예비동작,
내려치기 시간, 칼끝 속도, 위에서 본 궤적), 게임 속도 기준(평타 길이, 달리기 속도), 속도와 무관한 튐·고르기
측정, 무기를 별도 GLB로 내보내 Unreal에서 소켓에 붙여 검사하기.

0.3.0은 움직임의 질을 잽니다: 공격에서 골반이 먼저 돌고 가슴과 팔이 차례로 따라오는지, 날이 베는 방향을
향하는지, 맞은 뒤 팔로스루가 이어지는지, 골반이 내려앉는지를 게이트로 재고(대조군 포함), 지연을 휘두르기에만
거는 `delay_window`, 이어진 몸통·바지(`box-modeling/references/continuous-body.md`), 쇄골 자동 상승과
보정 본(`mesh-rig`), Unreal이 동작을 30 fps로 다시 샘플링할 때의 경고(`mesh-export`)를 더했습니다.

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
