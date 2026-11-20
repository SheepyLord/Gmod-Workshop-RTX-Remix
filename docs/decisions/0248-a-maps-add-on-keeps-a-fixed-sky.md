# 0248: A map's add-on keeps a fixed sky, such as space, under the player's own sky

- Status: Accepted 2026-11-20 (the user's answer "Yes, keep orbit sky" to the question whether the gm_stelliferous
  remaster should keep its orbit sky also with their own sky setting); supersedes in part
  [ADR 0105](0105-the-players-sky-applies-from-a-maps-start.md), for a sky its add-on declares fixed
- Package only: the companion ([nativeloader_sky.lua](../../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md)).
  No `winmm.dll` change.

## Context

The remaster of gm_stelliferous (Workshop 3450250071; a local branch of the user's fork and the user's game, the
`remix-map-pbr` skill's lessons) is a space station above a planet. Its add-on shows the map's own orbit skybox
(black space with stars above, the planet's limb and its clouds below) and adds the sun as a Remix API distant
light, where the runtime's physical atmosphere puts the station under a blue daytime sky. Under ADR 0105 the
player's own sky ("Follow the map's sun" unticked, the user's setting in their game) is the companion's from every
map's start, also where a map's add-on sets a sky: on gm_stelliferous the station then hung in a pale daytime sky
over grey ground haze. A time of day, a season or a weather has no meaning for a sky that is part of the place.

## Decision

- A map's add-on whose sky belongs to the place, so that no time of day or weather fits it, answers the hook
  `NativeLoaderSkyFixed` with `true`, besides `NativeLoaderSkyOwner` with its name. It answers from the moment its
  Lua loads on that map: the companion decides at the map's start (`InitPostEntity`), before most map add-ons
  start.
- With a fixed sky the companion leaves the add-on's sky alone from the map's start, whatever "Follow the map's
  sun" says: it sends no sky, sun or weather. A sky or weather setting changed in the session still takes the sky
  over until the next map start, as ADR 0031 decided for the add-on of a map that is followed.
- `NATIVELOADER_SKY.takenOver()` tells an add-on whether the player's sky replaces its own now. A fixed-sky add-on
  sets its sky only while it is false, and when it turns true removes what would double the companion's sky (an
  API sun). An add-on without that function in reach (an older companion) goes on reading
  `nativeloader_sky_follow_map`, as before.
- The panel says so on such a map ("On this map %s keeps a sky of its own, such as space, that no time of day or
  weather fits..."), in the six languages; `nativeloader_sky_status` adds ", fixed" after the add-on's name.
- Every other add-on sky keeps ADR 0105: with "Follow the map's sun" unticked the player's sky replaces it from the
  map's start.

## Consequences

- gm_stelliferous shows its orbit sky also in the user's game; their time of day and weather apply again on the
  next map.
- The answer has to come from the add-on's load. An add-on that answered only later would find the companion's
  sky and weather already sent at the start, and the companion does not take back what it sent (R3-010).
- Ticking "Follow the map's sun" on such a map during a session is a change like any other: it takes the sky over
  (ADR 0105's consequence).
- The other maps, Modern House RTX among them, behave as before.

## Alternatives considered

- **A list of maps in the companion** (gm_stelliferous recognised by name, as Modern House RTX is by its
  `MHRTX_Config`): the map's add-on knows its sky, and the companion would need an update for each new space map.
- **Every map add-on's sky kept under the player's own sky**: undoes ADR 0105 (the user's item 44 of R16: the
  player's settings must apply from the start).
- **The add-on setting its sky again after the companion's**: the companion puts the player's sky back in the same
  tick (R5); the two would fight.
- **A checkbox for the player** ("let maps keep a fixed sky"): one more setting for a choice the user has made;
  changing a setting in the panel already overrides the map's sky.
