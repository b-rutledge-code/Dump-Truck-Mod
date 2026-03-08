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

## Known Limitations

- **Mechanic panel blank** – Open hood → E shows a blank left panel because the vehicle script lacks `carMechanicsOverlay`. Fix: add `carMechanicsOverlay = Base.Van` to the vehicle script (functional but not pixel-perfect for FE6).
- **No bed tilt animation** – The truck bed does not visually tilt when dumping; would require model/animation support (see design-notes “Bed tilt animation”).
- **Erosion cannot be re-enabled** – Once gravel is placed we call `disableErosion()`. If the player removes gravel (e.g. shovels), the game has no API to re-enable erosion on that square. “Traffic maintains the road” is not feasible without a game change.
- **Tile-gap when driving fast diagonally** – **Mitigated:** When the truck skips more than one tile between ticks, Bresenham-style interpolation places gravel at each intermediate position (full road width), so the gap is filled. Single-tile steps unchanged.
- **Gravel loop volume not zoom-dependent** – Dump truck sounds are script clips, not FMOD; zoom-based volume (fridge-style) is documented as a Lua follow-up (`getCore():getZoom()`, `setVolume(handle, volume)`), not yet implemented.

## Open Issues

- **Straightaways: edge blends not filling in** – SP and MP verified for pour effect and edge blends (SP fix: server no longer re-places in same process; MP: dedicated server still places and syncs). If rare edge cases appear, investigate.
- **Turn off debug before release** – `DumpTruckCore.debugMode` in `DumpTruckCore.lua` is currently `true` (console + unlimited gravel for testing). Set to `false` before packaging/release (see design-notes “Debug”).
- **Zoom-based gravel loop volume** – Optional: while loop is playing, set volume from `getCore():getZoom()` (normalize with min/max) and `vehicle:getEmitter():setVolume(data.gravelLoopSoundID, volume)`.
- **Snap Line UX** – Future ideas in design-notes: auto-regulator on engage, preview line on ground, pre-aim mode. No decision yet on priority.
