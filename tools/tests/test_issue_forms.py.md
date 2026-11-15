# test_issue_forms.py

Checks the GitHub issue forms in [`.github/ISSUE_TEMPLATE`](../../.github/ISSUE_TEMPLATE/bug_report.yml): the bug
report, the feature request and the chooser's `config.yml`. GitHub shows a form only when it follows its form schema
and leaves a broken one out of the chooser without telling the reporter, so the rules are checked here; and the bug
report names buttons, files and console commands of the game, so those are checked against the code that makes them.

```powershell
cd tools; python -m unittest discover -s tests -p test_issue_forms.py
```

| Test | Checks |
|---|---|
| every form follows GitHub's form schema | each form parses as YAML; only GitHub's top-level keys, with `name` (more than 3 characters, unique among the forms), `description` and `body`; `labels` a list of names; at least one field besides text; each element a known type (`markdown`, `textarea`, `input`, `dropdown`, `checkboxes`) with its required attributes and no unknown ones; ids of letters, digits, `-` and `_`, each once; each field label once; `markdown` without an id or validations; `validations.required` a boolean; dropdown options distinct and not empty, a `default` an index, and no `None` or `n/a` option beside a default; checkbox options with a label and an optional boolean `required` |
| the chooser | `config.yml` holds only `blank_issues_enabled` (a boolean) and `contact_links`, each with a `name`, an `https://` `url` and an `about` |
| the diagnostics panel and its button | the form names the main menu's panel and button by their English labels in `loader/proxy/ui/labels.json` (**RTX Remix diagnostics**, **Copy diagnostics**), the panel still sits at the bottom right (`mainmenu.js`), and the message after a crash still names its evidence folder |
| the log files | `native-loader\logs\loader.log` (`bootstrap.cpp`), `native-loader\logs\sessions` (`evidence.h`) and `rtx-remix\logs\remix-dxvk.log` (`evidence.cpp`) are where the form says |
| the lag report | the console command `nativeloader_lag_report` and its files `garrysmod\data\nativeloader\lag_report_client.txt` and `lag_report_server.txt` (`nativeloader_lag_report.lua`) |
| the start-up stall report | `garrysmod\data\native-loader\startup-stall.json` (the companion's engine guard script) and the watchdog's 90 seconds (`watchdog.h`) |
| the Workshop item and the repository | every GitHub link in the forms points into this repository, as the main menu's project link does, and every Workshop link names an item `dist/native-loader/config.json` allows |

The schema tests need PyYAML and are skipped without it (GitHub's runner installs only Pillow); the tests of what the
form names read the files as text and run everywhere. Reads only; exit 0 when every test passes.
