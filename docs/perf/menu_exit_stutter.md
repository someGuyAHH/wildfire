# Match setup exit stutter

## Symptom
Leaving the match setup screen (the boxes pop up and fall off while the title slides back) stuttered on
real hardware. Menus already run at about 45-77 fps (13-27 ms frames), so there is little budget to lose.

## Measured (headless, `tools/checks/menu_exit_perf.gd`, `--fixed-fps 120`)
Script / layout / scene-tree cost only. Headless has no GPU, so shader compiles, render-target allocation
cost and GPU frame time were **not** measured. What was counted instead is how often the carousel's
full-screen 3D viewport is resized, which is what costs on a real GPU.

| | before | after |
|---|---|---|
| exit, mean CPU per frame | 1.09 ms (idle 0.46) | 1.15 ms |
| exit, worst frame | 4.87 ms | 4.86 ms |
| carousel control `resized` during one exit | **316** | **0** |
| carousel 3D SubViewport size changes during one exit | **312** | **0** |

The CPU time never mattered (about 1 ms); the viewport resizes did.

## Root cause
`ModeWheel` holds a full-screen `SubViewportContainer` (stretch on) with a 3D `SubViewport` (4x MSAA). The
boxes were moved by writing their `offset_left/top/right/bottom` one after another. Between the writes the
wheel (a full-rect box) briefly had a different size, so every frame it emitted `resized` several times,
the stretching container resized its `SubViewport` each time, and the viewport reallocated its
render targets (1080p with 4x MSAA) again and again, about 300 times in one exit. The build-in
had the same problem.

(A first attempt moved boxes with `position`; that let PLAY's size drift, see the commit history.)

## Fix
- Boxes move with Control's **offset transform** (`offset_transform_position`, `_rotation`, pivot ratio
  0.5, Godot 4.7): visual only, no size, anchor or layout change, so nothing resizes. Resting state is
  the transform switched off, so a box can't end up anywhere but its laid-out rect.
- While the boxes fall, the carousel's 3D viewport is set to not re-render (`ModeWheel.set_live(false)`;
  nothing in it changes), and back on when the setup is shown again.
- The fall's duration estimate had its sign wrong (it only sized the safety cap): fixed.

## Not covered / still open
- GPU compile hitches (first rotation of a material, first use of a shader) cannot show up headless. The
  fall adds no new materials or shaders and creates no nodes per frame, but this was not verified on a GPU.
- The first time the setup is shown there is a one-off ~22 ms frame (building the carousel's card
  viewports and first layout). It happens at PLAY, not in the exit; not touched.
- While the setup is shown idle, the carousel's 3D viewport re-renders every frame at full-screen 4x MSAA
  even though it only changes when it turns. Rendering it only when it changes would save that cost on
  every setup frame; not done.
