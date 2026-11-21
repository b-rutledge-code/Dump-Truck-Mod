#!/usr/bin/env python3
"""Assert bin-mouth cells emit no kind=floor in bake manifest / cells lua.

Run after bake (manifest) and/or pack (LoadingHopper2dCells.lua):
  python3 mouth_gate.py
  python3 mouth_gate.py --packed
"""

from __future__ import annotations

import os
import re
import sys

import pz_iso

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "2d_tiles", "manifest.txt")
CELLS_LUA = os.path.join(
    HERE,
    "..",
    "..",
    "Contents",
    "mods",
    "DumpTruckGravelMod",
    "42.20",
    "media",
    "lua",
    "shared",
    "DumpTruck",
    "LoadingHopper2dCells.lua",
)


def check_manifest(path: str) -> list[str]:
    bad = []
    if not os.path.isfile(path):
        return ["missing manifest: %s" % path]
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 5:
                continue
            gx, gy, fz = int(parts[0]), int(parts[1]), int(parts[2])
            kind = parts[3]
            if (gx, gy) in pz_iso.BIN_MOUTH_XY and kind == "floor":
                bad.append("manifest floor at mouth %s" % line)
    return bad


def check_packed_lua(path: str) -> list[str]:
    bad = []
    if not os.path.isfile(path):
        return ["missing cells lua: %s" % path]
    text = open(path, encoding="utf-8").read()
    # { gx = -1, gy = -1, fz = 3, kind = "floor", sprite = "..." },
    for m in re.finditer(
        r"\{\s*gx\s*=\s*(-?\d+)\s*,\s*gy\s*=\s*(-?\d+)\s*,\s*fz\s*=\s*(-?\d+)\s*,\s*kind\s*=\s*\"(\w+)\"",
        text,
    ):
        gx, gy, fz = int(m.group(1)), int(m.group(2)), int(m.group(3))
        kind = m.group(4)
        if (gx, gy) in pz_iso.BIN_MOUTH_XY and kind == "floor":
            bad.append("packed floor at mouth gx=%d gy=%d fz=%d" % (gx, gy, fz))
    return bad


def main() -> int:
    packed = "--packed" in sys.argv
    bad = check_manifest(MANIFEST)
    if packed:
        bad.extend(check_packed_lua(os.path.normpath(CELLS_LUA)))
    print("mouth_gate")
    print("  mouth_xy", sorted(pz_iso.BIN_MOUTH_XY))
    if bad:
        for b in bad:
            print("  FAIL", b)
        print("  result FAIL")
        return 1
    print("  result PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
