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

- **MP desync: bed contents / gravel duping (reported Mar 2026)** – In multiplayer, driver sees “gravel in the back” when starting, then hears it stop as if done; trunk shows only empty sacks on the driver’s client, while the other player still sees gravel in the bed. Can repeat. Reported that gravel can also be duplicated using this desync (e.g. one client thinks bed is empty, other still sees gravel; placement/consumption get out of sync). **Likely cause:** Gravel consumption (`consumeGravelFromTruckBed`) and/or placement may run only on one side or container state isn’t synced; fix likely needs server-authoritative consumption or explicit container sync so all clients agree on bed contents and placement stops consistently.
- **Turn off debug before release** – `DumpTruckCore.debugMode` in `DumpTruckCore.lua` is currently `true` (console + unlimited gravel for testing). Set to `false` before packaging/release (see design-notes “Debug”).
- **Zoom-based gravel loop volume** – Optional: while loop is playing, set volume from `getCore():getZoom()` (normalize with min/max) and `vehicle:getEmitter():setVolume(data.gravelLoopSoundID, volume)`.
- **Snap Line UX** – Future ideas in design-notes: auto-regulator on engage, preview line on ground, pre-aim mode. No decision yet on priority.
