"""The GitHub issue forms in .github/ISSUE_TEMPLATE: valid for GitHub, and true about the game.

GitHub shows a form only when it follows its form schema; a broken one drops out of the template chooser without a
word to the reporter. These tests check the rules GitHub's documentation states for issue forms and for the chooser's
config.yml, and that what the bug report tells players to click, run or attach still exists in this repository: the
main menu's diagnostics panel and its button, the loader's log, the session evidence folders, Remix's log, the lag
report, the start-up stall report, the Workshop item and the repository's own address."""
import json
from pathlib import Path
import re
import unittest

try:
    import yaml
except ImportError:  # GitHub's runner installs only Pillow (build.yml); FormsTellTheTruth runs without PyYAML
    yaml = None

REPO = Path(__file__).resolve().parents[2]
FORMS = REPO / '.github' / 'ISSUE_TEMPLATE'
REPOSITORY = 'https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix'
WORKSHOP = 'https://steamcommunity.com/sharedfiles/filedetails/?id='
TOP = {'name', 'description', 'body', 'title', 'labels', 'assignees', 'projects', 'type'}
# type: (required attributes, optional attributes, validations it takes)
ELEMENTS = {
    'markdown': ({'value'}, set(), set()),
    'textarea': ({'label'}, {'description', 'placeholder', 'value', 'render'}, {'required'}),
    'input': ({'label'}, {'description', 'placeholder', 'value'}, {'required'}),
    'dropdown': ({'label', 'options'}, {'description', 'multiple', 'default'}, {'required'}),
    'checkboxes': ({'label', 'options'}, {'description'}, {'required'}),
}
ID = re.compile(r'[A-Za-z0-9_-]+')
MARKUP = re.compile(r'\*\*|__|`|\[[^\]]*\]\(')  # bold, code and links: shown raw in a checkbox label


def forms() -> list[Path]:
    return sorted(path for path in FORMS.glob('*.y*ml') if path.stem != 'config')


def text(path: str) -> str:
    return (REPO / path).read_text(encoding='utf-8')


@unittest.skipUnless(yaml, 'PyYAML is not installed')
class FormRules(unittest.TestCase):
    def test_every_form_follows_githubs_form_schema(self):
        self.assertTrue(forms(), 'no issue forms')
        names = set()
        for path in forms():
            with self.subTest(form=path.name):
                form = yaml.safe_load(path.read_text(encoding='utf-8'))
                self.assertIsInstance(form, dict)
                self.assertLessEqual(set(form), TOP, 'unknown top-level keys')
                for key in ('name', 'description'):
                    self.assertIsInstance(form.get(key), str, key)
                    self.assertTrue(form[key].strip(), key)
                self.assertGreater(len(form['name']), 3, 'GitHub hides a template whose name is 3 characters or fewer')
                self.assertNotIn(form['name'], names, 'two templates with one name')
                names.add(form['name'])
                labels = form.get('labels', [])
                self.assertIsInstance(labels, list)
                self.assertTrue(all(isinstance(label, str) and label.strip() for label in labels))
                body = form.get('body')
                self.assertIsInstance(body, list)
                self.assertTrue(any(isinstance(element, dict) and element.get('type') != 'markdown' for element in body),
                                'a form needs a field besides text')
                ids, field_labels = set(), set()
                for index, element in enumerate(body):
                    self.check_element(f'body[{index}]', element, ids, field_labels)

    def check_element(self, where, element, ids, labels):
        self.assertIsInstance(element, dict, where)
        kind = element.get('type')
        self.assertIn(kind, ELEMENTS, f'{where}: type')
        required, optional, validations = ELEMENTS[kind]
        self.assertLessEqual(set(element), {'type', 'id', 'attributes', 'validations'}, where)
        attributes = element.get('attributes')
        self.assertIsInstance(attributes, dict, where)
        self.assertLessEqual(required, set(attributes), f'{where}: missing attributes')
        self.assertLessEqual(set(attributes), required | optional, f'{where}: unknown attributes')
        for key in ('value', 'label', 'description', 'placeholder', 'render'):
            if key in attributes:
                self.assertIsInstance(attributes[key], str, f'{where}: {key}')
                self.assertTrue(attributes[key].strip(), f'{where}: {key}')
        if kind == 'markdown':
            self.assertNotIn('id', element, f'{where}: markdown takes no id')
            self.assertNotIn('validations', element, f'{where}: markdown takes no validations')
            return
        if 'id' in element:
            self.assertIsInstance(element['id'], str, where)
            self.assertRegex(element['id'], f'^{ID.pattern}$', where)
            self.assertNotIn(element['id'], ids, f'{where}: id used twice')
            ids.add(element['id'])
        self.assertNotIn(attributes['label'], labels, f'{where}: label used twice')
        labels.add(attributes['label'])
        rules = element.get('validations', {})
        self.assertIsInstance(rules, dict, where)
        self.assertLessEqual(set(rules), validations, f'{where}: validations')
        if 'required' in rules:
            self.assertIsInstance(rules['required'], bool, where)
        options = attributes.get('options')
        if kind == 'dropdown':
            self.assertIsInstance(options, list, where)
            self.assertTrue(options, f'{where}: no options')
            self.assertTrue(all(isinstance(option, str) and option.strip() for option in options), where)
            self.assertEqual(len(options), len(set(options)), f'{where}: options must be distinct')
            if 'default' in attributes:
                self.assertIsInstance(attributes['default'], int, where)
                self.assertIn(attributes['default'], range(len(options)), where)
                self.assertFalse({'None', 'n/a'} & set(options), f'{where}: None and n/a are not options with a default')
            if 'multiple' in attributes:
                self.assertIsInstance(attributes['multiple'], bool, where)
        if kind == 'checkboxes':
            self.assertIsInstance(options, list, where)
            self.assertTrue(options, f'{where}: no options')
            for option in options:
                self.assertIsInstance(option, dict, where)
                self.assertLessEqual(set(option), {'label', 'required'}, where)
                self.assertIsInstance(option.get('label'), str, where)
                self.assertTrue(option['label'].strip(), where)
                self.assertNotRegex(option['label'], MARKUP,
                                    f"{where}: GitHub's preview shows a checkbox label's Markdown as it is; links go "
                                    'into the description')
                self.assertIsInstance(option.get('required', False), bool, where)

    def test_the_chooser(self):
        config = yaml.safe_load((FORMS / 'config.yml').read_text(encoding='utf-8'))
        self.assertIsInstance(config, dict)
        self.assertLessEqual(set(config), {'blank_issues_enabled', 'contact_links'})
        self.assertIsInstance(config.get('blank_issues_enabled'), bool)
        links = config.get('contact_links', [])
        self.assertIsInstance(links, list)
        for link in links:
            with self.subTest(link=link.get('name') if isinstance(link, dict) else link):
                self.assertIsInstance(link, dict)
                self.assertEqual(set(link), {'name', 'url', 'about'})
                self.assertTrue(all(isinstance(value, str) and value.strip() for value in link.values()))
                self.assertTrue(link['url'].startswith('https://'), link['url'])


class FormsTellTheTruth(unittest.TestCase):
    """What the bug report tells players to click, run or attach exists in this repository."""

    def setUp(self):
        self.form = (FORMS / 'bug_report.yml').read_text(encoding='utf-8')

    def test_the_diagnostics_panel_and_its_button(self):
        english = json.loads(text('loader/proxy/ui/labels.json'))['en']
        self.assertIn(f"**{english['heading']}** panel at the bottom right", self.form)
        self.assertIn(f"**{english['copy']}** button", self.form)
        self.assertIn('position:fixed;right:18px;bottom:82px', text('loader/proxy/ui/mainmenu.js'),
                      'the panel is no longer where the form says')
        self.assertIn('exit_evidence', english, 'the message after a crash names its evidence folder')

    def test_the_log_files(self):
        self.assertIn(r'L"\\native-loader\\logs\\loader.log"', text('loader/proxy/bootstrap.cpp'))
        self.assertIn('kSessions = "native-loader/logs/sessions"', text('loader/core/include/nl/evidence.h'))
        self.assertIn('"rtx-remix/logs/remix-dxvk.log"', text('loader/core/src/evidence.cpp'))
        for path in (r'native-loader\logs\loader.log', r'native-loader\logs\sessions', r'rtx-remix\logs\remix-dxvk.log'):
            # a code span that ends in the path: from the game folder, or from the Steam library as the owner wrote it
            self.assertRegex(self.form, r'`(?:[^`\s]*\\)?' + re.escape(path) + '`')

    def test_the_lag_report(self):
        lua = text('companion/nativeloader/lua/autorun/nativeloader_lag_report.lua')
        self.assertIn('concommand.Add("nativeloader_lag_report",', lua)
        self.assertIn('local realm = SERVER and "server" or "client"', lua)
        self.assertIn('file.Write("nativeloader/lag_report_" .. realm .. ".txt"', lua)
        self.assertIn('`nativeloader_lag_report`', self.form)
        self.assertIn(r'`garrysmod\data\nativeloader\lag_report_client.txt` and `lag_report_server.txt`', self.form)

    def test_the_start_up_stall_report(self):
        self.assertIn('local REPORT = "native-loader/startup-stall.json"',
                      text('companion/nativeloader/lua/autorun/!!!!nativeloader_engine_guard.lua'))
        self.assertIn('kStallMs = 90000;', text('engine_guard/watchdog.h'))
        self.assertIn(r'after 90 seconds the game shows a message', self.form)
        self.assertIn(r'`garrysmod\data\native-loader\startup-stall.json`', self.form)

    def test_the_workshop_item_and_the_repository(self):
        allowed = json.loads(text('dist/native-loader/config.json'))['allow']['workshop']
        self.assertIn(f"'{REPOSITORY}'", text('loader/proxy/ui/mainmenu.js'), "the main menu's project link")
        for path in sorted(FORMS.glob('*.y*ml')):
            with self.subTest(file=path.name):
                content = path.read_text(encoding='utf-8')
                for url in re.findall(r'https://github\.com/[^\s)]+', content):
                    self.assertTrue(url == REPOSITORY or url.startswith((REPOSITORY + '/', REPOSITORY + '#')), url)
                for item in re.findall(re.escape(WORKSHOP) + r'(\d+)', content):
                    self.assertIn(item, allowed, 'a Workshop link to an item the loader does not allow')


if __name__ == '__main__':
    unittest.main()
