# 6. Tooling: running, generating, checking, exporting

The `godot` binary on the owner's PATH is **4.7.2.stable.official**. Run everything from the
project root (`/home/toker/Projects/tag-3d`).

## Ground rules for running Godot

- **Headless only** (`--headless`) for anything an agent runs. Never open a window on the owner's
  desktop: windowed runs pop up and grab the mouse while they're working, and they were furious about it.
  If something truly needs rendering (a screenshot, GPU timing), **ask first**.
- **Always wrap a run in `timeout`**, sized to about 2–3× the expected time. A batch once stalled for 24
  minutes unnoticed.
- **Simulations use `--fixed-fps 120`**, so physics runs unthrottled (a 60 s round takes ~4 s).
- Never press Reset or save settings from a test: checks must not touch `user://settings.cfg`.
- The owner may have the editor open. It re-saves `.tscn`/`.tres` files with added `uid=` fields.
  Those diffs are the editor's, not yours. Leave them out of your commits unless asked.

## Common commands

```bash
# re-import (needed once after adding a new class_name, before headless scripts can see it)
timeout 300 godot --headless --import

# regenerate a map (outputs: scene, meshes, navmesh, terrain data, materials)
timeout 900 godot --headless --script res://tools/mapgen/overworld_gen.gd
timeout 900 godot --headless --script res://tools/mapgen/jungle_gen.gd
timeout 900 godot --headless --script res://tools/mapgen/inferno_gen.gd

# quick parse check of the whole project: any script error shows up as SCRIPT ERROR / Parse Error
timeout 120 godot --headless --quit 2>&1 | grep -i "error" | head
```

## Checks (`tools/checks/`)

Each check is a `SceneTree` script driven by environment variables. **`MAPI`** is the map index in
`Main._MAPS`: 0 Gym, 1 Overworld, 2 Jungle, 3 Inferno.

| Check | Command | Prints / expects |
|---|---|---|
| **pads** | `SCENE=res://scn/map/inferno.tscn timeout 300 godot --headless --fixed-fps 120 -s res://tools/checks/pads.gd` | `pads landing on target: N / N`. Currently Inferno 29/29, Jungle 52/52, Overworld 37/37. |
| **nav_reach** | `SCENE=… FROM="x,y,z" SPOTS="x,y,z;x,y,z" timeout 120 godot --headless -s res://tools/checks/nav_reach.gd` | `reachable: k / n`; lists paths ending > 1.5 m short. (A first "query before first map synchronization" error line is normal.) |
| **reach** | `MAPI=3 START="x,y,z" SPOTS="…" [TRACE=1] timeout 400 godot --headless --fixed-fps 120 -s res://tools/checks/reach.gd` | A Torch bot chases a frozen player placed on each spot: did it get there, and how fast? `TRACE` logs per tick. |
| **stuck** | `MAPI=3 [MODE=…] [WHY=1] timeout 400 godot --headless --fixed-fps 120 -s res://tools/checks/stuck.gd` | A 2-minute Classic match with 9 bots: `done: 0 bots stuck, N lava falls`. A bot is stuck if it stays within 2.5 m for 10 s. Lava falls are counted by the `is_slowed` rising edge. |
| **spread** | `MAPI=3 timeout 300 godot --headless --fixed-fps 120 -s res://tools/checks/spread.gd` | Spread with 11 bots: Torch counts at 30 / 60 / 90 s (with the old scatter: 2–4 at 30 s, rounds 80–120 s; since everyone starts together, 2–10 at 30 s, rounds 30–110 s). |
| **lava** | `MAPI=3 timeout 200 godot --headless --fixed-fps 120 -s res://tools/checks/lava.gd` | The player dropped into lava ends up at a checkpoint, slowed, with the feed line, and unslowed 2.2 s later. |
| **cheats** | `MAPI=3 timeout 200 godot --headless --fixed-fps 120 -s res://tools/checks/cheats.gd` | no-tag, alone (+ restore), fly (rises; collision mask restored), freeze, and the label. |
| **nav_time** | `SCENE=… timeout 120 godot --headless --fixed-fps 120 -s res://tools/checks/nav_time.gd` | How long until a map's navigation answers (Jungle ~2.5 s, Overworld ~0.6 s). |

Filter the noise with `grep -iv "border_size\|clipmap\|Godot Engine"`. A Jolt "exceeded the maximum
number of jobs" warning shows up sometimes and is harmless.

### Writing a new check: gotchas

- Scripts in `tools/` can't reference autoloads (`STG`) or freshly added `class_name`s at compile
  time. Use `get_node("/root/STG")` / `load()` at runtime, and run `--import` after adding a class.
- Typed inference from an untyped Dictionary fails to parse (`var run := not dict[k]`). Declare
  the type (`var run: bool = …`). A parse error in `main.gd` makes the check hang until the timeout,
  so read the error output.
- The scratchpad gets wiped between sessions. Checks worth keeping live in `tools/checks/`.

## Export

`export_presets.cfg` has one preset, **Linux**, exporting to `../../Desktop/Wildfire.x86_64` (relative
to the project, i.e. `~/Desktop`). In a release build the debug keys (F2–F6, 7–0) are off.

```bash
timeout 600 godot --headless --export-release "Linux" ../../Desktop/Wildfire.x86_64
```

## Git

- One branch, `master` (the session tooling calls `main` the "main branch", but it doesn't exist).
  **No remote is configured**, so moving devices means copying the folder or adding a remote.
- History is one commit per logical change, with messages written as "what changed, then why".
  Commits end with a `Co-Authored-By:` trailer for the agent.
- The working tree right now has two editor re-saves (`assets/tres/match/spread_rules.tres` and
  `scn/main/main.tscn`: added `uid=` fields, a dropped `;` comment). They're harmless and not part of
  any change.
