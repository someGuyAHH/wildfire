# Test Gym

**Purpose:** tuning and regression. Every movement mechanic has a labelled, measured obstacle so a
change to the controller can be checked by feel and by numbers. It is not a play map; the title
screen starts on it and it's the first entry of the MAP stepper.

**Built by** `src/map/test_gym.gd` at runtime (a `@tool` GameMap: the generated nodes aren't
saved). 420 m square, flat ground, arena radius 190 (dry edge from 0.85 × that).

## Stations (all labelled in the scene)

| Station | Tests | Notes |
|---|---|---|
| Stairs | step-up (auto-step height) | steps at the controller's step height |
| Ramps | slopes at fixed angles up to the floor limit (62°) | anything steeper is a wall |
| Vault walls | 0.9 / 1.2 / 1.5 m walls | vault height 1.5 m; nav links both sides |
| Slide tunnel | crouch under a low ceiling | |
| Wall-jump shaft | tower 5 m between it and a thin wall | 3 wall-jumps + jump ≈ 5–6 m here; WALL-JUMP nav link |
| Pillar field | hop chains at mixed heights | seeded (pillar_seed) |
| Pads | aimed pads up to a platform, long pad, momentum pad | nav links |
| Speed track | speed strips, overdrive (30+ m/s) | |
| Slide hill | 90 m at 15°, long slides | pad to the top |

Bots: links are added by hand in `_build_nav_links()` (not the generator's auto links).

## Next (M6 and later)

- Keep it greybox: it's a measuring tool. Only update it when a mechanic changes.
- Add a station when a new mechanic lands (portals, lava respawn) so it can be tuned here.
