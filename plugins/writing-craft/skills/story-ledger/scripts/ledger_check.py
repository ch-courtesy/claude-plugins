"""사용법: python ledger_check.py 장부폴더 [--foreshadow-limit 30]

본문 분량: --episodes-text-dir 본문폴더 --min-chars 3000
--count without_spaces 또는 with_spaces로 하한 계산 방식을 고른다.
Python 3.11 이상에서 실행하라. 확정 기록만 시간·생사·소유 검사에 쓴다.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import tomllib


# 필드 이름과 형식은 references/schema.md와 함께 유지한다.
SPECS = {
    'bible': ('settings', 'SET', {'fact': str, 'conditions': str, 'exceptions': str}),
    'characters': ('characters', 'CHR', {'name': str, 'desire': str, 'strategy': str, 'relationships': list, 'speech': str, 'body': str, 'state': str, 'possessions': list}),
    'knowledge': ('knowledge', 'INF', {'fact': str, 'awareness': list, 'reader_episode': int}),
    'timeline': ('events', 'EVT', {'episode': int, 'time': str, 'duration': str, 'location': str, 'movement': str}),
    'foreshadow': ('foreshadows', 'FS', {'setup_episode': int, 'reappearances': list}),
    'episode': (None, 'E', {'episode': int, 'events': list, 'choice_cost': str, 'new_facts': list, 'unresolved': list, 'next_plan': str}),
    'scene': (None, 'S', {'episode': int, 'participants': list, 'pov': str, 'time': str, 'location': str, 'goal': str, 'resistance': str, 'result': str, 'aftermath': str, 'before': str, 'after': str, 'forbidden_info': list, 'foreshadows': list}),
}
NESTED = {
    'relationships': {'character': str, 'relation': str},
    'possessions': {'item': str, 'episode': int, 'status': str, 'evidence': str},
    'awareness': {'character': str, 'understanding': str, 'status': str, 'evidence': str},
}


def check(ledger_dir, foreshadow_limit=30, min_chars=None, count='without_spaces', episodes_text_dir=None):
    root = Path(ledger_dir)
    files, findings, records, ids = {}, [], [], {}

    def add(kind, file, record, message, evidence=None, severity='error'):
        findings.append({'check': kind, 'severity': severity, 'file': file, 'id': record.get('id', ''), 'message': message, 'evidence': evidence if evidence is not None else record.get('evidence', '')})

    if not root.is_dir():
        add('missing_field', '.', {}, '장부 디렉터리가 없다.')
    for name in ('bible', 'characters', 'knowledge', 'timeline', 'foreshadow'):
        if not (root / f'{name}.toml').is_file():
            add('missing_field', f'{name}.toml', {}, '필수 장부 파일이 없다.')
    for path in sorted(root.rglob('*.toml')):
        file = path.relative_to(root).as_posix()
        raw = path.read_bytes()
        files[file] = hashlib.sha256(raw).hexdigest()
        try:
            data = tomllib.loads(raw.decode('utf-8-sig'))
        except (tomllib.TOMLDecodeError, UnicodeDecodeError) as exc:
            match = re.search(r'line (\d+)', str(exc))
            line = getattr(exc, 'lineno', None) or (int(match[1]) if match else raw.count(b'\n') + 1)
            add('missing_field', file, {}, f'TOML 구문 또는 UTF-8 인코딩 오류: {line}줄.', {'line': line})
            continue
        kind = 'episode' if path.parent.name == 'episodes' else 'scene' if path.parent.name == 'scenes' else path.stem
        if kind not in SPECS:
            continue
        table, prefix, fields = SPECS[kind]
        rows = data.get(table) if table else [data]
        if not isinstance(rows, list):
            add('missing_field', file, {}, f'{table} 배열 테이블이 필요하다.')
            continue
        for row in rows:
            if not isinstance(row, dict):
                add('missing_field', file, {}, '기록은 테이블이어야 한다.')
                continue
            valid = True
            required = {'id': str, 'status': str, 'evidence': str, **fields}
            for field, typ in required.items():
                if field not in row or type(row[field]) is not typ:
                    add('missing_field', file, row, f'필수 필드 {field}가 없거나 형식이 다르다.')
                    valid = False
            identifier = row.get('id', '')
            pattern = r'E\d{3,}' if prefix == 'E' else r'E\d{3,}-S\d{2,}' if prefix == 'S' else prefix + r'-\d{3,}'
            if not isinstance(identifier, str) or not re.fullmatch(pattern, identifier):
                add('missing_field', file, row, 'ID 형식이 잘못되었다.')
                valid = False
            elif identifier in ids:
                add('id_duplicate', file, row, f'중복 ID {identifier}.', {'previous_file': ids[identifier][0], 'current': row.get('evidence', '')})
            else:
                ids[identifier] = (file, kind, row)
            if row.get('status') not in ('confirmed', 'planned', 'belief'):
                add('missing_field', file, row, 'status는 confirmed, planned, belief 중 하나여야 한다.')
                valid = False
            if kind == 'characters' and (row.get('state') not in ('alive', 'dead') or (row.get('state') == 'dead' and type(row.get('death_episode')) is not int)):
                add('missing_field', file, row, 'state 또는 사망 회차 death_episode를 확인하라.')
                valid = False
            for key, nested_fields in NESTED.items():
                for entry in row.get(key, []) if isinstance(row.get(key, []), list) else []:
                    if not isinstance(entry, dict) or any(type(entry.get(k)) is not t for k, t in nested_fields.items()):
                        add('missing_field', file, row, f'{key} 항목의 필수 필드가 없거나 형식이 다르다.')
                        valid = False
                    elif 'status' in nested_fields and entry['status'] not in ('confirmed', 'planned', 'belief'):
                        add('missing_field', file, row, f'{key} 항목의 status가 잘못되었다.')
                        valid = False
            if valid:
                records.append((file, kind, row))

    def ref(value, allowed, file, row):
        if not isinstance(value, str) or value not in ids or ids[value][1] not in allowed:
            add('missing_ref', file, row, f'참조 대상 {value}가 없거나 종류가 다르다.')

    for file, kind, row in records:
        for key, allowed in {'participants': {'characters'}, 'events': {'timeline'}, 'new_facts': {'bible', 'knowledge'}, 'forbidden_info': {'knowledge'}, 'foreshadows': {'foreshadow'}}.items():
            for value in row.get(key, []):
                ref(value, allowed, file, row)
        for key, allowed in {'location': {'bible'}, 'pov': {'characters'}}.items():
            if key in row:
                ref(row[key], allowed, file, row)
        for key in ('relationships', 'awareness'):
            for entry in row.get(key, []):
                ref(entry['character'], {'characters'}, file, row)
        for entry in row.get('possessions', []):
            ref(entry['item'], {'bible'}, file, row)

    confirmed = [(f, k, r) for f, k, r in records if r['status'] == 'confirmed']
    dated = []
    for file, kind, row in confirmed:
        if kind == 'timeline' and 'date' in row:
            try:
                date = datetime.date.fromisoformat(str(row['date']))
                dated.append((row['episode'], date, file, row))
            except ValueError:
                add('missing_field', file, row, 'date는 YYYY-MM-DD여야 한다.')
    for episode, date, file, row in dated:
        for earlier, earlier_date, earlier_file, earlier_row in dated:
            if earlier < episode and earlier_date > date:
                add('date_order', file, row, '앞 회차의 사건보다 명시 날짜가 이르다.', {'earlier': earlier_row['id'], 'earlier_file': earlier_file, 'date': str(date), 'earlier_date': str(earlier_date)})
    owners = {}
    for file, kind, row in confirmed:
        if kind == 'characters':
            for entry in row['possessions']:
                if entry['status'] != 'confirmed':
                    continue
                key = (entry['episode'], entry['item'])
                previous = owners.setdefault(key, row['id'])
                if previous != row['id']:
                    add('owner_conflict', file, row, f'{key[0]}회차 물건 {key[1]}의 소유자가 둘이다.', {'owners': [previous, row['id']], 'evidence': entry['evidence']})
        if kind == 'scene' and not row.get('flashback', False):
            for participant in row['participants']:
                target = ids.get(participant)
                if target and target[1] == 'characters':
                    person = target[2]
                    if person.get('status') == 'confirmed' and person.get('state') == 'dead' and type(person.get('death_episode')) is int and row['episode'] > person['death_episode']:
                        add('dead_character', file, row, f'사망 뒤 인물 {participant}이 참여한다.', {'death_episode': person['death_episode'], 'scene': row['evidence'], 'death': person['evidence']})
    latest = max((r['episode'] for _, k, r in confirmed if k == 'episode'), default=0)
    for file, kind, row in confirmed:
        if kind == 'foreshadow' and not row.get('resolved_episode') and not row.get('discarded_episode') and latest - row['setup_episode'] > foreshadow_limit:
            add('stale_foreshadow', file, row, f'회수·폐기 없이 {latest - row["setup_episode"]}회차가 지났다.', severity='warn')
    if episodes_text_dir:
        for path in sorted(Path(episodes_text_dir).iterdir()):
            if not re.fullmatch(r'E\d{3,}\.(md|txt)', path.name):
                continue
            raw = path.read_bytes()
            file = 'texts/' + path.name
            files[file] = hashlib.sha256(raw).hexdigest()
            text = raw.decode('utf-8-sig').replace('\r\n', '\n').replace('\r', '\n')
            counts = {'with_spaces': len(text), 'without_spaces': len(re.sub(r'\s', '', text))}
            if min_chars is not None and counts[count] < min_chars:
                add('short_episode', file, {'id': path.stem}, f'본문 {counts[count]}자가 하한 {min_chars}자보다 작다.', counts)
    return {'files': files, 'findings': findings, 'ok': not any(f['severity'] == 'error' for f in findings)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ledger_dir')
    parser.add_argument('--foreshadow-limit', type=int, default=30)
    parser.add_argument('--min-chars', type=int)
    parser.add_argument('--count', choices=('with_spaces', 'without_spaces'), default='without_spaces')
    parser.add_argument('--episodes-text-dir')
    report = check(**vars(parser.parse_args()))
    print(json.dumps(report, ensure_ascii=True))
    return 0 if report['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
