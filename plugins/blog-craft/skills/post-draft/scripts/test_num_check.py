"""num_check.py 명령이 실제로 돌고 자료에 없는 값을 표시하는지 시험."""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
ENV = {**os.environ, 'PYTHONIOENCODING': 'utf-8'}


def run(*args):
    return subprocess.run([sys.executable, str(HERE / 'num_check.py'), *map(str, args)],
                          capture_output=True, encoding='utf-8', env=ENV)


def test_help_runs():
    r = run('--help')
    assert r.returncode == 0, r.stderr


def test_reports_unsupported_number(tmp_path):
    src = tmp_path / 's.md'
    src.write_text('자료 100개를 확인했다.\n', encoding='utf-8')
    draft = tmp_path / 'd.md'
    draft.write_text('# 글\n\n자료 100개와 777개를 확인했다.\n', encoding='utf-8')
    r = run(draft, src)
    assert r.returncode == 0, r.stderr
    assert '| 3 | 100 |' in r.stdout and '일치' in r.stdout
    assert any('| 777 |' in line and '근거 없음' in line for line in r.stdout.splitlines())


def test_missing_source_path_stops(tmp_path):
    draft = tmp_path / 'd.md'
    draft.write_text('# 글\n\n자료 100개를 확인했다.\n', encoding='utf-8')
    r = subprocess.run([sys.executable, str(HERE / 'num_check.py'), str(draft), str(draft), str(tmp_path / '없음.md')],
                       capture_output=True)
    assert r.returncode != 0 and r.stdout == b''


def report_line(stdout, needle):
    return next(line for line in stdout.splitlines() if needle in line)


def test_year_mismatch_is_flagged(tmp_path):
    src = tmp_path / 's.md'
    src.write_text('2025-11-20 점검했다. 3월 4일 회의.\n', encoding='utf-8')
    draft = tmp_path / 'd.md'
    draft.write_text('# 글\n\n2026-11-20에 점검했다. 2025-11-20 기록. 2026년 3월 4일 회의. 11-20 다시.\n', encoding='utf-8')
    r = run(draft, src)
    assert r.returncode == 0, r.stderr
    assert '연도 다름' in report_line(r.stdout, '| 2026-11-20 |')
    assert '| 일치 |' in report_line(r.stdout, '| 2025-11-20 |')
    assert '자료에 연도 없음' in report_line(r.stdout, '2026년 3월 4일')
    assert '| 일치 |' in report_line(r.stdout, '| 11-20 |')


def test_negative_sign_kept(tmp_path):
    src = tmp_path / 's.md'
    src.write_text('수익 -100원, 3-5개, 작업 W-701.\n', encoding='utf-8')
    draft = tmp_path / 'd.md'
    draft.write_text('# 글\n\n수익 100원이었다.\n\n손익 -100원이었다.\n', encoding='utf-8')
    r = run(draft, src)
    assert r.returncode == 0, r.stderr
    assert '근거 없음' in report_line(r.stdout, '| 3 | 100 |')
    assert '| 일치 |' in report_line(r.stdout, '| 5 | -100 |')
    assert '근거 없음 1개' in r.stdout
