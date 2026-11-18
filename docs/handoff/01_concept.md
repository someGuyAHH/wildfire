# 1. The game: concept, modes, rules

## Pitch

A fast 3D game of tag against bots, on big maps built for movement. Everyone, bots included,
can sprint, slide, dash, wall-jump, slam and vault. A chase is a contest of routes, not a footrace
you lose from the start. The speed target is Ultrakill-like. The intended look is crisp vector-style
shapes under realistic lighting (not done yet: everything is greybox).

**Design pillars** (from `docs/PLAN.md`)
1. **Movement never holds you back:** momentum is kept, there's no stamina and no fall damage,
   and low obstacles get stepped over or vaulted automatically.
2. **Bots play by the player's rules:** they drive the same controller through the same input
   struct. Difficulty comes from decisions and reaction time, never from speed cheats.
3. **Maps are playgrounds:** big, open, with loops, vertical routes and traversal props. Every area has more than
   one way out.
4. **Readable chaos:** the Torch is always obvious and tags are loud.

## Theme: WILDFIRE

Tag, but the tag is **fire**.

| Concept | Name in game | In code |
|---|---|---|
| Tagged player | **the Torch** (glowing red, embers, name shown through walls) | `get_torch()`, `torch_added/removed`, `MatchRules.torch_*` |
| Tagging | **setting someone alight** | `tag`, `tagged` stay the generic verbs |
| Runners | **kindling** | |
| Score | **time burning** | `get_torch_time`, `get_score` |
| Body slam at 20+ m/s | **shove** (on the Torch it's a **snuff**) | `bump*` |
| Slam down onto someone | **stomp** | `_try_stomp` |

HUD lines read like "YOU'RE ON FIRE!" and "Bot 3 set You alight". Blue/cyan flames on screen mean
you're fast enough to shove (20+ m/s); violet flames + sparks = **overdrive** (30+ m/s).

## Modes

All mode numbers live in `MatchRules` resources: `assets/tres/match/{classic,spread,hunted,hot_potato}_rules.tres`.
Script defaults are in `src/match/match_rules.gd`, and each `.tres` overrides only what differs.
`TagManager` (`src/match/tag_manager.gd`) runs the rounds: countdown (3 s) → play → results
(8 s) → next round (auto-restart).

| Mode | Rules | Win | Round |
|---|---|---|---|
| **Classic** | One Torch. Touch passes the fire. The new Torch is frozen 1.5 s (the very first Torch 3 s); the previous Torch can't be lit straight back for 3 s. | **Lowest** score (time burning − bonuses) | 180 s |
| **Spread** | Everyone you light becomes another Torch. No freeze for a fresh Torch, no Torch speed/dash bonus (a pack doesn't need it). Everyone starts **scattered** over the map. The player never starts on fire. | **Highest** score (time survived + bonuses). Ends when nobody is left unlit or time runs out | 150 s |
| **Hunted** | You (`TagManager.focus`) vs the swarm. Bots start on fire and hunt you as one. If any bot lights you, they're all put out and you're on fire; if you light any bot, the whole swarm catches fire again. Each side gets a brief immunity after losing the fire. | Your time not burning | 180 s |
| **Hot Potato** | Classic passing, plus a **fuse** (20 s ± 4 s jitter). Whoever holds the fire when it blows **burns out** (eliminated; the camera spectates, and jump cycles who you watch). A **storm wall** closes in after 15 s, shrinking to r 25 m over 120 s; standing in it builds heat, and full storm heat burns you out too. | Last one standing | 400 s |

## Rules that apply in every mode

| Rule | Numbers (MatchRules) | What it does |
|---|---|---|
| **Tag contact** | `tag_radius` 1.3 m, `tag_height` 1.9 m | The Torch's reach. Automatic, so player and bots are judged the same way. |
| **Torch bonus** | `torch_speed_mult` 1.06, `torch_dash_regen_mult` 1.3 (both 1.0 in Spread) | The Torch runs 6% faster and recharges dashes faster. |
| **Shove** (body slam) | `bump_speed` 20 m/s closing speed, `bump_margin` 0.3 m capsule gap, `bump_stun` 1.5 s, `bump_immunity` 3 s, `bump_knockback` 9, attacker disoriented 1 s | Run (or dash point-blank) into anyone at 20+ m/s: they're stunned, and you bounce off a bit dizzy. The reach never drops below the tag reach, so a snuff can beat the Torch's touch. The Torch touching you is always just a tag. |
| **Stomp** | `stomp_min_drop` 3 m, `stomp_bounce` 9 | Slam down onto someone after falling ≥ 3 m: they're stunned like a shove, and you bounce up. |
| **Snuff scoring** | `snuff_bonus` 3 s, `shove_bonus` 1 s | Shoving the Torch takes 3 s off your score; shoving kindling takes 1 s off. |
| **Dry edge** | `edge_start` 0.85 × arena radius (or the map's `dry_edge_radius`), `heat_rate` 0.35/s, `heat_drain` 0.5/s, `smolder_score_rate` 0.5, `smolder_ignite_time` 5 s | The outer band (amber on the ground) heats kindling up. At full heat you **smolder**: burning time ticks up at half rate. After 5 s smoldering you **catch fire and become the Torch**. Moving back inside cools you off. |
| **Smoke (no hiding)** | `still_distance` 8 m, `still_time` 6 s, `smoke_time` 4 s | Stay within 8 m of one spot for 6 s and you start **smoking**: a visible column and a 4 s warning. Still there when it ends? You catch fire and become the Torch. |
| **Map bound** | `GameMap.get_bound_radius()` = arena radius × 1.2 | An invisible wall: anyone past it is put back on it and loses their outward speed. |
| **Lava** (Inferno) | `GameMap.lava_height` −8, slow 2 s at ×0.5 | Not a death: you're put at the nearest checkpoint marker, slowed, and can't dash while slowed. |
| **Kill height** | `Main.kill_height` −60 | Below this you respawn (mostly for the Gym). |
| **Hunted warning** | | A red screen edge and an off-screen arrow appear when a bot is actually chasing you. |

## Ideas from the plan that were dropped or changed

- **Infection** became **Spread**. **Freeze tag** and **Hunter's sense** (outline the nearest runner
  after 20 s without a tag) were never built.
- **Portals** were built for a hidden room (a doorway showing another place live) and then removed
  for being buggy. The owner asked for "a real room, no illusion whatsoever".
- **Collectibles** (an M5 item: pick-ups on movement-tech spots) were never started.
- PLAN.md's starting movement numbers (gravity 32, jump 11.5, floor angle 50°) were retuned.
  The real values are in [02_mechanics.md](02_mechanics.md).
