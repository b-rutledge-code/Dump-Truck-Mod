# Hopper mesh → tileset pipeline

Scripted path from `loading_hopper.fbx` to in-game `hopper_2d_*` stamps. TileZed is optional QA only.

Dig hypotheses, results, and locked learnings: [`hopper-2d-digs.md`](hopper-2d-digs.md).

## Stages

1. **Shared projection** — [`models/loading-hopper/pz_iso.py`](../models/loading-hopper/pz_iso.py)  
   IsoUtils `XToScreen` / `YToScreen` at `tileScale=2`, `FLOOR_M = sqrt(6)`, sprite `128×256`. North corner of cell `(gx,gy,fz)` → sprite pixel `(64, 192)`. Cell sprites sit at engine offsets `(64*(gx−gy), 32*(gx+gy) − 192*fz)` (`engine_offset`). `canvas_layout` places world `(0,0,0)` on an integer canvas pixel so every cell sprite is an integer-aligned 128×256 window. `point_owner(x, y, z)` gives the owning cell and kind of a surface point.

2. **Bake** — [`bake_2d_tiles.py`](../models/loading-hopper/bake_2d_tiles.py) (Blender, GPU)  
   One ortho canvas camera renders the uncut hopper twice, each as an RGBA PNG (sun 3.2, grey world, 16 TAA samples, default view transform) plus a world-position EXR (emission override, 1 sample, filter 0, 32-bit float):
   - `full` — the whole hopper.
   - `under` — the same mesh with every surface at or above `DECK_LAYER_Z = 7.30` transparent to the camera through a shader cut; its shadow stays opaque (`use_transparent_shadow = False`). The mesh stays uncut, so shading below the deck is bit-identical to `full`.

   Ownership per pixel:
   - Cell `(floor x, floor y)`; level `3` for `z ≥ DECK_LAYER_Z`, else `floor(z / FLOOR_M)` clamped to 0–2.
   - Deck kind `floor` up to `DECK_SURFACE_Z + 0.005` outside `BIN_MOUTH_XY`, `upper` above it and on the mouth.
   - Alpha-only fringe pixels take the nearest positioned owner within 2 px.

   Layers and crops:
   - Deck sprites crop `full`.
   - Lower sprites crop `lower.png`, which is `full` where it shows a level 0–2 surface and `under` behind deck pixels.
   - Each mask grows by `MASK_PAD_PX = 2` into identical pixels of its own source image.
   - Every owner with at least one pixel emits a sprite.

   Outputs:
   - `2d_tiles/*.png` and `2d_tiles/manifest.txt` (`gx gy fz kind filename`, `kind` ∈ `{floor, object}`).
   - `2d_tiles/_render/`: the four renders, `lower.png`, `deck.png`, owner maps (`*_own.npy`) and `layout.json`.

3. **Pack** — [`pack_2d_tiles.py`](../models/loading-hopper/pack_2d_tiles.py)  
   Ownership-hull clip, pack entries, `hopper_2d.tiles`, `LoadingHopper2dCells.lua` (`kind` + `sprite`). `Hopper2dDeckAsFloor = true`. Baked pixels already lie inside their hulls; `stack_truth_metric.py -- --packed` confirms the packed sprites reproduce the renders exactly.

4. **Deploy** — `scripts/deploy.sh` → `~/Zomboid/mods/DumpTruckGravelMod` (restart client so tiledef/pack reload).

5. **Stamp** — `DumpTruck.placeHopper` modes: `calib`, `dig1`, `dig2`, `dig3`, `fixture`, `flood`, `floorpath`. Anchor z forced to `0` for multi-floor modes; `clearArea` (radius 20) runs before each stamp. `kind=floor` → `placeFloor`; `kind=object` → `IsoObject`.

## Commands

Blender renders need the GPU (run outside the agent sandbox).

```bash
cd mods/DumpTruckGravelMod/models/loading-hopper
blender --background --python bake_2d_tiles.py                # full
blender --background --python bake_2d_tiles.py -- --dig2      # write only DIG2 crops
blender --background --python bake_2d_tiles.py -- --dig3
blender --background --python bake_2d_tiles.py -- --footing
blender --background --python bake_2d_tiles.py -- --fixture
blender --background --python stack_truth_metric.py
blender --background --python stack_truth_metric.py -- --dig3
python3 dig2_seam_metric.py
python3 footing_seam_metric.py
python3 mouth_gate.py
python3 pack_2d_tiles.py
python3 mouth_gate.py --packed
blender --background --python stack_truth_metric.py -- --packed
../../scripts/deploy.sh
```

```text
exec_dev hook DumpTruck.placeHopper payload {"mode":"calib"}
exec_dev hook DumpTruck.placeHopper payload {"mode":"dig2"}
exec_dev hook DumpTruck.placeHopper payload {"mode":"dig3"}
exec_dev hook DumpTruck.placeHopper payload {"mode":"fixture"}
exec_dev hook DumpTruck.placeHopper payload {"mode":"flood"}
```

## Accept gates

| Gate | Pass |
|------|------|
| Registration | Deck floor bbox rows ~192–256; `calib` shared edge collinear with sandstone @ z=3 |
| Position reprojection | `stack_truth_metric.py` — every decoded world point within 0.5 px of its pixel centre (full and under) |
| Lighting preserved | `stack_truth_metric.py` — same surface in `full` and `under`, 2+ px from the deck silhouette: RGB within 2/255 on ≥ 99.5% |
| Deck shown | `stack_truth_metric.py` — lower then deck sprites (replace) equal `full.png`: 0 uncovered, 0 extra, 0 colour diff |
| Deck hidden | `stack_truth_metric.py` — lower sprites alone equal `lower.png`: same zeros |
| Dig3 stack | `stack_truth_metric.py -- --dig3` — both truth checks on `DIG3_CELLS` pixels |
| Packed | `stack_truth_metric.py -- --packed` — all checks on the shipped sprites |
| Dig2 seam | `dig2_seam_metric.py` on the pasted composite: fill ≥ 0.95 and seam ≥ 0.95 |
| Footing RGB | `footing_seam_metric.py` on the pasted composite: seam ≥ 0.90, rgb_agree ≥ 0.85 |
| Mouth | `mouth_gate.py` — no `kind=floor` on `BIN_MOUTH_XY` |
| Full flood | All manifest cells place; legs continuous across floor joints; bin mouth open; day/night outdoor lighting |

## Props (`hopper_2d.tiles`)

- `solidfloor` on `kind=floor`
- Object sprites (`kind=object`, `kind=upper`): alpha is hardened to 0 or 255 at threshold 128 (`harden_alpha` in `pack_2d_tiles.py`). Partly transparent edge pixels blended with the ground and read as a green halo on the steel. Floor sprites keep their alpha.
- `transparentFloor` on the outer-ring floor cells (`is_edge_cell` in `pack_2d_tiles.py`, `edge = true` in `LoadingHopper2dCells.lua`). Their z=2 square below is created by `placeCell` in `LoadingHopperProof.lua` before the floor is placed. See [black band](hopper-2d-digs.md#black-band-under-the-deck-front-edges-2026-11-18).
- Floor sprites (`kind=floor`): texture is the deck-top bounding box of the cell's walk surface; `frame_offset` = box origin inside the 128×256 frame; `frame_size` = 128×256. The engine draws the trimmed texture at that offset.
- `NeverCutaway` on `kind=object` with `fz >= 1`
- Column collision: one blocker tile, the last index, carries `solid`. `LoadingHopper2dCells.lua` lists it as `kind=blocker` on every `SOLID_XY` square at `fz==0`. Its texture is 1×1 transparent with `frame_offset = [64, 255]` in a 128×256 frame, so the texture rect sits at the cell's south tip. The engine fades `solid` objects whose texture rect overlaps the player bounds on the player's level (`FBORenderCell.isObjectObscuringPlayer`). The south-tip rect stays clear of those bounds, so the visible post sprites (no `solid`) and the blocker both draw opaque while the posts still block movement.

`mod.info`: `tiledef=hopper_2d 4732`

## Out of scope

- TileZed required to author v1
- Replacing live G3 with flood as the product stamp
- Hybrid vanilla post/sandstone structure
- Stairs / feed belt / restock
- Mirroring into older version folders
- Soft alpha feather between cells
- Changing engine per-square lighting
