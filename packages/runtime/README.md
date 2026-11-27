# RTX Remix runtime part

The combined package puts `files/` under `native/payload/runtime/` in the GMA. The loader extracts it to
`native-loader/packages/gmod-rtx-remix/<version>_<generation>/runtime/`. The active generation contains
`d3d9.dll`, its dependencies and the two skies. The Standard sky reads `atmosphere/`. The experimental
Enhanced sky reads the following files beside that DLL.

| Folder in the active runtime | Contents |
|---|---|
| `numos/spirv/` | 41 compiled compute passes. The DLL checks each shader against its compiled pass table. |
| `numos/nightsky/` | The Milky Way, Moon, low-resolution starlight and star catalogue, with their original credits. |
| `numos/` and `numos/licenses/` | The NUMOS Apache-2.0 licence, copyright notice, third-party notices and six third-party licence texts. |

NUMOS is pinned at `41842c69e9281f197acff95263260a0149876007`. Its notices credit Kim2091 (Sparkles)
and the contributing projects. The night-sky credits give the attribution and terms for each dataset,
including CC BY-SA 3.0 IGO for the Milky Way and low-resolution starlight.
[LICENSE](files/numos/LICENSE), [NOTICE](files/numos/NOTICE), [third-party notices](files/numos/THIRD_PARTY_NOTICES.md),
[night-sky credits](files/numos/nightsky/CREDITS.md)

The tagged Meson install supplies the complete `numos/` folder. Local packages unpack the indexed
bytes under `files/`. The release workflow collects the same paths from its own tagged install.
[File index](files.json), [runtime build record](../../runtime/base.json)
