# Credits

Every third-party file in the project: where it came from, who made it, its licence, and where it
lives here. Only licences that allow use in a game (CC0 preferred; CC-BY with credit).

| Asset | Source | Author | Licence | Used as |
|---|---|---|---|---|
| Bark 012 (colour, normal GL, roughness, 2K JPG) | https://ambientcg.com/view?id=Bark012 | ambientCG (Lennart Demes) | CC0 1.0 | `assets/images/foliage/bark012_*.jpg`: the Jungle's tree trunks and the bark role |
| LeafSet024 (colour, opacity, 2K JPG) | https://ambientcg.com/view?id=LeafSet024 | ambientCG (Lennart Demes) | CC0 1.0 | `tools/texgen/sources/leafset024_*.jpg`, composed into `assets/images/foliage/twigs.png` by `tools/texgen/foliage.py` |
| Planks 012 (colour, normal GL, roughness, 2K JPG) | https://ambientcg.com/view?id=Planks012 | ambientCG (Lennart Demes) | CC0 1.0 | `assets/images/wood/planks012_*.jpg`: the Jungle's wood (decks, bridges, chutes) |
| Universal Animation Library (Standard) and Universal Animation Library 2 (Standard): rig + clips | https://opengameart.org/content/universal-animation-library , https://opengameart.org/content/universal-animation-library-2 (also quaternius.com) | Quaternius | CC0 1.0 | `tools/blender/sources/ual/ual1_standard.glb`, `ual2_standard.glb`: the runner's rig and its clips (some retargeted from UAL2), built by `tools/blender/runner.py` into `assets/models/characters/runner.glb` |
| Barlow and Barlow Condensed (Medium, SemiBold, Bold; Condensed SemiBold, Bold Italic, ExtraBold Italic) | https://github.com/google/fonts/tree/main/ofl/barlow , .../ofl/barlowcondensed (also https://github.com/jpt/barlow) | The Barlow Project Authors (Jeremy Tribby) | SIL OFL 1.1 (`assets/fonts/OFL-Barlow.txt`) | `assets/fonts/*.ttf`: every UI font (Condensed for titles, numbers and the timer; Barlow for body text) |
| Phosphor Icons (fill): fire, person-simple-run, snowflake | https://phosphoricons.com (npm `@phosphor-icons/core` 2.1.1) | Phosphor Icons (Helena Zhang, Tobias Fried) | MIT | `assets/images/ui/*.svg` (fill made white so the HUD tints it): the Torch and runner icons, frozen |
| Impact Sounds 1.0 (footsteps, impacts) | https://kenney.nl/assets/impact-sounds | Kenney (Kenney Vleugels) | CC0 1.0 | footsteps, landings, bonks, shoves, vaults and wall kicks: layers in `assets/sfx/one_shots/` |
| Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | Kenney | CC0 1.0 | `ui_back`, `ui_confirm`, `ui_toggle_*`, `ui_open`, `ui_close`, layers of `ui_pop_*` |
| UI Audio (UI SFX Set) | https://kenney.nl/assets/ui-audio | Kenney | CC0 1.0 | `ui_hover_1` (rollover2), `ui_click_*`, `ui_tick_*`, `ui_turn_*` |
| Digital Audio | https://kenney.nl/assets/digital-audio | Kenney | CC0 1.0 | `countdown_*`, `win`, `lose`, `fuse_tick_*` |
| Sci-Fi Sounds 1.0 | https://kenney.nl/assets/sci-fi-sounds | Kenney | CC0 1.0 | layers of `dash_*`, `ignite_*`, `explosion_*`, `slam_land_*`, `smoke_warn`, `storm_start` |
| 100 CC0 SFX | https://opengameart.org/content/100-cc0-sfx | rubberduck | CC0 1.0 | layers of `slam_land_*`, `pad_launch_*`, `lava_in`, `ui_pop_*` |
| 25 CC0 bang / firework SFX | https://opengameart.org/content/25-cc0-bang-firework-sfx | rubberduck | CC0 1.0 | layers of `explosion_*` |
| 40 CC0 water / splash / slime SFX | https://opengameart.org/content/40-cc0-water-splash-slime-sfx | rubberduck | CC0 1.0 | layer of `lava_in` |
| Fireplace Sound loop | https://opengameart.org/content/fireplace-sound-loop | PagDev | CC0 1.0 | `torch_loop`, `smolder_loop`, `amb_lava` (cut, filtered, looped) |
| Catching fire | https://opengameart.org/content/catching-fire | themightyglider | CC0 1.0 | layers of `ignite_*`, `lava_in`; reversed in `extinguish_*` |
| Simple Fuse Sound | https://opengameart.org/content/simple-fuse-sound | themightyglider | CC0 1.0 | `fuse_loop` |
| Mild Wind Background Noise | https://opengameart.org/content/mild-wind-background-noise | Bashar3A | CC0 1.0 | `slide_loop`, `wall_slide_loop`, `wind_speed`, `skid_*`, `storm_loop`, `amb_wind`, `amb_plains`, `extinguish_*` (filtered noise) |
| Air whoosh | https://opengameart.org/content/air-whoosh | pyranostudios | CC0 1.0 | `slam_start`, `brake_air`, `ui_whoosh_*` |
| Swishes Sound Pack | https://opengameart.org/content/swishes-sound-pack | artisticdude | CC0 1.0 | layers of `dash_*`, `jump_*`, `wall_jump_*`, `vault_*`, `shove_*` |
| rumble fx | https://opengameart.org/content/rumble-fx | cinameng | CC0 1.0 | `smoke_warn`, `storm_*`, `amb_lava` |
| AMB Morning Sounds (Perfect Loop) | https://opengameart.org/content/amb-morning-sounds-perfect-loop | Kresiek The Furry | CC0 1.0 | `assets/sfx/ambience/amb_jungle.ogg` (Jungle) |
| Loopable Dungeon Ambience | https://opengameart.org/content/loopable-dungeon-ambience | JaggedStone | CC0 1.0 | `assets/sfx/ambience/amb_hall.ogg` (Inferno) |

The sound files in `assets/sfx/` are **derived**: `tools/audio/build_sfx.py` cuts, filters, layers, trims, loops and normalises the packs above
(raw downloads live in the git-ignored `tools/audio/sources/`); each row's "Used as" names what came out of it. Nothing there is a file
from a source that needs an account or a non-commercial licence. Sound packs from Freesound were skipped: its downloads need a sign-in.

Tools (not shipped): Blender 5.2.4 LTS (GPL), installed portable in `tools/.blender/` (git-ignored).

Patched third-party code: `addons/terrain_3d/src/export_plugin.gd` (Terrain3D 1.1.0, MIT) – `_begin_customize_resources` called `plugin.terrain.get_version()`, but `terrain` is null whenever no Terrain3D node is selected in the editor, so every export logged "Nonexistent function 'get_version' in base 'Nil'". It now falls back to a fixed cache-hash string. Re-apply this after updating the addon (upstream may have fixed it).
