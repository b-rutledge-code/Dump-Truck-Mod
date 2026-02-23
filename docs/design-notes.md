# Dump Truck Gravel Mod – design notes

Mod-specific design and future ideas (not general PZ modding knowledge).

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

**Short-lived custom sprites (viable):**

- **Idea:** Custom sprites that look like grass with increasing grey dots; flash them briefly on the square when gravel is placed to suggest pour/splash. No fade—just show the sprite for a short time then remove it.
- **Implementation:** Create an **IsoObject** with the effect sprite, add it to the square with `square:AddTileObject(overlay)`, then remove it after ~0.1–0.2s with `square:RemoveTileObject(overlay)`. Use a **separate** IsoObject (do not use the floor's AttachExistingAnim for this), so we don't wipe edge blends (RemoveAttachedAnims() removes all). Schedule removal via a small table of { object, removeAt } and an OnTick (or similar) handler that checks `getTimestampMs()` and removes expired objects.
- **Assets:** A **few sprites** are enough (e.g. 3–5 frames: grass → grass+few dots → more dots). Flash each briefly (e.g. 50–100 ms) then remove; slightly choppy is fine for Zomboid and still reads as "something pouring." Add sprites to the mod's media.
- **Asset generation:** Start from the **existing gravel sprite** we use. Produce 3–5 variants by adding **increasing gray noise/dots** on top—no new art needed, just "base + more noise" per frame. Well-suited to an AI image tool or a simple script (e.g. overlay gray noise at increasing density).
- **One effect vs per-floor:** Using the *same* gravel-colored pour overlay on every square would look odd: the base floor (grass, dirt, concrete) would still show, then get "colored in" with the gravel overlay, then snap to gravel—visually weird. To look right we'd need a **different pour sprite set per flooring type** (grass+dots on grass, dirt+dots on dirt, etc.), which is a lot of assets. **Compromise:** use a **neutral "dust" effect**—sprites that are just grey/dark speckles (no gravel base), so they read as "debris/dust pouring" and don't clash with any terrain. One set of 3–5 frames, works on any floor. Otherwise: accept per-floor sprite sets for a proper match, or skip the overlay and rely on sound + bed tilt.
- **When to show:** Right when placing gravel (or just before): spawn the effect object on the target square, register for removal; optionally spawn on the last N squares behind the truck for a short "trail" of flashes.

- **Sprite transparency:** The game **does** support transparent sprites—it's baked into the asset (alpha channel). Gap fillers and many tiles use it. So the neutral dust effect can be **grey speckles on a transparent background**; transparent areas show the underlying floor. What isn't supported is *runtime* alpha from Lua (`setAlpha()` is for wall cutaway only). We can add custom sprites with transparency; we just can't fade them in/out from script.

### How to add sprites (for pour effect or any custom sprite)

1. **Create the image(s)**  
   PNG format, **lowercase** filenames (e.g. `dumptruck_pour_01.png`). Use alpha for transparent areas. Typical tile sprite size is up to 128×256; match your use case (e.g. one tile-sized PNG per frame).

2. **Create a texture pack**  
   PZ loads sprites from `.pack` files (texture atlases). Two options:
   - **TileZed:** Tools → .pack files → Create .pack File. Choose the folder containing your PNG(s). Save as e.g. `media/texturepacks/DumpTruckGravelMod.pack` in the mod. TileZed will trim and pack the images and generate entry names from filenames.
   - **pz-pack tool** (see `reference/pz-pack/README.md`): Put each PNG in a folder with a TOML file that defines **entries** (one per sprite). Each entry has a name (the key in TOML), `pos`, `size`, and optionally `frame_offset` (transparent padding), `frame_size`. Run `pz-pack-tool pack ./InputDir ./OutputFile.pack`.

3. **Place the pack in the mod**  
   e.g. `Contents/mods/DumpTruckGravelMod/42.13/media/texturepacks/DumpTruckGravelMod.pack` (or a shared `media/texturepacks/` if you have one).

4. **Register the pack in mod.info**  
   Add a line: `pack=DumpTruckGravelMod` (name without `.pack`). The game loads this pack with the mod.

5. **Use in Lua**  
   Sprite name in code is the **pack entry name** (from TileZed output or your TOML key). e.g. `getSprite("dumptruck_pour_01")` or whatever the packed name is. Then e.g. `IsoObject.new(getCell(), square, getSprite("dumptruck_pour_01"))`.

**References:** PZwiki [Adding new tiles](https://pzwiki.net/wiki/Adding_new_tiles); `reference/pz-pack/README.md` (TOML format, transparent padding).

**Current feedback for dumping:** Sound + bed tilt (see below). Short-lived sprites above would add a visual "splash" without needing particles or transparency.

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

## Cardinal Lock – gravel snap (VIABLE ALTERNATIVE)

Instead of steering the truck, **snap gravel placement to a grid line** so the road is straight even if the truck wobbles:

### How it works

1. When the cardinal lock engages (state machine above), record the vehicle's grid position:
   - Heading N or S (0 or 180 degrees): store `lockedX = math.floor(vehicle:getX() + 0.5)`
   - Heading E or W (90 or 270 degrees): store `lockedY = math.floor(vehicle:getY() + 0.5)`

2. In `tryPourGravelUnderTruck()` (in `DumpTruckGravel.lua`), when cardinal lock is active, override the cross-axis coordinate (`cx` or `cy`) with the locked value before calling `getBackSquares()`.

3. The truck can wobble ~5-10 degrees off cardinal. The road still lands on a perfectly straight line of tiles.

### UX concern

The truck visually wanders but gravel is straight. This is cosmetically weird but functionally correct. The player needs to understand that gravel placement is "snapped" and doesn't follow the truck exactly. Could mitigate with a visual indicator (e.g. "LOCKED" text, or the dust overlay sprites landing on the snapped line).

### Status

Not yet implemented. The lock state machine is in place in `DumpTruckCardinalLock.lua`; the gravel snap logic in `DumpTruckGravel.lua` needs to be added.

---

## Cardinal Lock – auto-regulator (cruise control)

The game has a built-in speed regulator (cruise control): `vehicle:setRegulator(true)` + `vehicle:setRegulatorSpeed(kmh)`. When the cardinal lock engages, we can auto-enable the regulator at 5 km/h so the player doesn't need to hold the gas. The controller already respects the regulator—it's read in `updateRegulator()` inside `CarController.update()`.

**Concern:** If the player is already holding the gas key when the regulator kicks in, releasing gas might feel weird. Need to test whether holding gas overrides the regulator or conflicts with it.

**Status:** Not yet implemented.

---

## Cardinal Lock – audio feedback

When the lock engages, play 3 short car-related sounds (e.g. seatbelt ding) to signal the player that the lock is active.

**Status:** Not yet implemented.

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
