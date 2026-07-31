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

## Multiplayer (dedicated server)

- [ ] Road looks the same as it does in SP, including blends and gap fillers
- [ ] Pour alongside a road built before this change: seams clear, since classification reads sprites rather than metadata
- [ ] With `debugMode` on, `[DumpTruck] cleanup (x, y, z)` lines appear during pours
- [ ] `console.txt` has no new `ObjectModDataPacket.parse: object is null` or `not consistent` warnings
- [ ] Second client sees the same blends as the driver
- [ ] Leave the area, return: floors and blends survive
- [ ] Reconnect: blends still present

## Before release

- [ ] `DumpTruckCore.debugMode = false`
- [ ] `./scripts/run-overlay-tests.sh` green
- [ ] Deploy with `scripts/deploy_server.sh`
