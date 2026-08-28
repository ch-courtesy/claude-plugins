# ASCII 그림 문법

정본은 스펙 §7.6 — 이 발췌를 고치면 스펙과 함께 고친다. 승인 화면에 항상 표시한다.

*예제: §7.6의 그림 넷*

CLI에서 보므로 ASCII가 기본이다. 다른 형식은 사용자가 원할 때 그린다.

표기는 구성 요소의 종류를 구분한다. **상자와 머리에 적는 이름은 구성 요소의 `id`다.**

5.2의 예제를 그리면 이렇다.

```
graph.in.repo (text)
    │
    ▼
 [scan]  pattern='*.py'             노드는 [이름], 상수는 옆에
    │ paths (text, list:1)          포트 이름과 shape·깊이
    ▼
╭─ review ── items ─────────────╮   컨테이너는 테두리, 반복 규칙을 머리에 —
│  path × focus='security'      │   split이 둘 이상이면 items·zip / items·product /
│  → review-file                │   items·nested처럼 combine을 함께 적는다(5.7)
╰───────────────────────────────╯   전개 대상 × 공유 상수(='값'이 상수 표식), → 감싼 스킬
    │ findings (json, list:2)  → pick.in.per_file
    │ messages (text, list:2) ≈ findings  → pick.in.per_msg
    ▼
 < pick >                           transform은 <이름>
   expr messages =                  출력 포트마다 식을 적는다
     zip(per_msg.flatten(), per_file.flatten())
       .filter(p, p.b.severity=='high')
       .map(p, p.a)
    │ messages (text, list:1)
    ▼
 < draft >
   expr spec = messages.join('\n')
    │ spec (text)
    ▼
╭─ fix ── condition ────────────╮   조건 컨테이너
│  until verdict=='clean'       │
│  max 5   carry draft→draft    │
│  draft=''                     │
│  → fix-draft                  │
╰───────────────────────────────╯
    │ draft (text)  → publish.in.body
    ▼
 [publish] ─ report (text) ═► graph.out.report    경계 출력은 ═►, 내는 포트와 shape를 적는다
    ╎
    ╎ order                         order 엣지는 점선
    ▼
 [cleanup]  root='.'
```

**`aligned` 짝은 포트 줄에 `≈ 상대이름`으로 적는다.**

**`transform`의 `expr`는 상자 안에 원문으로 적는다.**

**다중 출력 `transform`**은 상자에서 나가는 선을 출력 포트마다 그리고 포트 이름을 적는다.

```
 < route >
   sec:  items.filter(i, i.kind == 'security')
   perf: items.filter(i, i.kind == 'perf')
   rest: items.filter(i, i.kind != 'security' && i.kind != 'perf')
    ├─ sec  (json, list:1) ─► [fix-security]
    ├─ perf (json, list:1) ─► [fix-perf]
    └─ rest (json, list:1) ─► [report]
```

**order 엣지는 상자 종류와 무관하게 아래 변 가운데에서 나가 다음 상자의 위 변 가운데로 들어간다.** 데이터 화살표는 `▼`이고 order는 `╎`이며, **order 선에는 포트 이름을 적지 않는다.**

**워크플로를 노드로 쓴 상자는 `[[이름]]`으로 그리고 컨테이너 깊이를 옆에 적는다.** 깊이는 1 이상일 때만 적고 0이면 생략하며, 세는 규칙은 7.5의 컨테이너 깊이 규칙과 같다.

```
 [[audit-repo]]  깊이 2
```

**팬아웃**은 분기선으로 그리고, 도착 포트가 갈리면 각 가지에 도착 포트를 적는다.

```
 [scan]
    │ paths (text, list:1)
    ├──────────────────────┐
    ▼ → lint.in.path       ▼ → pick.in.paths
╭─ lint ── items ──╮
│  path            │
│  → lint-file     │
╰──────────────────╯
    │ verdict (text, list:1)
    │ → pick.in.verdicts
    ▼
 < pick >
   kept: zip(paths, verdicts).filter(p, p.b == 'clean').map(p, p.a)
```

**멀리 떨어진 소비처는 선을 늘이지 않고 각주로 적는다** — 보내는 쪽 포트 줄에 `→ 노드.in.포트`를, 받는 쪽 상자 옆에 `(from 노드.out.포트)`를 적는다.

팬인은 화살표 여럿이 한 포트로 모이는 것으로 그리고 선언 순서를 번호로 표시한다. **도착 포트가 갈리는 팬아웃과 팬인이 한 화살표에서 만나면 둘 다 적는다** — `→ publish.in.findings 2` 형태다.
