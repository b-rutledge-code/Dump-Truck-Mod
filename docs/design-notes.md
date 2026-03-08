# Dump Truck Gravel Mod – design notes

Mod-specific design and future ideas (not general PZ modding knowledge).

---

## Debug

**Single debug flag:** `DumpTruckCore.debugMode` in `DumpTruckCore.lua`. When `true`:
- **Console:** `DumpTruckCore.debugPrint()` runs — vehicle pos (cx, cy, tile), then path: `[interp] first run`, `[interp] gap path: ... points=N`, or `[interp] single-tile step`.
- **Unlimited gravel:** `consumeGravelFromTruckBed` and `getGravelCount` act as if the bed always has gravel (for testing without loading sacks).

**Set to `false` before release.** Leave a `TODO: set false before release` comment when enabling. See bugs.md open issue.

---

## Noted: admin-only dump trucks (Workshop request)

A comment asked for a sandbox/mod option so dump trucks are **not** added to vehicle spawn tables—i.e. spawnable by admins only. Not implemented; noted for future consideration.

---

## Vehicle direction (gravel dumping)

We use **vehicle `getAngleZ()`** (converted to a unit vector) for dump direction, not the driver's `getForwardDirection()`.

**Why not driver direction:** The driver's forward is only updated when the vehicle runs `playCharacterAnim()` (e.g. driving pose). That runs when the anim is set or changed, not every frame, so `driver:getForwardDirection(vector)` can be stale when we read it each dump tick. **Prefer `vehicle:getAngleZ()`** and build (fx, fy) in Lua for the vehicle's actual facing.

---

## Future idea: traffic maintains the road

If the game ever exposes a way to re-enable erosion (e.g. `square:enableErosion()` or callable `ErosionData.Square.reset()`):

- **"Traffic maintains the road"** – Gravel could expire / erosion could turn back on only when the road is no longer driven on; driving on it would stave off decay.
- Would need per-tile "last driven" (or similar) and an API to re-enable erosion on that square.

Currently not possible: erosion can only be disabled from Lua, not re-enabled.

---

## Erosion and gravel (custom tiles, re-enable)

**When erosion runs:** Erosion is driven by `EveryTenMinutes()` → `mainTimer()`. `eTicks` advance once per in-game day (144 × 10 min). Each loaded square is processed at most once per eTick. So erosion runs every 10 in-game minutes at the world level; per-square update is once per in-game day.

**Which floors get erosion:** Erosion only runs on a subset of floor types. The engine uses **ErosionRegions** (e.g. `blends_natural_01`, `blends_street`) plus null regions with wall/exterior checks. If the floor's sprite doesn't match any region, the square is still "seen" by erosion once—and that's when the trap happens.

**Why a "custom non-erodable" sprite is a bad idea:** The idea was: use a custom gravel sprite that doesn't match any erosion region, so we never call `disableErosion()`. Then when the player shovels the gravel or swaps the floor, erosion could run again. **In practice:** When a chunk is first processed by erosion and the square has that custom floor, `validateSpawn()` finds no matching region and sets `doNothing = true`. That value is persisted. Nothing in the game resets erosion when the floor changes (digging or swapping doesn't call `ErosionData.Square.reset()`). So the square is permanently non-eroding even after the gravel is gone. This "first seen with custom floor" case happens whenever someone crosses into a chunk that was gravelled before that chunk was ever processed by erosion—e.g. every new chunk boundary—so the edge case is common, not rare.

**Vanilla tiles:** Vanilla base tiles match a region, so they never get `doNothing = true` from this path. Only our custom (non-region-matching) tile triggers it.

**"Hitching a ride" on an existing region:** We could use a vanilla sprite that *does* match a region so `doNothing` is never set. Then the square would remain "erodable" after we swap or dig. But then that region's erosion category (cracks, vegetation, etc.) runs on that square. We'd need a vanilla tile that matches a region but is effectively a no-op for that category, or we'd have to accept some erosion (e.g. cracks or grass) on gravelled squares. Not explored further for this mod.

**Conclusion for this mod:** We call `disableErosion()` after placing gravel so the tile stays clear. Re-enabling erosion (e.g. "traffic maintains the road") is not possible without a game API; avoiding `disableErosion()` via a custom non-matching sprite does not work because the engine sets `doNothing` on first encounter anyway.

### Erosion on vanilla game roads

Vanilla in-game roads use `blends_street` tiles that match the **street** erosion region. The erosion system does run on them, but vanilla erosion for streets is very mild—mostly cracks and minor vegetation at the edges over time, **not** trees or heavy foliage. Trees growing through roads would be a bug or unintended behavior; it's not how vanilla erosion works on `blends_street` tiles.

Our gravel uses a different sprite (not `blends_street`), so it doesn't get the same "mild crack" erosion that vanilla streets do. Without `disableErosion()`, our gravel squares get the natural region's erosion (grass, trees, bushes), which is why trees grow right through the road. With `disableErosion()`, nothing grows but we can never re-enable it.

### Idea: wipe foliage but allow cracks

Let erosion run but periodically remove foliage objects (trees, bushes) from gravelled squares. This would let cracks appear (cosmetically appropriate) while preventing trees. Concern: polling all gravel squares for foliage objects could be expensive for large road networks.

---

## Gravel dump visual / animation

**Transparency / fade-out is not viable:**

- `IsoObject.setAlpha()` is used by the game for per-player **wall cutaway** (see-through walls), not for blending or fading floor sprites. There is no Lua API for sprite alpha blending on floors.
- Even if we could fade the gravel sprite, there is **no subfloor layer** to reveal underneath—the gravel is the floor. So a "fade to show road underneath" idea doesn't apply.

See also **Post-Release → Not Feasible**: "Gravel dumping animation" (no Lua API for sprite alpha blending).

**Particle system is not open to Lua modding:**

- The engine's particle systems (`ParticlesFire`, weather particles) are Java-only and **not exposed** to Lua. There is no API from Lua to spawn or configure custom particle effects (position, velocity, texture, etc.).
- **IsoFireManager** and **IsoFire** are exposed to Lua, so you can start a fire on a square and get the built-in fire/smoke look via attached anims—but that uses the game's fire logic and "Fire"/"Smoke" sprites, not a generic "spawn particles here" API. Not suitable for custom gravel-dust.
- **Conclusion:** Custom "gravel dust" or other dump visuals via particles would require a game change that exposes a particle API; from Lua alone there is no supported way.

**Short-lived custom sprites — IMPLEMENTED (v1.2.0):**

### Architecture: synchronous floor + stacked overlays

The pour effect places gravel immediately but hides it behind temporary overlays that animate the "pouring" visual. This ensures `smoothRoad` edge blends work correctly (they need the real gravel floor to already exist).

**On each square when gravel is placed (`DumpTruckPourEffect.schedulePlaceAndEffect`):**

1. Save the name of the existing floor sprite (e.g. `blends_natural_01_0`).
2. Call `placeGravelFloorOnSquare()` immediately — the real gravel is now the floor.
3. Call `consumeGravelFromTruckBed()` — deduct from inventory.
4. Create **IsoObject #1 ("fakeFloor")** using the saved old floor sprite → `square:AddTileObject(fakeFloor)`. This visually hides the gravel underneath.
5. Create **IsoObject #2 ("overlay")** using `POUR_SPRITES[1]` (sparse speckles on transparent background) → `square:AddTileObject(overlay)`. This sits on top of the fake floor.
6. Store `{ fakeFloor, overlay, square, stage=1, nextSwapAt=now+POUR_STAGE_MS }` in a `pending` table.

**Animation progression (`onTick`):**

- Each tick, check `pending` entries against `getTimestampMs()`.
- If `now >= nextSwapAt` and not on the final stage: swap the overlay's sprite to the next `POUR_SPRITES` entry (more gravel speckles), call `overlay:DirtySlice()`, advance stage.
- When the final stage expires: remove both fakeFloor and overlay from the square, call `sq:RecalcProperties()` and `sq:DirtySlice()`. The real gravel floor is revealed.

### Sprite stages

Three stages, progressing from sparse to dense gravel speckles on a transparent background:

| Stage | Sprite | Density |
|-------|--------|---------|
| 1 | `dumptruck_pour_00` | ~6% (sparse) |
| 2 | `dumptruck_pour_005` | ~13% (mid) |
| 3 | `dumptruck_pour_01` | ~20% (medium) |

After stage 3 completes, overlays are removed and the full gravel tile is visible.

### Timing

`POUR_STAGE_MS = 120` — each stage lasts 120ms, total animation ~360ms. This was tuned through in-game testing; shorter felt too abrupt, longer was noticeable as a delay.

**Future idea: speed-scaled duration.** The stage duration could scale with vehicle speed (`vehicle:getCurrentSpeedKmHour()`) so the effect completes faster when the truck is moving quickly and lingers when crawling. Not yet implemented.

### Assets

Sprites are 128×256 transparent PNGs with grey gravel speckles at increasing density. Generated via a Python script using `struct`/`zlib` (no PIL dependency). Source PNGs and TOMLs live in `media/texturepacks_src/pour/`. Compiled into `media/texturepacks/DumpTruckGravelMod.pack`.

### Key learnings

- **Stacked IsoObjects work.** You can `AddTileObject()` multiple IsoObjects on a square and they render in order. `RemoveTileObject()` removes a specific one without affecting others or the floor.
- **`DirtySlice()` is the correct method** to force a re-render after changing a sprite on an existing IsoObject. `setDirty()` does not exist on IsoObject.
- **Sprite transparency works** — the game renders alpha channels from PNGs in texture packs. Transparent areas show whatever is underneath. Runtime alpha (`setAlpha()`) is still wall-cutaway only.
- **`smoothRoad` needs real gravel floors** — it checks adjacent squares for gravel sprites to decide edge blends. If gravel is deferred (placed later by `onTick`), `smoothRoad` won't see it. The synchronous placement + overlay approach solves this.
- **Edge blends are hidden by the pour effect** — they attach via `AttachExistingAnim` to the gravel floor, which is behind the fake floor + speckle overlay. They only become visible when the overlays are removed. No timing issue.
- **Gap fillers appear before pour finishes (known issue, fixed)** — gap fillers call `placeGapFiller` on a *separate neighbor square* with no pour effect. The gravel + triangle overlay appears instantly while adjacent road tiles are still mid-animation. Fix: delay gap filler placement by the same duration as the pour effect (~360ms) using the `pending` system. The gap filler square gets a fake floor overlay that hides it until the timer expires, then removes the fake floor to reveal the gravel + triangle underneath. No per-terrain pour sprites needed.

### setMaxSpeed is not a speed cap (removed in v1.2.0)

`vehicle:setMaxSpeed()` does not hard-cap speed. The engine tapers force over a 20 km/h window above the set value (formula: `engineForce * ((maxSpeed + 20 - speed) / 20)`). Setting it to 5.0 means force starts reducing at 5 but doesn't reach zero until 25 km/h. It also wrecks gear ratios (`speedPerGear = maxSpeed / gearCount`) and steering sensitivity (`1.0 - speed / maxSpeed` clamps to 0.1 at "top speed"). Removed entirely — dump speed is uncapped.

### Vehicle mechanic panel blank (missing carMechanicsOverlay)

The mechanics UI (open hood → E) shows a blank left panel because the vehicle script is missing `carMechanicsOverlay`. This is the top-down 2D diagram the UI renders for clickable part areas. Vanilla vans use `carMechanicsOverlay = Base.Van`. Fix: add `carMechanicsOverlay = Base.Van,` to the vehicle script. Won't be pixel-perfect for the FE6 shape but makes the panel functional. A custom overlay image could be drawn later.

### How to add sprites (for pour effect or any custom sprite)

1. **Create the image(s)**  
   PNG format, **lowercase** filenames (e.g. `dumptruck_pour_01.png`). Use alpha for transparent areas. Typical tile sprite size is up to 128×256; match your use case (e.g. one tile-sized PNG per frame).

2. **Create a texture pack**  
   PZ loads sprites from `.pack` files (texture atlases). Two options:
   - **TileZed:** Tools → .pack files → Create .pack File. Choose the folder containing your PNG(s). Save as e.g. `media/texturepacks/DumpTruckGravelMod.pack` in the mod. TileZed will trim and pack the images and generate entry names from filenames.
   - **pz-pack tool** (see `reference/pz-pack/README.md`): Put each PNG in a folder with a matching TOML file. **Critical: the TOML filename stem must match the PNG filename stem** (e.g. `dumptruck_pour_01.png` needs `dumptruck_pour_01.toml`). A single TOML for multiple PNGs won't work — the tool pairs by name. Each TOML specifies `pos` and `size`. Run `pz-pack-tool pack ./InputDir ./OutputFile.pack`.

3. **Place the pack in the mod**  
   e.g. `Contents/mods/DumpTruckGravelMod/42.13/media/texturepacks/DumpTruckGravelMod.pack`.

4. **Register the pack in mod.info**  
   Add a line: `pack=DumpTruckGravelMod` (name without `.pack`). The game loads this pack with the mod.

5. **Use in Lua**  
   Sprite name in code is the **PNG filename stem** (e.g. `dumptruck_pour_01`). Use `getSprite("dumptruck_pour_01")` to get the sprite object, then `IsoObject.new(getCell(), square, getSprite("dumptruck_pour_01"))`.

**References:** PZwiki [Adding new tiles](https://pzwiki.net/wiki/Adding_new_tiles); `reference/pz-pack/README.md` (TOML format, transparent padding).

---

## Bed tilt animation (what it would take)

To animate the back of the truck tilting when dumping (bed up/down):

1. **If the model already has a tilt animation**  
   The Volvo FE6 dump mesh (`fhqFE6Dump`) may already include a bed-raise anim. You'd need to: (a) confirm with the model author or by inspecting the mesh/anim list, (b) find the anim ID for the TruckBed part, (c) from Lua call the part's animation when `dumpingGravelActive` turns true/false. No 3D or animation skill needed—only hooking existing anims.

2. **If the model has no tilt animation**  
   You'd need either:
   - A **second mesh** (bed in raised position) and a second **model** block in the vehicle script (e.g. `model Raised` with that mesh), then switch the part's model state from Lua when dumping starts/stops; or  
   - A **new animation** (bed rotating from down to up) authored in a 3D tool (e.g. Blender), exported for PZ, and wired in the vehicle script.  
   Both require someone who can edit the 3D model or create animations.

3. **No "set rotation" API**  
   There is no known Lua API to just set a part's rotation (e.g. "tilt bed by 45 degrees"). Tilt is done via pre-made meshes or animations, not script-driven angles.

**Summary:** Easiest path is if the existing model already has a bed tilt; then it's Lua-only. Otherwise you need a 3D/animation asset (second mesh or new anim) and possibly an animator or the original model author.

**Reference:** Skizot's Dump Truck (Workshop 2964155927, mod ID FiliDumper) uses **two static meshes** (bed down / bed tilted) and swaps them in Lua with `part:setModelVisible("ModelName", true/false)` when the trunk is locked—no animator, no timeline. Same pattern we'd use with a Blender-tilted mesh.

### Creating a tilted bed mesh in Blender

If you have permission to use or change the model, adding a tilted-bed pose is straightforward:

1. **Import the model**  
   Bring the vehicle (or just the bed submesh) into Blender. PZ often uses FBX; check what the mod ships (e.g. under `media/models/` or similar).

2. **Isolate the bed**  
   Select only the bed mesh. You may match by name to what the vehicle script uses (e.g. the part that has the trunk/bed mesh).

3. **Tilt the bed**  
   - Define a **pivot** where the bed hinges (usually at the front of the bed, against the cab).  
   - Rotate the bed around that axis (often X) by ~30-45 degrees.  
   - No animation needed—just a single posed mesh.

4. **Export a second mesh**  
   - Duplicate the bed in Blender: one at 0 degrees, one tilted.  
   - Export so the game has two meshes (e.g. `Trunk` and `TrunkDump`), then in the vehicle script add a second **model** block for the tilted mesh and switch visibility from Lua (same pattern as FiliDumper).

**Difficulty:** Conceptually simple (one rotation, then export). The fiddly parts are matching PZ's export scale/axes so the tilted bed lines up in-game, and choosing the right pivot so the tilt looks hinged at the cab. If the mod does not ship source, you may need to extract or convert the mesh first.

---

## Cardinal Lock – steering the vehicle from Lua (DEAD END)

**Goal:** When dumping gravel, lock the truck's heading to a cardinal direction (N/E/S/W) so roads come out straight.

### State machine (works)

In `DumpTruckCardinalLock.lua`, when dumping is active we check if the vehicle heading is within `DETECTION_THRESHOLD` (10 degrees) of a cardinal direction for `DELAY` (3 s). Once the timer expires and heading is within `LOCK_THRESHOLD` (10 degrees), the lock engages. It releases on braking or deliberate steering input. This part works correctly.

### Steering correction (NOTHING WORKS)

Every approach to actually steer the vehicle toward the locked heading from Lua has failed:

| Approach | What happened |
|----------|---------------|
| `setCurrentSteering(correction)` | **Overwritten by CarController.** `OnPlayerUpdate` fires at IsoPlayer:2302, then `updatePhysics()` fires at 4762 which calls `CarController.update()` → `setCurrentSteering(vehicleSteering)` → `Bullet.controlVehicle(...)`. Our value never reaches the physics step. Truck stays ~4 degrees off, drifts one tile every few seconds. |
| `controller.clientControls.steering` | **CarController is not exposed to Lua.** `BaseVehicle` is in `LuaManager.Exposer.setExposed()` (line 2313 of LuaManager.java) but `CarController` is not. `vehicle:getController()` returns an opaque Java object; `ctrl.clientControls` is always nil from Lua. Complete dead end. |
| `vehicle:setAngles(x, y, z)` | **Flips the vehicle.** Sets the Bullet rigid body's world transform directly. Heading correction was perfect in logs (error converged to 0.00 in 5 frames, held exactly). But overriding the transform conflicts with Bullet physics internal state (velocities, wheel contacts, suspension forces). Vehicle **rolls sideways and flips** within seconds. Tried forcing X=0, Y=0 with a 0.5-degree dead zone; still flipped. Unsafe on a moving vehicle. |
| `OnTick` post-correction | Runs after `updateControls()` but before next frame's `updatePhysics()`. Setting `setCurrentSteering` here doesn't help because `CarController.update()` reads its own internal `vehicleSteering`, not the vehicle's `currentSteering` field. And `clientControls` isn't accessible (see above). |

### Why `setCurrentSteering` gets overwritten (decompiled proof)

**Frame execution order** (from `IsoPlayer.java`):

1. **Line 2302:** `LuaEventManager.triggerEvent("OnPlayerUpdate", this)` — our Lua runs here
2. **Line 4762:** `vehicle.updatePhysics()` → calls `CarController.update()`
3. Inside `CarController.update()`:
   - Line 295: `vehicleSteering` blended toward `-clientControls.steering`
   - Line 326: `vehicleObject.setCurrentSteering(this.vehicleSteering)` — **overwrites our value**
   - Line 330: `Bullet.controlVehicle(...)` — sends to physics engine
4. **Line 4775:** `vehicle.updateControls()` → reads keyboard into `clientControls` for **next** frame

So anything we set on `currentSteering` in step 1 is replaced in step 3 before the physics engine sees it.

### Why `setAngles` flips the truck

`setAngles(x, y, z)` calls through to `Bullet.setVehicleTransform(...)` which directly sets the rigid body's world rotation matrix. But Bullet maintains internal state: angular velocity, suspension forces, tire contact normals. When we set the rotation, these internal values become inconsistent with the new orientation—the engine "sees" forces that should not exist at the new angle and overcorrects, causing a feedback loop that rolls and flips the vehicle within seconds.

**First attempt:** `setAngles(getAngleX(), getAngleY(), correctedZ)` — read back X/Y and only change Z. Amplified small pitch/roll errors over time (X/Y drifted from noise). Flipped within ~10 seconds.

**Second attempt:** `setAngles(0, 0, correctedZ)` with 0.5-degree dead zone — force X=0, Y=0 to prevent pitch/roll accumulation. Still flipped. Even with flat pitch/roll, the yaw change alone creates enough inconsistency with Bullet's internal angular momentum.

### Conclusion

**There is no safe way to control vehicle heading from Lua in PZ Build 42.** The steering controller is not exposed to Lua, steering values get overwritten, and direct transform manipulation breaks physics.

---

## Snap Line — gravel snap (IMPLEMENTED)

Instead of steering the truck (which is impossible from Lua — see "steering the vehicle from Lua" above), **snap gravel placement to a grid line** so the road is straight even if the truck wobbles.

### How it works

1. Player opens radial menu and selects **"Enable Snap Line (N)"** (label shows predicted direction). The mod checks if the truck is within 25 degrees of a cardinal heading (`SNAP_LINE_ENGAGE_THRESHOLD`). If not, engage is refused with a buzzer sound.
2. On engage: capture the actual forward vector from `DumpTruckCore.getVectorFromPlayer()` — the same function the normal dump path uses — and snap it to the nearest cardinal axis. Store the snapped `fx, fy`, the cross-axis coordinate, and heading label in vehicle modData (`snapLineAxis`, `snapLineValue`, `snapLineHeading`, `snapLineFx`, `snapLineFy`). This guarantees the locked vector uses the exact same sign convention as the working dump logic.
3. In `tryPourGravelUnderTruck()`, when Snap Line is active:
   - **Brake check:** if `vehicle:isBraking()`, auto-disengage lock + stop dumping + warning sound.
   - **Drift check:** if the truck has drifted more than `SNAP_LINE_DRIFT_MAX` (3) tiles off the locked line, auto-disengage lock + stop dumping + warning sound.
   - **Position snap:** override `cx` or `cy` with the locked value before calling `getBackSquares()`.
   - **Forward vector override:** use the stored cardinal `fx, fy` instead of the driver's actual direction, so `getBackSquares` computes the perpendicular correctly.
4. **All disengage paths stop dumping** — whether from drift, braking, or the radial menu toggle. The player must re-engage deliberately.
5. The truck can wobble — the road still lands on a perfectly straight line of tiles.

### Key design decision: trust the existing forward vector

Early iterations used a hardcoded lookup table mapping `getAngleZ()` cardinal centers to pre-computed `fx, fy` values. This produced a sign convention mismatch with the existing dump logic (which uses `getVectorFromPlayer`), causing gravel to dump from the front or drift off-axis. The fix: capture the real player forward vector at engage time and snap it, so the locked vector is guaranteed to match.

### Files

- `DumpTruckSnapLine.lua` (shared) — `engage()`, `disengage()`, `isActive()`, `getSnappedPosition()`, `getLockedForwardVector()`, `checkDrift()`, `getNearestHeading()`
- `DumpTruckGravel.lua` — brake + drift check + position/vector override in `tryPourGravelUnderTruck`
- `ISVehicleMenuDumpTruck.lua` — radial menu slices: "Enable Snap Line (N)" / "Disable Snap Line (N)" (action-oriented labels with direction)
- `DumpTruckConstants.lua` — `SNAP_LINE_DRIFT_MAX = 3`, `SNAP_LINE_ENGAGE_THRESHOLD = 25`

### Audio feedback

- **Engage:** `VehicleSeatBelt`
- **Disengage (manual):** `VehicleDoorCloseWindow`
- **Disengage (drift or braking):** `VehicleReverseBuzzer`
- **Engage refused (not facing cardinal):** `VehicleReverseBuzzer`

### UX: action-oriented radial menu labels

Early labeling showed state ("Axis Lock: OFF" / "Axis Lock: N"), which led to accidental engages — users clicked the "OFF" label thinking it would keep it off, but it toggled it on. Changed to action-oriented labels: **"Enable Snap Line (N)"** / **"Disable Snap Line (N)"**. Both show the direction (predicted or current) so the player knows what they're locking to before clicking.

### Previous approach: steering the vehicle (DEAD END)

See "Cardinal Lock — steering the vehicle from Lua" above. Direct steering manipulation failed because `setCurrentSteering` is overwritten by `CarController`, `clientControls` is not Lua-exposed, and `setAngles` flips the vehicle. The gravel snap approach sidesteps all of this.

### Future ideas

- **Auto-regulator (cruise control):** `vehicle:setRegulator(true)` + `vehicle:setRegulatorSpeed(5)` on lock engage so the player doesn't need to hold the gas.
- **Preview line on ground:** Show a visual line at the snap position before dumping starts.
- **Pre-aim mode:** Player aims to set a start marker, then dumps along that line.

---

## Sound — gravel loop volume by zoom (approach documented)

**Goal:** Make the gravel dump loop (and optionally start/end) get quieter when the camera is zoomed out, similar to the fridge hum.

**Current setup:** Dump truck sounds are **script clips** in `media/scripts/sounds_dumptruck.txt` (e.g. `GravelDumpStart`, `GravelDumpLoop`, `GravelDumpEnd`), not FMOD events. The fridge uses FMOD with a global **CameraZoom** parameter; that’s authored in the FMOD project. We have no FMOD project for these clips, so we can’t get fridge-style zoom ducking via FMOD.

**Lua approach (supported by the engine):** The game exposes both zoom and per-handle volume to Lua:

- **Zoom:** `Core` is exposed; `getCore():getZoom(playerNum)` returns the current zoom. `getCore():getMinZoom()` and `getCore():getMaxZoom()` exist for normalizing (e.g. to a 0–1 factor).
- **Volume:** `BaseSoundEmitter` is exposed; `setVolume(long handle, float volume)` adjusts a playing sound. The vehicle’s emitter is `vehicle:getEmitter()`, and we already store the loop handle in `data.gravelLoopSoundID` from `emitter:playSound("GravelDumpLoop")`.

**Implementation sketch:** While the loop is playing (e.g. in the same place we call `emitter:tick()` or in an update that runs when dumping is active):

1. `local zoom = getCore():getZoom(getPlayer():getPlayerNum())`
2. Normalize to 0–1 with min/max zoom (e.g. `(zoom - min) / (max - min)` or a curve) so “zoomed in = full volume, zoomed out = quieter”.
3. `vehicle:getEmitter():setVolume(data.gravelLoopSoundID, volume)` with that factor.

No FMOD changes required; the actual Lua change can be done in a follow-up.

---

## Cardinal Lock – UX of starting a straight road

Getting the truck pointed exactly cardinal and beginning to dump at the exact right spot is awkward. Several ideas discussed:

**Problem:** The player wants to start dumping from a precise spot (e.g. the edge of a road for a T-intersection) and go dead straight. But the lock takes 3 seconds to engage, during which gravel is being placed at the truck's actual (non-straight) heading.

**Ideas considered:**

- **Shorter delay:** Risky—could lock on the wrong heading if the player is still turning.
- **Require dead-straight before dumping:** Too restrictive; hard to get exactly 0/90/180/270 before pressing dump.
- **Buffer gravel:** Don't place gravel until the lock engages, then retroactively place it on the locked line. Adds complexity and delay, might feel laggy.
- **Pre-aim mode:** Before dumping, show a preview line on the ground at the nearest cardinal. Player confirms, then dumping starts already locked. Best UX but most implementation work.

**No decision made yet.** The gravel snap approach partially solves this because once the lock engages the line is straight; only the first 3 seconds of gravel (before lock) would be off-line.

---

## Tile-gap interpolation (TODO)

**Problem:** When driving at an angle (especially at moderate speed), the truck can skip over tiles between ticks. The dump logic only places gravel at the vehicle's current tile position each tick — if it jumps from tile (5,5) to tile (7,7), tile (6,6) gets no gravel, leaving a visible one-tile gap in the road.

**Observed:** Gaps appear intermittently when driving diagonally. Straight cardinal driving is unaffected (axis lock makes this a non-issue for locked roads). Backing up and re-driving over the gap fills it, but it's annoying.

**Proposed fix:** When the new tile position differs from the previous by more than 1 in either axis, interpolate between `(oldX, oldY)` and `(tileX, tileY)` using a Bresenham-style line walk. Call `getBackSquares` and place gravel for each intermediate position. Only kicks in when there's a gap, so no performance cost during normal slow driving.

**Scope:** This is a general dump logic fix, not specific to axis lock. Should be done on `main`, not the `feature/axis-lock` branch.

**Status:** Not yet implemented.
