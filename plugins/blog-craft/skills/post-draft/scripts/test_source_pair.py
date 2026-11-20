"""source_pair.py 4절(부재·유일 주장의 반증 줄) 시험."""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
SRC = """# 출처: 일지 발췌
journal/2026-11-02.md:148:- 사용량 보고. agy는 HQ가 한 번도 쓰지 않았다.
journal/2026-11-02.md:159:- 정정: 오너 말에 다시 확인했다. `agy -p`가 정상으로 답했다.
journal/2026-11-02.md:165:- W-35: agy 2회 실패(명령 권한 거부, 5분 시간 초과, 빈 출력) → Sonnet 조사원으로 대체해 진행 중.
journal/2026-11-04.md:11:- agy 1회는 5분 제한에 걸려 결과 없음.
journal/2026-11-06.md:21:- web-fetch 서브에이전트 2개를 썼고 agy는 안 썼다.
journal/2026-11-06.md:26:- content-writer 2개와 web-fetch 1개를 썼다.
"""
DRAFT = """# 제목

| 날짜 | 기록 |
|---|---|
| 11-02 | 이날 HQ는 agy를 한 번도 쓰지 않았습니다. |

원문을 읽은 서브에이전트는 11-06의 web-fetch 1개입니다.

일지에 실패로 적힌 줄은 발췌에 없습니다.

## 작업 메모
- 이 절은 보지 않는다. 한 번도 없다.
"""


def run(tmp_path):
    (tmp_path / "src.md").write_text(SRC, encoding="utf-8")
    (tmp_path / "draft.md").write_text(DRAFT, encoding="utf-8")
    out = tmp_path / "rep.md"
    subprocess.run([sys.executable, str(HERE / "source_pair.py"), str(tmp_path / "draft.md"),
                    str(tmp_path / "src.md"), "--out", str(out)], check=True, capture_output=True)
    rep = out.read_text(encoding="utf-8")
    return rep.split("## 4.")[1]


def block(sec, needle):
    parts = sec.split("\n- 초안 ")
    hit = [p for p in parts if needle in p.splitlines()[0]]
    assert hit, needle
    return hit[0]


def test_same_day_lines_all_listed(tmp_path):
    b = block(run(tmp_path), "한 번도")
    assert "날짜 11-02" in b
    for ln in ("src.md:2(", "src.md:3(", "src.md:4("):  # 11-02의 148·159·165줄
        assert ln in b
    assert "src.md:5" not in b  # 11-04 줄은 빠진다


def test_count_claim_gets_every_matching_line(tmp_path):
    b = block(run(tmp_path), "1개입니다")
    assert "src.md:6(" in b and "src.md:7(" in b


def test_no_name_claim_uses_rare_word(tmp_path):
    b = block(run(tmp_path), "실패로 적힌")
    assert "src.md:4(실패)" in b


def test_line_text_once_in_appendix(tmp_path):
    sec = run(tmp_path)
    app = sec.split("### 4-1.")[1]
    assert app.count("src.md:4:") == 1 and "Sonnet 조사원으로 대체해 진행 중" in app


def test_work_memo_ignored(tmp_path):
    assert "이 절은 보지 않는다" not in run(tmp_path)
