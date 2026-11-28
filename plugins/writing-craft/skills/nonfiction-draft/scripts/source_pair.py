#!/usr/bin/env python3
"""초안 문장마다 가장 가까운 자료 원문을 짝지어, 옮기면서 빠진 한정어와 넓힌 말을 표시한다.

사용: python source_pair.py <초안.md> <자료 폴더나 파일> [...] [--out 보고.md] [--min 0.3] [--max-lines 60]

숫자 대조(num_check)는 값이 맞는지만 본다. 이 도구는 숫자가 맞아도 뜻이 바뀌는 옮김을 찾는다.
  - 빠진 한정어: 짝지은 자료 문장에는 있는데 초안 문장에는 없는 조건·범위·확신 표시
    (괄호 속 조건, '~의 경우', '일부', '약', '[추정]'·'가정'·'확인 못 함', '진행 중', '예:' 등)
  - 넓힌 말: 초안 문장에만 있는 '모두'·'두 종류'·'항상'·'어느 쪽도'·'해당 사항 없음' 같은 전칭·분류어
  - '원문대로'·'그대로'라고 쓴 문장: 이어지는 따옴표 인용이 자료에 글자 그대로 있는지
  - 부재·유일·전체 주장('한 번도', '없다', '기록 없음', '뿐', '~만 있', '유일', 'n개입니다', '모두', '세 가지',
    '대부분', '거의', '어느 쪽도', '아무', '다시 ~지 않', '~지 않고'):
    그 문장(표 행이면 같은 행)의 날짜·도구명·드문 낱말이 함께 나오는 자료 줄을 '모두' 뽑는다.
    가장 가까운 한 줄만 보는 1절은 반대 증거가 다른 줄에 있는 이 주장을 구조상 못 잡는다.
판정은 하지 않는다. 사람(또는 초안을 쓰지 않은 세션)이 짝을 보고 고칠지 정한다.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

TEXT_EXT = {".txt", ".md", ".csv", ".tsv", ".json", ".log", ".yaml", ".yml"}

# 자료 쪽에 있으면 옮길 때 남아야 하는 한정어. (이름, 정규식)
HEDGES = [
    ("괄호 조건", None),  # 따로 처리
    ("~의 경우", re.compile(r"[가-힣A-Za-z]+(?:의|인|일|한)?\s*경우")),
    ("추정·가정 표시", re.compile(r"\[?추정\]?|가정|추론|듯하|듯이|것으로 보|보인다|보임|짐작")),
    ("확인 못 함", re.compile(r"확인\s*(?:못|안|하지\s*못|되지\s*않)|미확인|모름|알 수 없|불명|출처\s*없")),
    ("끝나지 않은 상태", re.compile(r"진행\s*중|보류|미완|대기|시도 중|확인 중")),
    ("실패·대체", re.compile(r"대체|대신|중단|실패|거부|빈 출력")),
    ("예시 표시", re.compile(r"예\s*:|예를 들어|예컨대|가령|예시|\b등\b|등을|등이|등의")),
    ("범위·정도", re.compile(r"일부|약\s|쯤|정도|대부분|대체로|보통|주로|이상|이하|미만|초과|까지|부터|만\s|뿐|최소|최대|안팎")),
    ("조건", re.compile(r"(?:하면|이면|라면|때만|때에만|경우에만|한해|한정|조건)")),
]
WIDEN = re.compile(
    r"모두|모든|전부|항상|언제나|반드시|늘\s|어느 쪽(?:에|도|이든)|어디서나|누구나|"
    r"[두세네]\s*(?:종류|가지|유형)|유일|처음|전혀|해당\s*사항\s*없|원문대로|원문 그대로|그대로 옮"
)
PAREN_HEDGE = re.compile(r"경우|때|만(?![가-힣])|추정|가정|확인|진행|일부|약\s|예[:\s]|제외|포함|기준|한정|이상|이하|까지|부터|대상|조건|뿐")
QUOTE = re.compile(r"[\"“”'‘’「」『』]([^\"“”'‘’「」『』]{6,})[\"“”'‘’「」『』]")
# 부재·유일·전체 주장. 이 문장이 맞으려면 자료 전체에 반대 줄이 없어야 한다.
ABSENT = re.compile(
    r"한\s*번도|전혀|없(?:다|습니다|었|음|는|어)|않(?:았|는다|습니다)|안\s*(?:썼|씀|했)|기록\s*없|"
    r"뿐|(?<=\w)만 ?[있남적]|유일|처음|모두|모든|전부|오직|대부분|거의|어느\s*쪽도|아무(?:도|것도|런|\s)|다시\s*\S+지\s*않|지\s*않고|"
    r"\d+\s*(?:개|건|회|번|곳|편|명)(?:입니다|이다|였|뿐|만|밖에)|[한두세네다섯]\s*(?:가지|종류)"
)
QUANT = re.compile(r"대부분|거의|모두|모든|전부")
ABSENT_CELL = re.compile(r"(?:\(?발췌에\s*)?(?:기록\s*)?(?:없음|없다|없습니다)\.?\)?")
RELDAY = re.compile(r"이날|그날|당일|이 날|그 날|같은 날")
DATE_RX = re.compile(r"(?:(?:19|20)\d{2}[-./]\s*)?(?<!\d)(\d{1,2})\s*(?:[-/]|월\s*)\s*(\d{1,2})(?:일)?(?!\d)")
NAME_RX = re.compile(r"`([^`]{2,40})`|([A-Za-z][A-Za-z0-9_.+-]*[A-Za-z0-9])")
NAME_STOP = {"md", "hq", "the", "and", "or", "of", "to", "in", "is"}
JOSA = re.compile(r"(?:으로는|에서는|으로|에서|에게|까지|부터|처럼|보다|이라|라는|이나|과의|와의|은|는|이|가|을|를|에|의|와|과|도|만|로|나)$")
KO_STOP = {"없다", "없습니다", "없음", "없는", "기록", "번도", "모두", "모든", "전부", "유일", "처음", "가지", "종류",
           "않았", "않았습니다", "않았다", "않고", "대부분", "거의", "어느", "쪽도", "아무도", "아무것도", "다시", "입니다", "있다", "있습니다", "이날", "그날", "당일", "같은", "자료", "발췌", "일지",
           "적힌", "쓰지", "사용하지", "하지", "했습니다", "했다"}


def norm_dates(s: str):
    out = set()
    for m in DATE_RX.finditer(s):
        mo, d = int(m.group(1)), int(m.group(2))
        if 1 <= mo <= 12 and 1 <= d <= 31:
            out.add(f"{mo:02d}-{d:02d}")
    return out


def name_terms(s: str):
    out = set()
    for m in NAME_RX.finditer(s):
        t = (m.group(1) or m.group(2)).strip()
        if t.lower() not in NAME_STOP and not re.fullmatch(r"[\d.,%:-]+", t):
            out.add(t)
    return out


def ko_terms(s: str, *, table_row=False):
    out = set()
    for w in re.findall(r"[가-힣]{2,}", s):
        stem = JOSA.sub("", w)
        if not table_row or len(stem) >= 2:
            w = stem  # 표 머리의 '한도'처럼 조사를 떼면 한 글자가 되는 낱말은 원형을 쓴다.
        if len(w) >= 2 and w not in KO_STOP and not ABSENT.search(w):
            out.add(w)
    return out


def counter_lines(sent, row, prev_date, lines):
    """부재·유일 주장 한 문장에 대해, 자료에서 같은 날짜·이름·드문 낱말이 함께 나오는 줄을 모두 돌려준다.

    lines는 자료의 줄 단위 목록 (파일, 줄, 줄 전체)이다. 한 줄 안의 뒤 문장도 그 줄 앞의 날짜를 따르게 줄로 본다.
    날짜가 없으면 자료 줄의 1/3 넘게 나오는 이름(글의 주제어)은 조건에서 뺀다. 남는 조건이 없으면 None.
    """
    dates = norm_dates(row) or (prev_date if RELDAY.search(sent) else set())
    lows = [f"{f}:{i}:{u}".lower() for f, i, u in lines]
    n = len(lines)
    cap = max(3, n // 6)

    def terms(text):
        nm = set()
        for t in name_terms(text):
            k = sum(t.lower() in h for h in lows)
            if k and (dates or k <= max(3, n // 3)):
                nm.add(t)
        return nm, {w for w in ko_terms(text) if 0 < sum(w in u for _, _, u in lines) <= cap}

    names, rare = terms(sent)
    if not (dates or names or rare) and row.strip() != sent.strip():
        names, rare = terms(row)  # 표의 '기록 없음' 칸처럼 문장에 낱말이 없으면 같은 행에서 가져온다
    absence_cell = row.lstrip().startswith("|") and bool(ABSENT_CELL.fullmatch(sent.strip()))
    if not (dates or names or rare) and (absence_cell or QUANT.search(sent)):
        # 표의 부재 칸은 같은 행에서, 수량 주장은 그 문장에서 자료에 가장 덜 나오는 낱말 하나를 고른다.
        topic = row if absence_cell else sent
        topic_names = name_terms(topic)
        freq = {w: sum(w in u for _, _, u in lines) for w in ko_terms(topic, table_row=absence_cell)}
        freq.update({t: sum(t.lower() in h for h in lows) for t in topic_names})
        freq = {w: k for w, k in freq.items() if k}
        if freq:
            w = min(freq, key=freq.get)
            if w in topic_names:
                names = {w}
            else:
                rare = {w}
    if not (dates or names or rare):
        return None
    need = min(2, len(rare))
    hits = []
    for (f, i, u), low in zip(lines, lows):
        if dates and not (norm_dates(u) & dates):
            continue
        got = sorted(t for t in names if t.lower() in low)
        if names and not got:
            continue
        kr = sorted(w for w in rare if w in u)
        if not dates and not names and len(kr) < need:
            continue
        hits.append((f, i, u, got + kr))
    return dates, names, rare, hits


SENT_SPLIT = re.compile(r"(?<=[다요음함됨임])\.\s+|(?<=[.!?])\s+(?=[가-힣A-Z\"“'‘(])|\n")


def read_sources(paths):
    files = []
    for p in map(Path, paths):
        if p.is_dir():
            files += sorted(f for f in p.rglob("*") if f.is_file() and f.suffix.lower() in TEXT_EXT)
        elif p.is_file():
            files.append(p)
        else:
            sys.exit(f"자료 경로가 없다: {p}")
    units, lines = [], []  # (파일, 줄, 문장), (파일, 줄, 줄 전체)
    cwd = Path.cwd().resolve()
    for f in files:
        # 다른 폴더의 같은 이름 파일이 섞이지 않게 현재 폴더 기준 상대 경로(밖이면 전체 경로)로 적는다
        try:
            label = f.resolve().relative_to(cwd).as_posix()
        except ValueError:
            label = f.resolve().as_posix()
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            print(f"경고: UTF-8이 아닌 글자가 있어 깨진 글자를 대체해 읽음: {label}", file=sys.stderr)
            text = f.read_text(encoding="utf-8", errors="replace")
        for i, line in enumerate(text.splitlines(), 1):
            us = split_units(line)
            for u in us:
                units.append((label, i, u))
            if us:
                lines.append((label, i, line.strip()))
    return units, lines


def split_units(line: str):
    line = line.strip()
    if not line or set(line) <= set("|-: "):
        return []
    parts = [c.strip() for c in line.strip("|").split("|")] if line.startswith("|") else [line]
    out = []
    for p in parts:
        for s in SENT_SPLIT.split(p):
            s = s.strip(" -*#>`")
            if len(re.sub(r"\s", "", s)) >= 8:
                out.append(s)
    return out


def grams(s: str, n: int = 3):
    t = re.sub(r"[\s\W_]+", "", s.lower())
    return {t[i:i + n] for i in range(max(0, len(t) - n + 1))}


def draft_units(text: str, with_row: bool = False):
    """초안 문장 (줄, 문장) 또는 (줄, 문장, 그 줄 전체, 그 줄 앞에서 마지막으로 나온 날짜)."""
    text = re.split(r"\n#+\s*작업 메모", text)[0]
    units, in_code, last = [], False, set()
    for i, line in enumerate(text.splitlines(), 1):
        if line.strip().startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        if line.startswith("#"):
            last = norm_dates(line)
            continue
        us = split_units(line)
        if with_row and line.lstrip().startswith("|"):
            # 표의 짧은 칸('기록 없음', '없음')도 주장이다. 8글자 미만이라 split_units가 버린 칸을 되살린다.
            us += [c.strip() for c in line.strip().strip("|").split("|")
                   if c.strip() and c.strip() not in us and ABSENT.search(c)]
        for u in us:
            units.append((i, u, line, set(last)) if with_row else (i, u))
        last = norm_dates(line) or last
    return units


def paren_conditions(s: str):
    return [m.group(1).strip() for m in re.finditer(r"[(（]([^()（）]{2,40})[)）]", s)]


def missing_hedges(src: str, dr: str):
    miss = []
    for cond in paren_conditions(src):
        if not PAREN_HEDGE.search(cond):
            continue
        words = [w for w in re.findall(r"[가-힣A-Za-z]{2,}", cond)]
        if words and not any(w in dr for w in words):
            miss.append(f"괄호 조건 '({cond})'")
    for name, rx in HEDGES[1:]:
        s_hits = {m.group(0).strip() for m in rx.finditer(src)}
        if s_hits and not rx.search(dr):
            miss.append(f"{name} '{'/'.join(sorted(s_hits))[:30]}'")
    return miss


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("draft")
    ap.add_argument("sources", nargs="+")
    ap.add_argument("--out")
    ap.add_argument("--min", type=float, default=0.3, help="짝으로 볼 최소 겹침(초안 문장 3글자 조각 중 자료 문장에 있는 비율)")
    ap.add_argument("--max-lines", type=int, default=60, help="4절에서 주장 하나에 적을 자료 줄 위치 수 상한")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    src, src_lines = read_sources(a.sources)
    if not src:
        sys.exit("자료 파일을 못 읽었다")
    src_g = [(f, i, u, grams(u)) for f, i, u in src]
    src_all = "\n".join(u for _, _, u in src)
    src_flat = re.sub(r"\s+", "", src_all)

    draft_text = Path(a.draft).read_text(encoding="utf-8")
    absent = []
    for ln, s, row, prev in draft_units(draft_text, with_row=True):
        if not ABSENT.search(s):
            continue
        r = counter_lines(s, row, prev, src_lines)
        if r and r[3]:
            absent.append((ln, s, [m.group(0) for m in ABSENT.finditer(s)], r))

    rows, widen_only, quote_bad = [], [], []
    for ln, s in draft_units(draft_text):
        g = grams(s)
        if len(g) < 6:
            continue
        best = max(src_g, key=lambda x: len(g & x[3]) / len(g))
        score = len(g & best[3]) / len(g)
        widen = sorted({m.group(0).strip() for m in WIDEN.finditer(s)} - {m.group(0).strip() for m in WIDEN.finditer(best[2])})
        for q in QUOTE.findall(s):
            if re.sub(r"\s+", "", q) not in src_flat:
                quote_bad.append((ln, q))
        if score < a.min:
            if widen:
                widen_only.append((ln, s, widen))
            continue
        miss = missing_hedges(best[2], s)
        if miss or widen:
            rows.append((ln, s, f"{best[0]}:{best[1]}", best[2], score, miss, widen))

    out = [f"# 원문 짝 대조 — {Path(a.draft).name}", "",
           "짝은 3글자 조각 겹침으로 고른 후보다. 짝이 틀렸으면 무시한다. 표시된 것마다 '자료 문장의 조건·범위·확신이 초안에 남았는가, 예시를 전체로 바꾸지 않았는가, 상태(진행 중·대체·실패)를 바꾸지 않았는가'를 본다.", ""]
    out.append(f"## 1. 빠진 한정어·넓힌 말 ({len(rows)}건)")
    for ln, s, loc, sv, sc, miss, widen in rows:
        out += ["", f"- 초안 {ln}줄: {s}", f"  - 자료 {loc} (겹침 {sc:.2f}): {sv}"]
        if miss:
            out.append(f"  - 빠진 한정어 후보: {', '.join(miss)}")
        if widen:
            out.append(f"  - 초안에만 있는 넓힌 말: {', '.join(widen)}")
    out += ["", f"## 2. 짝 없는 문장의 넓힌 말 ({len(widen_only)}건)",
            "자료와 겹침이 낮은 문장에 전칭·분류어가 있다. 자료 여러 줄을 묶은 판단이면 그 줄들을 모두 열어 범위를 맞춘다."]
    for ln, s, widen in widen_only:
        out.append(f"- 초안 {ln}줄 [{', '.join(widen)}]: {s}")
    out += ["", f"## 3. 자료에 글자 그대로 없는 인용 ({len(quote_bad)}건)",
            "따옴표 안 문장이 자료에 그대로 없다. '원문'·'그대로'라고 했으면 자료 글자로 바꾸고, 풀어 쓴 것이면 따옴표와 '원문대로'를 뺀다."]
    for ln, q in quote_bad:
        out.append(f"- 초안 {ln}줄: \"{q}\"")
    out += ["", f"## 4. 부재·유일·전체 주장의 반증 후보 줄 ({len(absent)}건)",
            "'한 번도·없다·기록 없음·뿐·~만 있·유일·n개입니다·모두·세 가지·대부분·거의·어느 쪽도·아무·다시 ~지 않·~지 않고' 문장마다, 그 문장(표 행이면 같은 행, '이날'이면 앞에 나온 날짜)의 "
            "날짜·이름·드문 낱말이 함께 나오는 자료 줄을 빠짐없이 모았다. 목록을 끝까지 읽고 한 줄이라도 주장과 어긋나면"
            "(그날 다른 줄에서 썼다, 같은 것이 더 있다, 실패 줄이 있다) 주장을 그 줄들의 범위로 좁히거나 뺀다. "
            "자료가 발췌·일부라면 '발췌에는'처럼 범위를 밝힌다. 증상(빈 출력)과 원인(권한 거부)을 같은 목록으로 세지 않는다. "
            "주장마다 자료 줄 위치만 적고, 줄 원문은 이 절 끝 '4-1'에 한 번씩 모았다."]
    seen: dict[tuple, str] = {}
    for ln, s, keys, (dates, names, rare, hits) in absent:
        cond = []
        if dates:
            cond.append("날짜 " + "·".join(sorted(dates)))
        if names:
            cond.append("이름 " + "·".join(sorted(names)))
        if rare and not dates and not names:
            cond.append("낱말 " + "·".join(sorted(rare)))
        out += ["", f"- 초안 {ln}줄 [{', '.join(dict.fromkeys(k.strip() for k in keys))}]: {s}",
                f"  - 모은 조건: {' / '.join(cond)} → 자료 {len(hits)}줄"]
        refs = []
        for f, i, u, got in hits[:a.max_lines]:
            seen.setdefault((f, i), u)
            refs.append(f"{f}:{i}" + (f"({'·'.join(got)})" if got else ""))
        more = f" … {len(hits) - a.max_lines}줄 더(--max-lines로 늘림)" if len(hits) > a.max_lines else ""
        out.append(f"  - 자료 줄: {', '.join(refs)}{more}")
    if seen:
        out += ["", f"### 4-1. 4절에 나온 자료 줄 원문 ({len(seen)}줄)"]
        for (f, i), u in sorted(seen.items(), key=lambda x: (x[0][0], x[0][1])):
            out.append(f"- {f}:{i}: {u[:600]}")
    report = "\n".join(out) + "\n"
    if a.out:
        Path(a.out).write_text(report, encoding="utf-8")
        print(f"{a.out}: 한정어 {len(rows)} · 넓힌 말 {len(widen_only)} · 인용 {len(quote_bad)} · 부재 주장 {len(absent)}")
    else:
        print(report)


if __name__ == "__main__":
    main()
