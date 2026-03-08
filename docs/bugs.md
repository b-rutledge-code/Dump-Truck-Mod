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

## Known Limitations

- **Mechanic panel blank** – Open hood → E shows a blank left panel because the vehicle script lacks `carMechanicsOverlay`. Fix: add `carMechanicsOverlay = Base.Van` to the vehicle script (functional but not pixel-perfect for FE6).
- **No bed tilt animation** – The truck bed does not visually tilt when dumping; would require model/animation support (see design-notes “Bed tilt animation”).
- **Erosion cannot be re-enabled** – Once gravel is placed we call `disableErosion()`. If the player removes gravel (e.g. shovels), the game has no API to re-enable erosion on that square. “Traffic maintains the road” is not feasible without a game change.
- **Tile-gap when driving fast diagonally** – **Mitigated:** When the truck skips more than one tile between ticks, Bresenham-style interpolation (branch `feature/tile-gap-interpolation`) places gravel at each intermediate position (full road width), so the gap is filled. Single-tile steps unchanged.
- **Gravel loop volume not zoom-dependent** – Dump truck sounds are script clips, not FMOD; zoom-based volume (fridge-style) is documented as a Lua follow-up (`getCore():getZoom()`, `setVolume(handle, volume)`), not yet implemented.

## Open Issues

- **Edge blends next to gap fillers** – Edge blends beside gap filler tiles (gravel triangles at corners) are wrong: either they were not cleaned up when the gap filler was placed, or they were incorrectly placed after the gap filler was laid. (Recurring / “old friend” issue.)
- **Straightaways: edge blends not filling in** – On straight road sections, edge blends (smooth transition from gravel to grass/terrain) are no longer being placed. (Recurring / “old friend” issue.)
- **MP desync: bed contents / gravel duping (reported Mar 2026)** – In multiplayer, driver sees “gravel in the back” when starting, then hears it stop as if done; trunk shows only empty sacks on the driver’s client, while the other player still sees gravel in the bed. Can repeat. Reported that gravel can also be duplicated using this desync (e.g. one client thinks bed is empty, other still sees gravel; placement/consumption get out of sync). **Cause:** Consumption is only run inside client-only `DumpTruckPourEffect.schedulePlaceAndEffect()` (which does place + `consumeGravelFromTruckBed`). The server never runs that path, so only the driver's client removes gravel; server and other clients never see the consumption. **Fix:** Make consumption (and placement) server-authoritative: server runs the gravel tick and does place + consume; clients do the visual pour effect only, or add an explicit sync (e.g. server command) so the server is the single source of truth for bed contents.
- **Turn off debug before release** – `DumpTruckCore.debugMode` in `DumpTruckCore.lua` is currently `true` (console + unlimited gravel for testing). Set to `false` before packaging/release (see design-notes “Debug”).
- **Zoom-based gravel loop volume** – Optional: while loop is playing, set volume from `getCore():getZoom()` (normalize with min/max) and `vehicle:getEmitter():setVolume(data.gravelLoopSoundID, volume)`.
- **Snap Line UX** – Future ideas in design-notes: auto-regulator on engage, preview line on ground, pre-aim mode. No decision yet on priority.
