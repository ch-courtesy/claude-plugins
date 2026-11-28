"""장부 검사 CLI의 실제 출력과 종료 코드를 검증한다."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import pytest

SCRIPT = Path(__file__).with_name('ledger_check.py')
FIXTURES = Path(__file__).with_name('fixtures')


def run(path, *args):
    result = subprocess.run([sys.executable, str(SCRIPT), str(path), *map(str, args)], capture_output=True, encoding='utf-8')
    assert result.stdout, result.stderr
    return result.returncode, json.loads(result.stdout)


def test_clean_and_hashes():
    code, report = run(FIXTURES / 'clean')
    assert code == 0
    assert report['ok'] and report['findings'] == []
    assert 'bible.toml' in report['files']
    assert all(len(value) == 64 for value in report['files'].values())


def test_broken_six_checks():
    code, report = run(FIXTURES / 'broken', '--foreshadow-limit', 1, '--min-chars', 10, '--episodes-text-dir', FIXTURES / 'broken' / 'texts')
    assert code == 1
    assert {item['check'] for item in report['findings']} == {'id_duplicate', 'date_order', 'dead_character', 'owner_conflict', 'stale_foreshadow', 'short_episode'}


@pytest.fixture
def ledger(tmp_path):
    target = tmp_path / 'ledger'
    shutil.copytree(FIXTURES / 'clean', target)
    return target


def test_flashback(ledger):
    path = ledger / 'characters.toml'
    path.write_text(path.read_text(encoding='utf-8').replace('state = "alive"', 'state = "dead"\ndeath_episode = 1', 1), encoding='utf-8')
    path = ledger / 'scenes/E003-S01.toml'
    path.write_text(path.read_text(encoding='utf-8') + '\nflashback = true\n', encoding='utf-8')
    assert run(ledger)[1]['findings'] == []


def test_syntax_error(ledger):
    (ledger / 'bible.toml').write_text('[[settings]\n', encoding='utf-8')
    code, report = run(ledger)
    assert code == 1
    assert any(f['file'] == 'bible.toml' and '줄' in f['message'] for f in report['findings'])
    assert 'bible.toml' in report['files']


def test_missing_ref_and_field(ledger):
    path = ledger / 'scenes/E003-S01.toml'
    path.write_text(path.read_text(encoding='utf-8').replace('CHR-001', 'CHR-999').replace('goal = "열쇠 찾기"\n', ''), encoding='utf-8')
    assert 'missing_field' in {f['check'] for f in run(ledger)[1]['findings']}
    path.write_text(path.read_text(encoding='utf-8') + '\ngoal = "열쇠 찾기"\n', encoding='utf-8')
    assert 'missing_ref' in {f['check'] for f in run(ledger)[1]['findings']}


def test_counts_and_limit(ledger):
    texts = ledger / 'texts'
    texts.mkdir()
    (texts / 'E001.txt').write_text('가 나\n', encoding='utf-8')
    report = run(ledger, '--min-chars', 3, '--episodes-text-dir', texts)[1]
    finding = next(f for f in report['findings'] if f['check'] == 'short_episode')
    assert finding['evidence']['with_spaces'] == 4
    assert finding['evidence']['without_spaces'] == 2
    assert run(ledger, '--min-chars', 3, '--count', 'with_spaces', '--episodes-text-dir', texts)[1]['findings'] == []



def test_min_chars_without_texts_is_error(ledger, tmp_path):
    empty = tmp_path / 'empty_texts'
    empty.mkdir()
    (empty / 'notes.md').write_text('본문 아님\n', encoding='utf-8')
    for args in (('--min-chars', 3000, '--episodes-text-dir', empty), ('--min-chars', 3000)):
        code, report = run(ledger, *args)
        assert code == 1
        assert 'no_episode_text' in {f['check'] for f in report['findings']}
    code, report = run(ledger)
    assert 'no_episode_text' not in {f['check'] for f in report['findings']}


@pytest.mark.parametrize('filename,old,new', [
    ('timeline.toml', 'SET-001', 'SET-999'),
    ('knowledge.toml', 'CHR-001', 'CHR-999'),
])
def test_other_reference_types(ledger, filename, old, new):
    path = ledger / filename
    path.write_text(path.read_text(encoding='utf-8-sig').replace(old, new), encoding='utf-8')
    assert 'missing_ref' in {f['check'] for f in run(ledger)[1]['findings']}


def test_stale_boundary_warning_and_resolution(ledger):
    path = ledger / 'foreshadow.toml'
    text = path.read_text(encoding='utf-8').replace('resolved_episode = 3\n', '')
    path.write_text(text, encoding='utf-8')
    assert run(ledger, '--foreshadow-limit', 2)[1]['findings'] == []
    code, report = run(ledger, '--foreshadow-limit', 1)
    assert code == 0 and report['ok']
    assert [f['check'] for f in report['findings']] == ['stale_foreshadow']
    path.write_text(text + '\ndiscarded_episode = 3\ndiscarded_evidence = "E003-S01:P001"\n', encoding='utf-8')
    assert run(ledger, '--foreshadow-limit', 1)[1]['findings'] == []


def test_planned_death_is_not_fact(ledger):
    path = ledger / 'characters.toml'
    text = path.read_text(encoding='utf-8').replace('state = "alive"', 'state = "dead"\ndeath_episode = 1', 1)
    path.write_text(text.replace('status = "confirmed"\nevidence', 'status = "planned"\nevidence', 1), encoding='utf-8')
    assert run(ledger)[1]['findings'] == []


def test_invalid_nested_status(ledger):
    path = ledger / 'knowledge.toml'
    text = path.read_text(encoding='utf-8-sig').replace('status = "confirmed",', 'status = "unknown",')
    path.write_text(text, encoding='utf-8')
    assert 'missing_field' in {f['check'] for f in run(ledger)[1]['findings']}


def test_missing_text_dir_is_reported():
    code, report = run(FIXTURES / 'clean', '--episodes-text-dir', FIXTURES / '없는폴더')
    assert code == 1
    assert [item['check'] for item in report['findings']] == ['missing_field']


@pytest.mark.parametrize('bad', ['[["CHR-001"]]', '[1]', '[{id = "CHR-001"}]'])
def test_non_string_participant_is_reported_not_crash(ledger, bad):
    path = ledger / 'scenes' / 'E003-S01.toml'
    path.write_text(path.read_text(encoding='utf-8-sig').replace('participants = ["CHR-001", "CHR-002"]', f'participants = {bad}'), encoding='utf-8')
    code, report = run(ledger)
    assert code == 1
    assert any(f['check'] == 'missing_field' and 'participants' in f['message'] for f in report['findings'])
