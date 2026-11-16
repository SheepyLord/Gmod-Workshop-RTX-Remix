# 0233: The Mesh Separator selects in its editor only

- Status: Accepted 2026-11-16 (the user's request after testing the separator; the checks in the report)
- Decided by: the user ("Instead of drawing overlay in world, makes it directly open the editor when left click, skip
  the in world overlay entirely. Remove the in world overlay. Thus the slow overlay issue is mitigated."); how it is
  built was the agent's choice.
- Supersedes in part: [0232](0232-the-mesh-separator.md): its clicks in the world (decision 2's piece, part and brush
  under the crosshair) and the highlight on the model.
- Report: [mesh-separator-report.md](../handover/mesh-separator-report.md), its last section.

## Context

ADR 0232's tool selected in the world: a left click added the piece under the crosshair (or its whole part, or painted
with a brush), a right click took it away, reload opened the editor, and the selection and the piece under the aim were
drawn on the model. Under RTX Remix, which draws such meshes as a white coating, they were drawn on the screen instead:
one `surface.DrawPoly`, one draw call, a triangle, at most about 6,000 a frame. Its cost in the PoC (gm_construct, RTX
on, 1920x1080; [RESEARCH](../RESEARCH.md)):

| Selection | The overlay's hook, average | Frame time |
|---|---|---|
| The oil drum, 252 triangles | 1.5 ms | 16.6 ms |
| A citizen ragdoll's body, 4,427 triangles | 22.9 ms | 37.3 ms |
| All of a character, 209,152 triangles (about 6,000 drawn) | 50.5 ms | 65.7 ms |

The editor already selects every way (a piece, a part, the brush, a box, a lasso, the parts list) on its own picture of
the model, which Remix draws as interface.

## Decision

1. **A left click opens the editor** for the model aimed at, or for the model being worked on when the aim passes its
   body (a hairpin outside a ragdoll's physics hull). The server checks the click as before (`S.MayUse`: owners and
   administrators, `mmdhl_separator_enabled`). The piece is selected in the editor.
2. **Nothing is drawn on the model in the world**, with or without RTX: no selection, no piece under the aim, no brush.
   The selection is drawn in the editor only.
3. **Right click and reload do nothing**; the tool's information shows the left click alone.
4. **The tool's panel** keeps the status, Open the editor, Clear, the name, the shape, the physics, freeze, place and
   Detach. The way a click selects and the brush size leave it (the editor has both); the editor keeps its way to
   select for the next time it opens (`mmdhl_separator_mode`).
5. **The message to the client keeps its action field**: the server sends 3 (the editor), and a client opens the editor
   whatever an older server's click sends.

## Consequences

- The tool costs the world nothing, whatever is selected: with all of the character selected and the tool out, frames
  took 15.5 ms in the PoC (65.7 ms with the overlay).
- Outside RTX the selection is no longer shown on the model either. Detach, in the editor or the panel, takes the
  selection made in the editor.
- Each model is opened with its own click; the editor closes the previous one.
- Seven texts leave the seven catalogs (the right click, reload, the panel's way to select and its three choices, the
  world pick's miss); the left click's line is each language's existing line for opening the editor on the model aimed
  at. The separator keeps 57 texts.
