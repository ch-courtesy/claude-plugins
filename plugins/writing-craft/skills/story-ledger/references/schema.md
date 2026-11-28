# TOML 이야기 장부

Python 3.11 이상을 사용하라. 아래 일곱 종류를 장부 폴더에 두어라.
본문에서 채택한 사실만 확정하라. 이 형식은 조사 7.1~7.6의 운영 설계안을
기계 검사 가능한 필드로 구체화한 것이다. 문학적 타당성은 별도로 판단하라.

## 공통 규칙

- 모든 기록에 문자열 `id`, `status`, `evidence`를 반드시 넣어라.
- `status`는 `"confirmed"`(확정), `"planned"`(계획), `"belief"`(믿음) 중 하나로 정하라.
  인지·소유 하위 기록에도 상태와 근거를 넣어라. 계획·믿음을 세계의 확정 사실로 취급하지 마라.
- 근거는 `E014-S03:P008`처럼 회차·장면·문단으로 적어라. 계획은
  `plan:기획.md#결말`처럼 본문 밖 위치를 명시하라. 최초 근거를 보존하라.
- ID는 장부 전체에서 유일하게 정하라. 설정·장소·물건은 `SET-001`,
  인물은 `CHR-001`, 정보는 `INF-001`, 사건은 `EVT-001`, 복선은 `FS-001`을 써라.
  숫자는 세 자리 이상으로 적어라. 회차는 `E001`, 장면은 `E001-S01`로 적어라.
  장면 번호는 두 자리 이상으로 적어라. 파일명과 ID를 맞춰라.
- 회차 수치는 양의 정수, 목록은 TOML 배열로 적어라. 없는 목록도 `[]`로 남겨라.
- 장소·물건 참조는 설정 ID, 인물 참조는 인물 ID, 사건 참조는 사건 ID로 적어라.
- 아래 예시의 필드는 선택이라고 적은 것 외에는 모두 필수다.
  배열 테이블은 기록마다 반복하라. 빈 장부는 `knowledge = []`처럼 명시하라.

## bible.toml

`settings` 배열에 사실 `fact`, 적용 조건 `conditions`, 예외 `exceptions`를 문자열로 적어라.
장소·물건도 설정에 등록하라.

```toml
[[settings]]
id = "SET-001"
fact = "폐역은 해 질 때 잠긴다."
conditions = "매일"
exceptions = "역장이 열 수 있다."
status = "confirmed"
evidence = "E001-S01:P001"

[[settings]]
id = "SET-002"
fact = "폐역 열쇠"
conditions = "문을 열 때"
exceptions = "없음"
status = "confirmed"
evidence = "E001-S01:P002"
```

## characters.toml

`characters` 배열에 이름 `name`, 욕망 `desire`, 전략 `strategy`, 말투 카드 `speech`,
신체 상태 `body`를 문자열로 적어라. `state`는 `"alive"` 또는 `"dead"`로 정하라.
사망이면 정수 `death_episode`도 반드시 적어라. 관계 `relationships`는
`{character = 인물ID, relation = 관계설명}` 목록이다.
`possessions`는 `{item = 설정ID, episode = 회차, status = 상태, evidence = 근거}` 목록이다.
소유는 해당 회차의 스냅샷이다. 이전 회차에서 자동으로 이어지지 않는다.
한 회차 내 소유 이전은 최종 소유자만 기록하라.

```toml
[[characters]]
id = "CHR-001"
name = "지연"
desire = "귀환"
strategy = "열쇠를 찾는다."
relationships = []
speech = "짧은 해라체"
body = "왼발 부상"
state = "alive"
possessions = [{item = "SET-002", episode = 1, status = "confirmed", evidence = "E001-S01:P002"}]
status = "confirmed"
evidence = "E001-S01:P002"
```

## knowledge.toml

`knowledge` 배열에 실제 사실 `fact`, 인물별 인지 `awareness`, 독자 공개 회차
`reader_episode`를 넣어라. 미공개는 `reader_episode = 0`으로 적어라.
인지 항목은 `character`, 문자열 `understanding`, `status`, `evidence`를 갖는다.
인물의 오해는 인지 항목에 `belief`로 적어 실제 사실과 구별하라.

```toml
[[knowledge]]
id = "INF-001"
fact = "폐역 문은 잠겼다."
awareness = [{character = "CHR-001", understanding = "열려 있다고 믿음", status = "belief", evidence = "E001-S01:P003"}]
reader_episode = 1
status = "confirmed"
evidence = "E001-S01:P003"
```

## timeline.toml

`events` 배열에 `episode`, 시간·상대 시간 `time`, 지속 `duration`, 장소 ID
`location`, 이동 설명 `movement`를 넣어라. 명시 날짜가 있을 때만 선택 필드
`date = "YYYY-MM-DD"`를 넣어라. 날짜를 추정하지 마라.
다른 회차의 명시 날짜만 비교한다. 회상 사건은 본문 공개 회차 대신 사건이 속한 시간선
회차에 배치하라. 같은 회차의 사건 순서는 자동 판단하지 않는다.

```toml
[[events]]
id = "EVT-001"
episode = 1
date = "2026-01-01"
time = "정오"
duration = "1시간"
location = "SET-001"
movement = "도보로 도착"
status = "confirmed"
evidence = "E001-S01:P004"
```

## episodes/E001.toml

파일 하나에 회차 하나를 적어라. 실제 사건 ID 목록 `events`, 선택과 비용
`choice_cost`, 새 확정 설정·정보 ID 목록 `new_facts`, 미해결 설명 목록 `unresolved`,
다음 계획 문자열 `next_plan`을 넣어라. `next_plan`은 항상 미확정 계획이다.

```toml
id = "E001"
episode = 1
events = ["EVT-001"]
choice_cost = "역으로 돌아가 시간을 쓴다."
new_facts = ["INF-001"]
unresolved = ["열쇠의 위치"]
next_plan = "역장을 만날 예정(미확정)"
status = "confirmed"
evidence = "E001-S01:P004"
```

## scenes/E001-S01.toml

파일 하나에 장면 하나를 적어라. 시점 인물 `pov`, 참여자 ID 목록 `participants`,
시간 `time`, 장소 ID `location`, 목표 `goal`, 저항 `resistance`, 결과 `result`,
여파 `aftermath`, 입장 상태 `before`, 퇴장 상태 `after`를 넣어라.
금지 정보 ID 목록 `forbidden_info`, 설치·회수 관련 복선 ID 목록 `foreshadows`를 넣어라.
회상이면 선택 필드 `flashback = true`를 넣어 사망 뒤 참여 검사에서 제외하라.

```toml
id = "E001-S01"
episode = 1
pov = "CHR-001"
participants = ["CHR-001"]
time = "정오"
location = "SET-001"
goal = "문을 연다."
resistance = "잠긴 문"
result = "실패"
aftermath = "역장을 찾는다."
before = "문이 열렸다고 믿음"
after = "잠겼음을 앎"
forbidden_info = []
foreshadows = ["FS-001"]
status = "confirmed"
evidence = "E001-S01:P004"
```

## foreshadow.toml

`foreshadows` 배열에 설치 회차 `setup_episode`, 재등장 회차 목록 `reappearances`를
넣어라. 회수하면 선택 필드 `resolved_episode`, `resolved_evidence`를,
폐기하면 `discarded_episode`, `discarded_evidence`를 추가하라.
설치 근거는 공통 `evidence`에 적어라. 최신 확정 회차와 설치 회차 차이가
`--foreshadow-limit`보다 클 때 회수·폐기 기록이 없으면 경고한다.

```toml
[[foreshadows]]
id = "FS-001"
setup_episode = 1
reappearances = []
status = "confirmed"
evidence = "E001-S01:P004"
```

## 검사 실행

`python scripts/ledger_check.py 장부폴더`로 실행하라. 본문은 별도 폴더에
`E001.md` 또는 `E001.txt`로 두고 `--episodes-text-dir 본문폴더`를 지정하라.
`--min-chars`를 주면 하한 미달을 오류로 낸다. `--count without_spaces`가 기본이다.
공백 미포함은 모든 유니코드 공백을 제거하고, 포함은 줄바꿈까지 센다.
CRLF·CR 줄바꿈은 LF로 정규화해 줄바꿈 하나를 한 글자로 세라.
분량 finding에는 두 수치를 모두 남긴다. 본문 해시는 `texts/파일명` 키에 남긴다.
장부 해시는 장부 루트 상대 경로로 남긴다. 경고만 있으면 종료 코드 0,
오류가 있으면 1이다. `ok`는 오류가 없다는 뜻이다.
TOML 구문·필드 형식 오류는 `missing_field`로 보고한다.
