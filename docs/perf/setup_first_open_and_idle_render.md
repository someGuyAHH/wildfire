# Match setup: first-open hitch and idle carousel rendering

Follow-up to `menu_exit_stutter.md`. Headless only (`tools/checks/setup_first_open.gd`, `--fixed-fps 120`):
script, layout and scene-tree cost plus a count of how often the carousel's 3D ring is asked to draw.
Headless has no GPU, so GPU frame time, shader / pipeline compiles and render-target allocation were
**not** measured.

## 1. One-off long frame the first time the setup opens
| | before | after |
|---|---|---|
| first frame after PLAY (worst of first 60) | 25.4 ms | 1.4 ms |
| second open | 1.7-2.1 ms | 1.7-2.3 ms |
| startup frame 2 (where the warm-up now lands) | 0.7 ms | 22.7 ms |

Cause (bisected by timing each step of `_enter`): the key-hint bar. The first time it draws the setup's
hints ("Change", "Section", "Next / Play", the arrow keycaps) their text is shaped and the glyphs rasterised,
~21 ms. Building the boxes, cards, layout, `select` / `swing_in` and the shade tween cost under 1 ms each.

Fix: `MainMenu._prewarm()`, run right after the title is up, draws a transparent hint bar with the setup's
hints for two frames, and shows the (hidden) setup screen at alpha 0 so its layout is done and the carousel's
3D ring draws once, which on a GPU also takes its shader compile and 4x MSAA target allocation then (not
measurable here). The cost moves to startup frame 2, right behind the 49 ms first frame.

## 2. Carousel re-rendered every frame while idle
The ring's `SubViewport` was `UPDATE_WHEN_VISIBLE`: a full-screen 4x MSAA draw on every setup frame.
Now it is `UPDATE_DISABLED` and `ModeWheel.request_render()` draws it for the frame of a change plus two more
(a card texture and a resized viewport land a frame late). Requests come from turning (`_set_turn`, so every
frame of the 0.5 s spin), `select`, layout / resize, adding a card, `set_live(true)` and the wheel becoming
visible. Hidden (setup not shown) it is disabled outright. `set_live(false)` (during the exit fall) still
turns it off. No card has a live animated preview (card textures are drawn once and redrawn on selection), so
nothing needed a low update rate.

| frames drawn (`ModeWheel.renders`) | before | after |
|---|---|---|
| title, setup hidden (60 f) | 0 | 0 |
| setup idle (120 f) | 120 | **0** |
| turning one card (90 f) | 90 | 61 (the 0.5 s spin + 2) |
| idle after the turn (60 f) | 60 | **0** |

## Still to confirm on a GPU
- Nothing freezes or shows a stale/blank ring after a turn, a window resize, the swing-in, or returning from
  settings / how-to.
- The first PLAY press no longer hitches (compare with a build before this change).
