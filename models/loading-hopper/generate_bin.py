"""Author a small hopper bin over the 2×2 bay opening (meters, Z-up)."""

from __future__ import annotations

import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OBJ_PATH = os.path.join(HERE, "loading_hopper_bin.obj")
MTL_PATH = os.path.join(HERE, "loading_hopper_bin.mtl")

FLOOR_M = 2.44949
DECK_Z = 3 * FLOOR_M  # top of z=2 band / walk deck underside region
BIN_TOP = DECK_Z + 0.35
BIN_BOTTOM = DECK_Z - 1.6


class Mesh:
    def __init__(self):
        self.verts: list[np.ndarray] = []
        self.faces: list[tuple[int, int, int, str]] = []

    def add_vert(self, v):
        self.verts.append(np.asarray(v, dtype=float))
        return len(self.verts)

    def box(self, x0, y0, z0, x1, y1, z1, mat):
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        z0, z1 = sorted((z0, z1))
        idx = [
            self.add_vert((x0, y0, z0)),
            self.add_vert((x1, y0, z0)),
            self.add_vert((x1, y1, z0)),
            self.add_vert((x0, y1, z0)),
            self.add_vert((x0, y0, z1)),
            self.add_vert((x1, y0, z1)),
            self.add_vert((x1, y1, z1)),
            self.add_vert((x0, y1, z1)),
        ]
        quads = (
            (0, 1, 2, 3),
            (4, 7, 6, 5),
            (0, 4, 5, 1),
            (1, 5, 6, 2),
            (2, 6, 7, 3),
            (3, 7, 4, 0),
        )
        for a, b, c, d in quads:
            self.faces.append((idx[a], idx[b], idx[c], mat))
            self.faces.append((idx[a], idx[c], idx[d], mat))

    def shell(self, z_top, w_top, d_top, z_bot, w_bot, d_bot, mat, thick=0.08):
        # Four walls of a frustum (outer boxes approximating the funnel).
        for sx in (-1, 1):
            self.box(
                sx * (w_top / 2) - (thick if sx > 0 else 0),
                -d_top / 2,
                z_bot,
                sx * (w_bot / 2) + (0 if sx > 0 else thick),
                d_top / 2,
                z_top,
                mat,
            )
        for sy in (-1, 1):
            self.box(
                -w_top / 2,
                sy * (d_top / 2) - (thick if sy > 0 else 0),
                z_bot,
                w_top / 2,
                sy * (d_bot / 2) + (0 if sy > 0 else thick),
                z_top,
                mat,
            )


def build() -> Mesh:
    m = Mesh()
    # Rim at deck height, funnel down into the bay, slight offset to bin tile centers.
    # Opening spans blender x,y in [-1,1] roughly (world cols covering bay).
    m.box(-1.05, -1.05, BIN_TOP - 0.1, 1.05, 1.05, BIN_TOP, "galvanized")
    m.box(-0.95, -0.95, DECK_Z - 0.05, 0.95, 0.95, DECK_Z + 0.05, "deck")
    # Funnel walls.
    for i in range(6):
        t0, t1 = i / 6, (i + 1) / 6
        z0 = BIN_TOP - 0.15 - t0 * (BIN_TOP - 0.15 - BIN_BOTTOM)
        z1 = BIN_TOP - 0.15 - t1 * (BIN_TOP - 0.15 - BIN_BOTTOM)
        w0 = 1.9 - t0 * 1.2
        w1 = 1.9 - t1 * 1.2
        d0, d1 = w0, w1
        # Approximate each band as a box ring.
        m.box(-w0 / 2, -d0 / 2, z1, -w0 / 2 + 0.1, d0 / 2, z0, "hopper")
        m.box(w0 / 2 - 0.1, -d0 / 2, z1, w0 / 2, d0 / 2, z0, "hopper")
        m.box(-w0 / 2, -d0 / 2, z1, w0 / 2, -d0 / 2 + 0.1, z0, "hopper")
        m.box(-w0 / 2, d0 / 2 - 0.1, z1, w0 / 2, d0 / 2, z0, "hopper")
    # Chute lip under the bay.
    m.box(-0.35, -0.35, BIN_BOTTOM - 0.2, 0.35, 0.35, BIN_BOTTOM + 0.05, "galvanized")
    return m


def write_obj(mesh: Mesh) -> None:
    mats = sorted({f[3] for f in mesh.faces})
    with open(MTL_PATH, "w", encoding="utf-8") as handle:
        for name in mats:
            handle.write("newmtl %s\nKd 0.5 0.5 0.5\n\n" % name)
    with open(OBJ_PATH, "w", encoding="utf-8") as handle:
        handle.write("mtllib loading_hopper_bin.mtl\n")
        for v in mesh.verts:
            handle.write("v %.6f %.6f %.6f\n" % (v[0], v[1], v[2]))
        current = None
        for a, b, c, mat in mesh.faces:
            if mat != current:
                handle.write("usemtl %s\n" % mat)
                current = mat
            handle.write("f %d %d %d\n" % (a, b, c))
    print("wrote", OBJ_PATH, "verts", len(mesh.verts), "faces", len(mesh.faces))


if __name__ == "__main__":
    write_obj(build())
