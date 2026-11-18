# Hopper 2D early proofs

Kill criteria before a full multi-floor 2D rebuild. Stamp via `DumpTruck.placeHopper` with `payload.mode` ([`LoadingHopperProof.lua`](../Contents/mods/DumpTruckGravelMod/42.20/media/lua/client/DumpTruck/LoadingHopperProof.lua)).

| Mode | What | Pass if |
|------|------|---------|
| `proof1` | Vanilla `construction_01_48` @ z=0 + `floors_exterior_tilesandstone_01_4` @ z=3 | Floor readable by day; follows outdoor night |
| `proof2` | 3×3 ring of floors+rails @ z=3 (opening empty); FBX cell bakes in `models/loading-hopper/2d_tiles/` | Adjacent cells read as one platform |
| `proof3` | Corner posts z=0..2 + deck ring @ z=3, open bay | Under-bay: no cutaway erase / black voids |

```text
exec_dev hook DumpTruck.placeHopper payload {"mode":"proof1"}
```

Omit `mode` / use `g3` for frozen 3D G3 hopper.

## Results (2026-11-16)

| Proof | Result | Notes |
|-------|--------|-------|
| 1 lighting | **PASS** | `getOrCreateGridSquare` + `addFloor` places `floors_exterior_tilesandstone_01_4` @ z=3 (`floorOk`/`postOk`). Day noon: tile readable sandstone. Night ~04:00: tile follows outdoor dark (no mesh night-glow). Verify standing on z=3 (ground freefly can miss elevated level). Shots: `~/Zomboid/Screenshots/pz-dev-mcp/proof1-day-z3.png`, `proof1-night-z3.png`. |
| 2 iso crop | **PASS** | In-game: 8× `floors_exterior_tilesandstone_01_4` + rails @ z=3, center open; adjacent cells read as one platform (`proof2-day-ring.png`). Offline bake PNGs remain for later custom-tile stamp. |
| 3 bay cutaway | **PASS** | Corner posts z0–z2 + deck ring @ z=3 with open bay. Under-bay and deck-edge: opening shows ground; no cutaway erase of posts/deck. Shots: `proof3-overview.png`, `proof3-under-bay.png`, `proof3-deck-bay.png`. |

## Art bake + flood

```bash
cd mods/DumpTruckGravelMod/models/loading-hopper
blender --background --python bake_2d_tiles.py
python3 pack_2d_tiles.py
# pack → media/hopper_2d.tiles + texturepacks + LoadingHopper2dCells.lua
```

```text
exec_dev hook DumpTruck.placeHopper payload {"mode":"flood"}
```

## Stop rule

Proofs 1–3 passed. Custom bake (216 cells) + `flood` mode is the live 2D path.