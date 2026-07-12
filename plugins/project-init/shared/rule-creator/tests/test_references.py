"""Tests for shared rule-creator deterministic scripts (single source).

stdlib only (subprocess + unittest). Each script encodes one error-prone
deterministic operation the rule-creator SKILL.md bodies must NOT improvise:
  - scan_templates.py  (파싱)  template frontmatter -> normalized candidate JSON
  - list_target_dirs.py (명령열) target depth1 dirs minus exclude set
  - render_rule.py     (치환)  strip frontmatter + substitute placeholders
                               + render bullets + temp_path default/normalize
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.normpath(os.path.join(HERE, ".."))


def run(script, *args, stdin=None):
    proc = subprocess.run(
        [sys.executable, os.path.join(REF, script), *args],
        input=stdin, capture_output=True, text=True,
    )
    return proc


class ScanTemplates(unittest.TestCase):
    def _skill(self, templates):
        d = tempfile.mkdtemp()
        tdir = os.path.join(d, "templates")
        os.makedirs(tdir)
        for name, content in templates.items():
            with open(os.path.join(tdir, name), "w", encoding="utf-8") as f:
                f.write(content)
        return d

    def test_parses_and_normalizes(self):
        skill = self._skill({
            "versioning.md": (
                "---\n"
                "label: 버전 관리 (versioning)\n"
                "description: 버전 규약 정의\n"
                "recommended: true\n"
                "inputs:\n"
                "  - name: scheme\n"
                "    header: 버전 규약\n"
                "    question: 규약?\n"
                "    options:\n"
                "      - label: SemVer\n"
                "        description: 표준\n"
                "dynamic_inputs:\n"
                "  - name: watch_directories\n"
                "    candidate_source: depth1_dirs_filtered\n"
                "    render: bullet_list\n"
                "---\n\n# body\n{{scheme}}\n"
            ),
        })
        proc = run("scan_templates.py", skill)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        data = json.loads(proc.stdout)
        self.assertEqual(len(data["candidates"]), 1)
        c = data["candidates"][0]
        self.assertEqual(c["id"], "versioning")
        self.assertEqual(c["label"], "버전 관리 (versioning)")
        self.assertTrue(c["recommended"])
        self.assertEqual(c["inputs"][0]["name"], "scheme")
        self.assertEqual(c["dynamic_inputs"][0]["name"], "watch_directories")

    def test_recommended_first(self):
        skill = self._skill({
            "aaa.md": "---\nlabel: A\n---\nbody\n",
            "zzz.md": "---\nlabel: Z\nrecommended: true\n---\nbody\n",
        })
        proc = run("scan_templates.py", skill)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        data = json.loads(proc.stdout)
        self.assertEqual([c["id"] for c in data["candidates"]], ["zzz", "aaa"])

    def test_missing_label_skipped(self):
        skill = self._skill({
            "good.md": "---\nlabel: Good\n---\nbody\n",
            "bad.md": "---\ndescription: no label\n---\nbody\n",
        })
        proc = run("scan_templates.py", skill)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        data = json.loads(proc.stdout)
        self.assertEqual([c["id"] for c in data["candidates"]], ["good"])
        self.assertIn("bad", [s["id"] for s in data["skipped"]])


class ListTargetDirs(unittest.TestCase):
    def test_filters_excludes_and_hidden(self):
        d = tempfile.mkdtemp()
        for name in ["src", "lib", ".git", "node_modules", "dist",
                     "build", "target", "docs"]:
            os.makedirs(os.path.join(d, name))
        # a file at depth1 must not appear
        with open(os.path.join(d, "README.md"), "w") as f:
            f.write("x")
        proc = run("list_target_dirs.py", d)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        dirs = json.loads(proc.stdout)
        self.assertEqual(dirs, ["docs", "lib", "src"])


class RenderRule(unittest.TestCase):
    def _template(self, content):
        fd, path = tempfile.mkstemp(suffix=".md")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        return path

    def _render(self, content, answers, *extra_args):
        tpl = self._template(content)
        proc = run("render_rule.py", tpl, *extra_args, stdin=json.dumps(answers))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout

    def test_strips_frontmatter(self):
        out = self._render("---\nlabel: X\n---\n# Title\nbody line\n", {})
        self.assertNotIn("label: X", out)
        self.assertIn("# Title", out)

    def test_scalar_substitution(self):
        out = self._render(
            "---\nlabel: X\n---\n규약 **{{scheme}}** 적용\n",
            {"scheme": "SemVer"},
        )
        self.assertIn("규약 **SemVer** 적용", out)
        self.assertNotIn("{{scheme}}", out)

    def test_missing_answer_preserves_placeholder(self):
        out = self._render(
            "---\nlabel: X\n---\n값 {{scheme}} 끝\n", {})
        self.assertIn("{{scheme}}", out)

    def test_empty_string_preserves_placeholder(self):
        out = self._render(
            "---\nlabel: X\n---\n값 {{scheme}} 끝\n", {"scheme": ""})
        self.assertIn("{{scheme}}", out)

    def test_bullet_list_render(self):
        out = self._render(
            "---\nlabel: X\n---\n목록:\n{{watch_directories}}\n끝\n",
            {"watch_directories": ["src", "lib"]},
        )
        self.assertIn("- `src`", out)
        self.assertIn("- `lib`", out)

    def test_bullet_list_empty_sentinel_default(self):
        out = self._render(
            "---\nlabel: X\n---\n목록:\n{{watch_directories}}\n끝\n",
            {"watch_directories": []},
        )
        self.assertIn("(대상 없음 — 검토 필요)", out)

    def test_bullet_list_empty_sentinel_arg(self):
        # 빈 목록 대체 문구는 스킬 고유 — 두 번째 인자로 전달한다.
        out = self._render(
            "---\nlabel: X\n---\n목록:\n{{watch_directories}}\n끝\n",
            {"watch_directories": []},
            "(워치 대상 없음 — 검토 필요)",
        )
        self.assertIn("(워치 대상 없음 — 검토 필요)", out)

    def test_temp_path_default_on_missing(self):
        # temp_path 는 미응답이어도 placeholder 보존이 아니라 기본값 .tmp/ 로 치환.
        out = self._render(
            "---\nlabel: X\n---\n경로 {{temp_path}} 끝\n", {})
        self.assertIn("경로 .tmp/ 끝", out)
        self.assertNotIn("{{temp_path}}", out)

    def test_temp_path_default_on_empty(self):
        out = self._render(
            "---\nlabel: X\n---\n경로 {{temp_path}} 끝\n", {"temp_path": ""})
        self.assertIn("경로 .tmp/ 끝", out)

    def test_temp_path_trailing_slash_normalized(self):
        out = self._render(
            "---\nlabel: X\n---\n경로 {{temp_path}}sub/ 끝\n",
            {"temp_path": ".scratch"},
        )
        self.assertIn("경로 .scratch/sub/ 끝", out)


if __name__ == "__main__":
    unittest.main()
