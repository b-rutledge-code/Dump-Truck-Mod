# Loading hopper

One brush tile stamps a bin on legs with an upper deck around the opening. A dump truck drives through the bay and sits under the chute.

## Layout

| Role | Implementation |
|------|----------------|
| Frame, bin, chute, upper deck, rails | Custom `loading_hopper_*` spriteModels from `generate_hopper.py` → `bake_and_slice.py` |
| Legs | `solid` on the ground posts |
| Upper deck | Strategy **G3**: rim band only on `z=3` with invisible `solidfloor` (+ ForceAmbient); bands 1–2 on `z=0`. See [`hopper-black-blob.md`](hopper-black-blob.md) |

## Footprint (anchor = bay center, ground)

- Columns at x = ±2.40 m, y = ±3.30 m. Ends stay open under the header (clearance about 4.26 m).
- Upper deck is a walk ring around the hopper opening, 0.82 m outside the columns, with a closed rail.
- Chute underside at 3.65 m, outlet 0.82 m square, centered on the bay.
- Bay clear width about 4.58 m.

### Planned 2D tile grid (after early proofs pass)

| Floor | Squares (relative to anchor) | Content |
|-------|------------------------------|---------|
| z=0 | column feet (±2,±3) and (±2,0); open N/S bay | Concrete + low posts; Fill panel on -X,+Y column; vanilla `overlay_grime_wall_01_*` multiply-baked into fz=0 sprites (metal: bottom-weighted + vertical streaks; concrete: soft even stain) |
| z=1 | same column XY | Mid posts / X-brace reads |
| z=2 | column XY + bin footprint | Upper frame + bin body |
| z=3 | deck ring (rim XY; opening center empty) | `solidfloor` + rails |

Stamp via `DumpTruck.placeHopper` (`payload.mode` for proofs). See [`hopper-2d-proofs.md`](hopper-2d-proofs.md).

## Operation

The control is on the outer south (+Y) face of the -X, +Y column (world offset (-3, +3) from the bay centre, the square `DumpTruckHopper.PANEL_DX/DY` points at), at chest height, so you stand at the drive-through end looking into the bay. On foot, right-click any hopper tile. When a dump truck is sitting under the chute and the bed has room, Fill bed walks you up to the control and runs a timed action. Gravel bags go into the bed as the bar advances. The time scales with how many bags this pour moves. Without a dump truck in the bay, or with a full bed, the option is not offered.

Fill needs power on the panel square — the same rule as a fuel pump: `hasGridPower()`, or `AllowExteriorGenerator` with `haveElectricity()`. Without power the menu shows Fill bed (no power) and an in-progress pour stops.

The hopper holds 600 gravel bags on the anchor (`modData.hopperBags`). A full truck bed is 200 bags, so the stock covers three full refills. Each pour fills empty sacks in the bed first, then adds new gravel bags into leftover weight room. It moves `min(those slots, bags left in the hopper)`. When the stock is empty, Fill bed is not offered. Restocking is out of scope; an empty hopper stays empty.

### Mouth gravel indicator

Stock drives a thin gravel surface inside the bin cavity. Bag-count bands pick the plane: `>400` high (~67%+), `>200` mid (~34%), `>100` low (~17%), `>0` very-low (funnel), `0` empty. Each plane is a set of per-cell `hopper_gravel_*` objects at `fz=2`, baked from a gravel disc inside the hopper mesh so the rim and near walls cut the silhouette. Cell layout and shimmer frames live in `LoadingHopperGravelCells.lua` (from `pack_gravel_planes.py`). `DumpTruckHopper.syncGravelVisual` places or clears those objects after stock writes and after a flood stamp, and leaves them alone when the plane is unchanged.

While stock is changing (and for a few seconds after), the client cycles three frames per cell. High is a center-weighted UV noise crawl; mid and low add light inward circular ripples on top of that noise. Very-low stays visual-only with no ripple treatment.

Stepping away, the truck leaving the bay, lost power, a full bed, or an empty hopper stops the pour. Bags already loaded stay in the bed. Fill sound is `DumpTruckHopper.FILL_SOUND` (nil until a clip is chosen).

Interior deck floors are a blue `industry_01_37` grate on the baked walk footprint, with an opaque underlay in the grate holes so elevated tiles meet; the stamp stays inside the walk so the bin mouth stays open. Outer-ring edge squares keep the trimmed painted walkway.

## Placement

`LoadingHopperBind.lua`: place `loading_hopper_0` on ground at bay center. It stamps the piece list and binds spriteModels. `modData.hopperGrid` blocks restamp. After rebuild, delete old hoppers and place a new anchor; restart so tiledefs reload.

Dev: `DumpTruck.placeHopper` hook (PzDevMcp) places/restamps at the player square.

## Build

```bash
cd models/loading-hopper
python3 generate_hopper.py
blender --background --python bake_and_slice.py
# install 42.20 + common into ~/Zomboid/mods/DumpTruckGravelMod
```

`mod.info`: `tiledef=loading_hopper 4731`

## Notes

- 3D stamp lighting freeze (G3): [`hopper-black-blob.md`](hopper-black-blob.md). Elevated `spriteModel` path exhausted; multi-floor **2D** tiles via scripted bake + `placeHopper`.
- Mesh → tileset pipeline (IsoUtils bake, ownership clip, pack, flood): [`hopper-mesh-tileset.md`](hopper-mesh-tileset.md).
- Dig + flood results: [`hopper-2d-digs.md`](hopper-2d-digs.md).
- `generate_hopper.py` / FBX kept as art reference for the 2D look.

## Out of scope

- Stairs and a feed belt
- Hopper restock after the 600 bags are spent
- Vanilla steel tower stamp as the live structure
- Workshop release / `42.13/` mirror
- Further 3D stamp-floor variants (A–H)
