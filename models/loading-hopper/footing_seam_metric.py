#!/usr/bin/env python3
"""Offline footing XY seam gate: opaque shared edge + RGB continuity.

Samples the pasted composite of every baked sprite. Adjacent mid-column feet
FOOTING_SEAM_CELLS (-3,-1,0) and (-3,0,0) share the +Y face at y = 0.

Pass gates (defaults):
  seam_frac   >= 0.90  — opaque along shared face, inset 0.02 m into each cell
  rgb_agree   >= 0.85  — fraction of opaque sample pairs with mean |RGB| < 0.12

Run (after bake):
  python3 footing_seam_metric.py
"""

from __future__ import annotations

import sys

import pz_iso
from dig2_seam_metric import ALPHA_ON, load_composite

SEAM_MIN = 0.90
RGB_AGREE_MIN = 0.85
RGB_MAX_DELTA = 0.12
SEAM_SAMPLES = 48
SEAM_INSET_M = 0.02
Z_SAMPLE_M = 0.35


def pixel(comp, layout, x: float, y: float, z: float):
    cx, cy = pz_iso.world_to_canvas(x, y, z, layout["x0"], layout["y0"])
    return comp[int(cy), int(cx)]


def sample_shared_face(comp, layout, gx: int, gy_b: int):
    y_edge = float(gy_b)
    hit_a = hit_b = agree = compared = 0
    for i in range(SEAM_SAMPLES):
        x = gx + (i + 0.5) / SEAM_SAMPLES
        ca = pixel(comp, layout, x, y_edge - SEAM_INSET_M, Z_SAMPLE_M)
        cb = pixel(comp, layout, x, y_edge + SEAM_INSET_M, Z_SAMPLE_M)
        on_a = ca[3] > ALPHA_ON
        on_b = cb[3] > ALPHA_ON
        hit_a += int(on_a)
        hit_b += int(on_b)
        if on_a and on_b:
            compared += 1
            d = sum(abs(int(ca[k]) - int(cb[k])) for k in range(3)) / (3.0 * 255.0)
            if d <= RGB_MAX_DELTA:
                agree += 1
    rgb_agree = agree / compared if compared else 0.0
    return hit_a / SEAM_SAMPLES, hit_b / SEAM_SAMPLES, rgb_agree, compared


def main() -> int:
    (gx_a, gy_a, fz_a), (gx_b, gy_b, fz_b) = pz_iso.FOOTING_SEAM_CELLS[0], pz_iso.FOOTING_SEAM_CELLS[1]
    if fz_a != fz_b or gx_a != gx_b or gy_b != gy_a + 1:
        print("FAIL footing cells are not +Y adjacent", pz_iso.FOOTING_SEAM_CELLS)
        return 1
    comp, layout = load_composite()
    seam_a, seam_b, rgb_agree, compared = sample_shared_face(comp, layout, gx_a, gy_b)

    print("footing_seam_metric")
    print("  cells", pz_iso.FOOTING_SEAM_CELLS[0], pz_iso.FOOTING_SEAM_CELLS[1])
    print(
        "  seam_a %.4f  seam_b %.4f  samples=%d inset_m=%.2f  min=%.2f"
        % (seam_a, seam_b, SEAM_SAMPLES, SEAM_INSET_M, SEAM_MIN)
    )
    print(
        "  rgb_agree %.4f  compared=%d  max_delta=%.2f  min=%.2f"
        % (rgb_agree, compared, RGB_MAX_DELTA, RGB_AGREE_MIN)
    )
    ok = (
        seam_a >= SEAM_MIN
        and seam_b >= SEAM_MIN
        and compared > 0
        and rgb_agree >= RGB_AGREE_MIN
    )
    print("  result", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
