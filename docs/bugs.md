# Dump Truck Gravel Mod – Bug Tracking

## Resolved

### Gap fillers visible before pour animation finished (v1.2.0)

**Problem:** Gap filler gravel (triangle on adjacent square) appeared instantly while the main tile was still showing the pour animation, so the corner looked wrong until the animation completed.

**Root cause:** Gap fillers were placed on a separate square without the pour-effect delay; only the primary tile had the fake-floor + overlay sequence.

**Fix:** Delay gap filler placement by the same duration as the pour effect (~360ms) using the `pending` system. The gap filler square gets a fake floor overlay that hides it until the timer expires, then the overlay is removed to reveal the gravel and triangle.

### 16-bit PNG crash when loading Snap Line icons (v1.3.0)

**Problem:** Game threw `Unsupported bit depth: 16` when loading `snap_line_on.png` (and similar icons). Radial menu could crash the game.

**Root cause:** ImageMagick wrote 16-bit PNGs by default; PZ's texture loader only supports 8-bit.

**Fix:** Regenerate all radial UI icons with `-depth 8`. Document in design-notes that PZ requires 8-bit PNGs for UI textures.

### Grey square behind Snap Line arrow on radial menu (v1.3.0)

**Problem:** Snap Line icon showed a visible grey (or white) square behind the arrow, unlike other radial icons.

**Root cause:** Original icons had an opaque background. Later, over-aggressive transparency made the arrow a thin outline only.

**Fix:** Replaced with new 60×60 icons: solid grey arrow (off) and solid green arrow (on), white stroke, transparent background, 8-bit. Same style applied to `road_2.png` and `road_3.png` (morphology dilate + composite for stroke).

### Edge blends next to gap fillers wrong after reload

**Problem:** Edge blends beside gap filler tiles (gravel triangles at corners) were wrong only after log out and come back. In-session cleanup worked; on reload the neighbor tile showed the edge blend again.

**Root cause:** Client cleared the overlay (removeOverlay + resetOverlayMetadata) locally, but the server’s copy of that floor was never updated. The server’s state is what gets saved, so the saved world still had overlaySprite set and LoadGridsquare re-attached the blend.

**Fix:** When the client clears overlay metadata (in `resetOverlayMetadata`), send `clearOverlayAt` (x, y, z) to the server. Server handles it in OnClientCommand and calls `removeOverlayFromSquare(sq)` so the server’s floor has cleared metadata and that state persists to save.

### MP gravel consumption desync / bed contents wrong for other players

**Problem:** In multiplayer, the driver's client ran placement and consumption in client-only code. The server never consumed gravel, so the server's bed state (and other clients' view) stayed out of sync: driver saw empty bed, other players still saw gravel; gravel could appear to duplicate or never deplete.

**Root cause:** Only the driver's client called `consumeGravelFromTruckBed(vehicle)`; the server's copy of the vehicle container was never updated.

**Fix:** Client no longer consumes locally. After placing gravel and scheduling the pour effect, the client sends `sendServerCommand(..., "consumeGravel", { vehicle = vehicle:getId() })`. The server handles it in OnClientCommand and calls `DumpTruck.consumeGravelFromTruckBed(vehicle)` so the server is the source of truth; container state then syncs to all clients. Single-player unchanged (host is both client and server).

### SP: edge blends and pour effect not visible (server re-place)

**Problem:** In singleplayer, edge blends (gravel-to-grass transitions) and the pour effect did not appear even though placement and consume ran and logs showed one `smoothRoad` and `placeEdgeBlend ok=true`.

**Root cause:** In SP the same process acts as both “client” and “server”. The client path placed gravel, ran `smoothRoad` (attaching edge blends to the floor), and sent `consumeGravel`. The server handler then ran `placeGravelFloorOnSquare` again. That second place replaced the floor with a new gravel tile, wiping the blends and the pour-effect floor.

**Fix:** In the server `OnClientCommand` handler for `consumeGravel`, only call `placeGravelFloorOnSquare` when `isServer()` is true (dedicated server). In SP `isServer()` is false, so we skip the server-side place and only run `consumeGravelFromTruckBed`, preserving the floor (and blends) already placed by the client path.

### MP: poured floors destroyed after placement

**Problem:** In multiplayer, roads look correct while pouring and are littered with black voids after leaving the area and returning. The voids give no right-click menu. Edge blends along the same stretch are missing or patchy. Neither symptom occurs in singleplayer.

**Not the older “Black Squares Bug.”** That one was `AddSpecialObject(overlay, 0)` shoving an overlay to object index 0 and breaking rendering while the floor object still existed (see Lessons Learned in `reference/general/multiplayer-architecture.md`). This bug is different: the square is **completely empty** (`getFloor()` nil, `getObjects():size()` 0). Same black look, different mechanism.

**How we proved it (reuse if it recurs):**

1. Client scan (around player): classify each square as `NIL_SQUARE` / `NO_FLOOR` / `BLANK_FLOOR` / ok. Voids were `NO_FLOOR` with `objects=0` — not missing chunks, not unresolved sprites.
2. Server lifecycle on every pour: log floor state immediately after `addFloor`, at end of `placeGravelFloorOnSquare` (after `transmitFloor` / `RecalcProperties`), then again ~2s and ~20s later by re-resolving the square from the cell.
3. Correlate destroyed coords with `ObjectModDataPacket.parse: object is null` (and the paired `not consistent` line).

**Measurements** (dedicated server, instrumented pour of 123 squares):

| Observation | Result |
|---|---|
| Floor present immediately after `addFloor` | 123 / 123 |
| Floor present at end of `placeGravelFloorOnSquare` (after `transmitFloor`) | 123 / 123 |
| Floor gone 2s later, `objects=0` | 42 / 123 |
| Floors that recovered by 20s | 0 |
| Destroyed squares with an `object is null` packet | 42 / 42 |
| Surviving squares with one | 3 / 81 |

So placement and `transmitFloor` succeed; destruction is asynchronous in a sub-2s window. Client scan of the damaged stretch: `nilSquare=0`, `blankFloor=0`, dozens of `NO_FLOOR` with `objects=0` — original terrain gone too (`addFloor` remove half ran; the replacement did not survive on the server).

**Root cause:** Clients called `transmitModData()` on floor objects they had placed locally. Object references are sent as a **position in the square’s object list**, not a stable id, so a client-placed floor often resolves to nothing on the server. `ObjectModDataPacket.parse` then logs and returns **without reading the modData payload**, leaving unread bytes on the wire; each `object is null` is paired with `INetworkPacket.logInconsistentPacket`. Engine detail: “Only the server may transmit modData for world objects” in `reference/general/multiplayer-architecture.md`.

Only the server’s copy is damaged, which is why the road renders correctly until the client refetches the square, and why singleplayer is unaffected (no packets).

**Fix:** Guard all three `transmitModData()` calls with `isServer()` — in `placeGravelFloorOnSquare` (`DumpTruckGravel.lua`) and in `initializeOverlayMetadata` and `resetOverlayMetadata` (`DumpTruckOverlays.lua`). The server places and announces its own floor; the client keeps drawing its local copy for responsiveness.

**Verified:** 90-square pour after the fix, then leaving the area and returning.

| Metric | Before | After |
|---|---|---|
| `object is null` warnings | 91 | 0 |
| `not consistent` warnings | 91 | 0 |
| Floors lost by 2s | 42 / 123 | 0 / 90 |
| Floors lost by 20s | 41 / 123 | 0 / 90 |
| Blend skips from `notGravel` | 30 | 0 |

Road renders correctly after the chunks unload and reload. The packet was causal, not a symptom of an already-empty square — removing it removed the floor loss. `notGravel` skips falling to zero confirms the missing edge blends were downstream of the floor loss rather than a fault in the blend logic.

### MP: black voids on gap-filler squares (second mechanism)

**Problem:** Same empty-square symptom as above — `getFloor()` nil, `objects=0`, black on return — but only on gap-filler squares, and only after the overlay metadata ectomy removed the `transmitModData()` calls that caused the first mechanism.

**Root cause:** `IsoGridSquare.addFloor` is asymmetric across the network.

| Half of `addFloor` | Call | Fires on |
|---|---|---|
| Remove the existing floor | `transmitRemoveItemFromSquare(o)` | `GameClient.client` — sends `RemoveItemFromSquare` |
| Add the replacement | `obj.transmitCompleteItemToClients()` | `GameServer.server` — sends `AddItemToMap` |

A client calling `addFloor` therefore tells the server to delete that square's terrain floor and never sends a replacement. The server's copy is left with no floor at all.

Ordinary poured tiles hide this: the client's removal reaches the server, then `consumeGravel` makes the server run `placeGravelFloorOnSquare`, so the server ends up with its own gravel floor. Gap fillers were the one path where the server placed nothing, so the deletion stood.

**How we proved it:** Instrumented `checkForCornerPattern` and `placeGapFiller` on both sides and poured one road.

| Metric | Client | Server |
|---|---|---|
| Corner evaluations | 126 | 126 |
| `corner noMapping` | 2 | 2 |
| `corner HIT` | 42 | 0 |
| Gap fillers placed | 42 | 0 |

Identical evaluation counts confirm both sides ran the same pass over the same rows; 0 of 42 rules out a race. A tile-by-tile diff showed all 163 client-poured tiles present on the server, so gravel replication was never the problem.

**Fix:** `applySmoothRoad` in `DumpTruckGravel.lua`. An MP client sends the row to the server and runs nothing locally; SP and the dedicated server compute in place. Both halves of `addFloor` transmit correctly from the server, so its result reaches every client.

This also removes a quieter failure. Blends and gap fillers are derived from neighbour state, so running the pass on both sides computed them against two different worlds and drifted the copies apart even where no floor was destroyed.

### MP: edge blend cleanup never runs

**Problem:** Stale edge blends accumulate in multiplayer and are never removed. Singleplayer cleans up correctly.

**Root cause:** `hasBlendPointingAtGravel` returned false unless `floor:getModData().overlayType` was `EDGE_BLEND`. On a dedicated server that modData is absent, so the check never matched and no blend was ever removed. Across 363 blends placed in one instrumented session, cleanup ran 0 times. Singleplayer worked because the modData is present in the same process.

A second cause hit every width-2 road in SP and MP alike: `smoothRoad` ran cleanup over `for i = 2, #currentSquares - 1`, which is an empty range for a 2-square row. The default road width is the vehicle width, so the common case never cleaned up at all.

**Fix:** Overlay identity now comes from the sprites attached to the floor (`DumpTruckOverlayClassify` + `DumpTruckCore.classifySquare`), which the engine saves and syncs on its own, so the server recognises its own blends and roads poured before the mod tracked overlays classify correctly too. Cleanup runs on every square in the row including the ends — safe because a blend counts as stale only when its own direction faces gravel, which the unit tests lock down.

Shovelling routes the same way. `ISShovelGround:perform()` reaches onto neighbouring squares, so an MP client sends `cleanupBlendsAt` and the server does the work and syncs the result, matching `applySmoothRoad`.

**Measured:** client and server scans agree exactly after a relog, with `stale=0` on both.

**Verify:** `docs/test-checklist-overlays.md`, MP section.

### MP: edge blends invisible until relog (third mechanism)

**Problem:** Poured roads looked correct, but their edge blends did not appear on the client until the player logged out and back in. The server's own scan reported the blends present the whole time.

**Root cause:** The client and the server each placed a gravel floor on the same square, leaving two stacked floors.

| Placer | Call site | Reaches the client as |
|---|---|---|
| Client | `DumpTruckPourEffect.schedulePlaceAndEffect` → `placeGravelFloorOnSquare` | placed directly in the local world |
| Server | `consumeGravel` handler → `placeGravelFloorOnSquare` | `AddItemToMap` |

`getFloor()` returns the first solid floor in the square's object list, so it resolved to the client's own copy. The coordinate-addressed `syncOverlay` handler attached the blend to that floor, while the server's floor sat later in the list and drew over it. The blend existed and was simply covered. Relogging discarded the local world and rebuilt the square from the server, which had one floor with the blend attached, so the blend appeared.

**How we proved it:** Logged the full object list on `syncOverlay` receipt. Every poured square carried two gravel floors ahead of the pour effect's own objects:

```
objects=[blends_street_01_55 blends_street_01_55 blends_natural_01_22 ?]
              client's            server's         fake floor      speckle
```

38 local placements across 38 unique coordinates ruled out the client placing twice, leaving the server's copy as the only source of the second floor.

**Fix:** An MP client no longer places the floor at all. `schedulePlaceAndEffect` gates `placeGravelFloorOnSquare` behind `not isClient()` and lets the server's `AddItemToMap` deliver the only floor, so `getFloor()` resolves to the copy that is actually drawn. The pour animation's fake terrain floor is skipped for the same reason: it stands in for terrain the local placement replaced, and with no local placement the real terrain is still there. SP and the host are unaffected, since the server-side handler already gates its own placement behind `isServer()`.

`DumpTruckPourEffect.isPending` covers the consequence. Without a local placement a poured square keeps reading as plain terrain until the server's copy arrives, and the overlapping rows the pour loop generates would pour it a second time and charge the truck twice. Squares stay pending for the length of the pour animation, comfortably longer than the round trip.

**Measured:** 60 sync events with zero duplicate floors, against every square before the fix. After a relog the two sides agreed exactly: `gravel=61 blends=40 gapFillers=10 stale=0 multiAttach=0 orphan=0 noFloor=0`.

## Known Limitations

- **Mechanics diagram** – Uses vanilla pickup overlay via `carMechanicsOverlay = Base.PickUpTruck` in `vehicle_dumptruck.txt` (functional, not FE6-accurate). Custom overlay art is optional follow-up.
- **No bed tilt animation** – The truck bed does not visually tilt when dumping; would require model/animation support (see design-notes “Bed tilt animation”).
- **Erosion cannot be re-enabled** – Once gravel is placed we call `disableErosion()`. If the player removes gravel (e.g. shovels), the game has no API to re-enable erosion on that square. “Traffic maintains the road” is not feasible without a game change.
- **Tile-gap when driving fast diagonally** – **Mitigated:** When the truck skips more than one tile between ticks, Bresenham-style interpolation places gravel at each intermediate position (full road width), so the gap is filled. Single-tile steps unchanged.
- **Gravel loop volume not zoom-dependent** – Dump truck sounds are script clips, not FMOD; zoom-based volume (fridge-style) is documented as a Lua follow-up (`getCore():getZoom()`, `setVolume(handle, volume)`), not yet implemented.

## Open Issues

- **Straightaways: edge blends not filling in** – SP and MP verified for pour effect and edge blends (SP fix: server no longer re-places in same process; MP: dedicated server still places and syncs). If rare edge cases appear, investigate.
- **One unclean edge blend observed** – Server coords (16360, 702): tile is on the **edge next to a gap filler**; several other gap-filler edges are fine, this was the only one. **Note:** Something about this spot left a blend we didn't clean. Cleanup only runs on inner row squares, so the square next to the gap filler is often a row-end and never gets removeOppositeEdgeBlends. If we can reproduce, consider cleanup on row-end squares when the blend borders gravel, or ensuring gap-filler-adjacent edges are covered.
- **Turn off debug before release** – `DumpTruckCore.debugMode` in `DumpTruckCore.lua` must be `false` before packaging/release (see design-notes “Debug”).
- **Zoom-based gravel loop volume** – Optional: while loop is playing, set volume from `getCore():getZoom()` (normalize with min/max) and `vehicle:getEmitter():setVolume(data.gravelLoopSoundID, volume)`.
- **ShovelledSprites overlays** – Extend shovel restore so gap fillers and edge blends are preserved/restored the same way as for poured gravel (attached overlays, not only the base floor sprite in `shovelledSprites`).
- **Snap Line UX** – Future ideas in design-notes: auto-regulator on engage, preview line on ground, pre-aim mode. No decision yet on priority.
