# 9. Working with the owner

The project belongs to one developer who designs, playtests and directs. The agent does almost all
of the implementation. These are the standing rules and habits from the sessions so far.

## Hard rules (they've said these explicitly)

1. **Godot runs headless only.** Never open a game or editor window on their desktop: no windowed
   screenshot runs, no benchmarks. If something genuinely needs a rendered frame or GPU numbers,
   **ask first**. (They were very angry the one time a window popped up.)
2. **Every simulation or long-running program goes under `timeout`**, sized to ~2–3× the expected run,
   with `--fixed-fps 120` for Godot sims. Prefer several short runs over one long batch. A test once stalled
   for 24 minutes unnoticed.
3. **Stay inside the project folder.** "You may not access outside your cwd unless explicitly given
   permission to do so." That includes reading `~/.local/share/godot/...` (the user settings file) or
   checksumming it. Those reads were denied.
4. **Never press Reset or save settings from tests run against the real game**: it would overwrite their
   own settings.
5. **Commit freely, push never.**
   - Commit each finished **and verified** logical change on `master` yourself, one commit per change, without asking.
   - Messages: a short subject naming the change, then a body with what and why.
   - **Never** push, tag, create branches or PRs, or rewrite history unless asked.
   - Don't commit broken or unverified work, and don't sweep the editor's own re-saves into your commits.

## How they work

- **They playtest in the Godot editor** (the game runs embedded in the editor) and report back in
  **numbered lists**, often 10+ items mixing bugs, questions and feature requests, with
  screenshots referenced by number ("[3]", "[5-6]"). Answer every item, by number. Some items are
  questions ("Are the short cut metal rods intentional?", "Could you explain what's happening there?").
  Answer those plainly, then fix the problem.
- **They retract things casually:** "My bad, no. 1 isn't a bug... ignore that one." Drop it.
- **They will revert what they don't like:** "nvm rewind the map swap fix, it's worse now. It'd been
  better". Revert cleanly (`git revert`) and don't argue.
- **They make design calls:**
  - "Real room, no illusion whatsoever."
  - "Move it to the far left corner of the Iron Gallows. It's darker there."
  - "Spire pads: keep the vertical, increase the horizontal."
  - "Make the rooms bigger and unique."
  - "More creative names."

  When there's a real design fork, ask (a short multiple-choice question works well; they answer
  quickly). Otherwise pick the sensible option, do it, and say what you picked.
- **Fairness to bots matters to them:** "They can't wall jump up here unlike me, this is unfair. Make
  links." Bots must be able to use what the player can.
- **They swear when frustrated**, especially at regressions or a blocker that stops testing ("I can't
  test the game further because of the fly switch off clipping bug"). Take that as a priority signal:
  fix the blocker first, and don't apologise at length.
- **They catch generalised mistakes:** "Same mistake with roughly every single ramp." Fix the rule in
  the generator, regenerate everything, and say that you did.
- **Visual quality is judged by eye.** Headless checks can't confirm looks, so always say what
  wasn't visually verified and ask them to check it.

## Reporting back

- Lead with what changed and whether it's verified. Give the check results as numbers (pads 29/29,
  0 stuck, …). State plainly what couldn't be checked headless.
- When something is a design trade-off or a technical limit (shadow resolution, adaptive VSync),
  explain the cause in plain words, then give the fix or the setting.
- Keep answers organised by their item numbers. Don't pad them.

## Their machine

- Linux (Debian, kernel 6.12), **Intel Iris Xe** integrated GPU, screen 3072 × 1602.
- Graphics defaults are tuned for it (render scale 0.6 with FSR; SSAO and MSAA off).
- Any rendering-cost change matters. Measured costs: SSAO ~10 ms, MSAA 2× ~9 ms, glow ~5 ms; the Jungle GPU frame is ~15.6 ms at defaults.
- Godot 4.7.2 is on PATH as `godot`. The Linux export goes to `~/Desktop/Wildfire.x86_64`.
