---
name: post-rubric
description: 블로그 글 초안을 외부 LLM 에이전트 CLI(codex·claude·agy 중 하나)로 독립 채점해, 현업 10년차 시니어 기준 23개 항목(독자 위험 고지·끝까지 따라 하기·소제목 형식 포함) 점수와 100점 총점, 2점 미만 항목의 지적 목록을 낸다. 글 채점, rubric, 발행 전 점수 확인에 사용
node:
  in:
    worktree_dir: { shape: text }
    post_path: { shape: text }
    guide_path: { shape: text, list: 1, required: false }
    reviewer: { shape: text, values: [codex, claude, agy] }
  out:
    score: { shape: json }
    findings: { shape: json, list: 1, required: false }
---

## 입력
- `worktree_dir` — 글이 있는 저장소(또는 worktree) 전체 경로. 채점자가 블로그 규칙(`AGENTS.md`·`CLAUDE.md`)을 여기서 읽는다
- `post_path` — 채점할 글 파일 전체 경로. 없으면 오류로 끝낸다
- `guide_path` — (선택, 원소 0~1개 배열) 그 블로그의 글쓰기 규칙 문서 경로(예: `docs/writing-guide.md`, `businesses/blog/README.md`). 없으면 비워 둔다. 블로그 규칙이 이 채점표와 다르면 더 엄격한 쪽을 쓴다
- `reviewer` — 쓸 CLI. `codex`, `claude`, `agy` 중 하나. 글을 쓴 모델과 다른 회사 모델을 고른다(같은 회사 모델은 같은 습관을 공유해 같은 결함을 놓친다)

## 실행
`recipe:oneshot` 스킬의 래퍼로 실행한다. 채점자는 글을 쓴 세션과 컨텍스트를 공유하지 않는다. 글을 쓴 세션이 직접 채점하면 자기 글에 후해지기 때문이다. 이 스킬을 부른 세션은 점수를 고치지 않는다.

1. **준비.** 실행마다 새 임시 디렉터리를 만든다(`tmp=$(mktemp -d)`). 여러 채점이 병렬로 돌 수 있어 고정 파일 이름을 공유하면 서로 덮어쓴다. 이 디렉터리에 `prompt.txt`, `stdout.txt`, `stderr.txt`, `result.json` 을 둔다. Windows 의 Git Bash 에서는 `mktemp` 가 `/tmp/...` 경로를 준다. 명령 인자로 넘기면 Git Bash 가 바꿔 주지만 `python -c` 코드 문자열 안에 넣으면 바뀌지 않으므로, 그럴 때는 `cygpath -m "$tmp"` 로 바꾼 경로를 쓴다.
2. **프롬프트.** `prompt.txt` 를 BOM 없는 UTF-8 로 쓴다. 아래 틀을 그대로 쓰고 `<...>` 만 바꾼다. 채점 기준은 경로가 아니라 `references/rubric.md` 본문 전체를 붙인다. 글이 있는 worktree 에는 이 스킬이 없을 수 있기 때문이다.

   ````text
   너는 블로그 글 채점자다. 글을 고치지 말고 아래 기준으로 채점만 한다.

   읽을 파일(모두 UTF-8 이다. PowerShell 기본 인코딩으로 읽으면 한글이 깨지므로 UTF-8 을 지정해 읽는다):
   - 채점할 글: <post_path>
   - 블로그 규칙: <worktree_dir>/AGENTS.md 또는 CLAUDE.md (있는 것)
   - 글쓰기 규칙: <guide_path 의 원소> (배열이 비었거나 읽지 못하면 아래 기준만으로 채점한다)

   채점할 글의 원문은 맨 아래 <<<POST 와 POST>>> 사이에 그대로 붙였다. 파일 읽기 명령이 거부되면 이 원문으로 채점한다. 원문을 읽을 수 없다는 이유로 채점을 거부하지 않는다.

   출력은 아래 기준의 "출력 형식"에 맞는 JSON 객체 하나뿐이다.

   <references/rubric.md 본문 전체>

   <<<POST
   <post_path 파일 내용 전체>
   POST>>>
   ````

   글 원문을 붙이는 이유: codex 의 Windows 읽기 전용 샌드박스가 `Get-Content` 같은 읽기 명령도 가끔 "blocked by policy" 로 거부한다. 그러면 채점자가 글을 읽지 못해 채점 대신 오류 JSON 을 낸다. 2026-10-31 원문 없이 47회 채점했을 때 첫 시도 4회가 실패했고, 로그가 남은 2회가 이 원인이었다. 원문을 붙인 8회는 모두 읽기 명령이 한 번씩 거부됐지만 첫 시도에 채점을 마쳤다
3. **실행.** `worktree_dir` 에서 `bash "$oneshot/references/oneshot.sh" --mode read --prompt-file "$tmp/prompt.txt" <reviewer> > "$tmp/stdout.txt" 2> "$tmp/stderr.txt"` 를 실행한다. `$oneshot` 은 설치된 recipe 플러그인의 oneshot 스킬 디렉터리다. 여러 버전이 있으면 가장 높은 버전을 쓴다(`ls -d ~/.claude/plugins/cache/*/recipe/*/skills/oneshot | sort -V | tail -1`). 모델과 effort 는 지정하지 않고 CLI 기본값을 쓴다. 종료 코드 0 또는 3(강등 — stdout 에 결과 있음)이면 다음 단계로 간다. stderr 는 codex 세션 로그가 항상 섞이므로 성공 판정에 쓰지 않고, 실패했을 때 원인을 찾는 데만 본다
4. **검증·계산.** `python <이 스킬 디렉터리>/scripts/score.py --rubric <이 스킬 디렉터리>/references/rubric.json --post <post_path> --review "$tmp/stdout.txt" --reviewer <reviewer> --out "$tmp/result.json"` (`python` 이 없으면 `python3`). 스크립트가 채점자 항목(C1~C17, C21, C22)의 누락, 점수 범위, 글 유형별 N/A 허용 여부, 인용이 글에 실제로 있는지를 검사한다. 원문에서 셀 수 있는 C18~C20·C23 은 같은 디렉터리의 `auto_items.py` 로 직접 센 뒤 총점을 계산한다. 총점은 채점자에게 맡기지 않는다. 결과는 `--out` 파일과 stdout 에 같은 JSON 으로 나오고, 실패 사유는 그 JSON 의 `errors` 에 있다
5. **다시 시키기(한 번만).** 3단계 종료 코드가 0·3 이 아니거나 4단계가 종료 코드 1(`ok: false`)이면, `prompt.txt` 끝에 아래 문단을 붙여 3·4단계를 한 번 더 실행한다. 3단계가 실패했으면 `<문제>` 에는 stderr 마지막 몇 줄의 요약을, 4단계가 실패했으면 `errors` 를 한 줄에 하나씩 넣는다. 처음부터 다시 채점하게 하는 것이므로 직전 출력은 붙이지 않는다

   ```text
   직전 출력의 문제(이것을 고쳐 C1~C17, C21, C22 전체를 다시 출력한다):
   - <문제>
   ```
6. **실패로 끝내기.** 두 번째도 실패하면 `score` 는 `{"total": null, "reviewer": <reviewer>, "error": "<요약>"}`, `findings` 는 `{"severity": "P1", "category": "writing", "location": "-", "issue": "<reviewer> 채점 실패: <요약>", "suggestion": "수동 채점", "reviewer": <reviewer>}` 하나로 낸다. 이때는 임시 디렉터리를 지우지 않고 경로를 보고해, 사람이 stdout·stderr 를 볼 수 있게 한다
7. **정리.** 성공했으면 `result.json` 에서 `score` 와 `findings` 를 꺼낸 뒤 임시 디렉터리를 지운다

## 출력
- `score` — `result.json` 의 `score`. `total`(0~100 정수), `pass_line`(합격선, `rubric.json` 의 값), `passed`(`total` 이 합격선 이상인지), `type`, `sections`(절별 환산 가중치와 점수), `items`(항목별 `score`·`evidence`·`location`·`reason`·`fix`), `na`(N/A 항목 id), `not_scored`(원문으로 채점하지 않는 규칙·관점과 사유), `warnings`
- `findings` — `result.json` 의 `findings`. 2점 미만 항목을 `apply-findings` 가 읽는 지적 형식(`severity` 0점→P2·1점→P3, `category: "writing"`)으로 바꾼 배열. 모두 2점이거나 N/A 면 빈 배열
- 사용자에게는 아래 형식으로 보고한다. 2점 미만 항목 표는 점수가 낮은 순서로 쓰고, `warnings` 가 있으면 표 아래에 그대로 옮긴다. `not_scored` 는 매번 반복하지 않는다

  ```markdown
  **총점 <total> / 100** (<reviewer>, type=<type>, N/A <na 개수>개, 합격선 <pass_line> <통과|미달>)

  | 절 | 점수 / 가중치 |
  |---|---|
  | 시작 | 11.2 / 15 |

  | 항목 | 점수 | 위치 | 이유 | 고칠 점 |
  |---|---|---|---|---|
  | C14 공식 문서 이상의 선택·이유·실패 | 0 | 전체 | ... | ... |
  ```
- 합격선 70 은 기존 글 24편을 codex 로 채점한 분포(39~85, 중앙값 55.5)와, 같은 글을 다시 채점했을 때의 차이(4~12점)를 보고 정했다(2026-10-31). 한 번의 채점이 이만큼 흔들리므로 합격선은 경고에만 쓰고 진행을 막지 않는다. 이 값은 채점표 5판(C1~C20) 기준이다. 6판(C21~C23 추가, 시니어 기준선)으로 기존 글을 다시 채점해 분포를 본 뒤 합격선을 다시 정한다. 그 전까지는 70을 그대로 쓴다
