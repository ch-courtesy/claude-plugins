"""문체 후보 검사의 누락과 대사·코드 오탐을 검증한다."""
import json
from pathlib import Path
import subprocess
import sys
import pytest


def run(tmp_path, text, *args):
    path = tmp_path / '원고.md'
    path.write_text(text, encoding='utf-8')
    result = subprocess.run([sys.executable, str(Path(__file__).with_name('auto_checks.py')), str(path), *args], capture_output=True, encoding='utf-8')
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)['checks']


def test_three_defects(tmp_path):
    report = run(tmp_path, '비가 온다. 바람이 붑니다. 집에 가요.\n\n[경험 확인 필요] TODO\n\n“닫지 않은 말')
    assert report['pairs'] and report['markers'] and report['register_mix']
    assert report['pairs'][0]['line'] == 5


def test_clean_dialogue(tmp_path):
    assert not any(run(tmp_path, '“집에 가요.” 그가 말했다. 비가 내렸다.\n\n나는 걷는다.').values())


@pytest.mark.parametrize('text', ['간다. 갑니다.', '간다. 가요.', '갑니다. 가요.'])
def test_register_pairs(tmp_path, text):
    assert run(tmp_path, text)['register_mix']


def test_exclusions_and_runs(tmp_path):
    report = run(tmp_path, '간다. `갑니다.`\n\n```\n가요. 갑니다.\n```\n\n| 간다. | 가요. |\n\n먹었다. 걸었다. 웃었다.')
    assert report['register_mix'] == []
    assert len(report['ending_runs']) == 1
    assert run(tmp_path, '먹었다. 걸었다. 웃었다.', '--sequence-limit', '4')['ending_runs'] == []


def test_markers_honorific_and_pairs(tmp_path):
    report = run(tmp_path, '(틀린」\n[출처 확인 필요] [직접 시험하지 않음]\n주문하신 커피 나오셨습니다.')
    assert len(report['pairs']) == 2
    assert len(report['markers']) == 2
    assert report['object_honorific'][0]['line'] == 3


def test_angle_bracket_dialogue_is_not_register_mix(tmp_path):
    checks = run(tmp_path, '민재가 말했다. 〈저는 어제 푹 잤어요〉. 연한 회색이었다.\n\n〈열린 꺾쇠만 있다.\n')
    assert checks['register_mix'] == []
    assert len(checks['pairs']) == 1


@pytest.mark.parametrize('opening', ["그는 don't라고 적었다.", "'닫지 않은 따옴표였다.", '“닫지 않은 말이었다.'])
def test_unclosed_quote_does_not_hide_later_paragraphs(tmp_path, opening):
    checks = run(tmp_path, opening + '\n\n비가 왔습니다. 길이 젖었다.\n')
    assert len(checks['register_mix']) == 1


def test_apostrophe_does_not_hide_same_paragraph(tmp_path):
    assert run(tmp_path, "그는 don't라고 적었다. 비가 왔습니다.")['register_mix']


def test_pairs_ignore_list_numbers_and_code(tmp_path):
    checks = run(tmp_path, "1) 첫째\n- 가) 둘째\n\n```\nprint(')')\n```\n\n`)` 기호\n\n끝)\n")
    assert [c['line'] for c in checks['pairs']] == [10]
