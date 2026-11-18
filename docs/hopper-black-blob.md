# Hopper black blob — investigation notes

Working notes from the I-beam / stamp-floor work (2026-11-16). **Closed:** stamp-floor lighting experiments A–H are exhausted for elevated `spriteModel`s. Product path moves to a multi-floor **2D tile** rebuild (see plan / `loading-hopper.md`).

## Freeze

Pure elevated `spriteModel` stamps cannot be both **day-readable** and **night-correct** on this build (42.22.2):

| Goal | What it required | Side effect |
|------|------------------|-------------|
| Readable top / no black slab | Rim mesh + `solidfloor` on `z=3` (G3) | Deck stays day-bright at night |
| Night matches outdoors | All mesh on `z=0` (H) | Top walk black-holed / shredded |

**Frozen 3D reference in repo:** strategy **G3** (rim @ `z=3` + solidfloor; bands 1–2 @ `z=0`). Keep `generate_hopper.py` / FBX / bake as art reference. Do not reopen A–H stamp variants.

## Settled facts (do not re-discover)

| Stamp situation | 3D mesh look |
|-----------------|--------------|
| Mesh on `z = 0` | Lit; follows outdoor night |
| Mesh on `z = 2` empty-air | Pitch-black silhouette |
| Mesh on `z = 3` with `solidfloor` same square | Readable by day; day-bright at night |
| `solidfloor` @3 alone, no elevated mesh | Black / holed walk (B/E/H) |

`ForceAmbient` tints the **2D** sprite path (`IsoObject.java` ~4119); it does not fix empty-air `z=2` meshes.

## Stamp strategies tried (summary)

A–D: elevated carpets vs torn tops. E/H: all mesh @0 → night OK, top broken. F–G2: shrink elevated footprint → black moves to deck/rails/underside. **G3:** best daytime 3D hold (glowing night deck).

## Confounders

Multiple hoppers / `hasSprite` skips / freefly / I-beam band-2 area / brush=hook same list.

## Current code state

- `slice_hopper.py`: **G3 freeze**
- Next: 2D multi-floor building with early lighting/iso/cutaway proofs

## 2D flood status (2026-11-18)

The black band under the deck's front edges is engine occlusion culling. The z=3 walkway floor cells mark the squares behind them as hidden. Where the outer-ring floor diamonds are not painted, the unrendered background shows as pure black. Full mechanism and evidence: [hopper-2d-digs.md](hopper-2d-digs.md#black-band-under-the-deck-front-edges-2026-11-18).

The fix is applied to the 31 outer-ring walkway cells: `transparentFloor` on the floor tile, and a z=2 square created below each one before the floor is placed. Ground-view check at 09:00 shows no black band under the front edges, and the hopper looks right at night. Under-deck walking and the metric gates are still to be checked.

## Files

| File | Role |
|------|------|
| `models/loading-hopper/slice_hopper.py` | G3 3D reference slice |
| `models/loading-hopper/generate_hopper.py` | Authored meters / I-beam frame |
| `Contents/.../LoadingHopperBind.lua` | Generated stamp list |
| `docs/loading-hopper.md` | Product layout |
