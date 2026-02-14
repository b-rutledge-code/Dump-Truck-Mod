# Agent Brief: Dump Truck Gravel Mod for Project Zomboid

### What You're Building

A Project Zomboid mod that adds a dump truck vehicle capable of building gravel roads while driving. Think of it like playing with a Hot Wheels truck that leaves a trail of gravel behind it - very Tonka vibes.

### Functional Requirements

**Vehicle**
- A dump truck with a truck bed that holds gravel as a consumable resource
- Spawns naturally in the game world at appropriate locations (industrial areas, construction sites)
- Some trucks spawn pre-loaded with gravel, others empty
- Players can manually load gravel into the truck bed

**Road Building Mechanic**
- Driver activates "dump mode" while in the vehicle
- While dump mode is active AND the truck is moving (below a speed threshold), gravel is deposited behind the truck
- Road width should be configurable by the player (e.g., 2-tile or 3-tile wide)
- Dumping consumes gravel from the truck bed
- Dumping stops if: truck stops moving, truck exceeds speed limit, or gravel runs out

**Road Appearance**
- Gravel roads replace existing terrain tiles
- Roads must blend naturally with surrounding terrain (no harsh edges)
- Diagonal driving and corners must produce continuous roads without gaps
- Visual consistency is critical - roads should look good at all angles

**Road Removal**
- Players can remove gravel roads using tools (shovel)
- Removal restores the original terrain underneath

**Multiplayer**
- All road changes must sync in real-time between clients
- Visual elements (blends, corners, edges) must appear identical for all players

### Constraints (Hard Rules)
- Only the driver can control dumping (not passengers)
- Truck MUST be in motion to dump - no stationary pouring
- Cannot pour gravel on: water, indoor tiles, or existing gravel roads
- Invalid pour attempts should fail gracefully (no errors, just no gravel placed)

### Development (branch / version)
- **Only modify the 42.13 branch.** The `Contents/mods/DumpTruckGravelMod/42.0/` tree is legacy; do not change it unless explicitly asked.

### Project Zomboid Technical Context

**Mod Structure**
- Client-side Lua goes in `media/lua/client/`
- Server-side Lua goes in `media/lua/server/`
- Shared Lua (runs on both) goes in `media/lua/shared/`
- Vehicle definitions use script files in `media/scripts/`
- Textures in `media/textures/`, models in `media/models_X/`

**Key API Areas to Research**
- Vehicle API: `BaseVehicle`, vehicle parts, vehicle scripts
- Terrain/IsoCell API: How to modify terrain tiles, `IsoGridSquare`
- Multiplayer sync: How to ensure client/server consistency for terrain changes
- Event hooks: `OnTick`, vehicle events, etc.

**Reference Documentation**
- Java API docs: https://demiurgequantified.github.io/ProjectZomboidJavaDocs/
- Vehicle API: https://demiurgequantified.github.io/ProjectZomboidJavaDocs/zombie/vehicles/BaseVehicle.html
- PZ Wiki Modding Hub: https://pzwiki.net/wiki/Modding

**Vanilla Game Files for Reference**
Located at: `/Users/jamesrutledge/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java/`
- `media/scripts/` - Vehicle and item definitions
- `media/lua/` - Game logic examples

### Success Criteria
1. Truck spawns in world and can be driven
2. Gravel loads into truck and tracks quantity
3. Dump mode toggles on/off via player action
4. Gravel deposits as continuous road while moving
5. Roads look good at all angles with proper blending
6. Roads can be removed and terrain restored
7. Everything syncs properly in multiplayer
