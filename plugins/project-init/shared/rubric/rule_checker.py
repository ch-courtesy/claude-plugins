#!/usr/bin/env python3
"""project-init: SKILL.md 규칙 기반 검사기 (17항목).

`shared/rubric/criteria.md`의 6개 섹션 중 결정적으로 판정 가능한 17개 항목을
정규식·카운트·AST(py_compile/bash -n)로 검사한다. 의미적 판정 13개 항목은 이
도구가 다루지 않고 `repair-skill`(또는 `create-skill`)을 실행하는 에이전트가
`criteria.md`의 모델 항목 정의를 기준으로 채운다.

이 스크립트는 project-init 플러그인의 자체 자산이며 다른 플러그인에 런타임
의존하지 않는다.

외부 의존성: frontmatter YAML 파싱·유효성 판정은 yq(mikefarah)에, 스크립트
syntax 검사는 bash 에 위임한다.

사용법:
    python3 rule_checker.py <SKILL.md 경로>
    python3 rule_checker.py all [repo_root]

평가에 성공하면 stdout 에 JSON 을 내고 exit code 0 으로 끝난다. 발견된 결함은
종료 코드가 아니라 각 결과의 grade·blocker_count·major_count·minor_count 에 담긴다.
입력 오류(단일 모드에서 경로가 없거나 읽을 수 없음)는 exit code 4, yq 미설치는 exit code 5.
"""

import datetime
import glob
import json
import os
import py_compile
import re
import shutil
import subprocess
import sys

SCHEMA_VERSION = "1.0"
ALLOWED_KEYS = {"name", "description", "allowed-tools", "argument-hint"}
RESERVED_WORDS = re.compile(r"(claude|anthropic)", re.IGNORECASE)
NAME_FORMAT = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
# 대문자로 시작하는 XML 류 태그(여는/닫는, 속성 포함). 소문자 HTML(<br>,<code>)은 오탐 방지를 위해 제외.
XML_TAG = re.compile(r"</?[A-Z][A-Z0-9_-]*(?:\s[^>]*)?>")
TIMING = re.compile(
    r"(\buse\b|when|whenever|before|after|during|trigger|"
    r"사용|활성화|요청|할 때|할때|때|시작)",
    re.IGNORECASE,
)
ARG_REF = re.compile(r"\$ARGUMENTS|\{\{\s*args?\s*\}\}")
PLACEHOLDER = re.compile(r"\[TODO\]|\[PLACEHOLDER\]|\bFIXME\b|\{\{[^}]+\}\}")
# 값이 $VAR / ${VAR} / <...> / {...} 로 시작하지 않는 평문 시크릿.
SECRET_RE = re.compile(
    r"(?i)(password|passwd|secret|api[_-]?key|access[_-]?key|token)\s*[=:]\s*"
    r"['\"]?(?![$<{*])[A-Za-z0-9_\-/+.]{8,}"
)
DESTRUCTIVE = re.compile(
    r"(rm\s+-[rf]+|rm\s+-[rf]+[rf]|git\s+push\s+--force|push\s+-f\b|"
    r"DROP\s+TABLE|truncate|mkfs|dd\s+if=)",
    re.IGNORECASE,
)

# (id, section, item, severity) — 검사 함수는 _CHECKS 에서 id 로 연결.
RULE_META = [
    ("S-YAML", "구조", "YAML 파싱 가능", "BLOCKER"),
    ("S-NAME-FORMAT", "구조", "name kebab-case·≤64자", "BLOCKER"),
    ("S-NAME-FOLDER", "구조", "name과 폴더명 일치", "BLOCKER"),
    ("S-DESC-LEN", "구조", "description 1-1024자", "BLOCKER"),
    ("S-NO-XML", "구조", "본문에 XML 태그 없음", "BLOCKER"),
    ("S-ALLOWED-KEYS", "구조", "허용 키만 사용", "MAJOR"),
    ("S-RESERVED", "구조", "예약어(claude/anthropic) 제외", "MAJOR"),
    ("S-README", "구조", "README.md 폴더 내 존재", "MINOR"),
    ("T-BODY-ONLY", "트리거", "Body-only 안티패턴 없음", "BLOCKER"),
    ("T-ARG-HINT", "트리거", "$ARGUMENTS 사용 시 argument-hint", "MINOR"),
    ("C-LENGTH", "콘텐츠", "본문 500줄 이하", "MINOR"),
    ("R-TOC", "리소스", "100줄+ reference 목차", "MINOR"),
    ("R-SYNTAX", "리소스", "스크립트 syntax 유효", "MAJOR"),
    ("R-SCRIPTPATH", "리소스", "scripts 경로 명시", "MINOR"),
    ("R-PLACEHOLDER", "리소스", "placeholder/TODO 잔재 없음", "MINOR"),
    ("SEC-SECRET", "안전성", "평문 secret 없음", "BLOCKER"),
    ("SEC-DESTRUCTIVE", "안전성", "destructive allowed-tools 없음", "BLOCKER"),
]


def parse_frontmatter(text):
    """첫 ---...--- frontmatter 를 (dict, body, ok) 로 반환.

    펜스 구간을 떼어 yq(mikefarah)로 진짜 YAML 파싱한다 — 손수 만든 파서 대신
    실제 YAML 파서가 유효성을 판정하므로 인용·이스케이프·주석 같은 문법 엣지를 정확히 다룬다.
    펜스가 없거나 닫히지 않거나 yq 파싱이 실패하면(유효하지 않은 YAML) ok=False.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text, False
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, "", False
    block = "\n".join(lines[1:end])
    body = "\n".join(lines[end + 1:])
    proc = subprocess.run(
        ["yq", "eval", "-o=json", "-"],
        input=block, capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return {}, body, False  # 유효하지 않은 YAML
    out = proc.stdout.strip()
    try:
        fm = json.loads(out) if out and out != "null" else {}
    except json.JSONDecodeError:
        return {}, body, False
    if not isinstance(fm, dict):
        return {}, body, False  # 매핑이 아니면 frontmatter 로 부적합
    return fm, body, True


def _ref_files(skill_dir, exts):
    refs = os.path.join(skill_dir, "references")
    out = []
    if os.path.isdir(refs):
        for name in sorted(os.listdir(refs)):
            if any(name.endswith(e) for e in exts):
                out.append(os.path.join(refs, name))
    return out


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def evaluate(skill_path):
    skill_dir = os.path.dirname(skill_path)
    text = _read(skill_path)
    fm, body, fm_ok = parse_frontmatter(text)
    name = fm.get("name") if isinstance(fm.get("name"), str) else None
    desc = fm.get("description") if isinstance(fm.get("description"), str) else None
    tools = fm.get("allowed-tools") if isinstance(fm.get("allowed-tools"), list) else []

    res = {}

    # 구조
    res["S-YAML"] = (fm_ok and bool(fm), "frontmatter 파싱 성공" if fm_ok and fm
                     else "frontmatter 펜스/구문 파싱 실패")
    if name is None:
        res["S-NAME-FORMAT"] = (False, "name 키 없음")
    else:
        ok = bool(NAME_FORMAT.match(name)) and len(name) <= 64
        res["S-NAME-FORMAT"] = (ok, f"name='{name}' (len={len(name)})")
    folder = os.path.basename(skill_dir)
    res["S-NAME-FOLDER"] = (name == folder, f"name='{name}' vs 폴더='{folder}'")
    if desc is None:
        res["S-DESC-LEN"] = (False, "description 키 없음")
    else:
        res["S-DESC-LEN"] = (1 <= len(desc) <= 1024, f"description {len(desc)}자")
    xml = XML_TAG.search(body)
    res["S-NO-XML"] = (xml is None,
                       f"대문자 XML 태그 '{xml.group(0)}' 발견" if xml else "XML 태그 없음")
    extra = sorted(set(fm.keys()) - ALLOWED_KEYS)
    res["S-ALLOWED-KEYS"] = (not extra, f"허용 외 키: {extra}" if extra else "허용 키만 사용")
    rsv = RESERVED_WORDS.search(name) if name else None
    res["S-RESERVED"] = (rsv is None, f"name에 예약어 '{rsv.group(0)}'" if rsv else "예약어 없음")
    readme = os.path.exists(os.path.join(skill_dir, "README.md"))
    res["S-README"] = (readme, "README.md 존재" if readme else "README.md 부재")

    # 트리거
    if not desc or len(desc) < 50:
        res["T-BODY-ONLY"] = (True, "description 길이 위임(S-DESC-LEN)")
    else:
        desc_t = bool(TIMING.search(desc))
        body_t = bool(TIMING.search(body))
        bad = (not desc_t) and body_t
        res["T-BODY-ONLY"] = (not bad,
                              "시점 정보가 본문에만 있음" if bad else "description에 시점 정보 있음")
    if ARG_REF.search(body):
        has_hint = "argument-hint" in fm
        res["T-ARG-HINT"] = (has_hint,
                             "argument-hint 있음" if has_hint else "$ARGUMENTS 사용하나 argument-hint 없음")
    else:
        res["T-ARG-HINT"] = (True, "$ARGUMENTS 미사용")

    # 콘텐츠
    nlines = len(body.split("\n"))
    res["C-LENGTH"] = (nlines <= 500, f"본문 {nlines}줄")

    # 리소스
    res["R-TOC"] = _check_toc(skill_dir)
    res["R-SYNTAX"] = _check_syntax(skill_dir)
    res["R-SCRIPTPATH"] = _check_scriptpath(skill_dir, body)
    ph = PLACEHOLDER.search(body)
    res["R-PLACEHOLDER"] = (ph is None,
                            f"잔재 '{ph.group(0)}' 발견" if ph else "placeholder/TODO 없음")

    # 안전성
    res["SEC-SECRET"] = _check_secret(skill_dir, body)
    dtool = next((t for t in tools if isinstance(t, str) and DESTRUCTIVE.search(t)), None)
    res["SEC-DESTRUCTIVE"] = (dtool is None,
                             f"destructive 도구 '{dtool}'" if dtool else "destructive 없음")

    checks = []
    for cid, section, item, severity in RULE_META:
        passed, evidence = res[cid]
        checks.append({
            "id": cid, "section": section, "item": item,
            "check_type": "rule", "severity": severity,
            "passed": bool(passed), "evidence": evidence,
        })
    return {
        "skill_path": skill_path,
        "skill_name": name or os.path.basename(skill_dir),
        "checks": checks,
        **_grade(checks),
    }


def _check_toc(skill_dir):
    bad = []
    for path in _ref_files(skill_dir, (".md",)):
        content = _read(path)
        if len(content.split("\n")) > 100:
            headers = len(re.findall(r"(?m)^#{1,3}\s+\S", content))
            if headers < 3:
                bad.append(os.path.basename(path))
    return (not bad, f"목차 부재: {bad}" if bad else "100줄+ 참고문서 목차 충족")


def _check_syntax(skill_dir):
    errors = []
    for path in _ref_files(skill_dir, (".py",)):
        try:
            py_compile.compile(path, doraise=True)
        except py_compile.PyCompileError as e:
            errors.append(f"{os.path.basename(path)}: {e.msg}")
    for path in _ref_files(skill_dir, (".sh",)):
        r = subprocess.run(["bash", "-n", path], capture_output=True, text=True)
        if r.returncode != 0:
            errors.append(f"{os.path.basename(path)}: {r.stderr.strip()}")
    return (not errors, f"syntax 오류: {errors}" if errors else "스크립트 syntax 유효")


def _check_scriptpath(skill_dir, body):
    scripts = _ref_files(skill_dir, (".sh", ".py"))
    missing = [os.path.basename(p) for p in scripts
               if os.path.basename(p) not in body and "references/" not in body]
    if not scripts:
        return (True, "스크립트 없음")
    return (not missing, f"본문 미언급: {missing}" if missing else "scripts 경로 본문 명시")


def _check_secret(skill_dir, body):
    sources = [("본문", body)]
    for path in _ref_files(skill_dir, (".py", ".sh")):
        sources.append((os.path.basename(path), _read(path)))
    for label, content in sources:
        m = SECRET_RE.search(content)
        if m:
            return (False, f"{label}에서 평문 secret 패턴 '{m.group(1)}' 발견")
    return (True, "평문 secret 없음")


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


def _find_skills(repo_root):
    pattern = os.path.join(repo_root, "plugins", "*", "skills", "*", "SKILL.md")
    return sorted(glob.glob(pattern))


def main(argv):
    if not shutil.which("yq"):
        sys.stderr.write(
            "error: yq (mikefarah) 가 필요합니다 — frontmatter YAML 파싱용. "
            "설치: https://github.com/mikefarah/yq/releases\n"
        )
        return 5
    if not argv or argv[0] == "all":
        repo_root = argv[1] if len(argv) > 1 else os.getcwd()
        paths = _find_skills(repo_root)
    else:
        path = argv[0]
        if not os.path.isfile(path) or not os.access(path, os.R_OK):
            sys.stderr.write(f"error: 파일이 없거나 읽을 수 없습니다: {path}\n")
            return 4
        paths = [path]
    results = [evaluate(p) for p in paths]
    grades = {g: 0 for g in "SABCF"}
    for r in results:
        grades[r["grade"]] += 1
    out = {
        "schema_version": SCHEMA_VERSION,
        "evaluated_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "results": results,
        "summary": {"total_skills": len(results), "grades": grades},
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0  # 평가 성공. 발견된 결함은 grade·*_count 에 있다(종료 코드 아님).


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
