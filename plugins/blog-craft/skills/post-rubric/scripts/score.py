"""채점자 출력을 검증하고 절별 가중치로 100점 총점과 findings 를 만든다.

사용: python score.py --rubric <rubric.json> --post <글.md> --review <채점자 stdout 파일> --reviewer <codex|claude> [--out <결과.json>]

rubric.json 에서 "auto": true 인 항목은 채점자가 내지 않고 auto_items.py 가 원문에서 센다.

종료 코드: 0 성공, 1 채점자 출력 검증 실패(errors 를 채점자에게 돌려 다시 시킨다), 2 사용법·입력 파일 오류
"""
import argparse
import json
import re
import sys

import auto_items

MARKUP = re.compile(r"[*`]")
SPACE = re.compile(r"\s+")
NA_WARN = 6  # 20개 중 이만큼 N/A 면 남은 항목이 적어 점수가 쉽게 부풀어 경고한다


def normalize(text):
    # 채점자가 강조·코드 표시를 빼고 인용하는 경우가 많아 비교에서 둘 다 지운다
    return SPACE.sub(" ", MARKUP.sub("", text)).strip()


def extract_json(raw):
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        start, end = raw.find("{"), raw.rfind("}")
        if start < 0 or end <= start:
            raise ValueError("출력에서 JSON 객체를 찾지 못했다")
        data = json.loads(raw[start : end + 1])
    # 배열·문자열 JSON 이면 뒤에서 .get 이 예외로 끝나 errors 를 내지 못한다
    if not isinstance(data, dict):
        raise ValueError(f"JSON 객체가 아니라 {type(data).__name__} 이다")
    return data


def na_allowed(item, post_type):
    na = item["na"]
    if na == "never":
        return False
    if na == "any":
        return True
    return post_type in na


def validate(rubric, review, post_text):
    errors = []
    post_norm = normalize(post_text)
    types = rubric["types"]
    post_type = review.get("type")
    if post_type not in types:
        errors.append(f"type 이 {types} 중 하나가 아니다: {post_type!r}")

    def check_quote(label, quote):
        if quote and normalize(quote) not in post_norm:
            errors.append(f"{label} 의 인용이 글에 없다(그대로 옮겨야 한다): {quote[:80]!r}")

    check_quote("type_evidence", review.get("type_evidence", ""))

    auto_ids = {i["id"] for i in rubric["items"] if i.get("auto")}
    by_id = {}
    entries = review.get("items", [])
    if not isinstance(entries, list):
        errors.append(f"items 는 배열이어야 한다: {type(entries).__name__}")
        entries = []
    elif not all(isinstance(e, dict) for e in entries):
        errors.append("items 의 원소는 모두 객체여야 한다")
        entries = [e for e in entries if isinstance(e, dict)]
    for entry in entries:
        if entry.get("id") in auto_ids:
            continue  # 채점자가 자동 항목을 내도 거부하지 않고 버린다. 다시 시킬 이유가 없다
        if not isinstance(entry.get("evidence", ""), (str, type(None))):
            errors.append(f"{entry.get('id')} evidence 는 문자열이어야 한다")
            entry["evidence"] = ""
        if entry.get("id") in by_id:
            errors.append(f"{entry.get('id')} 가 두 번 나온다")
        by_id[entry.get("id")] = entry

    for item in rubric["items"]:
        cid = item["id"]
        if item.get("auto"):
            continue
        entry = by_id.get(cid)
        if entry is None:
            errors.append(f"{cid} 가 없다")
            continue
        score = entry.get("score")
        if score not in (0, 1, 2, None) or isinstance(score, bool):
            errors.append(f"{cid} score 는 0, 1, 2, null 중 하나여야 한다: {score!r}")
            continue
        if score is None and not na_allowed(item, post_type):
            cond = item.get("na_condition", "N/A 를 쓸 수 없는 항목")
            errors.append(f"{cid} 는 type={post_type} 에서 N/A 를 쓸 수 없다(조건: {cond}, 허용: {item['na']})")
        if score in (1, 2) and not entry.get("evidence"):
            errors.append(f"{cid} 는 {score}점인데 evidence 인용이 없다")
        check_quote(cid, entry.get("evidence", ""))

    unknown = set(by_id) - {i["id"] for i in rubric["items"]} - auto_ids
    if unknown:
        errors.append(f"기준에 없는 항목: {sorted(unknown)}")
    return errors


def compute(rubric, review, reviewer, post_text):
    auto_ids = {i["id"] for i in rubric["items"] if i.get("auto")}
    by_id = {e["id"]: e for e in review["items"] if e["id"] not in auto_ids}
    by_id.update({e["id"]: e for e in auto_items.check(post_text) if e["id"] in auto_ids})
    raw_sections = []
    for section in rubric["sections"]:
        scores = [by_id[i["id"]]["score"] for i in rubric["items"] if i["section"] == section["id"]]
        scored = [s for s in scores if s is not None]
        ratio = sum(scored) / (2 * len(scored)) if scored else None
        raw_sections.append((section, ratio))

    # 항목이 모두 N/A 인 절은 빼고, 남은 절의 가중치를 합이 100 이 되게 늘린다
    live_weight = sum(s["weight"] for s, r in raw_sections if r is not None)
    sections = []
    total = 0.0
    for section, ratio in raw_sections:
        if ratio is None:
            sections.append({"id": section["id"], "title": section["title"], "weight": 0, "score": None})
            continue
        weight = section["weight"] * 100 / live_weight
        points = weight * ratio
        total += points
        sections.append({"id": section["id"], "title": section["title"], "weight": round(weight, 1), "score": round(points, 1)})

    meta = {i["id"]: i for i in rubric["items"]}
    items = [
        {**by_id[i["id"]], "title": i["title"], "rules": i["rules"], "section": i["section"]}
        for i in rubric["items"]
    ]
    findings = [
        {
            "severity": "P2" if e["score"] == 0 else "P3",
            "category": "writing",
            "location": e.get("location") or "-",
            "issue": f"[{e['id']} {meta[e['id']]['title']}] {e.get('reason', '')}".strip(),
            "suggestion": e.get("fix", ""),
            "reviewer": reviewer,
        }
        for e in items
        if e["score"] is not None and e["score"] < 2
    ]
    na_ids = [e["id"] for e in items if e["score"] is None]
    warnings = [
        f"{e['id']} evidence 가 {len(e['evidence'])}자로 길다. 핵심 문장만 인용하면 검토가 쉽다"
        for e in items
        if len(e.get("evidence") or "") > 200
    ]
    if len(na_ids) >= NA_WARN:
        warnings.append(f"N/A 가 {len(na_ids)}개다({', '.join(na_ids)}). 남은 항목만으로 절 점수가 정해지므로 N/A 조건을 다시 확인한다")
    pass_line = rubric.get("pass_line")
    score = {
        "total": round(total),
        "pass_line": pass_line,
        "passed": None if pass_line is None else round(total) >= pass_line,
        "type": review["type"],
        "type_evidence": review.get("type_evidence", ""),
        "reviewer": reviewer,
        "rubric_version": rubric["version"],
        "sections": sections,
        "items": items,
        "na": na_ids,
        "not_scored": rubric["not_scored"],
        "warnings": warnings,
    }
    return score, findings


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--rubric", required=True)
    parser.add_argument("--post", required=True)
    parser.add_argument("--review", required=True)
    parser.add_argument("--reviewer", required=True)
    parser.add_argument("--out")
    args = parser.parse_args()

    try:
        with open(args.rubric, encoding="utf-8-sig") as f:
            rubric = json.load(f)
        with open(args.post, encoding="utf-8-sig") as f:
            post_text = f.read()
        with open(args.review, encoding="utf-8-sig") as f:
            raw = f.read()
    except OSError as e:
        print(json.dumps({"ok": False, "errors": [str(e)]}, ensure_ascii=False))
        return 2

    try:
        review = extract_json(raw)
    except ValueError as e:
        result = {"ok": False, "errors": [f"JSON 파싱 실패: {e}"]}
    else:
        errors = validate(rubric, review, post_text)
        if errors:
            result = {"ok": False, "errors": errors}
        else:
            score, findings = compute(rubric, review, args.reviewer, post_text)
            result = {"ok": True, "score": score, "findings": findings}

    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.out:
        with open(args.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text + "\n")
    print(text)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
