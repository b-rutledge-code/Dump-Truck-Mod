"""Offline stack-truth gate for hopper_2d sprites against the bake renders.

Checks (all must PASS):
  position reprojection  every decoded world point projects onto its own
                         pixel within 0.5 px (full and under renders)
  lighting preserved     where full and under show the same surface, 2+ px
                         from the deck silhouette, RGB agrees within 2/255
                         on >= 99.5% of pixels
  deck shown             lower sprites then deck sprites, replace semantics,
                         equals full.png: 0 uncovered, 0 extra, 0 colour diff
  deck hidden            lower sprites alone equal lower.png, same zeros

--dig3 pastes only DIG3_CELLS and checks the pixels those cells own.
--packed reads the shipped sprites (texturepacks_src + LoadingHopper2dCells.lua).

Run (after bake; after pack for --packed):
  blender --background --python stack_truth_metric.py
  blender --background --python stack_truth_metric.py -- --dig3
  blender --background --python stack_truth_metric.py -- --packed
"""

from __future__ import annotations

import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bake_2d_tiles as bake  # noqa: E402
import pz_iso  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, "../../Contents/mods/DumpTruckGravelMod/42.20"))
PACKED_DIR = os.path.join(REPO, "media/texturepacks_src/hopper_2d")
CELLS_LUA = os.path.join(REPO, "media/lua/shared/DumpTruck/LoadingHopper2dCells.lua")
REPROJECT_MAX_PX = 0.5
LIGHT_TOL = 2
LIGHT_MIN = 0.995
LIGHT_SILHOUETTE_PX = 2
SAME_SURFACE_M = 1e-3


def load_layout():
    with open(bake.LAYOUT_JSON, encoding="utf-8") as handle:
        layout = json.load(handle)
    layout["owners"] = [tuple(k) for k in layout["owners"]]
    return layout


def render_path(name: str) -> str:
    return os.path.join(bake.RENDER_DIR, name)


def reprojection(pos, layout, label):
    world, valid = bake.decode_world(pos, layout["bmin"], layout["size"])
    jj, ii = np.nonzero(valid)
    p = world[jj, ii]
    cx = layout["x0"] + 64.0 * (p[:, 0] - p[:, 1])
    cy = layout["y0"] + 32.0 * (p[:, 0] + p[:, 1]) - 192.0 * p[:, 2] / pz_iso.FLOOR_M
    err = np.hypot(cx - (ii + 0.5), cy - (jj + 0.5))
    worst = float(err.max()) if err.size else 0.0
    over = int(np.count_nonzero(err > REPROJECT_MAX_PX))
    ok = err.size > 0 and over == 0
    print(
        "  reproject %-5s points %d max_err_px %.4f over_%.1f %d %s"
        % (label, err.size, worst, REPROJECT_MAX_PX, over, "PASS" if ok else "FAIL")
    )
    return ok, world, valid


def lighting(full, under, fw, fv, uw, uv, full_own, layout):
    fz_tab = np.array([k[2] for k in layout["owners"]], dtype=np.int64)
    deck = (full_own >= 0) & (fz_tab[np.maximum(full_own, 0)] == 3)
    near_deck = bake.dilate(deck, LIGHT_SILHOUETTE_PX)
    same = (
        fv
        & uv
        & (full[..., 3] == 255)
        & (under[..., 3] == 255)
        & (np.linalg.norm(fw - uw, axis=-1) < SAME_SURFACE_M)
        & ~near_deck
    )
    n = int(np.count_nonzero(same))
    d = np.abs(full[..., :3].astype(np.int32) - under[..., :3].astype(np.int32)).max(axis=-1)
    agree = int(np.count_nonzero(same & (d <= LIGHT_TOL)))
    frac = agree / n if n else 0.0
    ok = n > 0 and frac >= LIGHT_MIN
    print(
        "  lighting same_surface %d agree_within_%d %.5f min %.3f max_diff %d %s"
        % (n, LIGHT_TOL, frac, LIGHT_MIN, int(d[same].max()) if n else -1, "PASS" if ok else "FAIL")
    )
    return ok


def baked_rows():
    rows = pz_iso.read_manifest_rows(bake.MANIFEST)
    return [(gx, gy, fz, kind, os.path.join(bake.OUT_DIR, name)) for gx, gy, fz, kind, name in rows]


def load_packed(path: str) -> np.ndarray:
    """Shipped sprite as a 128x256 frame: the texture sits at its toml frame_offset (default 0,0)."""
    tex = bake.read_png(path)
    toml_text = open(path[: -len(".png")] + ".toml", encoding="utf-8").read()
    m = re.search(r"frame_offset = \[(\d+), (\d+)\]", toml_text)
    ox, oy = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    frame = np.zeros((pz_iso.TILE_H, pz_iso.TILE_W, 4), dtype=np.uint8)
    th, tw = tex.shape[:2]
    frame[oy : oy + th, ox : ox + tw] = tex
    return frame


def packed_rows():
    text = open(CELLS_LUA, encoding="utf-8").read()
    rows = []
    for m in re.finditer(
        r'gx = (-?\d+), gy = (-?\d+), fz = (-?\d+), kind = "(\w+)", sprite = "(\w+)"', text
    ):
        rows.append(
            (
                int(m.group(1)),
                int(m.group(2)),
                int(m.group(3)),
                m.group(4),
                os.path.join(PACKED_DIR, m.group(5) + ".png"),
            )
        )
    return rows


def truth(label, ref, comp, region):
    r_on = ref[..., 3] > 0
    c_on = comp[..., 3] > 0
    uncovered = int(np.count_nonzero(region & r_on & ~c_on))
    extra = int(np.count_nonzero(c_on & ~r_on))
    colour = int(np.count_nonzero(region & r_on & c_on & np.any(ref != comp, axis=-1)))
    checked = int(np.count_nonzero(region & r_on))
    ok = checked > 0 and uncovered == 0 and extra == 0 and colour == 0
    print(
        "  %-11s checked %d uncovered %d extra %d colour_diff %d %s"
        % (label, checked, uncovered, extra, colour, "PASS" if ok else "FAIL")
    )
    return ok


def owned_by(own, layout, cells):
    keys = layout["owners"]
    hit = np.array([(k[0], k[1], k[2]) in cells for k in keys], dtype=bool)
    return (own >= 0) & hit[np.maximum(own, 0)]


def main():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    dig3 = "--dig3" in args
    packed = "--packed" in args
    layout = load_layout()
    x0, y0, w, h = layout["x0"], layout["y0"], layout["w"], layout["h"]

    full = bake.read_png(render_path("full.png"))
    under = bake.read_png(render_path("under.png"))
    lower = bake.read_png(render_path("lower.png"))
    full_own = np.load(render_path("full_own.npy")).astype(np.int64)
    lower_own = np.load(render_path("lower_own.npy")).astype(np.int64)

    print("stack_truth_metric", "dig3" if dig3 else "all", "packed" if packed else "baked")
    ok_fp, fw, fv = reprojection(bake.read_exr(render_path("full_pos.exr")), layout, "full")
    ok_up, uw, uv = reprojection(bake.read_exr(render_path("under_pos.exr")), layout, "under")
    ok_light = lighting(full, under, fw, fv, uw, uv, full_own, layout)

    rows = packed_rows() if packed else baked_rows()
    if dig3:
        cells = set(pz_iso.DIG3_CELLS)
        rows = [r for r in rows if (r[0], r[1], r[2]) in cells]
        shown_region = owned_by(full_own, layout, cells)
        hidden_region = owned_by(lower_own, layout, cells)
    else:
        shown_region = np.ones((h, w), dtype=bool)
        hidden_region = shown_region
    cache = {}

    def load(path):
        if path not in cache:
            cache[path] = load_packed(path) if packed else bake.read_png(path)
        return cache[path]

    print("  sprites", len(rows))
    comp_shown = pz_iso.composite(rows, load, x0, y0, w, h, deck=True)
    comp_hidden = pz_iso.composite(rows, load, x0, y0, w, h, deck=False)
    tag = ("dig3_" if dig3 else "") + ("packed_" if packed else "")
    bake.write_png(render_path(tag + "comp_shown.png"), comp_shown)
    bake.write_png(render_path(tag + "comp_hidden.png"), comp_hidden)
    ok_shown = truth("deck shown", full, comp_shown, shown_region)
    ok_hidden = truth("deck hidden", lower, comp_hidden, hidden_region)

    ok = ok_fp and ok_up and ok_light and ok_shown and ok_hidden
    print("  result", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
