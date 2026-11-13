# 0178: VR hands, foregrip and physical weapons

Status: accepted for V4 implementation on the work branch. The user approved V2-V4 on 2026-11-12 and they were merged to `main`.

Follow [V4's controls and lifecycle](../handover/VR-V4-plan.md). Register nlvr_hands
lazily in both realms, give an instance to the active host and after spawn (next tick,
after the gamemode's loadout), and strip on Stop. Remember the weapon before VR and
select it again when available. Registration persists unused because GMod has no class
unregister API. Hands frees both controls; an armed main hand claims grip and trigger.

W's priority-300 resolver runs after P: close the main grip with the index on the
trigger; snap the gripped off hand to the foregrip with closed fingers. Foregrip aim
uses the two-hand line with a stable roll frame, not head aim. Known rifles/tools have
explicit metre points; unknown long world models receive a bounded barrel point.

Reuse P's unmodified Actions.Hit and Math.Damage for swept crowbar/stunstick heads,
including threshold, cooldown, force, damage type and protection; reuse Math.Throw for
grenades, including its 120 ms weighting and limits. Do not fork their damage/velocity
formulae. A small physics-map facade provides P's Hit exclusions. W suppresses damage
from the armed main proxy through EntityTakeDamage, since P's unarmed contacts still
run while controls are claimed. Off-hand and actual weapon damage continue normally.

Thrown frag/bugbait get 200 ms collision grace only against their owner and that
owner's proxies (not the world). Preserve the projectile's custom collision flag and
restore it on expiry/Exit, avoiding P's measured own-hand boost. No collision setting
or foreign file is changed. All resources are session-owned and survive neither death
as held state nor Exit as a hook/model/instance. Physical melee off restores trigger swing.
