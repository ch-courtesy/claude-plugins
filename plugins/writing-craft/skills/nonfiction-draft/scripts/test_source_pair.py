"""source_pair.py 4절(부재·유일 주장의 반증 줄) 시험."""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
SRC = """# 출처: 일지 발췌
log/2026-11-02.md:148:- 백업 점검. srv1은 restic을 한 번도 쓰지 않았다.
log/2026-11-02.md:159:- 정정: 담당자 말에 다시 확인했다. `restic check`가 정상으로 답했다.
log/2026-11-02.md:165:- 작업 35: restic 2회 실패(명령 권한 거부, 5분 시간 초과, 빈 출력) → rsync 복사로 대체해 진행 중.
log/2026-11-04.md:11:- restic 1회는 5분 제한에 걸려 결과 없음.
log/2026-11-06.md:21:- rclone 작업 2개를 썼고 restic은 안 썼다.
log/2026-11-06.md:26:- cron 작업 2개와 rclone 1개를 썼다.
"""
DRAFT = """# 제목

| 날짜 | 기록 |
|---|---|
| 11-02 | 이날 srv1은 restic을 한 번도 쓰지 않았습니다. |

원격으로 옮긴 작업은 11-06의 rclone 1개입니다.

일지에 실패로 적힌 줄은 발췌에 없습니다.

## 작업 메모
- 이 절은 보지 않는다. 한 번도 없다.
"""


def run(tmp_path, draft=DRAFT, src=SRC):
    (tmp_path / "src.md").write_text(src, encoding="utf-8")
    (tmp_path / "draft.md").write_text(draft, encoding="utf-8")
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
    assert app.count("src.md:4:") == 1 and "rsync 복사로 대체해 진행 중" in app


def test_work_memo_ignored(tmp_path):
    assert "이 절은 보지 않는다" not in run(tmp_path)


def test_missing_source_path_stops(tmp_path):
    draft = tmp_path / 'd.md'
    draft.write_text('# 글\n\n자료 100개를 확인했다.\n', encoding='utf-8')
    r = subprocess.run([sys.executable, str(HERE / 'source_pair.py'), str(draft), str(draft), str(tmp_path / '없음.md')],
                       capture_output=True)
    assert r.returncode != 0 and r.stdout == b''


DRAFT_WIDE = """# 제목

rsync 복사는 대부분 권한 거부로 끝났습니다.

11-04에는 restic을 다시 돌리지 않았습니다.

11-06에 rclone과 cron은 어느 쪽도 결과를 얻지 못했습니다.

11-02 담당자에게 묻지 않고 넘어갔습니다.
"""


def test_wider_quantity_and_absence_words(tmp_path):
    (tmp_path / "src.md").write_text(SRC, encoding="utf-8")
    (tmp_path / "draft.md").write_text(DRAFT_WIDE, encoding="utf-8")
    out = tmp_path / "rep.md"
    subprocess.run([sys.executable, str(HERE / "source_pair.py"), str(tmp_path / "draft.md"),
                    str(tmp_path / "src.md"), "--out", str(out)], check=True, capture_output=True)
    sec = out.read_text(encoding="utf-8").split("## 4.")[1]
    b = block(sec, "대부분")
    assert "src.md:4(" in b  # rsync가 나오는 유일한 줄
    assert "src.md:5(" in block(sec, "다시 돌리지")  # 11-04 줄
    b = block(sec, "어느 쪽도")
    assert "src.md:6(" in b and "src.md:7(" in b
    assert "src.md:3(" in block(sec, "묻지 않고")  # 11-02 담당자 줄


def test_quantity_claim_falls_back_to_topic_word(tmp_path):
    (tmp_path / "src.md").write_text(SRC, encoding="utf-8")
    (tmp_path / "draft.md").write_text("# 제목\n\nrestic은 대부분 그랬습니다.\n", encoding="utf-8")
    out = tmp_path / "rep.md"
    subprocess.run([sys.executable, str(HERE / "source_pair.py"), str(tmp_path / "draft.md"),
                    str(tmp_path / "src.md"), "--out", str(out)], check=True, capture_output=True)
    b = block(out.read_text(encoding="utf-8").split("## 4.")[1], "대부분")
    for ln in ("src.md:2(", "src.md:3(", "src.md:4(", "src.md:5(", "src.md:6("):  # restic이 나오는 줄 전부
        assert ln in b


def test_only_claim_lists_matching_backup_line(tmp_path):
    draft = """rsync 대체 투입 기록만 있습니다.
rsync 사용 횟수만남아 있습니다.
rsync 사용 횟수만 적었습니다.
rsync 복사본을 필요한 만큼 만들었습니다.
rsync 담당자를 만나 비용 만원을 지급했습니다.
rsync 실행 기록만  있습니다.
"""
    sec = run(tmp_path, draft)
    for claim in draft.splitlines()[:3]:
        assert "src.md:4(" in block(sec, claim)
    for other in draft.splitlines()[3:]:
        assert other not in sec


def test_absence_cell_uses_least_common_row_word(tmp_path):
    src = """백업 비용과 저장 한도를 점검했다.
원격 백업의 전송 한도를 올렸다.
백업 비용 및 복원 한도를 확인했다.
주간 백업 비용과 보관 한도를 검토했다.
야간 백업 비용을 정산했다.
복원 시험 비용을 추가했다.
"""
    for cell in ("기록 없음", "없음", "없다"):
        sec = run(tmp_path, f"| 비용·한도 | {cell} |", src)
        b = block(sec, cell)
        for ln in (1, 2, 3, 4):
            assert f"src.md:{ln}(한도)" in b
        assert "src.md:5" not in b and "src.md:6" not in b


def test_same_name_files_in_two_folders_kept_apart(tmp_path):
    (tmp_path / "mat" / "a").mkdir(parents=True)
    (tmp_path / "mat" / "b").mkdir(parents=True)
    (tmp_path / "mat" / "a" / "log.md").write_text("- srv1은 restic을 한 번도 쓰지 않았다.\n", encoding="utf-8")
    (tmp_path / "mat" / "b" / "log.md").write_text("- 정정: srv1 restic check가 정상으로 답했다.\n", encoding="utf-8")
    (tmp_path / "draft.md").write_text("# 제목\n\nsrv1은 restic을 한 번도 쓰지 않았습니다.\n", encoding="utf-8")
    r = subprocess.run([sys.executable, str(HERE / "source_pair.py"), "draft.md", "mat"],
                       cwd=tmp_path, capture_output=True, check=True)
    app = r.stdout.decode("utf-8").split("### 4-1.")[1]
    assert "mat/a/log.md:1:" in app and "mat/b/log.md:1:" in app
    assert "정상으로 답했다" in app
