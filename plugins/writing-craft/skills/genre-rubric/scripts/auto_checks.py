"""사용법: python auto_checks.py 원고.md [--sequence-limit 3]

점수나 자동 수정 없이 편집 후보를 JSON으로 출력한다.
문체는 종결 어미의 휴리스틱이며 언어학적 판정이 아니다.
"""
import argparse
import json
from pathlib import Path
import re


PAIRS = {'“': '”', '‘': '’', '「': '」', '『': '』', '〈': '〉', '《': '》', '(': ')'}
QUOTES = {'“': '”', '‘': '’', '「': '」', '『': '』', '〈': '〉', '《': '》', '"': '"', "'": "'"}


def analyze(path, sequence_limit=3):
    text = Path(path).read_text(encoding='utf-8-sig')
    checks = {key: [] for key in ('pairs', 'markers', 'register_mix', 'ending_runs', 'object_honorific')}
    lines = text.splitlines()

    def item(line, excerpt, **extra):
        return {'line': line, 'text': excerpt.strip()[:160], **extra}

    stack = []
    pair_fence = None
    for number, line in enumerate(lines, 1):
        match = re.match(r'^\s{0,3}(`{3,}|~{3,})', line)
        if match:
            if pair_fence is None:
                pair_fence = match[1]
            elif match[1][0] == pair_fence[0] and len(match[1]) >= len(pair_fence):
                pair_fence = None
        # 코드와 '1)' 같은 목록 번호의 괄호는 짝 검사에서 뺀다.
        pair_line = '' if match or pair_fence else re.sub(r'(`+).*?\1', '', line)
        pair_line = re.sub(r'^\s*(?:[-*+]\s+)?(?:\d{1,3}|[가-힣A-Za-z])\)(?=\s)', '', pair_line)
        for char in pair_line:
            if char in PAIRS:
                stack.append((char, number, line))
            elif char in PAIRS.values():
                if stack and PAIRS[stack[-1][0]] == char:
                    stack.pop()
                else:
                    checks['pairs'].append(item(number, line, message=f'짝 없는 닫는 기호 {char}'))
        for match in re.finditer(r'\[[^\]\n]*확인 필요\]|\[직접 시험하지 않음\]|\bTODO\b', line):
            checks['markers'].append(item(number, line, marker=match[0]))
    for char, number, line in stack:
        checks['pairs'].append(item(number, line, message=f'닫지 않은 기호 {char}'))
    patterns = Path(__file__).resolve().parent.parent / 'references/object-honorific.txt'
    for number, line in enumerate(lines, 1):
        for pattern in patterns.read_text(encoding='utf-8-sig').splitlines():
            if pattern.strip() and pattern in line:
                checks['object_honorific'].append(item(number, line, pattern=pattern))

    # 공백 치환으로 줄 위치를 보존하며 코드·표·인용을 제거한다.
    filtered = []
    fence = None
    quote_stack = []
    for line in lines:
        match = re.match(r'^\s{0,3}(`{3,}|~{3,})', line)
        if match:
            token = match[1]
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            filtered.append('')
            continue
        if fence or '|' in line:
            filtered.append('')
            continue
        line = re.sub(r'(`+).*?\1', lambda m: ' ' * len(m[0]), line)
        if not line.strip():
            # 닫지 않은 따옴표가 뒤 문단까지 지우지 않게 문단마다 다시 센다.
            quote_stack = []
        result = []
        for index, char in enumerate(line):
            if char == "'" and re.fullmatch(r"[A-Za-z0-9]'[A-Za-z0-9]", line[max(0, index - 1):index + 2]):
                result.append(char)  # don't 같은 아포스트로피는 인용 부호가 아니다.
            elif quote_stack and char == quote_stack[-1]:
                quote_stack.pop()
                result.append(' ')
            elif char in QUOTES:
                quote_stack.append(QUOTES[char])
                result.append(' ')
            else:
                result.append(' ' if quote_stack else char)
        filtered.append(''.join(result))

    def inspect(paragraph):
        if not paragraph:
            return
        joined = '\n'.join(line for _, line in paragraph)
        registers = set()
        run = []
        last_ending = None
        for match in re.finditer(r'([^.!?。！？]+)[.!?。！？]+|([^.!?。！？]+)$', joined):
            sentence = (match[1] or match[2]).strip()
            words = re.findall(r'[가-힣]+', sentence)
            if not words:
                run, last_ending = [], None
                continue
            end = words[-1]
            register = '합니다체' if re.search(r'(?:니다|니까)$', end) else '해요체' if end.endswith('요') else '해라체' if end.endswith('다') else None
            if register:
                registers.add(register)
            offset = match.start() + len(match[0]) - len(match[0].lstrip())
            number = paragraph[0][0] + joined[:offset].count('\n')
            ending = end[-2:]
            if register and ending == last_ending:
                run.append((number, sentence))
            else:
                run = [(number, sentence)] if register else []
            last_ending = ending if register else None
            if len(run) == sequence_limit:
                checks['ending_runs'].append(item(run[0][0], ' '.join(s for _, s in run), ending=ending, count=sequence_limit))
            elif len(run) > sequence_limit:
                checks['ending_runs'][-1]['count'] = len(run)
        if len(registers) > 1:
            checks['register_mix'].append(item(paragraph[0][0], joined, registers=sorted(registers)))

    paragraph = []
    for number, line in enumerate(filtered, 1):
        if not line.strip():
            inspect(paragraph)
            paragraph = []
        else:
            paragraph.append((number, line))
    inspect(paragraph)
    return {'file': str(path), 'checks': checks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path')
    parser.add_argument('--sequence-limit', type=int, default=3)
    args = parser.parse_args()
    if args.sequence_limit < 1:
        parser.error('--sequence-limit은 1 이상이어야 한다.')
    print(json.dumps(analyze(args.path, args.sequence_limit), ensure_ascii=True))


if __name__ == '__main__':
    main()
