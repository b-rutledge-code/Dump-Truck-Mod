# Hopper black blob — investigation notes

Working notes from the I-beam / stamp-floor work (2026-11-16). This records what we saw in-game and what the slice code did. It is not a finished fix plan.

## Symptom

Large pitch-black region in or behind the hopper bay when viewed in iso from the ground. Often:

- Fills the open air between the legs / under the bin
- Has a hard stair-step edge (iso tile grid), not a soft shadow
- Distinct from the dark grey deck material and from the dark bin interior

Also seen in the same sessions (may be related or separate):

- Black or missing patches on the upper walkway / bin lip
- A triangular hole in a funnel corner (grass visible through the shell)
- Ghost “extra” steel to the side of the main bay (second hopper footprint)

## Engine facts we verified

| Fact | Evidence |
|------|----------|
| `FLOOR_M = 2.44949` | `slice_hopper.py`; one game floor in mesh meters |
| `DECK_Z = 7.40` → `RIM_LEVEL = 3` | `floor(7.40 / 2.44949) = 3` |
| Mesh verts keep absolute Z; stamp `fz` only chooses which square owns the object | Slice export origin uses `stamp_fz * FLOOR_M`; verts are not rebased to zero |
| Tile props on mesh pieces: `invisible`, `alwaysDraw`, `NeverCutaway`, `ForceAmbient` | Written in `write_tiles` / `loading_hopper.tiles` |
| `ForceAmbient` in Java tints the **2D** `IsoObject` sprite path via ambient | `IsoObject.java` ~4119; does not prove 3D spriteModel lighting |
| 2D hopper pack tiles are almost all fully transparent (only `_0` has opaque pixels) | PIL on `texturepacks_src/hopper/*.png` |
| Empty-air squares at `z > 0` light spriteModels poorly → black 3D | Matches mid-bay blob whenever a large carpet of mesh stamps sits on `z = 2` |

### Floor bands (mesh Z → clip band)

| Band `fz` | Z range (m) | Notable geometry |
|-----------|-------------|------------------|
| 0 | 0 – 2.45 | Concrete feet, low girts |
| 1 | 2.45 – 4.90 | Header (~4.40), outlet (~3.65), lower funnel, mid braces |
| 2 | 4.90 – 7.35 | Upper columns, top chords, bin body, deck **underside** (~7.32) |
| 3 (rim) | 7.35 – … | Deck **top** (~7.40) and a thin top sliver of the deck box |

The deck box is only ~8 cm thick (`7.32`–`7.40`) and **straddles** the band 2 / band 3 split.

## Stamp strategies tried

Each row is a real bake + deploy + in-game look (PzDevMcp screenshot). Piece `dz` = world stamp floor in `LoadingHopperBind.lua`.

| # | Stamp rule | Typical piece `dz` | Observed |
|---|------------|--------------------|----------|
| A | Band 1 → `z=0`; bands 2+3 → `z=2` (`RIM_VISUAL`) | ~40 @0, ~80 @2, ~40 @3 floors | Mid-bay black **reduced** when only band 1 was the problem; with chunkier I-beams, **band 2** still filled the bay on `z=2` → black blob **returned** |
| B | All elevated bands → `z=0`; solidfloor @3 | ~79 @0, ~40 @3 | Mid-bay black **gone** (steel lit). Walk `solidfloor` @3 without mesh companions on `z=2` showed as **black / holed top deck** |
| C | Band 1 → `z=0`; band 2 split at `DECK_KEEP_Z=6.9` (lower→0, near→2); rim→2 | Mixed 0/2/3 | Top still wrong; funnel/deck corners torn where one member was split across stamps |
| D | Band 1 → `z=0`; **whole** band 2 + rim → `z=2` | ~39 @0, ~80 @2, ~40 @3 | Deck/bin lip more intact than C, but **mid-bay black blob back** (large `z=2` mesh carpet) |
| E (current deploy) | All elevated mesh → `z=0`; solidfloor @3 with `ForceAmbient` + `invisible` + `alwaysDraw` + `NeverCutaway` | **79 @0, 40 @3** (no `z=2` mesh) | Intended to keep bay lit and stop black walk floors. Last screenshots still showed **other** black regions and a **funnel corner hole**; not signed off |

## Confounders (made sessions look like circles)

1. **Multiple hoppers in one field.** `DumpTruck.placeHopper` was called many times at nearby squares. Old anchors outside a 6-tile clear left ghost steel and black patches beside the “current” hopper. Clear radius was later widened to 20 and place now scrubs other anchors first (`LoadingHopperBind` from slice template).
2. **`hasSprite` skip on restamp.** If a leftover piece with the same sprite name sat on a square, stamp skipped placing the new one → missing corners that looked like mesh bugs.
3. **Freefly / camera.** Debug coords sometimes showed `x` ≈ player−2000 while the hopper sat at the real square; easy to screenshot the wrong structure or an overlap.
4. **I-beam pass increased band-2 surface area.** Same stamp rule A that was “good enough” with box columns put much more unlit mesh on `z=2` after columns/rings became I-sections.

## Current code state (repo + last deploy)

- `slice_hopper.py` `mesh_cells`: band 1 → `z=0`; band 2 + rim → `RIM_VISUAL` (`z=2`) — strategy **D** (top intact; mid-bay black may still show on `z=2` carpet)
- Strategy **E** (all mesh → `z=0`) lit the bay but shredded the walk/bin lip; rolled back
- Deck walk: invisible `solidfloor` on `RIM_LEVEL` (3), with ForceAmbient set
- `DumpTruck.placeHopper`: clears hopper sprites in ±20 tiles (including other anchors), then places one fresh stamp

## What is still open

- Whether strategy **E** fully kills the mid-bay blob on a **single clean** hopper after a client restart that loads the new `.tiles` / FBX (last verify pass was noisy: leftover field hoppers, possible cutaway, funnel hole).
- Whether `ForceAmbient` on `z=3` solidfloors is enough for the walk ring when all deck **mesh** lives on `z=0`.
- Funnel corner hole: consistent with geometry **split across band 1 (`z=0`) and band 2 (when it was on `z=2`)**, or with missing/skipped tiles from overlaps — not fully isolated.
- Whether 3D spriteModels can be lit correctly on `z=2` at all on this build (42.22.2), or only by owning the mesh from a `z=0` square.

## Files

| File | Role |
|------|------|
| `models/loading-hopper/slice_hopper.py` | Floor clip, stamp floor, `.tiles` props, bind Lua |
| `models/loading-hopper/generate_hopper.py` | Authored meters / I-beam frame |
| `Contents/.../42.20/media/lua/client/DumpTruck/LoadingHopperBind.lua` | Generated stamp list + clear/place |
| `docs/loading-hopper.md` | Product layout (points at current stamp intent) |
