#!/usr/bin/env python3
"""project-init: 소비 프로젝트 훅 구조 표준 검사기 (결정적 10항목).

`shared/hook-standard/standard.md`가 정의하는 2계층 레이아웃·스크립트 계약 중
결정적으로 판정 가능한 항목(레이아웃·파일명·실행권한·셔뱅·settings 정합·lib 구조)을
파일시스템과 settings JSON 만으로 검사한다. 의미적 판정 항목(비차단 원칙 위배 소지,
과광 matcher, 위험 명령 등)은 이 도구가 다루지 않고 `standard.md`의 모델 판정 절을
기준으로 훅 스킬(create-hook/repair-hook)을 실행하는 에이전트가 채운다.

이 스크립트는 project-init 플러그인의 자체 자산이며 Python3 표준 라이브러리만 쓴다.

사용법:
    python3 hook_checker.py <소비 프로젝트의 .claude/hooks 디렉터리>

평가에 성공하면 stdout 에 JSON 을 내고 exit code 0 으로 끝난다. 발견된 결함은
종료 코드가 아니라 결과의 grade·blocker_count·major_count·minor_count 에 담긴다.
입력 오류(디렉터리 없음·읽기 불가)는 exit code 4.
"""

import datetime
import json
import os
import re
import sys

SCHEMA_VERSION = "1.0"

# Claude Code 훅 이벤트 — 핸들러 파일명은 이벤트명의 kebab-case + .sh.
EVENTS = [
    "PreToolUse", "PostToolUse", "UserPromptSubmit", "Notification",
    "Stop", "SubagentStop", "PreCompact", "SessionStart", "SessionEnd",
]
SHEBANG = "#!/bin/sh"
PLACEHOLDER = "${CLAUDE_PROJECT_DIR}"
SETTINGS_FILES = ("settings.json", "settings.local.json")

# (id, section, item, severity)
RULE_META = [
    ("L-EVENT-NAME", "레이아웃", "직속 파일은 이벤트명 kebab-case 핸들러", "BLOCKER"),
    ("S-EXEC-HANDLER", "스크립트 계약", "핸들러 실행권한", "BLOCKER"),
    ("G-REGISTERED", "settings 정합", "핸들러 파일마다 등록 존재", "BLOCKER"),
    ("G-FILE-EXISTS", "settings 정합", "등록된 핸들러 파일 실재", "BLOCKER"),
    ("L-NO-STRAY-SCRIPT", "레이아웃", "기능 스크립트는 lib/<command>/ 안", "MAJOR"),
    ("S-SHEBANG", "스크립트 계약", "모든 스크립트 셔뱅 #!/bin/sh", "MAJOR"),
    ("S-EXEC-LIB", "스크립트 계약", "lib 스크립트 실행권한", "MAJOR"),
    ("G-PLACEHOLDER", "settings 정합", "등록 경로 ${CLAUDE_PROJECT_DIR} 사용", "MAJOR"),
    ("G-ONE-HANDLER", "settings 정합", "이벤트당 핸들러 1개", "MAJOR"),
    ("L-LIB-STRUCTURE", "레이아웃", "lib/<command>/ 에 스크립트 존재", "MINOR"),
]


def kebab(event):
    return re.sub(r"(?<!^)(?=[A-Z])", "-", event).lower()


HANDLER_NAMES = {kebab(e) + ".sh": e for e in EVENTS}


def _scan(hooks_dir):
    """hooks 디렉터리를 (핸들러 후보, lib 스크립트, stray 스크립트, lib 디렉터리) 로 나눈다."""
    top, lib_scripts, stray, lib_dirs = [], [], [], []
    for root, dirs, files in os.walk(hooks_dir):
        dirs.sort()
        rel_root = os.path.relpath(root, hooks_dir)
        parts = [] if rel_root == "." else rel_root.split(os.sep)
        if len(parts) == 1 and parts[0] == "lib":
            lib_dirs.extend(os.path.join(root, d) for d in dirs)
        for name in sorted(files):
            path = os.path.join(root, name)
            if not parts:
                # 직속의 비스크립트 파일(README 등)은 핸들러 판정 대상이 아니다.
                if name.endswith(".sh"):
                    top.append(path)
            elif len(parts) == 2 and parts[0] == "lib":
                lib_scripts.append(path)
            elif parts[0] == "lib":
                # lib/<command>/ 보다 깊은 위치의 스크립트만 위반으로 본다(참조 파일은 허용).
                if name.endswith(".sh"):
                    stray.append(path)
            elif name.endswith(".sh"):
                stray.append(path)
    return top, lib_scripts, stray, lib_dirs


def _read_settings(hooks_dir):
    """hooks 디렉터리의 부모에서 settings 를 읽어 (이벤트, 명령) 등록 목록을 만든다.

    settings.json 과 settings.local.json 을 **둘 다** 읽되 병합 우선순위는 구현하지
    않는다 — "어느 파일에도 등록이 없음"만 위반으로 보아 과판정을 피한다.
    """
    parent = os.path.dirname(os.path.abspath(hooks_dir))
    regs = []
    for fname in SETTINGS_FILES:
        path = os.path.join(parent, fname)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        hooks = data.get("hooks") if isinstance(data, dict) else None
        if not isinstance(hooks, dict):
            continue
        for event, matchers in hooks.items():
            if not isinstance(matchers, list):
                continue
            for matcher in matchers:
                if not isinstance(matcher, dict):
                    continue
                for entry in matcher.get("hooks", []) or []:
                    if isinstance(entry, dict) and isinstance(entry.get("command"), str):
                        regs.append((event, entry["command"]))
    return regs


def _command_basename(command):
    """등록 명령 문자열에서 참조하는 핸들러 스크립트 파일명을 뽑는다.

    인용부호와 인터프리터 접두(`sh "<path>"`)를 견딘다 — `.sh` 로 끝나는 마지막
    토큰을 우선 쓰고, 없으면 첫 토큰의 basename 으로 폴백한다.
    """
    tokens = [t.strip("'\"") for t in command.strip().split()]
    if not tokens:
        return ""
    sh_tokens = [t for t in tokens if t.endswith(".sh")]
    return os.path.basename(sh_tokens[-1] if sh_tokens else tokens[0])


def _first_line(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.readline().rstrip("\n")
    except OSError:
        return ""


def evaluate(hooks_dir):
    top, lib_scripts, stray, lib_dirs = _scan(hooks_dir)
    regs = _read_settings(hooks_dir)
    res = {}

    # 레이아웃
    bad_names = [os.path.basename(p) for p in top
                 if os.path.basename(p) not in HANDLER_NAMES]
    res["L-EVENT-NAME"] = (not bad_names,
                           f"이벤트명이 아닌 직속 파일: {bad_names}" if bad_names
                           else f"핸들러 {len(top)}개 모두 이벤트명 kebab-case")
    rel_stray = [os.path.relpath(p, hooks_dir) for p in stray]
    res["L-NO-STRAY-SCRIPT"] = (not rel_stray,
                                f"lib/<command>/ 밖 기능 스크립트: {rel_stray}" if rel_stray
                                else "기능 스크립트가 모두 lib/<command>/ 안에 있음")
    empty_libs = [os.path.basename(d) for d in lib_dirs
                  if not any(os.path.dirname(s) == d and s.endswith(".sh")
                             for s in lib_scripts)]
    res["L-LIB-STRUCTURE"] = (not empty_libs,
                              f"스크립트 없는 lib command: {empty_libs}" if empty_libs
                              else f"lib command {len(lib_dirs)}개 스크립트 보유")

    # 스크립트 계약
    no_exec_top = [os.path.basename(p) for p in top if not os.access(p, os.X_OK)]
    res["S-EXEC-HANDLER"] = (not no_exec_top,
                             f"실행권한 없는 핸들러: {no_exec_top}" if no_exec_top
                             else "핸들러 실행권한 충족")
    no_exec_lib = [os.path.relpath(p, hooks_dir) for p in lib_scripts
                   if p.endswith(".sh") and not os.access(p, os.X_OK)]
    res["S-EXEC-LIB"] = (not no_exec_lib,
                         f"실행권한 없는 lib 스크립트: {no_exec_lib}" if no_exec_lib
                         else "lib 스크립트 실행권한 충족")
    bad_shebang = [os.path.relpath(p, hooks_dir)
                   for p in top + lib_scripts + stray
                   if p.endswith(".sh") and _first_line(p).strip() != SHEBANG]
    res["S-SHEBANG"] = (not bad_shebang,
                        f"셔뱅이 '{SHEBANG}' 가 아닌 스크립트: {bad_shebang}" if bad_shebang
                        else f"모든 스크립트 셔뱅 {SHEBANG}")

    # settings 정합 — 등록은 (이벤트, 핸들러 파일명) 쌍으로 비교한다: 같은 파일명이라도
    # 다른 이벤트에 등록된 것은 정합이 아니다(훅은 등록된 이벤트에서만 실행된다).
    registered = {(e, _command_basename(c)) for e, c in regs}
    unregistered = [os.path.basename(p) for p in top
                    if (HANDLER_NAMES.get(os.path.basename(p)),
                        os.path.basename(p)) not in registered]
    res["G-REGISTERED"] = (not unregistered,
                           f"settings 에 자기 이벤트로 등록 없는 핸들러: {unregistered}" if unregistered
                           else f"핸들러 {len(top)}개 모두 자기 이벤트로 등록됨")
    existing = {os.path.basename(p) for p in top}
    missing = sorted({_command_basename(c) for _, c in regs
                      if _command_basename(c) not in existing})
    res["G-FILE-EXISTS"] = (not missing,
                            f"등록됐으나 파일 부재: {missing}" if missing
                            else f"등록 {len(regs)}건 모두 파일 실재")
    no_ph = sorted({c for _, c in regs if PLACEHOLDER not in c})
    res["G-PLACEHOLDER"] = (not no_ph,
                            f"{PLACEHOLDER} 미사용 등록: {no_ph}" if no_ph
                            else f"등록 경로 모두 {PLACEHOLDER} 사용")
    per_event = {}
    for event, command in regs:
        per_event.setdefault(event, set()).add(_command_basename(command))
    multi = sorted(f"{e}: {sorted(v)}" for e, v in per_event.items() if len(v) > 1)
    res["G-ONE-HANDLER"] = (not multi,
                            f"이벤트당 핸들러 2개 이상: {multi}" if multi
                            else "이벤트당 핸들러 1개")

    checks = []
    for cid, section, item, severity in RULE_META:
        passed, evidence = res[cid]
        checks.append({
            "id": cid, "section": section, "item": item,
            "check_type": "rule", "severity": severity,
            "passed": bool(passed), "evidence": evidence,
        })
    return {
        "schema_version": SCHEMA_VERSION,
        "evaluated_at": datetime.datetime.now(datetime.timezone.utc)
                                 .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "hooks_dir": os.path.abspath(hooks_dir),
        "checks": checks,
        **_grade(checks),
    }


def _grade(checks):
    b = sum(1 for c in checks if not c["passed"] and c["severity"] == "BLOCKER")
    mj = sum(1 for c in checks if not c["passed"] and c["severity"] == "MAJOR")
    mn = sum(1 for c in checks if not c["passed"] and c["severity"] == "MINOR")
    if b >= 1:
        grade = "F"
    elif mj == 0:
        grade = "S"
    elif mj <= 2:
        grade = "A"
    elif mj <= 4:
        grade = "B"
    else:
        grade = "C"
    return {"grade": grade, "blocker_count": b, "major_count": mj, "minor_count": mn}


def main(argv):
    if not argv:
        sys.stderr.write("usage: hook_checker.py <.claude/hooks 디렉터리>\n")
        return 4
    hooks_dir = argv[0]
    if not os.path.isdir(hooks_dir) or not os.access(hooks_dir, os.R_OK):
        sys.stderr.write(f"error: 디렉터리가 없거나 읽을 수 없습니다: {hooks_dir}\n")
        return 4
    print(json.dumps(evaluate(hooks_dir), ensure_ascii=False, indent=2))
    return 0  # 평가 성공. 발견된 결함은 grade·*_count 에 있다(종료 코드 아님).


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
