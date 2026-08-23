# Plan: road overlays — add and remove

Two stages, each its own branch off `main`, merged in order. Highest versioned folder only (`42.20/`).

1. **Multi-overlay foundation** (e.g. `feature/multi-edge-blends`) — a road tile carries one blend per exposed face; place, remove, classify and cleanup manage the attached list per sprite. **Status: done on `feature/multi-edge-blends`** (`scripts/run-overlay-tests.sh` green).
2. **Shovel heal** (e.g. `feature/shovel-overlay-heal`) — the use cases below, built on stage 1. **Status: implemented on `feature/multi-edge-blends` alongside stage 1** (`scripts/run-overlay-tests.sh` green); in-game verify pending.

## Stage 1: multi-overlay foundation

**Status: implemented** on `feature/multi-edge-blends`. Unit tests green (`overlay_classify_test`, `band_raster_test`, `edge_blend_test`).

The engine already stores a list: `AttachExistingAnim` appends, `IsoObject.save`/`load` and the `syncOverlay` command carry every attached sprite. The changes make our writers stop enforcing a single winner.

- **`placeEdgeBlend`** keeps blends on other faces. It skips only an identical sprite, and replaces a same-direction blend of another material by removing that one sprite first.
- **`removeAttachedSprite(square, spriteName)`** — new primitive in `DumpTruckOverlays`: rebuild the floor's attached list without that sprite (the engine offers only `RemoveAttachedAnims()`, so remove-one is clear-then-reattach the keepers), then sync. `removeOverlay`'s full clear remains for whole-square resets (shovel restore, gap-filler conversion).
- **`removeEdgeBlendsBetweenPourableSquares`** removes only the stale-direction blends and keeps the rest of the list.
- **`classify` reports every blend**: the edge-blend result carries all directions present (gap filler still wins when a triangle is attached). `getEdgeBlendDirection` per sprite already exists; the change is not stopping at the first hit.
- **`addEdgeBlends`** places a blend on every exposed direction of an end square instead of the dominant one only — a diagonal staircase's outer corner takes both faces.

### Stage 1 tests (`tests/`, run by `scripts/run-overlay-tests.sh`)

- `overlay_classify_test.lua`: classify with zero, one, and two blends attached — all directions reported; triangle plus blend still classifies as gap filler. **Done.**
- `edge_blend_test.lua`: a corner square exposed on two perpendicular faces gets both blends; placing the second blend keeps the first; same-direction different-material replaces only that sprite. **Done.**
- New coverage for the remove path: remove one direction and the other survives; stale-blend cleanup removes the stale direction and keeps the live one; full clear still empties the list. **Done.**

## Stage 2: shovel heal — use cases

### 1) Add gravel on a tile next to an existing road

Player pours onto open ground beside poured road.

**Result:** new full poured floor with a complete `shovelledSprites` stamp (base + attached, vanilla-style). `smoothRoad` puts edge blends on poured-to-terrain faces and gap fillers only in L-pockets (open ground with exactly two full-road neighbours). Open ground with three or four road neighbours stays open; road faces get blends only.

**Path:** dump / `smoothRoad`.

**Refill note:** Pouring back into an open square left by UC2–UC6 is this same path. A square with three or four full-road neighbours still does not get a gap filler.

### 2) Remove a full road tile from the edge (2 or 3 full-road neighbours)

Player shovels a **full** poured floor with two or three cardinal neighbours still full road.

**Result:** removed square is prior terrain. Remaining full-road faces into that open square get edge blends. Gap fillers only on other open neighbours that are true L-pockets. The removed square never gets a gap filler or new road from this path. Three road neighbours is not an L-pocket — open terrain with blends on the three faces. Orphan gap fillers whose L-pattern is gone restore to terrain.

**Blends per face:** a neighbour that gains a hole-facing blend keeps the blends on its other exposed faces (stage 1).

**Path:** post-shovel local heal (after vanilla restore; world-owner).

### 3) Remove a full road tile from the centre (4 full-road neighbours)

Player shovels a **full** poured floor with four cardinal neighbours still full road.

**Result:** removed square is prior terrain. All four surrounding road faces get edge blends into it. No gap filler on the removed square. Orphan gap fillers clear as in UC2.

**Path:** same post-shovel heal as UC2.

### 4) Remove a gap filler

Player shovels a **gap filler** square (triangle overlay), not a full road tile.

**Conflict:** After restore the square is usually still an L-pocket (exactly two full-road neighbours). Neighbour-seeded `fillGaps` would match it again and re-place the triangle.

**Result:** removed square is prior terrain (triangle gone). Heal **excludes that square** from new gap fillers and new road floors for this pass, so the triangle does not come back. Remaining full-road neighbours retie edge blends into that open square. Other open neighbours still follow UC2 for orphans and new L-pockets.

**Exclusion lasts one heal pass.** A later pour whose smoothing reaches this square sees the same L-pocket and fills it — that is the pour path building road, and refilling pockets is its job.

**Path:** same post-shovel heal as UC2 (exclusion is mandatory for this case).

### 5) Remove a spur tip (1 full-road neighbour)

Player shovels a poured floor or gap filler with exactly one cardinal neighbour still full road.

**Result:** removed square is prior terrain. That one remaining full-road face gets an edge blend toward the open square. Orphan gap fillers nearby clear; new L-pockets only on other open squares if valid.

**Path:** same post-shovel heal as UC2.

### 6) Remove the last road tile (0 full-road neighbours)

Player shovels the final poured floor or gap filler of a patch; no cardinal neighbour is full road afterward.

**Result:** removed square is prior terrain. No road faces left to blend into that square. Neighbouring gap fillers that depended on this tile restore to terrain.

**Path:** same post-shovel heal as UC2 (restore + orphan cleanup; blend place is a no-op).

## Shared rules

- Gap fillers only for L-pockets (exactly two full-road cardinal neighbours).
- Stamp `shovelledSprites` on every pour and gap-filler place like `ISNaturalFloor.getFloorSpriteNames`.
- Heal seeds from the removed square’s four neighbours; the removed square is excluded from new pour or gap filler.
- **Exclusion and other remove cases:** One rule for UC2–UC6. Load-bearing for UC4 and for UC2 when the open square has exactly two full-road neighbours (that hole is an L-pocket; without exclusion heal would triangle it). For UC2 with three neighbours, UC3 (four), UC5 (one), and UC6 (zero), `fillGaps` would not match the open square anyway; exclusion is a no-op there. Other open L-pockets among neighbours still fill.
- Neighbour counts for UC2–UC6 use full road floors (`isFullRoadFloor`), not gap fillers.

### Heal composition (the `smoothRoad` pieces it reuses)

- **Pocket fill:** `checkForCornerPattern` / `placeGapFiller` on the full-road neighbours, with the removed square excluded.
- **Triangle-face heal:** `healGapFillerTriangleFaces` with no band set — a shovel has no pour band, so there is nothing to exempt. Open ground on a partner filler's triangle face is legal and stays open.
- **Blends into the hole:** a face-directed helper — given a road square and the cardinal toward the open square, attach that direction's blend sprite (`EDGE_BLEND_DIRECTION_OFFSETS` + material row). `addEdgeBlends` reads direction from a column's shape and the heal has no column, so this helper is new.
- **Cleanup:** `removeEdgeBlendsBetweenPourableSquares` over the touched squares, as `smoothRoad` does.

### Multiplayer

- The heal hooks `ISShovelGround:complete` in shared Lua. The engine runs `complete` only on the world owner (`!GameClient.client`), so a multiplayer client's dig heals on the server beside vanilla's restore — no command, no race against floor packets.

### Stage 2 tests (`tests/shovel_heal_test.lua`)

Floors carry real modData here, so the heal is exercised against the `shovelledSprites` stamp a pour leaves behind. A local `shovel()` does what vanilla `ISShovelGround:shovelGround` does, and the same heal is run against ground that has not been restored yet, which is the multiplayer race. **Done.**

- Stamps: a gap filler placed over grass wearing a tuft records both sprites, and its own triangle stays out of the stamp.
- UC2, UC3, UC5, UC6: the blended faces per hole shape, and a repeat heal stacking nothing.
- UC4: a dug filler stays open ground and its neighbours retie.
- Orphans: a filler that loses an arm returns to its stamped ground; one that keeps both arms is left alone.
- Edge tile: the hole-facing blend arrives beside the outward blend already there.

## Files

- Stage 1: `42.20/.../DumpTruckOverlays.lua`, `DumpTruckOverlayClassify.lua`; `tests/overlay_classify_test.lua`, `tests/edge_blend_test.lua`.
- Stage 2: `42.20/.../DumpTruckGravel.lua` / `DumpTruckOverlays.lua` — full `shovelledSprites`; heal helper. `42.20/.../ISShovelGroundDumpTruck.lua` — post-shovel heal.
- `docs/test-checklist-overlays.md` — verify by use case.
- `docs/bugs.md` — pointer here; "One blend per square" moved to Resolved for stage 1.

## Verify

- [ ] UC1: pour beside road — blends and L-pocket gap fillers correct.
- [ ] UC2: shovel edge (2- and 3-neighbour) — open stays terrain; road faces blended; no gap filler into a 3-neighbour open square.
- [ ] UC3: shovel centre — four blends into open square; no gap filler there.
- [ ] UC4: shovel a gap filler — terrain restored; neighbours retie.
- [ ] UC5: shovel a spur tip — one blend on the remaining face.
- [ ] UC6: shovel the last road tile — clean restore; orphan fillers cleared.
- [ ] MP: UC2–UC6; second client and reload match.
- [ ] Restore attachments when shoveling over ground that had vanilla attached sprites.
- [ ] Shovel a road square poured before `shovelledSprites` existed — restores to vanilla's default terrain without error.
- [ ] Edge tile carrying an outward blend gains the hole-facing blend and keeps the outward one.
- [x] `scripts/run-overlay-tests.sh` green after stage 1 (classify multi-blend + edge place/remove/cleanup coverage).
- [x] `scripts/run-overlay-tests.sh` green after stage 2 (stamps, heal per use case, orphan fillers, mid-restore).

## Out of scope

- Re-enabling erosion after shovel.
- Archiving our pour overlays into `shovelledSprites`.
- Snap Line, band raster, pour effect timing.
- Re-pouring onto the removed square from the shovel path (refill is UC1 / pour).
- Global re-smooth of the whole road network.
- A persistent "never refill" mark on shoveled squares.
- Retro-fitting second blends onto roads poured before stage 1 (new pours and heals get them; old bare corners fill in when a pass touches them again).
