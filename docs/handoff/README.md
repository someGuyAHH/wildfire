# WILDFIRE: handoff pack (start here)

This folder is a briefing for someone, human or agent, picking up the project with no prior
context. It was written on 2026-11-18 at commit `5098ce8` (branch `master`). Read this page
first, then whichever of the others you need.

| # | Page | What's in it |
|---|---|---|
| 1 | [01_concept.md](01_concept.md) | The game: pitch, theme, modes, rules, scoring, with the real numbers |
| 2 | [02_mechanics.md](02_mechanics.md) | Movement kit, controls, contact rules (tag, shove, stomp), hazards, debug keys |
| 3 | [03_architecture.md](03_architecture.md) | How the code fits together: scenes, scripts, data flow, every system |
| 4 | [04_bots.md](04_bots.md) | Bot AI: perception, decisions, navigation, nav links, skills |
| 5 | [05_maps.md](05_maps.md) | The four maps and the generator pipeline that builds three of them |
| 6 | [06_tooling.md](06_tooling.md) | Commands: running, generating maps, headless checks, exporting |
| 7 | [07_bug_history.md](07_bug_history.md) | Every notable bug so far: symptom, cause, fix, lesson |
| 8 | [08_status.md](08_status.md) | Where the project stands, known rough edges, what's next |
| 9 | [09_working_with_the_user.md](09_working_with_the_user.md) | How the owner works and what they expect from an agent. **Read this before acting.** |

Other docs already in the repo: [`docs/PLAN.md`](../PLAN.md), the original game plan and
milestone table. Some of its early numbers are out of date; where they disagree, these pages
and the code win. [`docs/maps/`](../maps/README.md) has one design page per map.

## The project in ten lines

- **WILDFIRE** is a fast 3D game of tag against bots, built for movement in the spirit of Ultrakill's speed.
  The tagged player is **the Torch** (on fire). Touching someone sets them alight. Lowest time burning wins.
- **Engine:** Godot **4.7.2** stable, Forward+ renderer, **Jolt** physics at **120 Hz** with physics
  interpolation. Pure typed **GDScript**. Addon: **Terrain3D 1.1.0** (`addons/terrain_3d`).
- **Location:** `/home/toker/Projects/tag-3d` on the owner's Linux machine (Debian, kernel 6.12; integrated
  Intel Iris Xe GPU at 3072 × 1602). Branch `master`; ~56 commits. **There is no git remote.**
- **Players:** one human player and up to ~15 bots. Bots drive the *same* character controller through
  the same input struct (`CharacterIntent`): no movement cheats.
- **Modes:** Classic, Spread (infection), Hunted (you vs the swarm), Hot Potato (fuse + closing storm).
- **Maps:** Test Gym (built in code at runtime), Overworld and Jungle (Terrain3D heightmaps), and Inferno
  (box geometry over a lava sea). The last three are **generated headless** by `tools/mapgen/*_gen.gd`.
  Never hand-edit those scenes.
- **Stage:** milestones M0–M5 are done: movement, tag core, bots, modes, and greybox maps.
  M5's collectibles were cut. **M6 (art pass) started on 2026-11-18**: see [`docs/M6.md`](../M6.md). Then M7 (polish, audio).
- **Testing:** everything is verified with **headless** scripted checks in `tools/checks/`, always run under
  `timeout` and with `--fixed-fps 120`. Never open a Godot window on the owner's desktop.
- **UI:** everything is built in code (menus, HUD), styled with a project theme
  (`assets/tres/ui/wildfire_theme.tres`). The title screen runs a live bot match behind the menu.
- **Art:** greybox only. Materials are flat colours per role per map. No models, sounds or music yet.

## Five things that will bite you if you don't know them

1. **Generated maps:** `scn/map/overworld.tscn`, `jungle.tscn` and `inferno.tscn`, plus their meshes,
   navmeshes and terrain data, are outputs. Change `tools/mapgen/...` and regenerate (see
   [06_tooling.md](06_tooling.md)), then run the pad and nav checks.
2. **`tools/` has a `.gdignore`:** the editor doesn't import it, so scripts there `preload()` each
   other instead of using `class_name`. Also, a brand-new `class_name` in `src/` isn't visible to
   headless scripts until you run `godot --headless --import` once.
3. **Packed arrays are value types:** pulling a `PackedVector3Array` out of a Dictionary/Array and
   appending to it changes a copy. This bug once put every character at NaN. Use plain `Array`s
   inside containers.
4. **Godot editor shortcuts win over the game when it runs embedded in the editor:** F7 = pause, F8 = stop.
   That's why the debug cheats are on the number keys 7 8 9 0.
5. **Rules for the owner's machine:** headless only, always use a `timeout`, stay inside the project
   folder, never press Reset or save settings from tests. Commit each verified change on `master`
   yourself; never push, tag or branch unasked. See [09](09_working_with_the_user.md).
