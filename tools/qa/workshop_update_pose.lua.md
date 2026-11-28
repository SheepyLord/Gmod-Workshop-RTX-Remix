# workshop_update_pose.lua

The [WU driver](workshop_update_session.py.md) stages this shared autorun in the PoC's temporary add-on. It acts in single-player Sandbox on `gm_flatgrass` when the WU request is present.

The host's `nl_wu_aim` command sets an eye trace onto clear ground ahead. The helper holds the resulting test Citizen at yaw zero, in `Reference`, cycle zero, with stopped playback and zeroed pose parameters. V1 stores the run token on that NPC with Sandbox's duplicator. Only pasting an entity carrying that token in v2 labels it as the restored Citizen. Its mesh and carrier come from the Hotloader's normal restoration.

The client side resumes the [probe](workshop_update_probe.lua.md) if a save load creates a new Lua realm while the run's restore marker is present. The session restores the original add-on and data folders at exit. The helper has no separate command-line exit code.
