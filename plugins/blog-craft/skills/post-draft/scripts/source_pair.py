#!/usr/bin/env python3
"""초안 문장마다 가장 가까운 자료 원문을 짝지어, 옮기면서 빠진 한정어와 넓힌 말을 표시한다.

사용: python source_pair.py <초안.md> <자료 폴더나 파일> [...] [--out 보고.md] [--min 0.3]

숫자 대조(num_check)는 값이 맞는지만 본다. 이 도구는 숫자가 맞아도 뜻이 바뀌는 옮김을 찾는다.
  - 빠진 한정어: 짝지은 자료 문장에는 있는데 초안 문장에는 없는 조건·범위·확신 표시
    (괄호 속 조건, '~의 경우', '일부', '약', '[추정]'·'가정'·'확인 못 함', '진행 중', '예:' 등)
  - 넓힌 말: 초안 문장에만 있는 '모두'·'두 종류'·'항상'·'어느 쪽도'·'해당 사항 없음' 같은 전칭·분류어
  - '원문대로'·'그대로'라고 쓴 문장: 이어지는 따옴표 인용이 자료에 글자 그대로 있는지
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
SENT_SPLIT = re.compile(r"(?<=[다요음함됨임])\.\s+|(?<=[.!?])\s+(?=[가-힣A-Z\"“'‘(])|\n")


def read_sources(paths):
    files = []
    for p in map(Path, paths):
        if p.is_dir():
            files += sorted(f for f in p.rglob("*") if f.is_file() and f.suffix.lower() in TEXT_EXT)
        elif p.is_file():
            files.append(p)
    units = []  # (파일, 줄, 문장)
    for f in files:
        for i, line in enumerate(f.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            for u in split_units(line):
                units.append((f.name, i, u))
    return units


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


def draft_units(text: str):
    text = re.split(r"\n#+\s*작업 메모", text)[0]
    units, in_code = [], False
    for i, line in enumerate(text.splitlines(), 1):
        if line.strip().startswith("```"):
            in_code = not in_code
            continue
        if in_code or line.startswith("#"):
            continue
        for u in split_units(line):
            units.append((i, u))
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
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    src = read_sources(a.sources)
    if not src:
        sys.exit("자료 파일을 못 읽었다")
    src_g = [(f, i, u, grams(u)) for f, i, u in src]
    src_all = "\n".join(u for _, _, u in src)
    src_flat = re.sub(r"\s+", "", src_all)

    rows, widen_only, quote_bad = [], [], []
    for ln, s in draft_units(Path(a.draft).read_text(encoding="utf-8")):
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
    report = "\n".join(out) + "\n"
    if a.out:
        Path(a.out).write_text(report, encoding="utf-8")
        print(f"{a.out}: 한정어 {len(rows)} · 넓힌 말 {len(widen_only)} · 인용 {len(quote_bad)}")
    else:
        print(report)


if __name__ == "__main__":
    main()
