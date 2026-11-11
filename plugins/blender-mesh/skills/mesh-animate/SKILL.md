---
name: mesh-animate
description: Use when a rigged mesh-session character needs walking, idle, wave or action animation, or one-shot attacks with a weapon held in its fist (combos, dashes, spins, leaps), or its movement slides, pops, breaks the mesh or needs iterative scoring. 리깅 캐릭터 애니메이션 제작·채점·반복 개선.
---

# Animate — 만들고, 채점하고, 고치기

```bash
mesh.py <session> animate motion.json rig.json
mesh.py <session> gate animation --anim motions/<name> --note "변경 내용"
mesh.py <session> gate motion_walk --anim motions/<name> --note "변경 내용"
mesh.py <session> propcheck motions/<name> carry.json
mesh.py <session> gate prop_contact --anim motions/<name> --note "변경 내용"
mesh.py <session> controls rig.json --carry carry.json
mesh.py <session> animate attack.json rig.json --carry carry.json      # 무기를 쥔 한 번 실행 동작
mesh.py <session> gate animation_oneshot --anim motions/<name> --note "변경 내용"
mesh.py <session> gate motion_attack --anim motions/<name> --note "변경 내용"
mesh.py <session> controls rig.json --attack attack.json --carry carry.json
blender -b <session>/motions/<name>/motion.blend --python scripts/anim_render.py -- --out <dir> \
    --report <session>/motions/<name>/report.json [--carry carry.json]
```
`mesh.py`는 `mesh-session/scripts/mesh.py`이다. 텍스처와 리깅이 끝난 세션에서 실행한다.
걷기는 `motion_walk`, 대기는 `motion_idle`, 손 흔들기·등불 들기는 `motion_action`으로
두 번째 게이트를 고른다. 공통 `animation` 게이트와 동작 게이트가 모두 통과해야 한다.
한 번 실행하는 동작(`"loop": false`, 공격)은 공통 게이트로 `animation_oneshot`을, 무기 타격은
`motion_attack`(스킬) 또는 `motion_auto_attack`(평타: 길이 1.0초 이하)을 쓰고, 쥔 무기는 `prop_contact`로
잰다. 게임 속도 달리기는 `motion_run`(걷기 기준 + 3.3 m/s 이상)이다. 아래 "한 번 실행하는 동작과 공격"을 본다.

## 필요한 본 이름

helper 본(`elbow`, `knee`, `ankle`)은 선택이다. 없는 리그도 통과한다. 걷기와 포즈는 이 이름을 쓴다: `hips`, `spine`, `chest`, `head`, `upper_arm.L/R`, `forearm.L/R`, `hand.L/R`,
`thigh.L/R`, `shin.L/R`, `foot.L/R`. helper는 `elbow`, `knee`, `ankle`이다. 걷기의 팔꿈치 축은 리그의 위팔
방향에서 구한다. 포즈의 `axis`는 직접 쓴 값이므로 팔 각도가 다른 캐릭터는 다시 계산한다.
뒤따르는 부위와 발바닥 재질은 자유롭게 이름 짓는다. 동작 사양에서 `follow`, `overlap`, `sole_material`로 지정하고,
대조군은 `tail1`~`tail3`와 `Sole`로 쓰여 있으니 다른 이름이면 `rig.json`에 알려 준다:
`"control_names": {"tail1": "ear1.L", "tail2": "ear2.L", "tail3": "ear3.L", "Sole": "Pad"}`.
귀처럼 둘이면 `.L`, `.R` 체인을 각각 두고 `follow`에 둘 다 적으면 따로 움직인다.

## 출력과 반복

- `motions/<name>/`: `motion.blend`, `report.json`, 변형 검사 입력 `poses.json`, 검사 결과 `check/`.
- `motions/library.blend`: 이름별 액션을 모은 파일. 같은 이름을 다시 만들면 해당 액션을 교체한다.
  텍스처보다 오래되면 메시가 옛것이므로 `animate`는 새로 시작하고 `glb`는 거부한다. 동작을 모두 다시 굽는다.
- `scores.jsonl`: 각 게이트의 값·통과 여부·변경 메모. `mesh.py S gate --history`로 확인한다.

`stage-gate/assets/gates.json`의 기준은 측정 전에 고정한다. 실패한 항목의 원인을 보고 한 가지를
바꿔 다시 `animate`와 두 게이트를 실행한다. 한계값을 낮춰 통과시키지 않는다. 통과 후에는 렌더를
확인한다. 5회 연속 개선이 없으면 원인과 남은 항목을 보고한다.

예제는 `box-modeling/references/`의 `lampkeeper_walk.json`, `lampkeeper_{idle,wave,raise_lantern}.json`,
`lampkeeper_rig.json`, `lampkeeper_carry.json`이다. 원래 `work/lampkeeper/` 세션에서 쓰던 파일이라 경로는 그 세션 기준이다.

## 동작 형식

`name`은 액션·폴더 이름이다. `type: "walk"`는 아래 걷기 파라미터를 사용한다.
`type: "keys"`는 `frames`, `poses`, `keys`를 사용한다. 이 프로젝트의 검증된 예제는 모두
루프 동작이다 (`loop: true`). 걷기는 제자리에서 움직이고 실제 이동 속도는 보고서에 기록된다.

키 포즈는 `{"hips":[x,y,z],"rot":[{"bone":"head","axis":[0,0,1],"deg":5}]}`이고,
`keys`는 `{"frame":0,"pose":"rest"}`처럼 포즈 이름과 시간을 연결한다. 각 구간의 도착 키에
`ease: "inout" | "linear" | "in" | "out"`을 지정할 수 있다. 기본은 부드러운 `inout`이다.
`delay`는 본별 지연 프레임이며 helper 본도 원본 본의 지연을 따른다. 두 발은 IK로 고정한다.

`follow`는 `bone`, 가속도를 읽을 `source`, 진동 주기 `period`(프레임), 감쇠 `damp`,
반응 크기 `gain`을 지정한다. `drag`와 `drag_from`은 원본 본의 회전에 늦게 반응하게 한다.
`drag_share`는 그 회전을 얼마나 전달할지 정한다(기본 1). `follow`는 뒤로 뻗은 꼬리에 맞게 만들어져 있어,
아래로 늘어진 스카프는 옆으로 흔들리지 않고 비틀린다. 이때는 꼬리를 가슴 본에 달고 `drag_share`를 줄인다.
전체가 키로 구워지므로 제약조건 없이 내보낼 수 있다.

## 걷기
Each frame the upper body is posed from the spec, then each leg is solved by two-bone IK towards an
ankle target, and everything is baked to keys, so no constraints need to travel. The foot lands on
its heel, rolls flat, lifts its heel about the toe, then swings on a curve that leaves and meets
the ground at the stance speed. Helper bones follow automatically.

걷기 파라미터:
| key | meaning |
|---|---|
| `cycle_frames`, `stride`, `stance` | frames per cycle, metres per cycle, share of the cycle a foot is down; below 0.5 both feet leave the ground for part of the cycle, a run |
| `lift`, `heel_strike`, `heel_off`, `heel_strike_deg`, `heel_off_deg` | foot path and roll |
| `kick` | a run's heel rising behind just after toe-off, metres (default 0). The swing leaves at the stance speed, so with a short stance the foot carries on backwards; lifted, it stays within the leg's reach without a deep crouch |
| `toe_y`, `heel_y` | ankle to toe tip and to back of heel, in metres |
| `hang_limit` | how far the swinging foot may follow the shin, in degrees |
| `hip_drop`, `bob`, `sway`, `roll`, `yaw`, `lean`, `nod` | body motion |
| `arm_swing`, `elbow`, `carry_swing`, `carry_elbow` | free arm and the arm carrying something |
| `carry_out` | degrees the carrying arm is held away from the body, so what it carries clears the leg |
| `arm_down` | degrees both arms are lowered from the rest pose, for a rig with arms held wide |
| `follow` | secondary spring and rotational drag settings, as above |
| `carry_side` | `L`(기본) 또는 `R`: 물건을 든 팔. 그 팔은 `carry_swing`, `carry_elbow`, `carry_out`을 쓰고 다른 팔은 `arm_swing`, `elbow`를 쓴다. 양수 `elbow`·`carry_elbow`는 양쪽 모두 팔뚝을 앞으로 굽힌다 |
| `hold` | 키 동작과 같다: 매 프레임 마지막에 더하는 회전(칼을 쥔 주먹) |

## Fitting the walk to the body
Work out the reach first: hip height, ankle height and leg length set the longest step. A leg of
23 cm allows about ±6 cm. Heavy boots change the sums, because a long foot is a long lever: 14° of
heel lift raised the ankle 6.5 cm and folded the knee. Straighter legs and short steps suit a stubby
character, and slower cycles cut jumps by the square of the time.

Long feet need a low `hang_limit`: a swinging toe can reach the floor. `spacing_crest` ignores points moving under 1 mm a
frame, so it reads 0 on a calm idle and cannot fail there.

A straight leg costs bend: shortening a leg of length L by d takes about 2 acos(1 - d / L) at the knee, so 6 cm
on a 32 cm leg is about 70 degrees. `roll` also lifts the swing-side hip. A deep bend can pass the stretch gate,
because the allowance grows with the bend, while the knee balloons: look at the walk from the side.

## Reading the report
- `pop_at` names the frame, material and place of the largest jump. An identical number after a
  change means that change did not touch the cause.
- Deformation is checked by the rig's own test on sampled frames (`check/`), with its limits.
- Weights decide much of this. Boots use `split` in the rig: by height, with `fade` keeping the
  upper bone off the toe. Without it the sole tipped into the ground and the toe crushed.

`track`에 지정한 본 끝으로 spacing과 이동량을 측정한다. 게이트는 `spacing_crest`를 본다: 가속도의 첨도(최댓값 ÷
제곱평균제곱근)를 속도의 첨도로 나눈 값으로, 어느 빠르기·주기의 사인 움직임이든 1이고 선형 키처럼 속도가 꺾이는
곳에서 커진다. 예전 `spacing`(최대 가속도 ÷ 최대 속도)은 매끈한 움직임에서도 2π/주기라 빠른 리듬일수록 실패했으므로
참고로만 남는다. 액션의 `primary`는
`point`, `from`, `to`를 지정하며, 이 구간에서 anticipation·overshoot·arc 비율을 구한다.
이 항목들은 연출의 대리 지표다. 해당 연출이 필요 없는 새 동작에는 맞는 기준을 먼저 정한다.

`overlap: {"driver":"head","follower":"tail3"}`는 두 본의 **레스트 대비 회전**을 비교한다.
머리와 두건 끝의 절대 위치는 평행 이동과 서로 다른 지렛팔 길이가 섞이므로 회전 지연을
판정하는 데 사용하지 않는다. `overlap_space: "rest_relative_rotation"`로 측정 방식을 구분한다.
`overlap_lag_frames`는 양수면 뒤따름, 0이면 뻣뻣한 부착, 음수면 앞섬이다.
`overlap_at_limit`가 참이면 지연이 검색 상한(1/4주기)에 닿은 것이다. 그 값은 정점이 아니라 "적어도 이만큼"이다.
게이트는 지연 2프레임 이상과 함께 `follower_ratio`(두건 회전 폭 ÷ 머리 회전 폭) 1.2 이상을 요구한다.
양방향으로 최대 1/4주기를 검색한다. 회전이 거의 없거나 상관계수가 0.5 미만이면 `null`로
기록해 통과시키지 않는다. `overlap_correlation`, `follower_ratio`도 함께 읽는다.
과거 위치 기반 점수와 수정된 회전 점수는 직접 비교하지 않는다.
회전 지연이 크다고 두건 끝 위치가 그만큼 늦게 보이는 것은 아니다. 머리에 실려 함께 움직이는 양이 크기
때문이다. 걷기에서 회전 지연은 7프레임이지만 끝점 위치 지연은 약 1프레임이고, 드래그의 효과는 대신
움직임 폭으로 나타난다 (좌우 11.6 cm → 19.3 cm). 눈으로 보이는 뒤따름은 재생해서 판단한다.

## 한 번 실행하는 동작과 공격

LoL처럼 게임이 유닛을 옮기는 방식에 맞춰 동작은 **제자리**에서 만든다. 앞으로 나가는 거리는
`travel` 키로 기록만 하고(`root_path`, `travel_m`), 렌더는 그 경로를 따라 캐릭터를 움직여 보여 준다.
점프 높이처럼 몸이 실제로 하는 일은 포즈의 `hips`와 `feet`에 담는다.

| key | meaning |
|---|---|
| `loop: false`, `frames` | 한 번 재생. 마지막 프레임을 다시 굽지 않고, 고리 닫힘 대신 끝 자세를 잰다 |
| 포즈의 `feet` | `{"L": [dx, dy, dz, pitch]}`: 발목을 레스트에서 옮기는 거리(m)와 발 기울기(도). 생략하면 제자리 |
| `step_lift` | 두 키 사이에 위치가 바뀌는 발이 들리는 높이, 기본 0.05 m. 그 구간은 딛지 않은 것으로 센다 |
| 회전의 `"local": true` | 축을 그 본의 레스트 축으로 읽는다. 팔이 돌아도 손가락은 같은 방향으로 굽는다 |
| `hold` | 모든 포즈 뒤에 더하는 회전 목록. 칼 손잡이를 쥔 주먹처럼 계속 유지할 자세 |
| `include_poses` | 다른 파일의 포즈를 가져온다(동작 파일 기준 경로). 대기·연타가 같은 `guard`를 나눠 쓰게 한다. 동작 자신의 포즈가 우선한다 |
| `end_pose` | 끝 자세가 맞아야 하는 포즈 이름, 기본은 마지막 키. 다음 동작이 시작하는 포즈를 적는다 |
| `strike` | `{"tip": [x, y, z], "from": f, "impact": f}`: 무기 자체 좌표의 칼끝, 휘두르기를 찾기 시작할 프레임, 맞는 프레임. `--carry`가 필요하다 |
| `exempt` | `[[a, b]]`: 튀는 움직임을 재지 않을 구간(착지). 타격 구간 `from`~`impact + 2`는 자동으로 빠진다 |
| `travel` | `[{"frame": 0, "at": [0, 0, 0]}, {"frame": 12, "at": [0, -1.5, 0], "ease": "out"}]`: 게임이 옮기는 경로 |
| 포즈의 `yaw` | 몸 전체가 원점의 수직축을 도는 각도(도). 각도로 보간하므로 0 → 360처럼 반 바퀴를 넘는 회전도 된다. 발 위치·발 방향·무릎 방향이 함께 돈다. 두 키의 `yaw`가 다른 구간의 발은 딛지 않은 것으로 센다 |
| `hand_off` | `[{"bone": "lid", "hand": "hand.L", "grab": f0, "release": f1}]`: `grab`부터 `release` 전까지 그 본이 잡은 순간의 상대 위치 그대로 손을 따라간다. 놓는 순간 원래 자리로 돌아가므로 손이 제자리에 가져다 놓아야 하고, 아니면 튀는 움직임으로 잡힌다 |

측정 정의 (모두 `quality`, 24fps 기준은 `gates.json`의 `motion_attack`):
- **칼끝 최고 속도**와 그 프레임: 칼끝 궤적의 중앙 차분 속도에서 `from`~`impact + 3` 사이 최댓값.
- **타격 시간(`strike_s`)**: 최고 속도 프레임 앞쪽으로 최고 속도의 25% 이상인 프레임이 이어진 길이.
- **예비동작(`wind_up_s`)**: 타격이 시작되기 전 칼끝이 타격 방향의 반대쪽으로 가장 멀리 간 곳까지,
  뒤로 움직인 시간. 꼭대기에서 멈추는 시간은 세지 않는다. 예비동작 **도중에** 멈췄다가 다시 뒤로 가면
  마지막으로 뒤로 간 구간만 센다.
- **위에서 본 궤적(`top_travel_m`)**: 타격 시작부터 맞는 프레임까지 칼끝이 지면 평면에서 지나간 길이.
  탑뷰 카메라에서 공격이 읽히는지를 대신한다.
- **끝 자세(`end_pose_mm`)**: 마지막 프레임과 `end_pose`를 키 없이 세운 메시의 최대 정점 거리. 흔들림
  본(`follow`)에 주로 붙은 정점은 다음 동작에서 가라앉으므로 뺀다.
- 발 미끄러짐·뜸은 키에서 위치가 같고 높이가 0인 발만 딛은 것으로 보고 잰다. 균형은 딛은 발로만 잰다.
  `frames_no_foot_down`은 두 발 모두 딛지 않은 프레임 수다(공중이거나 몸과 함께 도는 중).
- 레스트에서 다리가 다 펴진 캐릭터는 엉덩이를 조금도 내리지 않으면 매 프레임 IK 도달 한계에 걸린다
  (`ik_out_of_reach`). 기본 자세(guard)에서 엉덩이를 몇 cm 내려 무릎을 굽힌다.
- 다리 helper(`hipjoint`처럼 다리 본을 따르는 본)도 IK가 정하므로 키에서 다시 보간하지 않는다.
- 키 사이의 회전은 늘 짧은 쪽으로 돈다(두 쿼터니언의 부호를 맞춘다). 반 바퀴를 넘는 회전은 `yaw`로 준다.
- **튀는 움직임(`pop_spike_ratio`)**: 한 프레임의 속도 변화(표본 정점의 2차 차분)를 두 프레임 앞뒤의 같은
  값 중 큰 쪽(+ 정지 여유 2 mm/frame²)과 비교한 배율. 동작 전체를 빨리 재생해도 그대로이고, 한 프레임만
  경로에서 벗어나면 커진다. 빠르게 휘두르는 도중의 같은 크기 튐은 덜 보이므로 덜 잡힌다. 타격 구간과
  `exempt`는 빼고 잰다. 가속도 자체(`pop_mm_per_frame2`)는 참고로만 남는다.
- `hand_off`로 손에 넘긴 본에 실린 부위와 원래 붙어 있던 부위의 간격은 변형 검사에서 빼고 잰다(리그의
  `attach` 쌍). 둘 다 함께 실린 부위(솥뚜껑과 꼭지)끼리는 그대로 잰다.

계산식은 `scripts/motion_metrics.py`의 `strike_metrics`, `pops`이며 `test_motion_metrics.py`가 정답이 아는
궤적으로 검사한다.

## 소품 들기

`carry.json`은 소품 하나의 들기 방식을 정하는 단일 설정이다. 렌더와 충돌 측정이 같은 `prop_attach.py`로
위치를 계산하므로 채점 대상과 그림이 어긋나지 않는다.

| key | meaning |
|---|---|
| `prop` | 소품 `.blend`, 프로젝트 루트 기준 |
| `bone`, `drop`, `swing` | 잡는 본, 본 중심에서 소품 원점까지 내려가는 거리(m), 진자 각도 |
| `handle` | 소품 자체 좌표에서 손잡이의 방향(도). 지정하면 손잡이가 손바닥을 가로지르도록 소품이 돈다. 비대칭 소품은 180을 더하면 앞뒤가 바뀐다 |
| `light` | 렌더에서 소품 안에 넣는 빛(W), 기본 0 |
| `offset` | 잡는 점을 본 중심에서 옮기는 거리 [x, y, z], 본 자체 축 기준(m). 손아귀가 본 중심에 없을 때 |
| `controls` | 이 들기에만 해당하는 음성 대조군, 일반 대조군 뒤에 실행 |
| `grip` | 손 안에 들어가도록 만든 부분의 재질 이름 |
| `mode` | `hang`(기본, 위 방식) 또는 `grip`: 무기처럼 소켓 본에 단단히 고정 |
| `grip_point` | grip: 소켓 본의 머리에 오는 소품 자체 좌표의 점, 예: 칼 손잡이 축 0.18 m는 `[0, 0, 0.18]` |
| `tip` | grip: 소품 자체 좌표의 끝점 [x, y, z]. 내보낼 때 소켓 아래 표시 본이 되어 엔진 검사가 이 점을 잰다 |
| `socket` | grip: 내보낼 때 만드는 소켓 본 이름, 기본 `prop_socket` |
| `rotate` | grip: 소켓 본 좌표에서의 XYZ 오일러 회전(도, X → Y → Z 순서). Y축이 손잡이를 따라 날 쪽을 향하는 소켓이면 `[-90, roll, 0]`: X -90으로 소품의 +Z를 본의 +Y에 눕힌 뒤 Y의 roll로 손잡이 둘레에서 날을 돌린다 |

`propcheck`는 모든 프레임에서 몸과 소품의 닫힌 셸을 하나씩 비교해 파고든 깊이를 잰다.
`grip` 재질과 잡는 손의 조합은 의도된 쥠이므로 `grip_depth_mm`로만 기록하고, 대신 매 프레임 닿아 있어야
한다(`frames_not_held`). 잡는 손은 소품을 든 본 하나다. grip 방식에서 가중치가 없는 소켓 본이면 가장 가까운
가중치 있는 조상 본과 그 아래 본(주먹의 손가락)이 잡는 손이다(`holders`). 소품의 나머지 부분은 같은 손과도 충돌로 센다. 보고서의 `pairs`는 어느 부위끼리
부딪혔는지, `by_frame_mm`은 언제인지 알려 준다.

- **그림은 믿지 않는다.** 등불이 배에 59mm 묻혀도 렌더로는 보이지 않았다.
- **손잡이 방향이 먼저다.** 고정된 소품은 팔을 들면 손잡이 다리가 소매를 가로지른다. 쥐는 방식을 고치기
  전에는 팔 자세 210개 중 4개만 통과했고, 고친 뒤 245개 중 75개가 통과했다.
- **대각선 손잡이는 모서리를 몸 쪽으로 돌린다.** 이때는 `carry_out`이나 포즈의 팔 벌림으로 간격을 만든다.
- **자세를 찾을 때는 막는 조합을 먼저 본다.** 각도를 무작정 늘리지 않는다.
- 한 프레임만 튀는 깊이는 동작이 아니라 측정 오류를 의심한다. 내부 판정은 세 방향 광선의 다수결이다.

측정기를 고치면 `test_shell_depth.py`를 실행한다:

```bash
blender -b --factory-startup --python-exit-code 1 --python scripts/test_shell_depth.py
```

## 채점기가 결함을 잡는지 확인

`controls`는 `assets/controls/`의 다섯 불량 동작을 생성하고 지정된 항목이 실패하는지 확인한다:
정지 동작의 최소 이동량, 선형 타이밍·예비 동작·과도 동작, 뻣뻣한 두건, 미끄러지는 발,
발 밖으로 나간 균형. 모두 잡혀야 한다. 실행 전후 실제 액션 라이브러리가 보존되는지도 확인한다.
`--carry`를 주면 `assets/controls_prop/placements.json`의 잘못된 들기도 걷기에서 시험한다: 가슴에 건 소품,
손에서 떨어진 소품, 너무 높이 건 소품. 값은 그 소품의 `drop`에 비례한다. 너무 높이 건 소품은 모양에 따라
몸을 뚫거나 손을 놓치므로 어느 쪽이든 거부되면 된다(`must_fail_any`). 쥐기 방식(`mode: grip`)의 carry는 `assets/controls_prop/grip.json`을 쓴다: 손 대신 가슴뼈에 쥔 무기(몸에 파고든 깊이), 소켓에서 0.5 m 떨어진 손잡이(손에 들려 있지 않음). 매달기 값(`drop`)은 쥐기에 쓰이지 않기 때문이다. 대조군을 돌릴 동작은 `--prop-motion NAME`으로 고른다(기본 `walk`). `--attack`을 주면 공격 대조군이 무기 대조군을 대신한다.

`--attack attack.json --carry carry.json`을 주면 통과한 공격을 한 가지씩 망가뜨려 각 기준이 잡는지
본다: `from` 앞 키부터 맞는 키까지의 타격 구간 자체를 6프레임 늘림(타격 시간), 맞는 프레임을 3프레임 당겨
적음(최고 속도 프레임), 예비동작 없앰(예비동작), 딛은 발을 밀어냄(발 미끄러짐), 타격·착지에서 먼 한 프레임에
몸 전체를 3 cm 밀어냄(튀는 움직임), 엉뚱한 끝 자세(끝 자세), 칼을 가슴뼈에 꽂음(몸에 파고든 깊이). 통과하는
공격에 돌려야 의미가 있다. 반복 동작용 `control_pop`도 한 프레임을 3 cm 밀어 튀는 움직임 기준이 잡는지 본다. 균형 대조군은 엉덩이를 발이 닿는 폭의 1.4배만큼 옆으로 민다
(`hips_feet_x`); 고정 거리 0.26 m는 발이 넓은 캐릭터의 발 안에 머물렀다.

회전 지연 계산을 바꿨다면 Blender의 NumPy로 회귀 테스트를 실행한다:

```bash
blender -b --factory-startup --python-exit-code 1 --python scripts/test_motion_metrics.py
```

렌더러는 걷기에서는 보폭에 맞춘 격자를, 보폭이 0인 대기·액션에서는 고정 크기 격자를 쓴다.
소품은 렌더에 붙는 별도 모델이며 이 캐릭터의 변형 점수나 GLB에 자동 포함되지 않는다. 몸과의 충돌은
`prop_contact` 게이트로 잰다.
수치 통과는 무게감·매력·소품 충돌을 보장하지 않으므로 루프와 주요 포즈를 직접 확인한다.
