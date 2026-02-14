# Post-Release Checklist

## Completed in v1.1.1
- [x] **Passenger crash fix** - Fixed crash when entering as passenger while dump mode active
- [x] **Empty sacks spawn** - Trucks without gravel now spawn with 50 empty sacks
- [x] **Workshop upload scripts** - Created `upload_workshop.sh` (native) and `upload_workshop_docker.sh` (Linux container)

## Future Features
1. **HUD indicator panel** - Real-time on-screen feedback showing dump status (ACTIVE/NO GRAVEL/TOO SLOW), road width, and gravel remaining
2. **Minimum speed enforcement** - Require 5+ km/h to dump (no dumping while parked)
3. **Delayed edge blends** - Make edge blends appear after a few in-game days (natural settling/weathering)
4. **Snow coverage for blends** - Investigate `AttachExistingAnim` for native snow coverage
5. **Cardinal direction lock** - When staying close to a cardinal direction (+/- 5 degrees) for X seconds, lock steering into that cardinal direction until steering or brake is applied. Helps players drive straighter roads.

## Code Quality - Completed
- [x] **Modularize DumpTruckGravel.lua** - Split into `DumpTruckCore.lua`, `DumpTruckOverlays.lua`, `DumpTruckBed.lua`, `DumpTruckConstants.lua`
- [x] **Centralize overlay methods** - `placeOverlay()` and `removeOverlay()` in DumpTruckOverlays.lua
- [x] **AttachExistingAnim refactor** - Switched from separate IsoObject instances to `IsoObject:AttachExistingAnim()` for overlays
- [x] **Overlay metadata abstraction** - `initializeOverlayMetadata()`, `resetOverlayMetadata()`, `getOverlayData()` centralize floor modData access
- [x] **Driver-only dump controls** - Hide dump menu from passengers (no need to sync vehicle modData)

## Code Quality - Future
1. **Better function naming** - `hasBlendPointingAtGravel` → clearer name
2. **Automated testing** - Framework to catch regressions

## Code Quality - Investigated, Not Worth It
- ~~**Simplify checkForCornerPattern**~~ - Nested loops look ugly but are necessary. "Simpler" diagonal-only approach has different coverage and misses corners. O(64) constant time is fine.

## Known Limitations
1. **Real-time MP overlay sync** - Player 2 needs relog to see edge blends placed by Player 1 (cosmetic only, gravel floor syncs fine)
2. **MP shovel overlay removal** - Shoveling may not remove overlays for other players in real-time (same root cause)

## Not Feasible
- ~~**Gravel dumping animation**~~ - `IsoObject.setAlpha()` is for per-player wall cutaway, not visual transparency. No Lua API for sprite alpha blending.

## Tooling
- SteamCMD on Mac crashes (Abort trap: 6) - use Docker script or in-game UI for now
