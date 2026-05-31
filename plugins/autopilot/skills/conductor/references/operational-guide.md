# conductor 상시 호스트 무인 운영 가이드 (C5)

`conductor poll`(→ `references/poll.sh`)을 **전용 상시 호스트(dedicated always-on host)**에서
무인으로 주기 실행해 spec→dispatch→리뷰→머지 파이프라인을 사람 개입 없이 닫기 위한
운영·보안 경계 문서다. 본 가이드는 호스트별 설정 산출물(systemd 유닛 등)을 만들지 않고
**문서로만** 안내한다(SPEC 비-목표).

> 사용자 확정 결정: **런타임은 전용 상시 호스트.** 이 호스트가 무인 `gh` 자격증명의
> 신뢰 경계(trust boundary)다. 개발자 노트북·공용 CI 러너가 아닌, 이 자동화 전용으로
> 격리된 호스트에서만 무인 토큰을 둔다.

---

## 1. 신뢰 경계 한눈에

```
전용 상시 호스트 (trust boundary)
├── 스케줄러 (cron / /schedule / /loop)
│      └── conductor poll          ← 무인 자격증명을 쓰는 유일 지점
│             ├── start  (dispatch → 자율 실행기 서브프로세스)   ※ push/merge 권한 미상속
│             ├── integrate (C2)   push (작업 브랜치 한정 토큰)
│             ├── review    (C3)   같은 head 브랜치 push (force 금지)
│             └── merge     (C4)   base 머지   ← 별도 approver 신원의 승인 후에만
└── 자격증명
       ├── BOT_TOKEN       범위 최소화된 자동화 토큰 (push·PR·이슈)
       └── APPROVER_TOKEN  분리된 승인 권한 신원 (승인 전용)   ← BOT 와 절대 공유 금지
```

핵심 3대 통제: **(1) 토큰 권한 스코프 최소화 · (2) approver 신원 분리 · (3) 자율 실행기
서브프로세스 권한 격리.** 아래에서 각각을 규정한다.

---

## 2. 무인 자격증명 토큰의 권한 스코프 (AC5)

무인 `gh` 토큰(`BOT_TOKEN`)은 **최소 권한 원칙**으로 발급한다. poll 드레인이 실제로
호출하는 forge 동작에 필요한 스코프만 부여하고, 그 외는 명시적으로 배제한다.

### 2.1 필요한 최소 스코프

| 동작 (호출 단위) | 필요한 권한 스코프 |
|---|---|
| 이슈=task 생성·상태·코멘트 (C1) | `issues: write` (Projects 사용 시 `repository-projects: write`) |
| 작업 브랜치 push (C2/C3) | `contents: write` — **단, 작업 브랜치 네임스페이스로 제한** |
| PR 생성/조회 (C2) | `pull_requests: write` |
| 리뷰/승인 조회 (C3/C4) | `pull_requests: read` |

- Fine-grained PAT 또는 GitHub App 설치 토큰을 권장한다(classic `repo` 광역 스코프 지양).
- **대상 저장소를 이 레포 하나로 한정**한다(조직 전체 토큰 금지).
- 토큰은 호스트의 비밀 저장소(예: `gh auth login` 의 OS 키체인, 또는 파일 권한 `600`
  의 환경 파일)에만 둔다. 레포·로그·`.conductor/` 상태 디렉토리에 절대 커밋·기록하지 않는다.
- 만료·로테이션: 짧은 만료(예: 90일 이하) + 주기 로테이션. 유출 시 폐기 절차를 문서화한다.

### 2.2 배제할 권한 (명시적 비-스코프)

- `BOT_TOKEN` 에 **승인(approve) 권한을 주지 않는다.** 승인은 §3 의 별도 `APPROVER`
  신원만 수행한다(자동화 토큰의 self-approve 차단).
- `BOT_TOKEN` 에 **branch protection 우회·force push·admin** 권한을 주지 않는다.
  poll 경로의 어떤 모듈도 force 를 쓰지 않으며(merge 는 `--ff-only`), 토큰 수준에서도 막는다.
- 조직 멤버십·secrets·Actions 관리 등 파이프라인과 무관한 스코프는 부여하지 않는다.

---

## 3. 승인 권한 신원(approver)의 분리 (AC6)

머지(C4)는 **분리된 승인 권한 신원**의 "승인됨"(APPROVED) 정식 리뷰가 있을 때만 일어난다.
이 신원을 자동 리뷰 봇·자동화 토큰과 **물리적으로 분리**해 권한 상승을 차단한다.

- **별도 신원·별도 토큰**: 승인은 `APPROVER`(별도 봇 계정 또는 사람의 PAT)만 수행한다.
  이 자격증명은 `BOT_TOKEN` 과 **공유하지 않으며**, 가능하면 다른 비밀 저장소/호스트 권한
  경계에 둔다.
- **self-approve 무효화**: 자동 리뷰 봇(`REVIEW_BOT`)이 자기 PR 을 승인해도 무효다.
  merge.sh 는 `REVIEW_BOT` 의 APPROVED 를 건너뛰고, `APPROVER` 가 설정되면 그 신원의
  승인만 인정한다. 운영 시 두 환경 변수를 **반드시 서로 다른 신원**으로 설정한다:

  ```sh
  export REVIEW_BOT="auto-review-bot"   # 자동 리뷰(변경요청) 신원 — 승인 불가
  export APPROVER="release-approver"    # 승인 전용 신원 — REVIEW_BOT 과 달라야 함
  ```

- **분리 불변식**: `APPROVER == REVIEW_BOT` 이거나 `APPROVER` 가 `BOT_TOKEN` 신원과
  같으면, 자동화가 스스로 승인·머지하는 권한 상승이 된다. 운영 점검 항목으로 둔다.
- 브랜치 보호 규칙(서버측)에서 "1+ 승인 필요 + self-approve 금지 + 자동수정 푸시 후
  승인 dismiss"를 함께 설정하면 호스트측 통제와 이중화된다.

---

## 4. 자율 실행기 서브프로세스 권한 격리 (AC6)

poll 의 `start`/`integrate`/`review` 는 구현을 **자율 실행기(loop/dispatch) 서브프로세스**에
위임한다. 이 서브프로세스는 **머지·base push 권한을 상속해서는 안 된다** — 사고 반경을
구현 작업 공간으로 가둔다.

- **권한 하향(de-privilege)**: 자율 실행기 자식 프로세스의 환경에서 `APPROVER_TOKEN`
  과 base 브랜치 푸시·머지 권한을 제거한다. 자식에는 작업 브랜치 push 에 필요한 최소
  토큰만, 또는 아예 토큰 없이(로컬 커밋만) 돌리고 push 는 poll 의 forge 단계가 수행한다.
- **머지는 자식이 아니라 poll 이 한다**: 머지(C4)는 자율 실행기 안에서 일어나지 않고,
  승인 게이트를 통과한 뒤 poll 의 merge 단계(`--ff-only`)에서만 일어난다. 자식 코드가
  base 를 직접 머지·push 할 수 없게 토큰·브랜치 보호로 막는다.
- **환경 변수 비전파**: `APPROVER`/`APPROVER_TOKEN` 등 승인 권한 자격증명을 자율 실행기
  자식의 환경에 내보내지 않는다(`export` 범위 점검). poll 은 자식에 task 컨텍스트
  (`POLL_CUR_TASK`)만 노출한다.
- **작업 공간 격리**: 자식은 자기 격리 워크트리/작업 공간에서만 쓰고, conductor 상태
  디렉토리(`.conductor/`) 밖을 건드리지 않는다. 정리는 머지 확인 후 loop 의 공개 cleanup
  인터페이스로만 위임한다(직접 삭제 금지).

---

## 5. 폴링 주기·실행 방식 (AC7)

전용 상시 호스트에서 `conductor poll` 을 **주기적으로** 돌린다. poll 은 호출 단위 무상태·
멱등이므로, 크래시·중복 실행에도 안전하다(중복 전이·중복 PR 없음). 다음 중 하나로 스케줄링한다.

### 5.1 권장 주기

- **기본 5–15분 간격.** 리뷰/승인 반응성과 forge API rate limit·비용 사이의 균형값.
  승인 대기가 주된 병목이면 길게(15–30분), 활발한 개발 중이면 짧게(5분) 조정한다.
- **단일 실행 보장**: 동시에 두 드레인이 겹치지 않도록 lock(예: `flock`)으로 직렬화한다.
  poll 자체가 멱등이라 겹쳐도 치명적이진 않으나, forge API 낭비를 막는다.

### 5.2 실행 수단 (택1) — 호스트별 설정 산출물은 만들지 않고 안내만 한다

- **호스트 cron** (전용 상시 호스트의 표준 수단):

  ```cron
  # 10분마다 멱등 드레인 1회 (flock 으로 중복 실행 방지)
  */10 * * * * /usr/bin/flock -n /tmp/conductor-poll.lock \
      bash /path/to/plugins/autopilot/skills/conductor/references/poll.sh poll \
      >> /var/log/conductor-poll.log 2>&1
  ```

- **하니스 `/schedule`** (원격 스케줄 에이전트): `conductor poll` 을 cron 식으로 등록.
- **하니스 `/loop`** (간격 반복 실행): 대화형/세션 호스트에서 `poll` 을 주기 반복.

> 어느 수단이든 본 가이드는 **글루(어떻게 주기 실행할지)만 문서화**하고, systemd 유닛
> 같은 호스트별 설정 파일은 산출하지 않는다(SPEC 비-목표).

### 5.3 운영 점검 체크리스트

- [ ] `BOT_TOKEN` 스코프 최소화(§2) — 승인·force·admin 권한 없음.
- [ ] `APPROVER` ≠ `REVIEW_BOT` ≠ `BOT_TOKEN` 신원 (§3 분리 불변식).
- [ ] 자율 실행기 자식에 승인·머지 권한 미상속 (§4).
- [ ] poll 단일 실행 lock + 주기(§5.1) 설정.
- [ ] 토큰을 레포·로그·`.conductor/` 에 기록하지 않음.
