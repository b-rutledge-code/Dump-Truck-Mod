# Dump Truck Gravel Mod – Requirements

## Goal

Enable players to build gravel roads in Project Zomboid using a dump truck: place gravel from the truck bed while driving, with straight roads (Snap Line), edge blending, and erosion prevention. The mod should feel like a natural extension of vanilla (no steering hijacking, Lua-only where possible).

## Functional

1. **Dump truck vehicle** – Volvo FE6 dump truck (script name per `DumpTruckConstants.VEHICLE_SCRIPT_NAME`). Player can drive, load gravel sacks into bed, raise/lower bed via radial menu.
2. **Gravel dumping** – Start/stop dumping via (G) or radial menu. Gravel is consumed from bed inventory and placed on the ground under the truck as it moves. Direction uses vehicle `getAngleZ()` (via `DumpTruckCore.getVectorFromPlayer()`), not driver forward (stale).
3. **Road width** – Toggle 2 or 3 tiles wide via radial menu (for vehicles &lt; 3 tiles wide). Stored in vehicle modData `wideRoadMode`.
4. **Edge blending** – Gravel roads blend smoothly with grass/terrain (`smoothRoad`). Gravel must be placed synchronously so edge blends see the real floor; pour effect uses overlays for animation only.
5. **Pour effect** – Short visual animation when gravel lands (synchronous floor + stacked overlays, ~360ms, three sprite stages). Gap fillers delayed by same duration so they don’t appear before pour finishes.
6. **Erosion prevention** – After placing gravel, call `disableErosion()` on the square so grass/trees don’t grow. Re-enabling erosion is not possible from Lua (game limitation).
7. **Snap Line (v1.3.0)** – Radial option to snap gravel placement to a cardinal grid line (N/S/E/W). Engage when truck is within 25° of cardinal; brake or drift &gt;3 tiles off-line auto-disengages and stops dumping. Position and forward vector overridden in `tryPourGravelUnderTruck()` when active.
8. **Radial menu icons** – Dump, road width, and Snap Line slices use 8-bit PNGs; UI icons have white stroke to match vanilla radial style. PZ does not support 16-bit PNGs.

## Constraints (By Design)

- **No steering control from Lua** – CarController is not exposed; `setCurrentSteering` is overwritten; `setAngles` flips the vehicle. Straight roads are achieved by snapping gravel placement (Snap Line), not by locking steering.
- **Erosion** – We only disable erosion; we never re-enable it (no game API). Custom non-erodable sprites are not used (engine sets `doNothing` on first encounter and never resets).
- **Dump speed** – No artificial speed cap from Lua (`setMaxSpeed` was removed); player drives slowly by choice.
- **Assets** – Tile/floor sprites from texture pack (`.pack`); UI icons loose PNGs under `media/ui/vehicles/`. All PNGs 8-bit for PZ compatibility.

## Technical

- **Target:** Project Zomboid Build 42 (42.13 active).
- **Layout:** `Contents/mods/DumpTruckGravelMod/42.13/` — media (lua, scripts, texturepacks, ui), vehicle script reference in mod.info.
- **Lua:** Client + shared (no dedicated server-only logic). Events: radial menu hook, `OnTick` for pour effect and gravel tick.
- **Source of truth:** `docs/design-notes.md` for design rationale, dead ends, and future ideas.
