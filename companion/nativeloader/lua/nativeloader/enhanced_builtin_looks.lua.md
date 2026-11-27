# enhanced_builtin_looks.lua

Supplies the Enhanced sky editor's nine built-in looks. Fair-weather cumulus, Broken cloud,
Altostratus sheet and Cirrus streaks correspond to Fair, Cloudy, Altostratus and Cirrus in NUMOS
`41842c6`, `src/weather.cpp`. Mackerel sky, Towering cumulus, Humid summer, High cirrus and After the rain
follow them in that order, with the starting values from Task E2. Each row has a translated label and a table of overrides.
[The editor](enhanced_editor.lua.md) applies these to the library defaults with both upper layers clear.

Usage is a client Lua include. It returns data, reads the companion's translation helper and performs
no file or option writes. There is no command or exit code.
