"""원문만 세면 되는 항목(렌더링 C18~C20, 소제목 형식 C23)을 채점자 대신 계산한다.

LLM 에게 줄 길이나 태그 개수를 세게 하면 실행마다 결과가 흔들리고 인용이 길어진다.
score.py 가 불러 쓰고, 단독으로 실행하면 글 하나의 결과를 출력한다.

사용: python auto_items.py <글.md>
"""
import json
import re
import sys

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})\s*([^\s`]*)")
TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")
LINK_TARGET = re.compile(r"\]\([^)]*\)")
IMAGE = re.compile(r"!\[([^\]]*)\]\(([^)\s]*)[^)]*\)")
HTML_IMG = re.compile(r"<img\b[^>]*>", re.I)
HTML_ALT = re.compile(r"\balt\s*=\s*(\"[^\"]*\"|'[^']*')", re.I)
AUTOLINK = re.compile(r"<([A-Za-z][A-Za-z0-9+.-]{1,31}):[^\s<>]*>")
KNOWN_SCHEMES = {"http", "https", "mailto", "ftp", "file", "tel", "ssh", "git", "vscode"}
MEANINGLESS_ALT = {"", "image", "img", "picture", "photo", "screenshot", "스크린샷", "이미지", "사진", "그림", "캡처"}
IMAGE_EXT = re.compile(r"\.(png|jpe?g|gif|webp|svg|bmp)$", re.I)
MARKUP = re.compile(r"[`*\[\]<>]")  # 화면에 보이지 않는 마크다운 기호
HEADING = re.compile(r"^ {0,3}#{1,6}(\s|$)")
SUBHEADING = re.compile(r"^ {0,3}(#{2,6})\s+(.*?)\s*#*\s*$")  # 글 제목(#)을 뺀 소제목
# 질문형: 물음표, 또는 '~나/~까/~는가/~는지'로 끝남. 문장형: 서술 어미로 끝남.
QUESTION_END = re.compile(r"(\?|[^하]나|까|[는은인던]가|[을는]지)$")
SENTENCE_END = re.compile(r"(니다|[었았였했봤됐갔왔]다|[한된]다|이다|있다|없다|[^개필중주수]요)$")
BLOCK_START = re.compile(r"^ {0,3}(#{1,6}(\s|$)|[-*+]\s|\d{1,9}[.)]\s|>)")  # 앞 문단을 끝내고 새 블록을 여는 줄

LONG_TOKEN = 45  # 모바일 한 줄에 영문 40자 정도가 들어간다. 경계에 걸리는 API 이름까지 잡지 않도록 여유를 둔다
LONG_CODE_LINE = 100
MAX_LISTED = 8


def split_front_matter(text):
    lines = text.splitlines()
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return i + 1, lines
    return 0, lines


def scan(text):
    """코드 블록과 본문 줄을 나눈다. 반환: (blocks, prose, unclosed)"""
    start, lines = split_front_matter(text)
    blocks, prose = [], []
    fence = None
    for no in range(start, len(lines)):
        line = lines[no]
        m = FENCE.match(line)
        if fence is None:
            if m:
                fence = {"mark": m.group(1), "lang": m.group(2), "line": no + 1, "body": []}
            else:
                prose.append((no + 1, line))
        elif m and m.group(1)[0] == fence["mark"][0] and len(m.group(1)) >= len(fence["mark"]) and not m.group(2):
            blocks.append(fence)
            fence = None
        else:
            fence["body"].append((no + 1, line))
    return blocks, prose, fence


def unmatched_backtick(line):
    """CommonMark 코드 스팬 규칙으로 짝이 없는 백틱 런의 위치를 찾는다. 없으면 None"""
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c == "\\" and i + 1 < n and line[i + 1] == "`":
            i += 2  # 코드 스팬 밖의 \` 는 글자 그대로의 백틱이다
            continue
        if c != "`":
            i += 1
            continue
        j = i
        while j < n and line[j] == "`":
            j += 1
        run = j - i
        # 같은 길이의 런을 찾는다. 코드 스팬 안에서는 백슬래시가 이스케이프하지 않는다
        k = j
        closed = None
        while k < n:
            if line[k] == "`":
                e = k
                while e < n and line[e] == "`":
                    e += 1
                if e - k == run:
                    closed = e
                    break
                k = e
            else:
                k += 1
        if closed is None:
            return i
        i = closed
    return None


def cells(line):
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    return [c.strip() for c in re.split(r"(?<!\\)\|", s)]


def check(text):
    blocks, prose, unclosed = scan(text)
    overflow, broken = [], []

    # 표: 머리글 다음 줄이 구분선인 연속된 | 줄 묶음
    table_lines = set()
    i = 0
    while i < len(prose) - 1:
        no, line = prose[i]
        if "|" in line and TABLE_SEP.match(prose[i + 1][1]) and prose[i + 1][0] == no + 1:
            ncol = len(cells(line))
            rows = [(no, line)]
            j = i + 2
            while j < len(prose) and prose[j][0] == prose[j - 1][0] + 1 and "|" in prose[j][1]:
                rows.append(prose[j])
                j += 1
            table_lines.update(rno for rno, _ in rows)
            table_lines.add(prose[i + 1][0])
            long_cell = next((c for _, r in rows for c in cells(r) if max(map(len, c.split()), default=0) >= LONG_TOKEN), None)
            if ncol >= 5:
                overflow.append((no, line.strip(), f"열이 {ncol}개인 표"))
            elif long_cell:
                overflow.append((no, long_cell, "표 칸에 공백 없는 긴 문자열"))
            bad = next(((rno, r) for rno, r in rows[1:] if len(cells(r)) != ncol), None)
            if bad:
                broken.append((bad[0], bad[1].strip(), f"표 행의 열 개수가 머리글({ncol}개)과 다르다"))
            i = j
            continue
        i += 1

    # 코드 스팬은 문단 안에서 줄을 넘을 수 있어서, 백틱 짝은 문단 단위로 본다
    paragraph = []

    def flush():
        if not paragraph:
            return
        joined = "\n".join(l for _, l in paragraph)
        pos = unmatched_backtick(joined)
        if pos is not None:
            no, line = paragraph[joined.count("\n", 0, pos)]
            col = pos - (joined.rfind("\n", 0, pos) + 1)
            broken.append((no, line[max(0, col - 20) : col + 20].strip(), "짝이 맞지 않는 백틱"))
        paragraph.clear()

    for no, line in prose:
        if no in table_lines or not line.strip():
            flush()
            continue
        if paragraph and (no != paragraph[-1][0] + 1 or BLOCK_START.match(line) or HEADING.match(paragraph[-1][1])):
            flush()
        paragraph.append((no, line))
        # 링크 주소는 화면에 보이지 않으므로 빼고, 남은 마크다운 기호도 빼고 잰다
        visible = MARKUP.sub("", LINK_TARGET.sub("] ", line))
        token = max(visible.split(), key=len, default="")
        if len(token) >= LONG_TOKEN:
            overflow.append((no, token, f"공백 없는 {len(token)}자 문자열"))
        stripped = re.sub(r"`[^`]*`", "", line)
        for m in AUTOLINK.finditer(stripped):
            if m.group(1).lower() not in KNOWN_SCHEMES:
                broken.append((no, m.group(0), f"'{m.group(1)}:' 를 스킴으로 읽는 자동 링크"))
    flush()

    # 코드 블록은 블록 안에서만 가로 스크롤되고 로그처럼 줄일 수 없는 줄도 많다.
    # 페이지 전체가 밀리는 본문 넘침보다 가벼우므로, 블록이 몇 개든 합쳐서 하나로 센다
    wide = []
    for b in blocks:
        long_lines = [(no, l) for no, l in b["body"] if len(l) > LONG_CODE_LINE]
        if long_lines:
            wide.append(max(long_lines, key=lambda x: len(x[1])))
    if wide:
        no, l = max(wide, key=lambda x: len(x[1]))
        where = ", ".join(f"{n}행" for n, _ in wide[:MAX_LISTED])
        overflow.append((no, l.strip()[:120], f"{LONG_CODE_LINE}자 넘는 줄이 있는 코드 블록 {len(wide)}개({where})"))
    if unclosed:
        broken.append((unclosed["line"], unclosed["mark"] + unclosed["lang"], "닫히지 않은 코드 펜스"))

    count = len(overflow) + 2 * len(broken)
    found = sorted(broken + overflow)
    c18 = item("C18", 2 if count == 0 else 1 if count <= 2 else 0, found,
               ok_reason="넓은 표, 공백 없는 긴 문자열, 100자 넘는 코드 줄, 마크다운 깨짐이 없다",
               head=f"넘침 {len(overflow)}개 + 깨짐 {len(broken)}개×2 = {count}",
               fix="긴 문자열은 링크 텍스트로 감싸거나 나누고, 긴 코드 줄은 줄바꿈하고, 깨진 마크다운은 고친다")

    untagged = [(b["line"], b["mark"], "언어 태그 없음") for b in blocks if not b["lang"]]
    if not blocks:
        c19 = na("C19", "코드 블록이 없다")
    else:
        m, n = len(untagged), len(blocks)
        c19 = item("C19", 2 if m == 0 else 1 if m <= 2 or m * 2 <= n else 0, untagged,
                   ok_reason=f"코드 블록 {n}개에 모두 언어 태그가 있다", head=f"코드 블록 {n}개 중 {m}개에 태그 없음",
                   fix="출력이나 일반 텍스트 블록에는 text 를, 코드에는 언어 이름을 단다")

    images = []
    for no, line in prose:
        for m in IMAGE.finditer(line):
            images.append((no, m.group(0)[:80], m.group(1)))
        for m in HTML_IMG.finditer(line):
            alt = HTML_ALT.search(m.group(0))
            images.append((no, m.group(0)[:80], alt.group(1)[1:-1] if alt else ""))
    if not images:
        c20 = na("C20", "이미지가 없다")
    else:
        bad = [(no, snip, f"alt '{alt}'") for no, snip, alt in images
               if alt.strip().lower() in MEANINGLESS_ALT or IMAGE_EXT.search(alt.strip()) or re.fullmatch(r"image\s*\d*", alt.strip(), re.I)]
        m, n = len(bad), len(images)
        c20 = item("C20", 2 if m == 0 else 1 if m * 2 <= n else 0, bad,
                   ok_reason=f"이미지 {n}개에 모두 내용을 설명하는 alt 가 있다", head=f"이미지 {n}개 중 {m}개의 alt 가 비었거나 의미 없음",
                   fix="이미지가 보여 주는 내용을 alt 에 한 문장으로 적는다")
    heads = []
    for no, line in prose:
        m = SUBHEADING.match(line)
        if m:
            text = re.sub(r"[*_`]", "", m.group(2)).strip().rstrip(".!")
            heads.append((no, text))
    if not heads:
        c23 = na("C23", "소제목이 없다")
    else:
        bad = [(no, t, "질문형 소제목" if QUESTION_END.search(t) else "문장형 소제목")
               for no, t in heads if QUESTION_END.search(t) or SENTENCE_END.search(t)]
        m = len(bad)
        c23 = item("C23", 2 if m == 0 else 1 if m == 1 else 0, bad,
                   ok_reason=f"소제목 {len(heads)}개가 모두 명사형이다", head=f"소제목 {len(heads)}개 중 {m}개가 질문형·문장형",
                   fix="'~는 왜 안 되나' → '~가 안 되는 이유', '~가 아니었다' → '~와 무관한 원인'처럼 명사형으로 바꾼다")
    return [c18, c19, c20, c23]


def item(cid, score, found, ok_reason, head, fix):
    if score == 2:
        return {"id": cid, "score": 2, "evidence": "", "location": "-", "reason": ok_reason, "fix": "", "auto": True}
    listed = "; ".join(f"{no}행 {what}" for no, _, what in found[:MAX_LISTED])
    more = f" 외 {len(found) - MAX_LISTED}개" if len(found) > MAX_LISTED else ""
    first = found[0]
    return {"id": cid, "score": score, "evidence": first[1], "location": f"{first[0]}행",
            "reason": f"{head}: {listed}{more}", "fix": fix, "auto": True}


def na(cid, reason):
    return {"id": cid, "score": None, "evidence": "", "location": "-", "reason": reason, "fix": "", "auto": True}


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    with open(sys.argv[1], encoding="utf-8-sig") as f:
        print(json.dumps(check(f.read()), ensure_ascii=False, indent=2))
