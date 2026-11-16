"""No runtime patch leaves a printf-style ImGui call whose format is a runtime value (the review of 2026-11-16,
finding 10: ImGuiSplash drew rtx.welcomeMessage, which any server can set, as TextWrapped's format).

Scans the code the runtime patches add (runtime/patches, in order; a call a later patch removes again is gone) for
ImGui::Text, TextWrapped, TextDisabled, TextColored, BulletText, LabelText, SetTooltip, LogText, TreeNode and TreeNodeEx
calls whose format argument is not a string literal and that pass nothing after it. The calls already in the series
that carry only fixed or driver text are listed below with the reason; anything else fails."""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import runtime_patch_text as patches  # noqa: E402

# ImGui functions whose format is the n-th argument (from 0), when the call has at least `least` arguments.
PRINTF = {
    'Text': (0, 1), 'TextWrapped': (0, 1), 'TextDisabled': (0, 1), 'BulletText': (0, 1), 'SetTooltip': (0, 1),
    'LogText': (0, 1), 'TextColored': (1, 2), 'LabelText': (1, 2), 'TreeNode': (1, 2), 'TreeNodeEx': (2, 3),
}
CALL = re.compile(r'\bImGui::(' + '|'.join(sorted(PRINTF, key=len, reverse=True)) + r')\s*\(')
SOURCE = re.compile(r'\.(c|cc|cpp|cxx|h|hh|hpp|inl)$')
# Dear ImGui's and ImPlot's own sources (their demo windows among them), vendored as they are upstream.
VENDORED = re.compile(r'(^|/)(imgui|imgui_demo|imgui_draw|imgui_internal|imgui_tables|imgui_widgets|imconfig|implot\w*|imstb_\w+)\.(cpp|h)$')
LITERAL = re.compile(r'^(u8|L|u|U)?"|^(u8|L|u|U)?R"')
TERNARY_OF_LITERALS = re.compile(r'^[^?]+\?\s*"(?:[^"\\]|\\.)*"\s*:\s*"(?:[^"\\]|\\.)*"$', re.S)

# Calls the series already has, each with the text it carries: none can come from a server, a Workshop item or a
# mod. (path, the call with its whitespace collapsed): reason. (The fork's base commit, which no patch shows, has a
# dozen more of the same kind; runtime/README.md, patch 0102, lists them.)
KNOWN = {
    ('src/dxvk/imgui/dxvk_imgui_development_settings.cpp', 'ImGui::Text(resourceAliasingQueryText.c_str())'):
        "the developer menu's aliasing query result, built from literals (upstream, patch 0093)",
}


def split_arguments(text: str, start: int):
    """The arguments of the call whose '(' ends at text[start - 1], or None when the text ends inside the call."""
    depth, args, current, i, quote = 0, [], '', start, None
    while i < len(text):
        c = text[i]
        if quote:
            current += c
            if c == '\\' and i + 1 < len(text):
                current += text[i + 1]
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in '"\'':
            quote = c
            current += c
        elif c in '([{':
            depth += 1
            current += c
        elif c in ')]}':
            if depth == 0:
                args.append(current.strip())
                return [a for a in args if a] if args != [''] else []
            depth -= 1
            current += c
        elif c == ',' and depth == 0:
            args.append(current.strip())
            current = ''
        elif c == '/' and text.startswith('//', i):
            i = text.find('\n', i)
            if i < 0:
                return None
            continue
        else:
            current += c
        i += 1
    return None


def runtime_format(text: str, match):
    """The call `match` starts, collapsed, when its format is a runtime value; else None."""
    function = match.group(1)
    args = split_arguments(text, match.end())
    if args is None:
        return None
    index, least = PRINTF[function]
    if len(args) < least or len(args) != index + 1:
        return None  # TreeNode(label), TreeNodeEx(label, flags): no format; arguments after the format: one meant
    fmt = args[index]
    if LITERAL.match(fmt) or TERNARY_OF_LITERALS.match(fmt):
        return None
    return ' '.join(('ImGui::' + function + '(' + ', '.join(args) + ')').split())


def runtime_formats(text: str):
    """[(function, the call collapsed)] for the printf-style calls in `text` whose format is a runtime value."""
    found = []
    for match in CALL.finditer(text):
        call = runtime_format(text, match)
        if call is not None:
            found.append((match.group(1), call))
    return found


def series_calls():
    """{(path, call): patch name} for every such call the series adds and keeps (a later patch may remove one)."""
    live = {}
    for patch_path in patches.patch_paths():
        for path, block in patches.file_blocks(patches.read(patch_path)).items():
            if not SOURCE.search(path) or VENDORED.search(path):
                continue
            hunks = patches.hunks(block)
            removed = {call for _, call in runtime_formats(
                '\n'.join(line[1:] for _, body in hunks for line in body if line.startswith('-')))}
            for key in [key for key in live if key[0] == path and key[1] in removed]:
                del live[key]
            for _, body in hunks:
                new_side = [line[1:] for line in body if line[0] in ' +']
                added = [line[0] == '+' for line in body if line[0] in ' +']
                text = '\n'.join(new_side)
                for match in CALL.finditer(text):
                    if added[text.count('\n', 0, match.start())]:
                        call = runtime_format(text, match)
                        if call is not None:
                            live[(path, call)] = patch_path.name
    return live


class ImGuiFormatScanTests(unittest.TestCase):
    def test_the_scanner_finds_the_splash_format_and_passes_safe_calls(self):
        self.assertEqual(runtime_formats('ImGui::TextWrapped(message.c_str());'),
                         [('TextWrapped', 'ImGui::TextWrapped(message.c_str())')])
        self.assertEqual(runtime_formats('ImGui::TextColored(red,\n  text.c_str());'),
                         [('TextColored', 'ImGui::TextColored(red, text.c_str())')])
        self.assertEqual(runtime_formats('ImGui::TreeNode(id, label.c_str());'), [('TreeNode', 'ImGui::TreeNode(id, label.c_str())')])
        for safe in ('ImGui::TextWrapped("%s", message.c_str());', 'ImGui::Text("%d items", count);',
                     'ImGui::TextUnformatted(message.c_str());', 'ImGui::TreeNode(modName.c_str());',
                     'ImGui::TreeNodeEx(label, flags);', 'ImGui::Text(active ? "Running." : "Stopped.");',
                     'ImGui::Text(u8"日本語");', 'ImGui::SetTooltip(R"(raw)");', 'ImGui::LabelText("label", "%s", value);',
                     'ImGui::Text(fmt, value);', 'RemixGui::SetTooltipToLastWidgetOnHover(text.c_str());',
                     'ImGui::Text("a, (b)");'):
            self.assertEqual(runtime_formats(safe), [], safe)

    def test_no_patch_leaves_a_runtime_format(self):
        live = series_calls()
        unknown = {key: name for key, name in live.items() if key not in KNOWN}
        self.assertEqual(unknown, {}, 'a printf-style ImGui call takes a runtime value as its format: draw text with '
                                      'ImGui::TextUnformatted or a "%s" format, or list it in KNOWN with the text it carries')

    def test_the_known_calls_are_still_there(self):
        live = series_calls()
        self.assertEqual(sorted(key for key in KNOWN if key not in live), [], 'a listed call is gone: drop it from KNOWN')

    def test_the_splash_draws_the_welcome_message_as_text(self):
        patch = patches.read(patches.one_patch(102))
        path = 'src/dxvk/imgui/dxvk_imgui_splash.cpp'
        self.assertIn('ImGui::TextWrapped(message.c_str());', patches.removed_lines(patch, path))
        self.assertIn('ImGui::TextWrapped("%s", message.c_str());', patches.added_lines(patch, path))
        self.assertEqual(runtime_formats(patches.added_lines(patch, path)), [])


if __name__ == '__main__':
    unittest.main()
