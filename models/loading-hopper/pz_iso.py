"""Shared IsoUtils ↔ sprite pixel math for hopper 2D tiles.

Matches zombie.iso.IsoUtils XToScreen / YToScreen at tileScale=2:
  sx = 32 * s * (x - y)
  sy = 16 * s * (x + y) + (screenZ - z_floors) * 96 * s

z_floors = z_meters / FLOOR_M. Engine draws at XToScreen/YToScreen(square)
minus (32*s, 96*s), so the cell north corner (gx, gy, fz) lands on sprite
pixel (TILE_W/2, FOOTING*TILE_H) = (64, 192). Floor diamond fills rows 192–256;
cell-centre floor is row 224.
"""

from __future__ import annotations

import math
from typing import Iterable, List, Sequence, Tuple

TILE_SCALE = 2
FLOOR_M = math.sqrt(6.0)  # engine floor height ≈ 2.44949
# IsoSprite / IsoObject offsetY = 96 * tileScale → north-corner row in a 256px sprite.
FOOTING = (96 * TILE_SCALE) / float(128 * TILE_SCALE)  # 0.75
TILE_W = 64 * TILE_SCALE  # 128
TILE_H = 128 * TILE_SCALE  # 256
# Cell-centre floor row as a fraction of TILE_H (north corner + 16*tileScale).
CENTRE_FOOTING = (FOOTING * TILE_H + 16.0 * TILE_SCALE) / float(TILE_H)  # 0.875 → row 224
# Exact world width of one tile along camera-right (1,-1,0).
ORTHO_SCALE = math.sqrt(2.0)
MASK_PAD_PX = 2


def x_to_screen(x: float, y: float, z_floors: float, screen_z: float = 0.0) -> float:
    _ = z_floors, screen_z
    return 32.0 * TILE_SCALE * (x - y)


def y_to_screen(x: float, y: float, z_floors: float, screen_z: float = 0.0) -> float:
    return (
        16.0 * TILE_SCALE * (x + y)
        + (screen_z - z_floors) * 96.0 * TILE_SCALE
    )


def world_to_sprite(
    x: float,
    y: float,
    z_m: float,
    gx: int,
    gy: int,
    fz: int,
) -> Tuple[float, float]:
    """Map world meters to sprite pixels for cell (gx,gy,fz).

    Origin is the cell north corner on the floor plane — matches IsoSprite
    prepareToRenderSprite (square x,y,z minus offset 32s/96s).
    """
    z_floors = z_m / FLOOR_M
    ox = float(gx)
    oy = float(gy)
    sx = x_to_screen(x, y, z_floors) - x_to_screen(ox, oy, float(fz))
    sy = y_to_screen(x, y, z_floors) - y_to_screen(ox, oy, float(fz))
    px = TILE_W * 0.5 + sx
    py = FOOTING * TILE_H + sy
    return px, py


def cell_box_corners_m(gx: int, gy: int, fz: int) -> List[Tuple[float, float, float]]:
    """Eight corners of the cell AABB in world meters."""
    z0 = fz * FLOOR_M
    z1 = (fz + 1) * FLOOR_M
    out = []
    for x in (float(gx), float(gx + 1)):
        for y in (float(gy), float(gy + 1)):
            for z in (z0, z1):
                out.append((x, y, z))
    return out


def ownership_hull(
    gx: int, gy: int, fz: int
) -> List[Tuple[float, float]]:
    """Convex hull of cell AABB in sprite pixels (ownership hex)."""
    pts = [world_to_sprite(x, y, z, gx, gy, fz) for x, y, z in cell_box_corners_m(gx, gy, fz)]
    return convex_hull(pts)


def convex_hull(points: Sequence[Tuple[float, float]]) -> List[Tuple[float, float]]:
    """Monotone-chain convex hull. Returns CCW vertices."""
    pts = sorted(set((float(x), float(y)) for x, y in points))
    if len(pts) <= 1:
        return list(pts)

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: List[Tuple[float, float]] = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper: List[Tuple[float, float]] = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def camera_basis_world():
    """Unit right / up / look-forward matching IsoUtils (orthonormal).

    IsoUtils sy increases down the screen and decreases with world Z, so
    screen-up (toward PNG row 0) is ∝ (-1, -1, +FLOOR_M) — opposite the sy
    gradient. Look direction is right × up (down at the cell from above).
    """
    # grad sx ∝ (1, -1, 0)
    right = (1.0 / math.sqrt(2.0), -1.0 / math.sqrt(2.0), 0.0)
    # screen-up = -grad sy ∝ (-1, -1, +FLOOR_M)
    up_raw = (-1.0, -1.0, FLOOR_M)
    up_len = math.sqrt(up_raw[0] ** 2 + up_raw[1] ** 2 + up_raw[2] ** 2)
    up = (up_raw[0] / up_len, up_raw[1] / up_len, up_raw[2] / up_len)
    # look = right × up (downward iso)
    fx = right[1] * up[2] - right[2] * up[1]
    fy = right[2] * up[0] - right[0] * up[2]
    fz = right[0] * up[1] - right[1] * up[0]
    fl = math.sqrt(fx * fx + fy * fy + fz * fz)
    forward = (fx / fl, fy / fl, fz / fl)
    return right, up, forward


# Fixture cells: one foot + fully-decked rim samples (bin mouth excluded).
FIXTURE_CELLS: List[Tuple[int, int, int]] = [
    (-3, -4, 0),
    (0, 2, 3),
    (1, 2, 3),
    (-1, 2, 3),
    (2, 2, 3),
    (0, 3, 3),
    (1, 3, 3),
    (-2, 2, 3),
    (2, -4, 3),
    (3, -4, 3),
]

# Dig #2: two adjacent fully-decked rim cells.
DIG2_CELLS: List[Tuple[int, int, int]] = [
    (0, 2, 3),
    (1, 2, 3),
]

# Dig #3: one east column stack + deck cell + rail-edge neighbour.
DIG3_CELLS: List[Tuple[int, int, int]] = [
    (2, -4, 0),
    (2, -4, 1),
    (2, -4, 2),
    (2, -4, 3),
    (3, -4, 3),
]

# Adjacent mid-column feet (shared +Y face) for XY seam RGB continuity.
FOOTING_SEAM_CELLS: List[Tuple[int, int, int]] = [
    (-3, -1, 0),
    (-3, 0, 0),
]

# Deck opening — must emit no kind=floor after bake/pack.
BIN_MOUTH_XY = {
    (-1, -1),
    (0, -1),
    (-1, 0),
    (0, 0),
}

DECK_SURFACE_Z = 7.40
# Deck level starts below the modelled slab underside (z 7.32) and above the
# support beam tops (z 7.29); everything at or above it is stamped on fz 3.
DECK_LAYER_Z = 7.30
DECK_FLOOR_TOP = DECK_SURFACE_Z + 0.005


def engine_offset(gx: int, gy: int, fz: int) -> Tuple[int, int]:
    """Screen offset of cell (gx,gy,fz) sprite relative to cell (0,0,0)."""
    return 64 * (gx - gy), 32 * (gx + gy) - 192 * fz


def point_owner(x: float, y: float, z: float) -> Tuple[int, int, int, str]:
    """Cell and sprite kind (floor / upper / object) that owns a surface point."""
    gx = int(math.floor(x))
    gy = int(math.floor(y))
    if z >= DECK_LAYER_Z:
        if z <= DECK_FLOOR_TOP and (gx, gy) not in BIN_MOUTH_XY:
            return gx, gy, 3, "floor"
        return gx, gy, 3, "upper"
    fz = min(2, max(0, int(math.floor(z / FLOOR_M))))
    return gx, gy, fz, "object"


def sprite_name(gx: int, gy: int, fz: int, kind: str) -> str:
    if kind == "floor":
        return "hopper_2d_%d_%d_%d_floor.png" % (gx, gy, fz)
    if kind == "upper":
        return "hopper_2d_%d_%d_%d_upper.png" % (gx, gy, fz)
    return "hopper_2d_%d_%d_%d.png" % (gx, gy, fz)


def manifest_kind(kind: str) -> str:
    return "floor" if kind == "floor" else "object"


def canvas_layout(cells: Iterable[Tuple[int, int, int]]) -> Tuple[int, int, int, int]:
    """Canvas (x0, y0, w, h) covering every cell sprite rect.

    (x0, y0) is the canvas pixel of world (0,0,0); cell sprite top-left is
    (x0 + ox - TILE_W/2, y0 + oy - FOOTING*TILE_H) with (ox, oy) = engine_offset.
    """
    half = TILE_W // 2
    foot = int(FOOTING * TILE_H)
    lefts, tops = [], []
    for gx, gy, fz in cells:
        ox, oy = engine_offset(gx, gy, fz)
        lefts.append(ox - half)
        tops.append(oy - foot)
    min_l, max_l = min(lefts), max(lefts) + TILE_W
    min_t, max_t = min(tops), max(tops) + TILE_H
    return -min_l, -min_t, max_l - min_l, max_t - min_t


def sprite_rect(gx: int, gy: int, fz: int, x0: int, y0: int) -> Tuple[int, int]:
    """Canvas top-left of a cell sprite."""
    ox, oy = engine_offset(gx, gy, fz)
    return x0 + ox - TILE_W // 2, y0 + oy - int(FOOTING * TILE_H)


def world_to_canvas(x: float, y: float, z_m: float, x0: int, y0: int) -> Tuple[float, float]:
    return (
        x0 + x_to_screen(x, y, 0.0),
        y0 + y_to_screen(x, y, z_m / FLOOR_M),
    )


def read_manifest_rows(path: str) -> List[Tuple[int, int, int, str, str]]:
    rows = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            gx, gy, fz, kind, name = line.split()
            rows.append((int(gx), int(gy), int(fz), kind, name))
    return rows


def paste_replace(canvas, sprite, left: int, top: int) -> None:
    """Write sprite pixels with alpha > 0 over canvas (numpy HxWx4)."""
    th, tw = sprite.shape[:2]
    win = canvas[top : top + th, left : left + tw]
    on = sprite[..., 3] > 0
    win[on] = sprite[on]


def composite(rows, load, x0: int, y0: int, w: int, h: int, deck: bool = True):
    """Paste lower-level sprites, then (when deck) fz 3 sprites, replace semantics.

    rows: (gx, gy, fz, kind, key); load(key) -> uint8 HxWx4 array.
    """
    import numpy as np

    canvas = np.zeros((h, w, 4), dtype=np.uint8)
    for want_deck in (False, True):
        if want_deck and not deck:
            break
        for gx, gy, fz, _kind, key in rows:
            if (fz == 3) != want_deck:
                continue
            left, top = sprite_rect(gx, gy, fz, x0, y0)
            paste_replace(canvas, load(key), left, top)
    return canvas

# Cells containing the columns (x=±2.40 → gx −3/2; y=±3.30 → −4/3; mid y=0 → −1/0).
SOLID_XY = {
    (-3, -4),
    (2, -4),
    (-3, 3),
    (2, 3),
    (-3, -1),
    (-3, 0),
    (2, -1),
    (2, 0),
}


def cell_role(gx: int, gy: int, fz: int) -> str:
    if fz == 0 and (gx, gy) in SOLID_XY:
        return "foot"
    if fz == 3:
        return "deck"
    return "wall"


def role_opaque_ok(role: str, opaque: int) -> bool:
    """Soft budget checks; hard fail is outside-hull, not density."""
    if role == "foot":
        return opaque < 12000
    if role == "deck":
        return opaque < 30000
    return opaque < 30000
