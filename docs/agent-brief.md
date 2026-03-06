# Dump Truck Gravel Mod – Agent Brief

## What It Does

Adds a dump truck (Volvo FE6) that places gravel on the ground to build roads. The player loads gravel sacks into the bed, raises the bed, and drives slowly while dumping; gravel is consumed from the bed and placed under the truck with a short pour animation. Roads blend at edges with terrain, and corners get gap fillers. **Snap Line** (v1.3.0) lets the player lock gravel placement to a cardinal grid line (N/S/E/W) via the radial menu so roads stay straight even if the truck wobbles. Erosion is disabled on placed gravel so grass and trees don’t grow through the road. All behavior is Lua-only; no steering control from Lua (see design-notes for why).

## Build Support

- **42.13:** `Contents/mods/DumpTruckGravelMod/42.13/` – Active development. Lua, media, and vehicle script live here.
- **42.0:** Legacy; do not add features or changes there.

## Key Flow

1. **Radial menu (V)** – Hooks `ISVehicleMenu.showRadialMenu`. For the dump truck script: adds slices Start/Stop Dumping, Road Width (2/3 tiles), Enable/Disable Snap Line (with direction label). Icons from `media/ui/vehicles/` (8-bit PNG, white stroke).
2. **Start dumping** – Sets vehicle modData `dumpingGravelActive`, starts gravel loop sound, begin bed-up state. Stop clears flag, stops sound, bed down.
3. **Gravel tick** – While dumping, shared logic runs each tick: get vehicle position and direction (`DumpTruckCore.getVectorFromPlayer` or Snap Line locked vector), brake/drift check if Snap Line active, compute back squares, place gravel (and gap fillers) with pour effect. Consume from bed inventory.
4. **Pour effect** – Client-only: when gravel is placed, add fake floor + overlay objects; over ~360ms swap overlay sprites then remove overlays to reveal gravel. Same delay for gap filler square so it doesn’t pop in early.
5. **Snap Line** – On engage: require ~25° of cardinal, capture and snap forward vector and cross-axis from `getVectorFromPlayer`, store in modData. In dump path: if active, use locked position and vector, and disengage on brake or drift &gt;3 tiles.

## Key Code & APIs

- **Namespace / modules:** `DumpTruck` (shared, gravel placement), `DumpTruckCore` (shared, vector/position), `DumpTruckSnapLine` (shared, engage/disengage/snap), `DumpTruckConstants` (shared), `DumpTruckPourEffect` (client), `DumpTruckBed` (shared), `DumpTruckOverlays` (shared). Menu: `ISVehicleMenuDumpTruck.lua` (client, hooks radial).
- **Config:** `DumpTruckConstants`: vehicle script name, drift/engage thresholds for Snap Line, pour stage ms, road width extents, etc. Vehicle modData: `dumpingGravelActive`, `wideRoadMode`, Snap Line keys (`snapLineAxis`, `snapLineValue`, `snapLineHeading`, `snapLineFx`, `snapLineFy`).
- **Events:** Radial menu is hooked by overriding `ISVehicleMenu.showRadialMenu`. Pour effect and gravel tick are driven from existing game update paths (client/server as appropriate).
- **APIs used:** `vehicle:getAngleZ()`, `getScript()`, `getModData()`, `getEmitter()`, `playSound`, `isBraking()`; `getCell()`, square methods, `AddTileObject`/`RemoveTileObject`, `getSprite()`, `DirtySlice()`, `RecalcProperties()`; `disableErosion()`; texture pack and sprite names from mod media. **Not used:** steering (CarController not exposed), `setAngles` (flips truck), re-enable erosion (no API).

## References

- **Design notes (source of truth):** `docs/design-notes.md` – vehicle direction, erosion, pour effect, Snap Line, Sound/zoom, Tile-gap TODO, dead ends (steering, bed tilt).
