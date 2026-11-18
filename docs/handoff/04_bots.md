# 4. Bots

Code: `src/bot/bot_brain.gd` (940 lines, one node per bot, `scn/bot/bot.tscn` = character +
Brain), `src/bot/bot_skill.gd` (the skill resource), and `src/debug/bot_debug.gd` (the F5 overlay).
A bot writes the same `CharacterIntent` the player's input does. **No movement cheats.**

## Loop (every physics tick, `_physics_process`)

1. Tick the timers. A burned-out bot (Hot Potato) just stands.
2. `_check_incoming_dash()`: the dodge reflex. It fires only for a dash the bot can **see**
   (in front of it, with line of sight), only after its reaction time, and with chance
   `juke_skill × 0.55`.
3. Every `reaction_time × rand(0.8..1.2)` it runs **`_decide()`** (staggered per bot at start).
4. When the repath timer runs out, **`_repath_now()`** queries a path on the navigation server.
   There's a global cap of **2 path queries per physics tick** across all bots. A bot over the cap
   keeps its old path and retries 10–30 ms later; this cap removed big hitches on the Jungle.
5. **`_steer()`** works out the wish direction: follow the path corners, or **steer a nav link**.
   `_handle_stuck` fires if the bot is below 1.5 m/s for 0.6 s.
6. Write the intent (wish, look, slide/jump held).

## Goals and decisions

`GOAL_WANDER 0, GOAL_CHASE 1, GOAL_SEARCH 2, GOAL_FLEE 3`.

**As a Torch** (`_decide_chaser`, `_pick_target`, `_chase`):
- **Target score** (`_pick_target`, lower is better):
  - flat distance + 3 × height difference;
  - +25 if the target is more than 2.5 m up, +40 if it's marked unreachable;
  - +12 per other Torch already chasing it (team spread);
  - +10 if it's out of sight, + how fast it's running away;
  - −8 for the current target, −4 if it has no dash charge.
  - Unseen targets past 1.5 × awareness are skipped.
- **Commitment:** a bot sticks to its target for `commit_time`. It still switches to someone within
  6 m who is under half as far away.
- **Intercept:** it aims at the target's position plus velocity × lead, scaled by `prediction`.
  If a teammate is already closer behind the target, it **flanks** (9 m offset).
- Within 9 m with line of sight it goes straight at the target. A **finishing dash** fires only when
  it would land, aimed where the target will be, at odds based on `dash_skill`.
- **Unreachable target** (perched up somewhere): the path stops short of its own goal, or the target
  stands off the navmesh. The bot then **camps** at the closest reachable spot under the target, or
  picks someone else.
- With no line of sight it goes to the last known position (memory `memory_time`), then wanders.

**As a runner** (`_decide_runner`, `_pick_escape`, `_escape_score`):
- **Perception:**
  - a view cone (`view_half_angle`) out to `awareness_radius`, with line of sight;
  - hearing within `hearing_radius`;
  - a glance back every `glance_interval`;
  - nobody past 160 m is visible.
  - Blunders (`blunder`) sometimes miss things. Bots are fallible on purpose: you can sneak up from behind.
- **Flee:** it samples `flee_samples` points on a ring of 18–45 m. Each is scored by distance from
  the threat, by heading away from it rather than past it, and by staying inside the arena. Spread
  adds a penalty for **every** Torch nearby, not only the nearest. It snaps only the best 3 to the
  navmesh (for speed). It re-picks once the escape point is older than 1.2 s.
- **Relax:** if the Torch is busy with someone else, is more than 15 m away and isn't closing faster
  than 6 m/s, the bot doesn't sprint. This also gives aggressive bots a chance to snuff.
- **Juke:** when the Torch is within 4.5 m, it sidesteps and/or dashes, timed by `juke_skill`.
- **Hazards** (`_avoid_hazards`):
  - Heat above 0.25 sends it back inside (unless the Torch is within 8 m).
  - Stillness above 0.55 makes it relocate 14 m away.
- **Snuff attempts** (`_try_snuff`): chance 0.3 × `aggression` per decision, within 30 m, only
  when the dash would land at ≥ bump_speed + 2. Shouts like "hold my beer".
- **Beef / suspicion** (`_update_suspicion`, `_do_beef`): another runner who hovers close, stares,
  closes in or dashes at the bot fills a suspicion meter. When it's full, the bot either
  **counter-slams** ("1v1 me") or **nopes out** ("nope"), depending on `aggression`. Shouts appear
  over its head via `Character.emote`.

## Navigation and links

- Navmesh:
  - **Gym:** baked at runtime from the static colliders.
  - **Generated maps:** pre-baked 128 m chunks plus a `NavLinkSet` resource of auto links (thousands).
- How a bot moves along each link kind (`_steer_link`):

| Link | Made by | Bot does |
|---|---|---|
| `LINK_PAD` 1 | every pad (one-way) | walks onto it, easing off over the last metres (an aimed pad lobs exactly only if you arrive slower than the lob). In the air it steers to the pad's **landing** (`Character.get_launch_target()`), even if it walked over the pad by accident. |
| `LINK_VAULT` 2 | auto: ledges ≤ 3.6 m up within 2 m | runs in with jump held. If it's right under a floating lip it backs out first (it used to bonk the underside forever). |
| `LINK_DROP` 3 | auto: edges ≤ 4 m above something; pad landings | walks off |
| `LINK_WALLJUMP` 4 | auto: ledges 3.6–9 m up within 2.5 m with a wall halfway; also kit links (Jungle "twins") | arrives slowly, jumps from a standstill, leans into the wall it's on (each wall-jump pushes it off, leaning brings it back), and goes over the top. It steers back in if it drifts more than 1.5 m out. |
| `LINK_JUMP` 5 | auto: gaps 1–6 m (rising ≤ 2.2 m within 4.5 m); jump-downs ≤ 9 m across, ≤ 12 m down (one-way) | runs to the edge (pace scaled to the gap), takes off, and brakes in the air so it doesn't sail past a narrow ledge |

- A link that takes longer than 4 s is abandoned and the bot repaths.
- **Pad and drop links must be one-way.** `NavigationLink3D` defaults to two-way, so early bots
  planned to ride pads backwards.
- How links are generated: see [05_maps.md](05_maps.md).

## Skill presets (`assets/tres/bot/*.tres`, BotSkill)

| Knob | Easy | Normal (script defaults) | Hard |
|---|---|---|---|
| reaction_time (s) | 0.4 | 0.22 | 0.12 |
| prediction | 0.3 | 0.7 | 0.95 |
| awareness_radius (m) | 30 | 45 | 65 |
| hearing_radius | 8 | 10 | 18 |
| view_half_angle (°) | 45 | 60 | 75 |
| glance_interval (s) | 2.5 | 2.0 | 0.8 |
| memory_time (s) | 2 | 3 | 4 |
| blunder | 0.3 | 0.12 | 0.03 |
| suspicion | 3.5 | 2.5 | 1.6 |
| commit_time | 3 | 5 | 7 |
| aggression | 0.3 | 0.5 | 0.65 |
| dash_skill | 0.25 | 0.6 | 0.9 |
| juke_skill | 0.15 | 0.5 | 0.85 |
| slide_use | 0.2 | 0.5 | 0.8 |
| flee_samples | 8 | 16 | 24 |
| steer_error_deg | 16 | 8 | 3 |

"Mixed" difficulty cycles easy, normal and hard over the bots.

## Performance

- 16 characters cost ~2.5 ms per 120 Hz physics tick on the Gym, and bot AI is ~0.2 ms of that, so
  no think-LOD was needed.
- The Jungle with 15 bots: average 2.3 ms/tick, worst ~7 ms after the query cap.
- Don't trust the `Performance` physics counter: it double-counts. Time with stamp nodes around the tick.

## Debugging bots

- **F5 overlay** (`bot_debug.gd`): over each bot's head it shows name, state, speed, goal (with target,
  distance and line of sight), camping/commit/forced flags, the current move (walk or link kind),
  path progress and the stuck/link timers. Its path is drawn in the world: the Torch orange,
  runners cyan. Link segments are coloured by kind: pad magenta, climb green, drop blue, wall-jump
  yellow, gap jump white. A cross marks the goal.
- `BotBrain.debug_text()` / `debug_path()` feed it.
- **F6:** the Torch hunts only you. **7 / 8 / 0:** no-tag / alone / freeze cheats.
- Headless checks: `reach.gd` (with `TRACE` env for a per-tick log), `stuck.gd`, `nav_reach.gd`
  ([06_tooling.md](06_tooling.md)).
