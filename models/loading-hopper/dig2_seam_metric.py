#!/usr/bin/env python3
"""Offline dig2 look metric: filled floor diamonds + opaque shared edge.

Samples the pasted composite of every baked sprite (lower levels, then the
deck), so anything drawn in front of a DIG2 deck cell counts as coverage.

Pass gates (defaults):
  fill_frac  >= 0.95  — opaque / floor-diamond pixels per cell
  seam_frac  >= 0.95  — opaque along the shared edge, inset 0.02 m into each cell

Run (after bake):
  python3 dig2_seam_metric.py
"""

from __future__ import annotations

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

import pz_iso

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(HERE, "2d_tiles")
MANIFEST = os.path.join(SRC_DIR, "manifest.txt")
LAYOUT_JSON = os.path.join(SRC_DIR, "_render", "layout.json")
ALPHA_ON = 8
FILL_MIN = 0.95
SEAM_MIN = 0.95
SEAM_SAMPLES = 64
SEAM_INSET_M = 0.02


def load_composite():
    with open(LAYOUT_JSON, encoding="utf-8") as handle:
        layout = json.load(handle)
    rows = pz_iso.read_manifest_rows(MANIFEST)

    def load(name):
        return np.asarray(Image.open(os.path.join(SRC_DIR, name)).convert("RGBA"))

    comp = pz_iso.composite(rows, load, layout["x0"], layout["y0"], layout["w"], layout["h"])
    return comp, layout


def floor_diamond_fill(comp, layout, gx: int, gy: int, fz: int):
    z = float(fz) * pz_iso.FLOOR_M
    corners = [(gx, gy), (gx + 1, gy), (gx + 1, gy + 1), (gx, gy + 1)]
    pts = [pz_iso.world_to_canvas(x, y, z, layout["x0"], layout["y0"]) for x, y in corners]
    mask = Image.new("L", (layout["w"], layout["h"]), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    inside = np.asarray(mask) > 0
    hull = int(np.count_nonzero(inside))
    opaque = int(np.count_nonzero(inside & (comp[..., 3] > ALPHA_ON)))
    return (opaque / hull if hull else 0.0), opaque, hull


def seam_hits(comp, layout, gx_a: int, gy: int, fz: int):
    """Opaque fraction just west and just east of the x = gx_a + 1 edge."""
    x_edge = float(gx_a + 1)
    z = float(fz) * pz_iso.FLOOR_M
    hit_a = hit_b = 0
    for i in range(SEAM_SAMPLES):
        y = gy + (i + 0.5) / SEAM_SAMPLES
        for side, dx in ((0, -SEAM_INSET_M), (1, SEAM_INSET_M)):
            cx, cy = pz_iso.world_to_canvas(x_edge + dx, y, z, layout["x0"], layout["y0"])
            if comp[int(cy), int(cx), 3] > ALPHA_ON:
                if side == 0:
                    hit_a += 1
                else:
                    hit_b += 1
    return hit_a / SEAM_SAMPLES, hit_b / SEAM_SAMPLES


def main() -> int:
    (gx_a, gy_a, fz_a), (gx_b, gy_b, fz_b) = pz_iso.DIG2_CELLS[0], pz_iso.DIG2_CELLS[1]
    if fz_a != fz_b or gy_a != gy_b or gx_b != gx_a + 1:
        print("FAIL dig2 cells are not +X adjacent", pz_iso.DIG2_CELLS)
        return 1
    comp, layout = load_composite()
    fill_a, opq_a, hull_a = floor_diamond_fill(comp, layout, gx_a, gy_a, fz_a)
    fill_b, opq_b, hull_b = floor_diamond_fill(comp, layout, gx_b, gy_b, fz_b)
    seam_a, seam_b = seam_hits(comp, layout, gx_a, gy_a, fz_a)

    print("dig2_seam_metric")
    print("  cells", pz_iso.DIG2_CELLS[0], pz_iso.DIG2_CELLS[1])
    print(
        "  fill_a %.4f (%d/%d)  fill_b %.4f (%d/%d)  min=%.2f"
        % (fill_a, opq_a, hull_a, fill_b, opq_b, hull_b, FILL_MIN)
    )
    print(
        "  seam_a %.4f  seam_b %.4f  samples=%d inset_m=%.2f  min=%.2f"
        % (seam_a, seam_b, SEAM_SAMPLES, SEAM_INSET_M, SEAM_MIN)
    )
    ok = fill_a >= FILL_MIN and fill_b >= FILL_MIN and seam_a >= SEAM_MIN and seam_b >= SEAM_MIN
    print("  result", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
