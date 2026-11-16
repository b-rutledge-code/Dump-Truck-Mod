# Loading hopper

One brush tile stamps a bin on legs with an upper deck around the opening. A dump truck drives through the bay and sits under the chute.

## Layout

| Role | Implementation |
|------|----------------|
| Frame, bin, chute, upper deck, rails | Custom `loading_hopper_*` spriteModels from `generate_hopper.py` → `bake_and_slice.py` |
| Legs | `solid` on the ground posts |
| Upper deck | Invisible `solidfloor` on the deck level. Deck, rail, and bin-rim meshes stamp one level below, with no floor flag, so they stay drawn when the truck is underneath |

## Footprint (anchor = bay center, ground)

- Columns at x = ±2.40 m, y = ±3.30 m. Ends stay open under the header (clearance about 4.26 m).
- Upper deck is a walk ring around the hopper opening, 0.82 m outside the columns, with a closed rail.
- Chute underside at 3.65 m, outlet 0.82 m square, centered on the bay.
- Bay clear width about 4.58 m.

## Operation

The control is on the outer south (+Y) face of the +X, +Y column, at chest height, so you stand at the drive-through end looking into the bay. On foot, right-click any hopper tile. When a dump truck is sitting under the chute and the bed has room, Fill bed walks you up to the control and runs a timed action. Gravel bags go into the bed as the bar advances. The time scales with how many bags this pour moves. Without a dump truck in the bay, or with a full bed, the option is not offered.

The hopper holds 600 gravel bags on the anchor (`modData.hopperBags`). A full truck bed is 200 bags, so the stock covers three full refills. Each pour fills empty sacks in the bed first, then adds new gravel bags into leftover weight room. It moves `min(those slots, bags left in the hopper)`. When the stock is empty, Fill bed is not offered. Restocking is out of scope; an empty hopper stays empty.

Stepping away, the truck leaving the bay, a full bed, or an empty hopper stops the pour. Bags already loaded stay in the bed. Fill sound is `DumpTruckHopper.FILL_SOUND` (nil until a clip is chosen).

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

## Out of scope

- Stairs and a feed belt
- Hopper restock after the 600 bags are spent
- Vanilla steel tower stamp as the live structure
- Workshop release / `42.13/` mirror
