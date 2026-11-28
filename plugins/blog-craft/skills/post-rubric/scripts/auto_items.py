"""원문 자동 항목(렌더링 C18~C20, 소제목 C23, 문체 C24·C25)을 채점자 대신 계산한다.

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
# 참조형 이미지: ![alt][ref], ![alt][] (ref = alt), ![alt] (단축형). 참조 정의가 있어야 이미지로 렌더된다
REF_IMAGE = re.compile(r"!\[([^\]]*)\](?:\[([^\]]*)\])?(?![\[(])")
REF_DEF = re.compile(r"^ {0,3}\[([^\]]+)\]:\s*\S+")
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


# 출처 번호는 post-draft/references/sources.md. 기준값은 품질 공정을 거친 공개 글 15편으로 보정(2026-11-16).
# TL04('로부터')·TL12('-적')·TL13('~것이다')·TL15('~ 중 하나')·AI15(방향어)·AI17('할 수 있습니다'):
# 공개 글에서 적중의 과반이 오탐(고치면 뜻이 바뀜)이라 자동 항목에서 뺐다. post-draft 지침에는 남겨 사람이 판단한다.
# AI09·10·11·14·18은 요청대로 C24에서 제외. M1~M7은 이 항목의 범위 밖이다.
# threshold=None: 매 적중을 후보로, 숫자: 해당 밀도를 초과한 패턴을 후보 하나로 센다.
STYLE_PATTERNS = (
    # TL01 [S37][S40]
    {"id": "TL01", "re": re.compile('에\\s?의(해|하여|한)\\s'), "threshold": None, "ex": '김 대리에 의해 작성됐습니다 → 김 대리가 작성했습니다'},
    # TL02 [S40]
    {"id": "TL02", "re": re.compile('(작업|처리|사용|분석|개발|운영|설계|구현|검토)에\\s?있어(서)?\\s'), "threshold": None, "ex": '엑셀 작업에 있어 중요한 것 → 엑셀로 작업할 때 중요한 것'},
    # TL03 [S40]
    {"id": "TL03", "re": re.compile('(시간|회의|간담회|모임|자리|기회|관심|의미|경험|대화)(을|를)\\s?(가지|갖|가졌)'), "threshold": None, "ex": '회의를 가졌습니다 → 회의했습니다'},
    # TL05 [S40]
    {"id": "TL05", "re": re.compile('(을|를)\\s?통(해|하여|한)'), "threshold": 1.0, "ex": '이 글을 통해 알아봅니다 → (삭제)'},
    # TL06 [S39][S40]
    {"id": "TL06", "re": re.compile('에\\s?(대한|대해(서)?|대하여|관한|관해(서)?|관하여)'), "threshold": 2.0, "ex": '범위에 대해서는 → 범위는'},
    # TL07 [S40]
    {"id": "TL07", "re": re.compile('(하는|되는)\\s?중(이다|입니다|에\\s?있)'), "threshold": None, "ex": '검토하는 중입니다 → 검토하고 있습니다'},
    # TL08 [S44]
    {"id": "TL08", "re": re.compile('(보여|잊혀|불려|쓰여|나뉘어|닫혀|열려|읽혀|되어)지(다|고|는|며|면|게|었|ㄴ|ㄹ|어|습)'), "threshold": None, "ex": '되어집니다 → 됩니다, 보여집니다 → 보입니다'},
    # TL09 조사 초안(출처 미확인/우리 기준)
    {"id": "TL09", "re": re.compile('에도\\s?불구하고'), "threshold": None, "ex": '→ ~지만, ~는데도'},
    # TL10 조사 초안(출처 미확인/우리 기준)
    {"id": "TL10", "re": re.compile('(으)?로\\s?인(해|하여|한)'), "threshold": 0.5, "ex": '오류로 인해 → 오류 때문에 / 오류로'},
    # TL11 [S40]
    {"id": "TL11", "re": re.compile('그녀'), "threshold": None, "ex": '그녀 → 이름·직책'},
    # TL14 [S39]
    {"id": "TL14", "re": re.compile('(모든|여러|각|많은|다양한)\\s[가-힣]+들(은|는|이|가|을|를|의|에)'), "threshold": None, "ex": '모든 파일들을 → 모든 파일을'},
    # TL16 조사 초안(출처 미확인/우리 기준)
    {"id": "TL16", "re": re.compile('(할|될)\\s?수\\s?있(을|는)\\s?것(으로|이다|입니다|\\s?같)'), "threshold": None, "ex": '해결될 수 있을 것입니다 → 해결됩니다 / 해결될 수 있습니다'},
    # TL17 [S39]
    {"id": "TL17", "re": re.compile('것\\s?같(다|습니다|아요)'), "threshold": 0.5, "ex": '문제인 것 같습니다 → 문제입니다(확실한 경우)'},
    # TL18 조사 초안(출처 미확인/우리 기준)
    {"id": "TL18", "re": re.compile('(을|를)\\s?진행(하|했|합|한|해)'), "threshold": None, "ex": '설치를 진행합니다 → 설치합니다'},
    # TL19 조사 초안(출처 미확인/우리 기준)
    {"id": "TL19", "re": re.compile('(소개|입력|연결|향상|감소|증가|발생|작동|설치)시(키|켜|킨|킵)'), "threshold": None, "ex": '입력시킵니다 → 입력합니다'},
    # TL20 [S40]
    {"id": "TL20", "re": re.compile('하기\\s?위(해|하여)서?'), "threshold": 1.0, "ex": '확인하기 위해 → 확인하려고'},
    # AI01 [S7]
    {"id": "AI01", "re": re.compile('(알아|살펴)(보겠습니다|볼까요|보도록\\s?하겠습니다|봅시다)'), "threshold": None, "ex": '알아보겠습니다 → 본론부터'},
    # AI02 조사 초안(출처 미확인/우리 기준)
    {"id": "AI02", "re": re.compile('(오늘은|이번\\s?(글|포스팅)에서는)'), "threshold": None, "ex": '오늘은 → 삭제'},
    # AI03 [S42] heading_re의 '정리' 등은 실용적인 요약 제목도 잡아 제외.
    {"id": "AI03", "re": re.compile('(결론적으로|요약하자면|정리하자면|마치며|마무리하며)'), "threshold": None, "ex": '요약하자면 → 삭제'},
    # AI04 조사 초안(출처 미확인/우리 기준)
    {"id": "AI04", "re": re.compile('(도움이\\s?되(셨|었)?(기를|길|으면)|댓글로\\s?(남겨|알려)|공감(과|\\s?및)\\s?구독|읽어\\s?주셔서\\s?감사)'), "threshold": None, "ex": '도움이 되셨기를 → 삭제'},
    # AI05 [S42]
    {"id": "AI05", "re": re.compile('(단순(히|한)\\s?[^.。]{0,20}(이|가)?\\s?아니(라|고)|뿐만\\s?아니라)'), "threshold": 0.5, "ex": '뿐만 아니라 → 문장 나누기'},
    # AI06 [S42] 실제 출력을 설명하는 '보여 줍니다'는 제외.
    {"id": "AI06", "re": re.compile('(중요한|핵심적인|필수적인|결정적인)\\s?(역할|의미|요소)'), "threshold": None, "ex": '핵심적인 역할 → 구체적인 역할'},
    # AI07 [S16]
    {"id": "AI07", "re": re.compile('(다양한|효과적(인|으로)|효율적(인|으로)|원활(한|하게)|혁신적(인|으로)|획기적(인|으로)|완벽(한|하게))'), "threshold": 1.0, "ex": '효과적인 → 수치·결과'},
    # AI08 [S32]
    {"id": "AI08", "re": re.compile('(여정|열쇠|첫걸음|날개를\\s?달|마법(처럼|같은)|게임\\s?체인저|판도를\\s?바꾸|두\\s?마리\\s?토끼|양날의\\s?검|한\\s?줄기\\s?빛)'), "threshold": None, "ex": '마법처럼 → 실제 작동 방식'},
    # AI12 조사 초안. 이모지 분기는 실제 데이터(✅)도 잡으므로 제외.
    {"id": "AI12", "re": re.compile('[!！]'), "threshold": None, "ex": '느낌표 → 마침표'},
    # AI13 [S37] 원칙 4
    {"id": "AI13", "re": re.compile(r'(정말|매우|아주|굉장히|상당히|너무나|무척|확실히)\s'), "threshold": 1.0, "ex": '매우 빠릅니다 → 빠릅니다 / 측정값'},
    # AI16 [S7]
    {"id": "AI16", "re": re.compile('\\[(여기|이곳|링크|클릭|바로\\s?가기)\\]'), "threshold": None, "ex": '여기 → 링크 대상 이름'},
)

STYLE_LIMITS = (0.5, 1.5)  # 후보/1,000자: 이하 2점, 이하 1점, 초과 0점
BOLD_LIMITS = (1.0, 3.0)  # 굵은 구간/1,000자. 30자 이상 구간은 최대 1점
INLINE_CODE = re.compile(r"(?<![\\`])(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)")
HTML_COMMENT = re.compile(r"<!--[\s\S]*?-->")
BARE_URL = re.compile(r"https?://[^\s<>]+")
BOLD = re.compile(r"(?<![\\*])\*\*([^*\n]+)\*\*(?!\*)|(?<![\\_])__([^_\n]+)__(?!_)")


def style_rows(text):
    """검사 대상 원문과 화면 글자를 함께 보존한다(링크 글자·굵게 표시는 검사에 필요)."""
    # 주석은 화면에 없는 편집 메모. 줄바꿈을 남겨 원문 줄 번호를 보존한다.
    text = HTML_COMMENT.sub(lambda m: "\n" * m[0].count("\n"), text)
    _, prose, _ = scan(text)
    lines = [""] * len(text.splitlines())
    included = set()
    for no, line in prose:
        if re.match(r"^ {0,3}>", line) or REF_DEF.match(line) or TABLE_SEP.match(line):
            continue
        lines[no - 1] = line
        included.add(no)
    joined = INLINE_CODE.sub(lambda m: "\n" * m[0].count("\n"), "\n".join(lines))
    rows = []
    for no, line in enumerate(joined.split("\n"), 1):
        if no not in included:
            continue
        line = AUTOLINK.sub("", LINK_TARGET.sub("]", line))
        line = BARE_URL.sub("", line)
        line = re.sub(r"!\[([^\]]*)\]", r"[\1]", line)
        visible = visible_text(line)
        visible = re.sub(r"^ {0,3}#{1,6}\s+", "", visible)
        visible = visible.replace("__", "")
        rows.append((no, line, visible))
    return rows


def style_metrics(text):
    rows = style_rows(text)
    # 본문 공백·빈 줄을 포함하고, 제외한 행의 줄바꿈은 세지 않는다.
    chars = len("\n".join(visible for _, _, visible in rows))
    unit = chars / 1000
    candidates, hits, bold, sentences = [], {}, [], []
    original_lines = text.splitlines()
    for pattern in STYLE_PATTERNS:
        # AI16은 링크 표기, 나머지는 화면에 보이는 글자로 검사한다.
        matched = [(no, original_lines[no - 1].strip(), pattern["id"] + ": " + pattern["ex"])
                   for no, raw, visible in rows
                   for _ in pattern["re"].finditer(raw if pattern["id"] == "AI16" else visible)]
        hits[pattern["id"]] = matched
        if pattern["threshold"] is None:
            candidates.extend(matched)
        elif matched and len(matched) > pattern["threshold"] * unit:
            candidates.append(matched[0])
    for no, raw, _ in rows:
        for match in BOLD.finditer(raw):
            content = match[1] if match[1] is not None else match[2]
            found = (no, match[0], "30자 이상 문장 굵게" if len(visible_text(content)) >= 30 else "굵은 구간")
            bold.append(found)
            if len(visible_text(content)) >= 30:
                sentences.append(found)
    return {"chars": chars, "hits": hits, "candidates": sorted(candidates),
            "style_density": len(candidates) / unit if unit else 0,
            "bold": bold, "sentences": sentences,
            "bold_density": len(bold) / unit if unit else 0}


def style_items(text):
    metrics = style_metrics(text)
    density = metrics["style_density"]
    score = 2 if density <= STYLE_LIMITS[0] else 1 if density <= STYLE_LIMITS[1] else 0
    c24 = item("C24", score, metrics["candidates"],
               ok_reason=f"문체 후보 {len(metrics['candidates'])}개, 1,000자당 {density:.2f}개",
               head=f"문체 후보 {len(metrics['candidates'])}개, 1,000자당 {density:.2f}개",
               fix="표시한 패턴을 문맥에 맞게 고치되 뜻이 바뀌는 경우 유지한다")
    density = metrics["bold_density"]
    score = 2 if density <= BOLD_LIMITS[0] else 1 if density <= BOLD_LIMITS[1] else 0
    if metrics["sentences"]:
        score = min(score, 1)
    found = metrics["sentences"] + [b for b in metrics["bold"] if b not in metrics["sentences"]]
    c25 = item("C25", score, found,
               ok_reason=f"굵은 구간 {len(metrics['bold'])}개, 1,000자당 {density:.2f}개, 문장 굵게 없음",
               head=f"굵은 구간 {len(metrics['bold'])}개, 1,000자당 {density:.2f}개, 30자 이상 {len(metrics['sentences'])}개",
               fix="굵은 글씨는 짧은 핵심어에만 쓰고 문장 전체의 강조를 푼다")
    return [c24, c25]


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
    c24, c25 = style_items(text)
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
            # 링크 주소와 마크다운 기호는 화면에 보이지 않으므로 본문과 같은 방식으로 빼고 잰다
            long_cell = next((c for _, r in rows for c in cells(r) if max(map(len, visible_text(c).split()), default=0) >= LONG_TOKEN), None)
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
        visible = visible_text(line)
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

    refs = {m.group(1).strip().lower() for _, line in prose if (m := REF_DEF.match(line))}
    images = []
    for no, line in prose:
        for m in IMAGE.finditer(line):
            images.append((no, m.group(0)[:80], m.group(1)))
        for m in REF_IMAGE.finditer(IMAGE.sub("", line)):
            label = (m.group(2) or m.group(1)).strip().lower()
            if label in refs:
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
    return [c18, c19, c20, c23, c24, c25]


def visible_text(text):
    return MARKUP.sub("", LINK_TARGET.sub("] ", text))


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
