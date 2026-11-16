# test_runtime_imgui_formats.py

The gate scan of finding 10 of the repository review of 2026-11-16: no runtime patch
([runtime/README.md](../../runtime/README.md)) leaves a printf-style ImGui call whose format is a runtime value.
`ImGuiSplash` drew `rtx.welcomeMessage`, which any server can set through the Remix API, as `TextWrapped`'s format
(`%s%s...` read pointers off the stack); patch 0102 draws it with `"%s"`.

```powershell
cd tools; python -m unittest discover -s tests -p test_runtime_imgui_formats.py
```

The scan reads the patches in order and looks at the code they add (a call a later patch removes again is gone), in
C and C++ files other than Dear ImGui's and ImPlot's own vendored sources. It flags `ImGui::Text`, `TextWrapped`,
`TextDisabled`, `TextColored`, `BulletText`, `LabelText`, `SetTooltip`, `LogText`, `TreeNode(id, fmt)` and
`TreeNodeEx(id, flags, fmt)` calls whose format argument is not a string literal (nor a choice between two literals)
and that pass nothing after it. `KNOWN` lists the calls already in the series with the text each carries; the fork's
base commit, which no patch shows, has more of the same shape (the README's patch 0102 entry names them).

| Test | Checks |
|---|---|
| the scanner finds the splash format and passes safe calls | the old splash call and other runtime formats are found, across lines too; `"%s"`, literal formats with arguments, `TextUnformatted`, `TreeNode(label)`, a choice between literals, raw and `u8` literals, a format meant to take arguments and RemixGui's tooltips are not |
| no patch leaves a runtime format | every such call the series adds and keeps is in `KNOWN` |
| the known calls are still there | every `KNOWN` entry is still in the series (drop it when a patch removes it) |
| the splash draws the welcome message as text | patch 0102 replaces `TextWrapped(message.c_str())` with `TextWrapped("%s", message.c_str())` |

Reads only `runtime/patches`. Exit 0 when every test passes.
