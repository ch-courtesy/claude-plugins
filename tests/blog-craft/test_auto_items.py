import sys, unittest
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'plugins/blog-craft/skills/post-rubric/scripts'))
import auto_items

class StyleTests(unittest.TestCase):
    def test_new_items_and_empty_body(self):
        result = auto_items.check('')
        self.assertEqual([i['id'] for i in result], ['C18','C19','C20','C23','C24','C25'])
        self.assertEqual([i['score'] for i in result[-2:]], [2,2])

    def test_bad_style(self):
        text = '오늘은 다양한 효과적인 방법에 대해 알아보겠습니다. 도움이 되셨기를 바랍니다.\n' + '**' + '긴 문장 전체를 굵게 표시하면 읽을 때 강조할 지점을 찾기 어렵습니다.' + '**'
        self.assertEqual([i['score'] for i in auto_items.check(text)[-2:]], [0,0])

    def test_subheading_does_not_replace_body_for_style(self):
        self.assertEqual(auto_items.check('## 설정\n오늘은 오늘은 알아보겠습니다.')[-2]['score'], 0)
        self.assertEqual(auto_items.check('## 설정\n**' + '가' * 30 + '**')[-1]['score'], 0)

    def test_excluded_text(self):
        text = '---\ntitle: 오늘은\n---\n> 오늘은 **인용**\n```text\n오늘은 **코드**\n```\n`오늘은 **인라인**`\n[본문](https://example.com/오늘은)\n| 항목 | 값 |\n| --- | --- |\n| `오늘은 **코드 칸**` | 본문 |'
        self.assertEqual([i['score'] for i in auto_items.check(text)[-2:]], [2,2])

    def test_density_gate_counts_one_pattern_and_is_strict(self):
        text = '다양한 ' + '가' * 996
        self.assertEqual(auto_items.style_metrics(text)['candidates'], [])
        text = '다양한 다양한 ' + '가' * 992
        self.assertEqual(len(auto_items.style_metrics(text)['candidates']), 1)
        self.assertEqual(len(auto_items.style_metrics('오늘은 오늘은')['candidates']), 2)

    def test_bold_variants_and_sentence_penalty(self):
        self.assertEqual(len(auto_items.style_metrics('**핵심**과 __기능__을')['bold']), 2)
        text = '**' + '가' * 30 + '**' + ' 나' * 1000
        self.assertEqual(auto_items.check(text)[-1]['score'], 1)
        self.assertEqual(auto_items.check('**' + '가' * 29 + '**' + ' 나' * 1000)[-1]['score'], 2)

    def test_code_multiline_comments_links_and_line_numbers(self):
        text = '``오늘은\n**굵게**``\n<!-- 오늘은 ! -->\n[여기](https://example.com/오늘은)'
        metrics = auto_items.style_metrics(text)
        self.assertEqual(len(metrics['candidates']), 1)
        self.assertEqual(metrics['candidates'][0][0], 4)
        self.assertEqual(metrics['bold'], [])

    def test_score_boundaries(self):
        for length, expected in [(2000,2),(1999,1),(667,1),(666,0)]:
            text = '오늘은 ' + '가' * (length - 4)
            self.assertEqual(auto_items.check(text)[-2]['score'], expected)
        for length, expected in [(1000,2),(999,1),(334,1),(333,0)]:
            text = '**말**' + '가' * (length - 1)
            self.assertEqual(auto_items.check(text)[-1]['score'], expected)

if __name__ == '__main__': unittest.main()
