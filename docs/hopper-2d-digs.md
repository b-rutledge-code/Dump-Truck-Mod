# Hopper 2D digs

Lab notes for the mesh→tileset path. Each dig states the hypothesis, the measured result, and what locked into the bake/stamp pipeline. Product stamp remains G3 ([`hopper-black-blob.md`](hopper-black-blob.md)).

Stamp modes: [`LoadingHopperProof.lua`](../Contents/mods/DumpTruckGravelMod/42.20/media/lua/client/DumpTruck/LoadingHopperProof.lua). Constants: [`pz_iso.py`](../models/loading-hopper/pz_iso.py). Pipeline: [`hopper-mesh-tileset.md`](hopper-mesh-tileset.md).

## Dig 1 — footing registration

**Hypothesis.** A custom baked sprite shares the engine’s floor footing with vanilla tiles.

**Result.** Engine draws at `XToScreen/YToScreen(square)` minus `(32*s, 96*s)`. North corner of a cell lands on sprite pixel `(64, 192)`; floor diamond fills rows 192–256; cell-centre floor is row 224. Reference: shipped `dumptruck_pour_03.png` bbox rows 192–256.

**In-game.** `calib` places `floors_exterior_tilesandstone_01_4` beside a custom deck floor at `z=3`; shared edge is collinear while standing on the pair.

**Locked.** `FOOTING=0.75`, north-corner `world_to_sprite`, engine offset `(64*(gx−gy), 32*(gx+gy) − 192*fz)`.

## Dig 2 — adjacent deck floors

**Hypothesis.** Two neighbouring modelled deck cells at `z=3` stamp as one walkable platform.

**Result.** `DIG2_CELLS = (0,2,3), (1,2,3)` (fully on the deck ring). `dig2_seam_metric.py` on the pasted composite: fill 1.000 / 1.000, seam 1.000 / 1.000 (inset 0.02 m, gates ≥ 0.95) → **PASS**.

**In-game.** Both cells `placeFloor`; player stands at `z=3`.

**Locked.** Deck floor = deck-level surfaces up to `DECK_SURFACE_Z + 0.005` outside the bin mouth; stamp `kind=floor` via `addFloor`.

## Dig 3 — column stack

**Hypothesis.** One column through floors 0–2 plus deck floor and rail-edge neighbour reproduces the single render across floor joints.

**Result.** `DIG3_CELLS = (2,-4,0..3), (3,-4,3)`. `stack_truth_metric.py -- --dig3`: deck shown 30,736 px and deck hidden 27,651 px, each with 0 uncovered, 0 extra, 0 colour diff → **PASS**.

**Locked.** Dig3 is the column-restricted stack-truth check.

## Fixture

**Hypothesis.** Sample foot + fully-decked rim cells (bin mouth excluded) place as a continuous walk surface.

**Result.** `FIXTURE_CELLS` updated off the bin mouth. Used as a fast bake set; full flood is the accept stamp.

## Full-render crop

**Hypothesis.** Floor-joint bands come from rendering each cell from its own plane-cut fragment: the fragment loses the shadows of the rest of the hopper, and the cuts re-split faces of the open, smooth-shaded shell. Cropping every sprite from one uncut render, with per-pixel ownership from world position, removes them.

**Baseline.** The previous per-cell bake pasted at engine offsets against one uncut render: dig3 column mean |RGB| 14.7/255, 52% of pixels off by > 8/255 or missing; whole hopper 16.9/255, 55%. In-game the legs showed lighter bands at floor joints and the deck had no rail shadows.

**Mesh facts.** Deck slab underside at z 7.32 and support beam tops at z 7.29, both below the level-3 floor plane (`3 * FLOOR_M` = 7.348). `DECK_LAYER_Z = 7.30` puts the whole slab on the deck level, so hiding the deck level hides the slab underside too.

**Under-deck render.** A geometry cut at `DECK_LAYER_Z` changed the shading of the long leg faces below it: lighting agreement 0.890, max diff 41/255 on the upper legs. A shader cut on the uncut mesh (transparent to camera above `DECK_LAYER_Z`, opaque shadow) gives agreement 1.00000, max diff 0.

**Result.** 
- Canvas 1408×1472. 502,662 positioned pixels in `full` and 378,076 in `under`; 0 fringe pixels unowned, 0 pixels outside their sprite rect.
- 235 sprites: 76 floor, 159 object. Floor cells are the same 76 squares as before. 2 sprites own fewer than 64 pixels; pack keeps all 235.
- `stack_truth_metric.py`:
  - Reprojection max 0.361 px (full and under).
  - Lighting 263,838 px at 1.00000.
  - Deck shown 525,892 px and deck hidden 398,581 px, each with 0 uncovered, 0 extra, 0 colour diff → **PASS**.
  - `--packed` gives the same → **PASS**.
- `footing_seam_metric.py`: seam 0.958 / 0.938, rgb_agree 1.000 → **PASS**.
- `mouth_gate.py` (manifest and packed) → **PASS**.

**Locked.** Sprites are crops of the two uncut renders; ownership by surface world position; 2 px dilation into identical pixels.

## Full flood

**Hypothesis.** The full bake + flood stamp reads like the uncut render in game.

**Result.** Stamp `flood` at (19176, 1087, 0): **placed 235, failed 0**.
- **Noon, freefly** (`~/Zomboid/Screenshots/pz-dev-mcp/zband-after-noon.png`): legs, braces and footings continuous across floor joints and match the render; deck shows rail shadows.
- **Player under the deck** (standing at the anchor): deck stays drawn.
- **Player behind the front leg** (19177, 1089): leg and footing draw over the player with the engine silhouette. The engine fades the deck in this pose, and the under-deck layer shows the bin walls and leg tops complete beneath it.
- **Night** (`zband-after-night.png`): structure follows outdoor dark.
- Console: no hopper errors.

**Measured residual (engine side; packed sprites equal the render offline).** These were already present with the previous bake.
- NW and NE deck rails draw black while the front rails draw light grey. Cause: occlusion culling ([black band](#black-band-under-the-deck-front-edges-2026-11-18)).
- A black band shows below the deck's front edges. Cause: occlusion culling (same section).
- Deck tiles alternate slightly in brightness.

## Bake path locked

| Piece | Value |
|-------|--------|
| Projection | IsoUtils `tileScale=2`, sprite `128×256`, north corner → `(64, 192)` |
| Camera | One ortho canvas camera from `camera_basis_world()`; world origin on an integer pixel |
| Renders | `full` and `under` (shader deck cut at `DECK_LAYER_Z = 7.30`), RGBA PNG + float EXR position |
| Ownership | `point_owner`: cell of surface point; deck level `z ≥ 7.30`; fringe → nearest owner within 2 px |
| Sprites | 128×256 crops at engine offsets; `MASK_PAD_PX = 2` dilation; every non-empty owner emits |
| Deck floor | Deck level up to `DECK_SURFACE_Z + 0.005`, outside the mouth; `kind=floor` → `solidfloor` + `placeFloor`; texture trimmed to the deck-top bounding box, `frame_offset` = box origin, `frame_size` 128×256 |
| Deck upper | Deck level above the walk surface and on the mouth; `kind=object` + `NeverCutaway` |
| Columns | `SOLID_XY` = `(-3,-4) (2,-4) (-3,3) (2,3) (-3,-1) (-3,0) (2,-1) (2,0)`; collision from a south-tip blocker tile (`kind=blocker`), post sprites draw opaque |
| Mouth | `BIN_MOUTH_XY` = `(-1,-1) (0,-1) (-1,0) (0,0)` — no floor |

## Baked shading

The renders are ambient-only: the grey world (background 0.55) lights the hopper, with no sun. Cast shadows and sun-facing brightness are not baked into the sprite pixels. The engine's per-square lighting supplies time of day at runtime.

**Measured.** `stack_truth_metric.py --packed`: reprojection PASS on both renders; lighting same-surface agreement 1.00000 (PASS); deck shown 0 uncovered, 0 extra, 0 colour diff (PASS); deck hidden 0 / 0 / 0 (PASS). The packed reader places each sprite's texture at its toml `frame_offset` inside a 128×256 frame. `mouth_gate.py --packed` PASS.

**Black band check after the change.** With the sun removed, the black band under the deck front edges is still visible in the ground view. Cast shadows are not its source.

## Black band under the deck front edges (2026-11-18)

**Cause: engine occlusion culling behind the walkway floor cells.** The band is unrendered background. Every band pixel in the in-game captures is exactly (0, 0, 0) (45,519 px in the original ground view), constant across day, night and bake lighting.

How the engine produces it (decompiled `zombie/iso/fboRenderChunk/`):
1. `FBORenderCutaways.ChunkLevelData.calculateOccludingSquares` projects each upper-level square onto the ground grid at `(x − 3z, y − 3z)` and records the highest covering level in `occludedGrid`. A square counts as covering when `getVisionMatrix(0, 0, −1)` is set (a `solidfloor` without `transparentFloor`, per `IsoGridSquare` ~7520) **or** when no square exists directly below it at `z − 1`.
2. `FBORenderOcclusion.isOccluded(x, y, z)` returns true when the square's own cell and the cells up to three steps north-west of it (its full 128×256 screen column) are all covered by a higher level.
3. `FBORenderCell` (~1290, ~3401) draws a square only when `!isOccluded(...)`. Culled squares draw nothing: no ground tile, grass, legs or bin pieces.
4. The engine treats each covering floor as an opaque diamond. Wherever the walkway floor sprite leaves part of its diamond transparent, the culled area behind it shows as black.

Where it happens: the 76 walkway floor cells span gx −4…3, gy −5…4. Projecting each cell's diamond onto the z=3 plane over `full.png` gives the share of diamond pixels that nothing in the render covers. Interior cells are 0%. The uncovered pixels sit only in the outer ring: gx = −4 (all cells), gy = −5 and gy = 4 (all cells), and gx = 3 except gy = 3 (which is 0%). Across the 76 cells, 54,762 of 312,000 diamond px (17.6%) are uncovered. Those are the band under the front edges and the back-rail area (the "NW and NE deck rails draw black" residual in [Full flood](#full-flood)).

How the tests fit the cause:
- Skipping the walkway floor cells removes the covering floors, so nothing is culled and the band is gone.
- Removing `solidfloor` leaves the band: the edge cells have no square at z=2 below them, which counts as covering on its own.
- Removing the sun, changing time of day and trimming the texture leave the band: the culled area is never drawn.
- An alpha-0 colour in the corners leaves the band black; an opaque magenta frame or opaque slab-grey corners paint over the holes.

**Evidence from the shipped data.**
- No referenced hopper sprite has opaque near-black pixels (alpha > 200, RGB max ≤ 8). The darkest opaque pixels are dark blue steel and grey shadow.
- The deployed pack matches `models/loading-hopper/2d_tiles/` for every referenced sprite.
- The deployed pack also holds 98 unreferenced `hopper_2d` entries (indices 236–333) from earlier builds. The Lua table does not reference them.

**In-game A/B** (ground view at (19141.8, 766.1, 0), flood anchor (19143, 770), 09:30 daylight):
- **Walkway floor cells skipped** (`kind=floor` returns placed without `addFloor`): the band is gone. Columns, bin, and legs unchanged.
- **`solidfloor` removed from walkway tiles:** the band remains. The walkway draws, and the player holds z=3 on it after a teleport.
- **Walkway frames filled with opaque magenta over the full 128×256 frame:** magenta covers the band area under the front edges. Magenta also extends past the deck rail on the front and left sides, matching the earlier overhang report.
- **Walkway textures trimmed to the deck-top bounding box** (frame offset kept, frame 128×256): the overhang past the rail is gone. The band remains.

**Measured.** The 76 trimmed walkway boxes total 428,136 px. 280,377 px (65%) are transparent: the empty corners of each rectangle, which sit below the deck's front edges.

**Corner tests.** With alpha 0 and slab-grey RGB in the lower empty corners of each trimmed box, the band stays black. With opaque slab grey (52, 50, 48), the band renders at (36, 34, 32), the deck-top tone, and the packed deck-shown gate fails (1,090 extra px, 1,864 colour diff). Opaque corners paint over the culled area, which also covers real bin and leg content behind it. The pack builder ships trimmed walkway textures with transparent corners.

**Fix (applied 2026-11-18).** The 31 outer-ring walkway cells (the set above, `is_edge_cell` in `pack_2d_tiles.py`) do two things:
- Their floor tile carries `transparentFloor` next to `solidfloor`. `IsoGridSquare` (~7521) stops treating a transparent-floor square as covering, and it keeps the walkable solid floor. The engine clears `transparentFloor` only when another non-transparent solid floor shares the square (~7839). Each walkway square has one floor, so the flag holds.
- Before the floor is placed, the game creates the square one level below (`squareAt(x, y, z − 1)` in `LoadingHopperProof.lua`, `placeCell`). This removes the second covering rule, "no square directly below at z − 1".

The pack writes `transparentFloor` into `loading_hopper.tiles` and `edge = true` into `LoadingHopper2dCells.lua` for these cells.

**Result (ground view at (19141.8, 766.1, 0), 09:00, after a restart and re-stamp).** No near-black pixels under the deck front edges. The 263 near-black pixels that remain in the crop are on the truck and bin, below the deck.

**Night (user check, in game).** The hopper looks right at night.

**Not yet verified.**
- Walking under the deck and standing behind a leg.
- `stack_truth_metric.py` gates after the change.
- The occluded-squares overlay in the Chunk Debugger, which I could only partly read.

## Metrics

```bash
cd models/loading-hopper
blender --background --python stack_truth_metric.py
blender --background --python stack_truth_metric.py -- --dig3
blender --background --python stack_truth_metric.py -- --packed   # after pack
python3 dig2_seam_metric.py
python3 footing_seam_metric.py
python3 mouth_gate.py
```

## Out of scope

- Replacing live G3 with flood as the product stamp
- Driving a truck through the flooded bay
- TileZed authoring
- Stairs / feed belt / restock
- Soft alpha feather between cells
- Changing engine per-square lighting (deck tile brightness alternation)
- Disabling engine occlusion culling
