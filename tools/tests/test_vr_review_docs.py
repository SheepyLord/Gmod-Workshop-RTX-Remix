"""VR handover placement and preservation of main's shared decision index."""
from pathlib import Path
import difflib
import subprocess
import unittest
from unittest import mock
from types import SimpleNamespace

ROOT=Path(__file__).resolve().parents[2]


class ReviewDocsTests(unittest.TestCase):
    def test_agents_has_one_short_vr_status_outside_repo_map(self):
        text=(ROOT/'AGENTS.md').read_text(encoding='utf-8')
        vr=text.split('VR:',1)[1].split('## Repo map',1)[0]
        self.assertLess(len(vr.split()),110,'Q status history belongs in report/resume')
        self.assertIn('VR-V4-report.md',vr)
        self.assertEqual(text.split('## Repo map',1)[1].split('| Path | What |',1)[0].strip(),'')

    def test_round4_result_records_changed_setup_and_field_limits(self):
        report=(ROOT/'docs/handover/VR-V4-report.md').read_text(encoding='utf-8')
        self.assertIn('## Round 4 evidence corrections',report)
        section=report.split('## Round 4 evidence corrections',1)[1].split('## ',1)[0]
        for fact in ('261104','16 of 16','1.04..1.26','2.85..2.93','45736','14:30:44','52744','NVIDIA'):
            self.assertIn(fact,section)

    def test_unmerged_main_decision_does_not_change_baseline(self):
        current=(ROOT/'docs/decisions/README.md').read_text(encoding='utf-8')
        def run(command,**kwargs):
            if command[1]=='merge-base':return SimpleNamespace(returncode=0,stdout='abc123\n')
            extra='\n| [9999](future.md) | Unmerged decision | Accepted |\n' if command[2].startswith('main:') else ''
            return SimpleNamespace(returncode=0,stdout=current+extra)
        with mock.patch.object(subprocess,'run',side_effect=run):
            self.test_decision_index_preserves_main_and_adds_only_table_rows()

    def test_decision_index_preserves_main_and_adds_only_table_rows(self):
        base=subprocess.run(['git','merge-base','main','HEAD'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
        if base.returncode:self.skipTest('main ref unavailable in this checkout')
        run=subprocess.run(['git','show',base.stdout.strip()+':docs/decisions/README.md'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
        if run.returncode:self.skipTest('main ref unavailable in this checkout')
        before=run.stdout.splitlines();after=(ROOT/'docs/decisions/README.md').read_text(encoding='utf-8').splitlines()
        self.assertIn('| # | Decision | Status |',after)
        for op,a,b,c,d in difflib.SequenceMatcher(None,before,after,autojunk=False).get_opcodes():
            self.assertNotIn(op,('delete','replace'),'shared main index content was removed/rewritten')
            if op=='insert':
                for line in after[c:d]:self.assertRegex(line,r'^\| \[\d{4}\]\(.+\.md\) \| .+ \| .+ \|$')


if __name__=='__main__':unittest.main()
