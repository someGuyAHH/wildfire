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

Tools (not shipped): Blender 5.2.4 LTS (GPL), installed portable in `tools/.blender/` (git-ignored).
