# Overlay test checklist

Run before deploying a change to edge blends, gap fillers, or gravel classification.

## Unit gate

```bash
./scripts/run-overlay-tests.sh
```

Pure Lua, no game. Must be green before any in-game pass.

## Singleplayer

- [ ] 2-wide road: gravel on both squares, outward edge blends on both sides
- [ ] 3-wide road: blends on the outer squares only, clean middle
- [ ] Corner: gap filler triangle appears on the diagonal square
- [ ] Drive a second road alongside the first: the seam between them has no blends left over
- [ ] Drive over an existing gap filler: it upgrades to full gravel and the triangle is gone
- [ ] Shovel a gravel square: original terrain returns, no orphan blend on that square
- [ ] Save, reload, return to the road: blends and gap fillers look the same as before

### Shovel heal, by use case

- [ ] Shovel a road square off the edge of a patch (2 or 3 road neighbours): the hole is terrain, every road face looking into it is blended, and no triangle appears in the hole
- [ ] Shovel a road square out of the middle of a patch (4 road neighbours): all four faces blended, hole stays open
- [ ] Shovel a gap filler: the triangle is gone and does not come back on the same pass
- [ ] Shovel a spur tip (1 road neighbour): that one face is blended
- [ ] Shovel the last square of a patch: clean terrain, nothing blended, no error
- [ ] Shovel an arm out from under a gap filler: the filler goes back to terrain instead of keeping a triangle for a corner that no longer exists
- [ ] Shovel beside a road end already carrying an outward blend: it gains the hole-facing blend and keeps the outward one
- [ ] Shovel ground that was poured over grass carrying a tuft or other attached sprite: the tuft comes back with the terrain
- [ ] Pour back into a shovelled hole: it fills as ordinary road, triangles only where the pocket is a true L

## Multiplayer (dedicated server)

- [ ] Road looks the same as it does in SP, including blends and gap fillers
- [ ] Pour alongside a road built before this change: seams clear, since classification reads sprites rather than metadata
- [ ] With `debugMode` on, `[DumpTruck] cleanup (x, y, z)` lines appear during pours
- [ ] `console.txt` has no new `ObjectModDataPacket.parse: object is null` or `not consistent` warnings
- [ ] Second client sees the same blends as the driver
- [ ] Leave the area, return: floors and blends survive
- [ ] Reconnect: blends still present
- [ ] Shovel a road square: the heal matches SP, and a second client sees the same result
- [ ] Shovel a road square, then leave and return: the heal survives the chunk reload

## Before release

- [ ] `DumpTruckCore.debugMode = false`
- [ ] `./scripts/run-overlay-tests.sh` green
- [ ] Deploy with `scripts/deploy_server.sh`
