#!/usr/bin/env python3
"""초안의 숫자·날짜를 자료와 기계로 맞대 보고, 자료의 '글에 쓰지 않음' 메모를 걸러 낸다.

사용: python num_check.py <초안.md> <자료 폴더나 파일> [...] [--out 보고.md]

보고에 나오는 것:
  1. 형식 — 첫 줄이 '# 제목'인지
  2. 숫자 대조 — 본문의 숫자·날짜마다 자료에서 같은 값이 나온 위치(파일:줄).
     자료에 없는 값은 (가) 같은 문장의 다른 숫자로 사칙·비율을 계산한 후보,
     (나) 자료 전체 숫자 두 개로 계산해 맞는 후보, (다) 값이 가까운 자료 숫자를 붙인다.
     자료에 없고 후보도 없으면 '근거 없음'이다. 후보가 있어도 맞는 계산인지는 사람이 본다.
  3. 제외 메모 — 자료에서 '글에는 쓰지 않음'·'내부용' 표시가 붙은 줄과,
     그 줄과 낱말이 많이 겹치는 본문 줄.
판정은 하지 않는다. 고칠 후보를 보여 주는 표시기다.
"""
from __future__ import annotations

import argparse
import itertools
import re
import sys
from pathlib import Path

TEXT_EXT = {".txt", ".md", ".csv", ".tsv", ".json", ".log", ".yaml", ".yml"}
EXCLUDE_MARK = re.compile(r"글에는?\s*(쓰지|안\s*씀|안\s*썼|넣지|옮기지)|내부용|글에\s*쓰지\s*않|독자용\s*아님")
# 부호는 숫자 바로 앞에 붙고 그 앞이 숫자·글자가 아닐 때만 음수로 본다('3-5'·'W-7'은 범위·이름)
NUM = re.compile(r"(?<![0-9A-Za-z_.])([-−]?)(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d+))?(\s*%)?(?![0-9A-Za-z_])")
DATE_KO = re.compile(r"(?:(\d{4})년\s*)?(\d{1,2})월\s*(\d{1,2})일")
DATE_ISO = re.compile(r"(?<![\d-])(?:(\d{4})-(\d{1,2})-(\d{1,2})|()(\d{2})-(\d{2}))(?![\d-])")
WORD = re.compile(r"[가-힣A-Za-z]{2,}")
STOP = set("그리고 그래서 하지만 있습니다 합니다 했습니다 없습니다 입니다 이다 있다 했다 것을 것이 것은 수 있는 없는 때문에 경우 이번 그때 다시 모두 같은 다른".split())


def read_sources(paths):
    files = []
    for p in map(Path, paths):
        if p.is_dir():
            files += sorted(f for f in p.rglob("*") if f.is_file() and f.suffix.lower() in TEXT_EXT)
        elif p.is_file():
            files.append(p)
        else:
            sys.exit(f"자료 경로가 없다: {p}")
    out = []
    for f in files:
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            print(f"경고: UTF-8이 아닌 글자가 있어 깨진 글자를 대체해 읽음: {f}", file=sys.stderr)
            text = f.read_text(encoding="utf-8", errors="replace")
        for i, line in enumerate(text.splitlines(), 1):
            out.append((f, i, line))
    return out


def norm_num(sign, intpart, frac):
    v = intpart.replace(",", "")
    v = v.lstrip("0") or "0"
    if frac and frac.strip("0"):
        v += "." + frac.rstrip("0")
    if sign and v != "0":
        v = "-" + v
    return v


def dates_in(line):
    """((연도 또는 None, 월, 일), 위치, 원문) 목록. 연도는 적혀 있을 때만 넣는다."""
    found = []
    for m in DATE_KO.finditer(line):
        y = int(m.group(1)) if m.group(1) else None
        found.append(((y, int(m.group(2)), int(m.group(3))), m.span(), m.group(0)))
    for m in DATE_ISO.finditer(line):
        g = m.groups()
        y, mo, d = (int(g[0]), int(g[1]), int(g[2])) if g[0] else (None, int(g[4]), int(g[5]))
        if 1 <= mo <= 12 and 1 <= d <= 31:
            found.append(((y, mo, d), m.span(), m.group(0)))
    return found


def nums_in(line, skip_spans=()):
    res = []
    for m in NUM.finditer(line):
        if any(a <= m.start() < b for a, b in skip_spans):
            continue
        res.append((norm_num(m.group(1), m.group(2), m.group(3)), bool(m.group(4)), m.group(0).strip()))
    return res


def fnum(s):
    return float(s)


def fmt(x):
    if abs(x - round(x)) < 1e-9:
        return str(int(round(x)))
    return f"{x:.2f}".rstrip("0").rstrip(".")


def ops(a, b):
    """두 값으로 만들 수 있는 흔한 계산과 그 이름."""
    out = [(a + b, f"{fmt(a)}+{fmt(b)}"), (a - b, f"{fmt(a)}−{fmt(b)}")]
    if b:
        out += [(a / b * 100, f"{fmt(a)}/{fmt(b)}×100"), (a / b, f"{fmt(a)}/{fmt(b)}")]
        out += [((a - b) / b * 100, f"({fmt(a)}−{fmt(b)})/{fmt(b)}×100")]
    if a:
        out += [((a - b) / a * 100, f"({fmt(a)}−{fmt(b)})/{fmt(a)}×100")]
    return out


def matches(target, value, decimals):
    tol = 0.5 * 10 ** (-decimals) + 1e-9
    return abs(value - target) <= tol


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("draft")
    ap.add_argument("materials", nargs="+")
    ap.add_argument("--out")
    ap.add_argument("--min", type=float, default=10, help="이보다 작은 정수(%%·소수 아님)는 건너뜀(기본 10)")
    a = ap.parse_args()

    draft_lines = Path(a.draft).read_text(encoding="utf-8").splitlines()
    src = read_sources(a.materials)
    if not src:
        sys.exit("자료 파일을 못 찾음")
    root = Path.cwd()

    def loc(f, i):
        try:
            return f"{f.resolve().relative_to(root.resolve())}:{i}"
        except ValueError:
            return f"{f.name}:{i}"

    # 자료 색인
    mat_num = {}
    mat_date = {}
    for f, i, line in src:
        ds = dates_in(line)
        for (y, mo, d), _, _ in ds:
            mat_date.setdefault((mo, d), []).append((y, loc(f, i)))
        for v, _, _ in nums_in(line, [s for _, s, _ in ds]):
            mat_num.setdefault(v, []).append(loc(f, i))
    mat_vals = sorted({fnum(v) for v in mat_num if len(v) < 16})
    first_loc = {}
    for v, locs in mat_num.items():
        first_loc.setdefault(fnum(v), locs[0])

    draft_vals = sorted({fnum(v) for l in draft_lines for v, pct, _ in nums_in(l)
                         if v in mat_num and (pct or "." in v or abs(fnum(v)) >= a.min)})

    rep = ["# 숫자·사실 대조 보고 (num_check)", ""]
    # 1. 형식
    first = next((l for l in draft_lines if l.strip()), "")
    rep += ["## 1. 형식", "- 첫 줄 '# 제목': " + ("통과" if first.startswith("# ") else f"**실패** — 첫 줄이 `{first[:60]}`"), ""]

    # 2. 숫자
    rep += ["## 2. 숫자·날짜 대조", "| 줄 | 본문 값 | 자료 위치 | 판정·후보 |", "|---|---|---|---|"]
    n_ok = n_bad = 0
    seen = set()
    for ln, line in enumerate(draft_lines, 1):
        ds = dates_in(line)
        for (y, mo, d), _, raw in ds:
            if (raw, ln) in seen:
                continue
            seen.add((raw, ln))
            hits = mat_date.get((mo, d), [])
            same = [l for hy, l in hits if y is None or hy == y]
            no_year = [l for hy, l in hits if hy is None]
            other_years = sorted({hy for hy, _ in hits if hy is not None and hy != y})
            if same:
                n_ok += 1
                rep.append(f"| {ln} | {raw} | {', '.join(same[:2])} | 일치 |")
            elif no_year:
                n_ok += 1
                rep.append(f"| {ln} | {raw} | {', '.join(no_year[:2])} | 월·일 일치(자료에 연도 없음 — 연도는 직접 본다) |")
            elif other_years:
                n_bad += 1
                rep.append(f"| {ln} | {raw} | {', '.join(l for _, l in hits[:2])} | **연도 다름** — 자료는 {', '.join(map(str, other_years))}년 |")
            else:
                n_bad += 1
                rep.append(f"| {ln} | {raw} | — | **자료에 없는 날짜** |")
        line_nums = nums_in(line, [s for _, s, _ in ds])
        for v, pct, raw in line_nums:
            x = fnum(v)
            if not pct and "." not in v and abs(x) < a.min:
                continue
            if (raw, ln) in seen:
                continue
            seen.add((raw, ln))
            hit = mat_num.get(v)
            if hit:
                n_ok += 1
                rep.append(f"| {ln} | {raw} | {', '.join(hit[:2])} | 일치 |")
                continue
            dec = len(v.split(".")[1]) if "." in v else 0
            cands = []
            # (가) 같은 문장의 다른 숫자로
            others = [fnum(o) for o, _, _ in line_nums if o != v and o in mat_num]
            for p, q in itertools.permutations(others, 2):
                for val, name in ops(p, q):
                    if matches(x, val, dec):
                        cands.append(f"같은 줄 계산 {name}={fmt(val)}")
            # (나) 본문 다른 곳에 쓴(자료에 있는) 숫자 두 개로
            if not cands:
                found = []
                for p, q in itertools.permutations(draft_vals, 2):
                    for val, name in ops(p, q):
                        if matches(x, val, dec):
                            found.append(name)
                            break
                    if len(found) >= 3:
                        break
                cands += [f"본문 두 값 계산 {n}" for n in found]
            # 같은 줄 숫자로 '맞는 계산'을 보여 준다(옮김 오류 확인용)
            same_line = []
            for p, q in itertools.permutations(others, 2):
                for val, name in ops(p, q)[:2]:
                    same_line.append(f"{name}={fmt(val)}")
            # (다) 가까운 자료 값
            near = [m for m in mat_vals if m and abs(m - x) / max(abs(x), 1) <= 0.03 and m != x]
            near = sorted(near, key=lambda m: abs(m - x))[:3]
            note = "; ".join(cands) if cands else "**근거 없음**"
            if near:
                note += "; 가까운 자료 값 " + ", ".join(f"{fmt(m)}({first_loc[m]})" for m in near)
            if not cands and same_line:
                note += "; 같은 줄 숫자 계산값 " + ", ".join(same_line[:4])
            n_bad += 0 if cands else 1
            rep.append(f"| {ln} | {raw} | — | {note} |")
    rep += ["", f"- 일치 {n_ok}개, 근거 없음 {n_bad}개. 계산 후보가 붙은 값은 계산식이 글의 뜻과 맞는지 직접 본다.", ""]

    # 3. 제외 메모
    rep += ["## 3. 자료의 '글에 쓰지 않음' 메모", ""]
    excl = [(f, i, l) for f, i, l in src if EXCLUDE_MARK.search(l)]
    if not excl:
        rep.append("- 없음")
    for f, i, l in excl:
        rep.append(f"- `{loc(f, i)}` {l.strip()[:200]}")
        words = {w for w in WORD.findall(EXCLUDE_MARK.sub("", l)) if w not in STOP}
        for ln, dl in enumerate(draft_lines, 1):
            dw = {w for w in WORD.findall(dl) if w not in STOP}
            common = words & dw
            if words and len(common) >= 3 and len(common) / len(words) >= 0.25:
                rep.append(f"  - **본문 {ln}줄과 겹침**({', '.join(sorted(common)[:6])}): `{dl.strip()[:100]}`")
    rep.append("")

    text = "\n".join(rep)
    if a.out:
        Path(a.out).write_text(text, encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
