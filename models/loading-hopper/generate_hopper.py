#!/usr/bin/env python3
"""Aggregate loading hopper — the bin-on-legs a dump truck drives under.

Units are meters. +Z is up. +Y is the direction the truck faces when it
drives through the bay. Origin is on the ground, centered between the columns.

    python3 generate_hopper.py

Writes loading_hopper.obj, loading_hopper.mtl, and preview PNGs.
The truck drawn in the scale preview is not part of the OBJ.
"""

from __future__ import annotations

import os
from collections import defaultdict

import numpy as np
from PIL import Image

# Column centers. The bay is wider than a truck and long enough for the bed
# to sit under the chute while the cab stays clear of the outlet.
HX = 2.40
HY = 3.30
# Vertical I-columns: depth = flange-to-flange, width = flange width.
# Chunkier than true scale so the I reads at PZ iso distance.
COL_DEPTH = 0.38
COL_WIDTH = 0.30
COL_TW = 0.040
COL_TF = 0.055
POST_DEPTH = 0.28
POST_WIDTH = 0.22
POST_TW = 0.036
POST_TF = 0.048
# Horizontal ring / header I-beams (depth vertical).
BEAM_DEPTH = 0.28
BEAM_WIDTH = 0.20
BEAM_TW = 0.034
BEAM_TF = 0.048

DECK_Z = 7.40
WALK = 0.82
RAIL_H = 1.05

HOPPER_W = 2.95
HOPPER_D = 3.35
BIN_BOTTOM = 6.05
FUNNEL_BOTTOM = 4.30
OUTLET_Z = 3.65
OUTLET_W = 0.82
OUTLET_D = 0.82
PLATE = 0.07

HEADER_Z = 4.40  # underside of the beam the truck drives under

HERE = os.path.dirname(os.path.abspath(__file__))

MAT = {
    "blue": (0.28, 0.48, 0.72),
    "blue_dark": (0.12, 0.24, 0.40),
    "concrete": (0.55, 0.53, 0.49),
    "deck": (0.22, 0.24, 0.26),
    "galvanized": (0.62, 0.64, 0.66),
    "belt": (0.06, 0.06, 0.07),
    "equipment": (0.16, 0.17, 0.18),
    "orange": (0.86, 0.32, 0.06),
    "rubber": (0.08, 0.08, 0.08),
    "glass": (0.45, 0.62, 0.72),
}


class Mesh:
    def __init__(self):
        self.verts = []
        self.tris = []

    def face4(self, pts, mat, group):
        idx = []
        for p in pts:
            self.verts.append((float(p[0]), float(p[1]), float(p[2])))
            idx.append(len(self.verts) - 1)
        self.tris.append((group, mat, idx[0], idx[1], idx[2]))
        self.tris.append((group, mat, idx[0], idx[2], idx[3]))

    def quad_dir(self, pts, direction, mat, group):
        p = [np.asarray(x, float) for x in pts]
        n = np.cross(p[1] - p[0], p[2] - p[0])
        if np.linalg.norm(n) < 1e-10:
            return
        if np.dot(n, np.asarray(direction, float)) < 0:
            p = [p[0], p[3], p[2], p[1]]
        self.face4(p, mat, group)

    def box(self, x0, y0, z0, x1, y1, z1, mat, group):
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        z0, z1 = sorted((z0, z1))
        if x1 - x0 < 1e-5 or y1 - y0 < 1e-5 or z1 - z0 < 1e-5:
            return
        c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        faces = [
            ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
            ([(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)], (0, 0, -1)),
            ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0)),
            ([(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)], (-1, 0, 0)),
            ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0)),
            ([(x1, y0, z0), (x0, y0, z0), (x0, y0, z1), (x1, y0, z1)], (0, -1, 0)),
        ]
        for pts, direction in faces:
            self.quad_dir(pts, direction, mat, group)

    def beam(self, a, b, width, depth, mat, group):
        """Solid rectangular tube — rails / thin members only."""
        a = np.asarray(a, float)
        b = np.asarray(b, float)
        d = b - a
        length = np.linalg.norm(d)
        if length < 1e-4:
            return
        x = d / length
        helper = np.array([0.0, 0.0, 1.0])
        if abs(np.dot(x, helper)) > 0.92:
            helper = np.array([0.0, 1.0, 0.0])
        y = np.cross(helper, x)
        y /= np.linalg.norm(y)
        z = np.cross(x, y)
        hw = width * 0.5
        hd = depth * 0.5

        def corner(s, sy, sz):
            return a + x * s + y * sy + z * sz

        quads = [
            ([corner(length, -hw, -hd), corner(length, hw, -hd), corner(length, hw, hd), corner(length, -hw, hd)], x),
            ([corner(0, hw, -hd), corner(0, -hw, -hd), corner(0, -hw, hd), corner(0, hw, hd)], -x),
            ([corner(0, hw, -hd), corner(length, hw, -hd), corner(length, hw, hd), corner(0, hw, hd)], y),
            ([corner(0, -hw, hd), corner(length, -hw, hd), corner(length, -hw, -hd), corner(0, -hw, -hd)], -y),
            ([corner(0, -hw, hd), corner(length, -hw, hd), corner(length, hw, hd), corner(0, hw, hd)], z),
            ([corner(0, hw, -hd), corner(length, hw, -hd), corner(length, -hw, -hd), corner(0, -hw, -hd)], -z),
        ]
        for pts, direction in quads:
            self.quad_dir(pts, direction, mat, group)

    def ibeam(self, a, b, depth, width, tw, tf, mat, group):
        """I-section from a→b. depth = flange-to-flange, width = flange width."""
        a = np.asarray(a, float)
        b = np.asarray(b, float)
        d = b - a
        length = np.linalg.norm(d)
        if length < 1e-4:
            return
        x = d / length
        # Depth (flange-to-flange) prefers world up on horizontals; world X on verticals.
        up = np.array([0.0, 0.0, 1.0])
        y = up if abs(np.dot(x, up)) < 0.92 else np.array([1.0, 0.0, 0.0])
        y = y - x * np.dot(y, x)
        y /= np.linalg.norm(y)
        z = np.cross(x, y)
        z /= np.linalg.norm(z)
        hd = depth * 0.5
        hw = width * 0.5
        htw = tw * 0.5
        # Two flanges + web as boxes in the beam frame.
        for s0, s1 in ((0.0, length),):
            # bottom flange (local -y)
            self._ibeam_box(a, x, y, z, s0, s1, -hd, -hd + tf, -hw, hw, mat, group)
            # top flange (local +y)
            self._ibeam_box(a, x, y, z, s0, s1, hd - tf, hd, -hw, hw, mat, group)
            # web
            self._ibeam_box(a, x, y, z, s0, s1, -hd + tf, hd - tf, -htw, htw, mat, group)

    def _ibeam_box(self, origin, x, y, z, s0, s1, y0, y1, z0, z1, mat, group):
        def corner(s, sy, sz):
            return origin + x * s + y * sy + z * sz

        quads = [
            ([corner(s1, y0, z0), corner(s1, y1, z0), corner(s1, y1, z1), corner(s1, y0, z1)], x),
            ([corner(s0, y1, z0), corner(s0, y0, z0), corner(s0, y0, z1), corner(s0, y1, z1)], -x),
            ([corner(s0, y1, z0), corner(s1, y1, z0), corner(s1, y1, z1), corner(s0, y1, z1)], y),
            ([corner(s0, y0, z1), corner(s1, y0, z1), corner(s1, y0, z0), corner(s0, y0, z0)], -y),
            ([corner(s0, y0, z1), corner(s1, y0, z1), corner(s1, y1, z1), corner(s0, y1, z1)], z),
            ([corner(s0, y1, z0), corner(s1, y1, z0), corner(s1, y0, z0), corner(s0, y0, z0)], -z),
        ]
        for pts, direction in quads:
            self.quad_dir(pts, direction, mat, group)

    def plate(self, corners, thickness, outward, mat_out, mat_in, group):
        p = [np.asarray(c, float) for c in corners]
        n = np.cross(p[1] - p[0], p[2] - p[0])
        ln = np.linalg.norm(n)
        if ln < 1e-10:
            return
        n /= ln
        if np.dot(n, np.asarray(outward, float)) < 0:
            p = [p[0], p[3], p[2], p[1]]
            n = -n
        inner = [c - n * thickness for c in p]
        self.face4(p, mat_out, group)
        self.face4([inner[0], inner[3], inner[2], inner[1]], mat_in, group)
        for i in range(4):
            j = (i + 1) % 4
            self.quad_dir([p[i], p[j], inner[j], inner[i]], np.cross(p[j] - p[i], inner[i] - p[i]), mat_out, group)

    def cylinder_x(self, center, radius, length, segments, mat, group):
        cx, cy, cz = center
        angles = np.linspace(0, 2 * np.pi, segments, endpoint=False)
        rings = []
        for x in (cx - length / 2, cx + length / 2):
            ring = []
            for a in angles:
                ring.append((x, cy + radius * np.cos(a), cz + radius * np.sin(a)))
            rings.append(ring)
        n = segments
        for i in range(n):
            j = (i + 1) % n
            outward = np.array([0.0, np.cos(angles[i]), np.sin(angles[i])])
            self.quad_dir(
                [rings[0][i], rings[0][j], rings[1][j], rings[1][i]],
                outward,
                mat,
                group,
            )
        for ring, direction in ((rings[0], (-1, 0, 0)), (rings[1], (1, 0, 0))):
            # Fan the cap. Winding is corrected per triangle pair via quad_dir's
            # neighbor; a triangle fan uses face4's first-three assumption, so
            # build quads from the center by splitting the loop into pairs.
            c = (ring[0][0], cy, cz)
            for i in range(0, n, 1):
                j = (i + 1) % n
                self.quad_dir([c, ring[i], ring[j], c], direction, mat, group)


def rect_corners(z, w, d):
    hw, hd = w / 2, d / 2
    return [
        np.array([-hw, -hd, z]),
        np.array([hw, -hd, z]),
        np.array([hw, hd, z]),
        np.array([-hw, hd, z]),
    ]


def add_shell(mesh, z_top, w_top, d_top, z_bot, w_bot, d_bot, thick, group):
    top = rect_corners(z_top, w_top, d_top)
    bot = rect_corners(z_bot, w_bot, d_bot)
    center = np.array([0.0, 0.0, (z_top + z_bot) / 2])
    for i in range(4):
        j = (i + 1) % 4
        mid = (top[i] + top[j] + bot[j] + bot[i]) / 4
        outward = mid - center
        outward[2] = 0.0
        mesh.plate(
            [top[i], top[j], bot[j], bot[i]],
            thick,
            outward,
            "blue",
            "blue_dark",
            group,
        )


def add_x_bay(mesh, origin, axis_u, axis_v, normal, u0, u1, v0, v1, section, group):
    origin = np.asarray(origin, float)
    axis_u = np.asarray(axis_u, float)
    axis_v = np.asarray(axis_v, float)
    normal = np.asarray(normal, float)

    def pt(u, v, shift):
        return origin + axis_u * u + axis_v * v + normal * shift

    mesh.beam(pt(u0, v0, 0.06), pt(u1, v1, 0.06), section, section, "blue", group)
    mesh.beam(pt(u1, v0, -0.06), pt(u0, v1, -0.06), section, section, "blue", group)


def add_rail_run(mesh, a, b, deck_z, group):
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    d = b - a
    length = np.linalg.norm(d)
    if length < 0.2:
        return
    direction = d / length
    mesh.beam(
        (a[0], a[1], deck_z + 0.06),
        (b[0], b[1], deck_z + 0.06),
        0.025,
        0.12,
        "galvanized",
        group,
    )
    mesh.beam(
        (a[0], a[1], deck_z + 0.52),
        (b[0], b[1], deck_z + 0.52),
        0.04,
        0.04,
        "galvanized",
        group,
    )
    mesh.beam(
        (a[0], a[1], deck_z + RAIL_H),
        (b[0], b[1], deck_z + RAIL_H),
        0.045,
        0.045,
        "galvanized",
        group,
    )
    n_posts = max(2, int(round(length / 1.15)) + 1)
    for i in range(n_posts):
        p = a + direction * (length * i / (n_posts - 1))
        mesh.box(
            p[0] - 0.03,
            p[1] - 0.03,
            deck_z,
            p[0] + 0.03,
            p[1] + 0.03,
            deck_z + RAIL_H,
            "galvanized",
            group,
        )


def build_hopper():
    m = Mesh()
    g = "frame"

    # Foundations. End bays stay open so the truck can drive through.
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * HX, sy * HY
            m.box(x - 0.62, y - 0.62, 0.0, x + 0.62, y + 0.62, 0.22, "concrete", "concrete")
            m.box(x - 0.48, y - 0.48, 0.22, x + 0.48, y + 0.48, 0.62, "concrete", "concrete")
            m.box(x - 0.28, y - 0.28, 0.60, x + 0.28, y + 0.28, 0.66, "blue", g)
            m.ibeam(
                (x, y, 0.62),
                (x, y, DECK_Z),
                COL_DEPTH,
                COL_WIDTH,
                COL_TW,
                COL_TF,
                "blue",
                g,
            )
        # Grade beam along each side, clear of the drive ends.
        x = sx * HX
        m.box(x - 0.18, -HY + 0.55, 0.0, x + 0.18, HY - 0.55, 0.38, "concrete", "concrete")
        # Center post on the long sides only.
        m.ibeam(
            (x, 0.0, 0.62),
            (x, 0.0, DECK_Z),
            POST_DEPTH,
            POST_WIDTH,
            POST_TW,
            POST_TF,
            "blue",
            g,
        )
        m.box(x - 0.34, -0.34, 0.0, x + 0.34, 0.34, 0.22, "concrete", "concrete")
        m.box(x - 0.26, -0.26, 0.22, x + 0.26, 0.26, 0.55, "concrete", "concrete")

    # Ring beams: ground girts on the sides, header the truck drives under, top chord.
    for x in (-HX, HX):
        m.ibeam((x, -HY, 1.05), (x, HY, 1.05), BEAM_DEPTH, BEAM_WIDTH, BEAM_TW, BEAM_TF, "blue", g)
        m.ibeam((x, -HY, HEADER_Z), (x, HY, HEADER_Z), BEAM_DEPTH, BEAM_WIDTH, BEAM_TW, BEAM_TF, "blue", g)
        m.ibeam(
            (x, -HY, DECK_Z - 0.10),
            (x, HY, DECK_Z - 0.10),
            BEAM_DEPTH,
            BEAM_WIDTH,
            BEAM_TW,
            BEAM_TF,
            "blue",
            g,
        )
    for y in (-HY, HY):
        m.ibeam((-HX, y, HEADER_Z), (HX, y, HEADER_Z), BEAM_DEPTH, BEAM_WIDTH, BEAM_TW, BEAM_TF, "blue", g)
        m.ibeam(
            (-HX, y, DECK_Z - 0.10),
            (HX, y, DECK_Z - 0.10),
            BEAM_DEPTH,
            BEAM_WIDTH,
            BEAM_TW,
            BEAM_TF,
            "blue",
            g,
        )

    # Side bays split by the center post. Ends are open below the header.
    section = 0.09
    for x, normal in ((HX, (1, 0, 0)), (-HX, (-1, 0, 0))):
        for u0, u1 in ((-HY, 0.0), (0.0, HY)):
            add_x_bay(
                m,
                (x, 0, 0),
                (0, 1, 0),
                (0, 0, 1),
                normal,
                u0,
                u1,
                1.05,
                HEADER_Z,
                section,
                g,
            )
            add_x_bay(
                m,
                (x, 0, 0),
                (0, 1, 0),
                (0, 0, 1),
                normal,
                u0,
                u1,
                HEADER_Z,
                DECK_Z - 0.15,
                section,
                g,
            )
    for y, normal in ((HY, (0, 1, 0)), (-HY, (0, -1, 0))):
        add_x_bay(
            m,
            (0, y, 0),
            (1, 0, 0),
            (0, 0, 1),
            normal,
            -HX,
            HX,
            HEADER_Z,
            DECK_Z - 0.15,
            section,
            g,
        )

    # Hopper. Upper bin, steep funnel, short chute. Rim stands above the top chord.
    add_shell(m, DECK_Z + 0.22, HOPPER_W + 0.16, HOPPER_D + 0.16, DECK_Z - 0.02, HOPPER_W, HOPPER_D, PLATE, "hopper")
    add_shell(m, DECK_Z - 0.02, HOPPER_W, HOPPER_D, BIN_BOTTOM, HOPPER_W, HOPPER_D, PLATE, "hopper")
    add_shell(m, BIN_BOTTOM, HOPPER_W, HOPPER_D, FUNNEL_BOTTOM, OUTLET_W + 0.08, OUTLET_D + 0.08, PLATE, "hopper")
    add_shell(m, FUNNEL_BOTTOM, OUTLET_W + 0.08, OUTLET_D + 0.08, OUTLET_Z, OUTLET_W, OUTLET_D, PLATE, "hopper")

    # Vertical ribs on the upper bin.
    rib_z0, rib_z1 = BIN_BOTTOM + 0.15, DECK_Z - 0.08
    for x in (-0.72, 0.0, 0.72):
        for sy, y0 in ((-1, -HOPPER_D / 2 - 0.07), (1, HOPPER_D / 2)):
            m.box(x - 0.04, y0, rib_z0, x + 0.04, y0 + 0.07, rib_z1, "blue", "hopper")
    for y in (-0.85, 0.85):
        for sx, x0 in ((-1, -HOPPER_W / 2 - 0.07), (1, HOPPER_W / 2)):
            m.box(x0, y - 0.04, rib_z0, x0 + 0.07, y + 0.04, rib_z1, "blue", "hopper")

    # Upper deck: a walk ring around the hopper opening, with a closed rail.
    ox = HX + WALK
    oy = HY + WALK
    ix = HOPPER_W / 2 - 0.02
    iy = HOPPER_D / 2 - 0.02
    top = DECK_Z
    bot = DECK_Z - 0.08
    m.box(-ox, -oy, bot, ox, -iy, top, "deck", "platform")
    m.box(-ox, iy, bot, ox, oy, top, "deck", "platform")
    m.box(-ox, -iy, bot, -ix, iy, top, "deck", "platform")
    m.box(ix, -iy, bot, ox, iy, top, "deck", "platform")
    add_rail_run(m, (-ox, -oy), (ox, -oy), top, "platform")
    add_rail_run(m, (ox, -oy), (ox, oy), top, "platform")
    add_rail_run(m, (ox, oy), (-ox, oy), top, "platform")
    add_rail_run(m, (-ox, oy), (-ox, -oy), top, "platform")

    # Control on the outer +Y (world south) face of the +X, +Y column.
    # Same model tile (2, 3) → world offset (-3, +3). DumpTruckHopper.lua.
    face = HY + COL_DEPTH / 2
    m.box(HX - 0.20, face - 0.04, 1.02, HX + 0.20, face + 0.16, 1.52, "equipment", "panel")
    m.box(HX - 0.12, face + 0.16, 1.18, HX + 0.12, face + 0.19, 1.40, "galvanized", "panel")

    return m


def add_scale_truck(mesh):
    """Block truck used only in the scale preview. Bed centered under the chute."""
    g = "preview_truck"
    bed_y0, bed_y1 = -2.55, 1.35
    mesh.box(-1.22, bed_y0, 1.15, 1.22, bed_y1, 2.28, "orange", g)
    mesh.box(-1.08, bed_y0 + 0.08, 1.22, 1.08, bed_y1 - 0.08, 1.32, "deck", g)
    mesh.box(-1.18, 1.35, 0.85, 1.18, 3.45, 2.85, "orange", g)
    mesh.box(-1.00, 2.15, 1.85, 1.00, 3.35, 2.72, "glass", g)
    mesh.box(-0.35, -2.7, 0.55, 0.35, 3.55, 0.95, "equipment", g)
    mesh.box(-1.15, -2.7, 0.95, 1.15, -2.45, 2.15, "orange", g)
    for y in (-1.85, -0.55, 2.55):
        for x in (-1.05, 1.05):
            mesh.cylinder_x((x, y, 0.48), 0.46, 0.28, 10, "rubber", g)


def write_obj(mesh, path):
    mtl_name = os.path.basename(path).replace(".obj", ".mtl")
    groups = defaultdict(list)
    order = []
    for tri in mesh.tris:
        group = tri[0]
        if group.startswith("preview_"):
            continue
        if group not in groups:
            order.append(group)
        groups[group].append(tri)

    with open(path, "w", encoding="utf-8") as f:
        f.write("# Aggregate loading hopper\n")
        f.write("# units: meters\n")
        f.write("# up: +Z    truck faces: +Y    origin: ground center of the bay\n")
        f.write(f"mtllib {mtl_name}\n")
        for v in mesh.verts:
            f.write(f"v {v[0]:.4f} {v[1]:.4f} {v[2]:.4f}\n")
        normal_index = {}
        normals = []

        def vn(i, j, k):
            a = np.array(mesh.verts[i])
            b = np.array(mesh.verts[j])
            c = np.array(mesh.verts[k])
            n = np.cross(b - a, c - a)
            ln = np.linalg.norm(n)
            if ln < 1e-12:
                n = np.array([0.0, 0.0, 1.0])
            else:
                n = n / ln
            key = tuple(np.round(n, 5))
            if key not in normal_index:
                normal_index[key] = len(normals) + 1
                normals.append(n)
                f.write(f"vn {n[0]:.5f} {n[1]:.5f} {n[2]:.5f}\n")
            return normal_index[key]

        # Normals must be written before faces. Collect first.
    # Rewrite with a two-pass so vn comes before f. Verts are already known.
    pending = []
    normal_index = {}
    normals = []
    for group in order:
        for tri in groups[group]:
            _, mat, i, j, k = tri
            a = np.array(mesh.verts[i])
            b = np.array(mesh.verts[j])
            c = np.array(mesh.verts[k])
            n = np.cross(b - a, c - a)
            ln = np.linalg.norm(n)
            n = np.array([0.0, 0.0, 1.0]) if ln < 1e-12 else n / ln
            key = tuple(np.round(n, 5))
            if key not in normal_index:
                normal_index[key] = len(normals) + 1
                normals.append(n)
            pending.append((group, mat, i, j, k, normal_index[key]))

    with open(path, "w", encoding="utf-8") as f:
        f.write("# Aggregate loading hopper\n")
        f.write("# units: meters\n")
        f.write("# up: +Z    truck faces: +Y    origin: ground center of the bay\n")
        f.write(f"mtllib {mtl_name}\n")
        for v in mesh.verts:
            f.write(f"v {v[0]:.4f} {v[1]:.4f} {v[2]:.4f}\n")
        for n in normals:
            f.write(f"vn {n[0]:.5f} {n[1]:.5f} {n[2]:.5f}\n")
        current_g = None
        current_m = None
        for group, mat, i, j, k, ni in pending:
            if group != current_g:
                f.write(f"g {group}\n")
                current_g = group
            if mat != current_m:
                f.write(f"usemtl {mat}\n")
                current_m = mat
            f.write(f"f {i+1}//{ni} {j+1}//{ni} {k+1}//{ni}\n")

    mtl_path = os.path.splitext(path)[0] + ".mtl"
    with open(mtl_path, "w", encoding="utf-8") as f:
        f.write("# Flat game colors. Swap these for textures when the prop is imported.\n")
        for name, rgb in MAT.items():
            if name in ("orange", "rubber", "glass"):
                continue
            f.write(f"newmtl {name}\n")
            f.write(f"Kd {rgb[0]:.3f} {rgb[1]:.3f} {rgb[2]:.3f}\n")
            f.write("Ka 0.05 0.05 0.05\nillum 2\nNs 20\n\n")


def render(mesh, path, eye, target, size=(1400, 900), fov_deg=38.0):
    w, h = size
    eye = np.asarray(eye, float)
    target = np.asarray(target, float)
    forward = target - eye
    forward /= np.linalg.norm(forward)
    world_up = np.array([0.0, 0.0, 1.0])
    right = np.cross(forward, world_up)
    right /= np.linalg.norm(right)
    up = np.cross(right, forward)

    img = np.zeros((h, w, 3), dtype=np.float32)
    # Sky gradient, lighter toward the horizon.
    t = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None, None]
    zenith = np.array([0.10, 0.38, 0.78], dtype=np.float32)
    horizon = np.array([0.62, 0.80, 0.92], dtype=np.float32)
    img[:] = zenith * (1.0 - t) + horizon * t
    zbuf = np.full((h, w), np.inf, dtype=np.float32)

    light = np.array([0.45, -0.25, 0.86], dtype=np.float64)
    light /= np.linalg.norm(light)
    fy = (h / 2) / np.tan(np.deg2rad(fov_deg) / 2)
    fx = fy

    verts = np.array(mesh.verts, dtype=np.float64)
    rel = verts - eye
    cam = np.stack(
        [rel @ right, rel @ up, rel @ forward],
        axis=1,
    )

    def project(poly):
        z = poly[:, 2]
        return np.stack([fx * poly[:, 0] / z + w / 2, h / 2 - fy * poly[:, 1] / z, z], axis=1)

    def clip_near(poly, near=0.2):
        out = []
        count = len(poly)
        for i in range(count):
            a = poly[i]
            b = poly[(i + 1) % count]
            a_in = a[2] >= near
            b_in = b[2] >= near
            if a_in and b_in:
                out.append(b)
            elif a_in and not b_in:
                t = (near - a[2]) / (b[2] - a[2])
                out.append(a + t * (b - a))
            elif (not a_in) and b_in:
                t = (near - a[2]) / (b[2] - a[2])
                out.append(a + t * (b - a))
                out.append(b)
        return out

    def shade(normal, rgb):
        n = normal
        if np.dot(n, light) < 0:
            n = -n
        ndotl = max(0.0, float(np.dot(n, light)))
        col = np.array(rgb) * (0.34 + 0.66 * ndotl)
        return np.clip(col, 0.0, 1.0)

    def paint(p2, rgb):
        # p2: Nx3 pixel x, pixel y, camera z
        xs = p2[:, 0]
        ys = p2[:, 1]
        minx = max(int(np.floor(xs.min())), 0)
        maxx = min(int(np.ceil(xs.max())), w - 1)
        miny = max(int(np.floor(ys.min())), 0)
        maxy = min(int(np.ceil(ys.max())), h - 1)
        if minx >= maxx or miny >= maxy:
            return
        v0, v1, v2 = p2
        den = (v1[1] - v2[1]) * (v0[0] - v2[0]) + (v2[0] - v1[0]) * (v0[1] - v2[1])
        if abs(den) < 1e-6:
            return
        gy, gx = np.mgrid[miny : maxy + 1, minx : maxx + 1]
        gx = gx + 0.5
        gy = gy + 0.5
        w0 = ((v1[1] - v2[1]) * (gx - v2[0]) + (v2[0] - v1[0]) * (gy - v2[1])) / den
        w1 = ((v2[1] - v0[1]) * (gx - v2[0]) + (v0[0] - v2[0]) * (gy - v2[1])) / den
        w2 = 1.0 - w0 - w1
        mask = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not np.any(mask):
            return
        depth = w0 * v0[2] + w1 * v1[2] + w2 * v2[2]
        zb = zbuf[miny : maxy + 1, minx : maxx + 1]
        hit = mask & (depth < zb)
        if not np.any(hit):
            return
        zb[hit] = depth[hit]
        zbuf[miny : maxy + 1, minx : maxx + 1] = zb
        tile = img[miny : maxy + 1, minx : maxx + 1]
        tile[hit] = rgb
        img[miny : maxy + 1, minx : maxx + 1] = tile

    # Ground first, so the structure sits on something.
    ground = np.array(
        [[-18, -18, 0], [18, -18, 0], [18, 22, 0], [-18, 22, 0]],
        dtype=np.float64,
    )
    ground_cam = np.stack(
        [
            (ground - eye) @ right,
            (ground - eye) @ up,
            (ground - eye) @ forward,
        ],
        axis=1,
    )
    clipped = clip_near(ground_cam)
    if len(clipped) >= 3:
        projected = project(np.array(clipped))
        ground_rgb = np.array([0.45, 0.38, 0.30])
        for i in range(1, len(projected) - 1):
            paint(projected[[0, i, i + 1]], ground_rgb)

    for group, mat, i, j, k in mesh.tris:
        poly = cam[[i, j, k]]
        if np.all(poly[:, 2] < 0.2):
            continue
        clipped = clip_near(poly)
        if len(clipped) < 3:
            continue
        n = np.cross(poly[1] - poly[0], poly[2] - poly[0])
        ln = np.linalg.norm(n)
        if ln < 1e-10:
            continue
        n /= ln
        # Backface cull in camera space. Camera looks down +Z, so a front face
        # has a normal with negative Z if it faces the camera... world normal
        # transformed: visible if it points back toward the eye, i.e. against +forward.
        world_n = np.cross(verts[j] - verts[i], verts[k] - verts[i])
        wln = np.linalg.norm(world_n)
        if wln < 1e-12:
            continue
        world_n /= wln
        if np.dot(world_n, forward) > 0.15:
            continue
        rgb = shade(world_n, MAT[mat])
        projected = project(np.array(clipped))
        for s in range(1, len(projected) - 1):
            paint(projected[[0, s, s + 1]], rgb)

    out = (np.clip(img, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(out, "RGB").save(path)
    print(f"wrote {path}")


def report(mesh):
    vs = np.array([v for v in mesh.verts]) if False else np.array(mesh.verts)
    used = [t for t in mesh.tris if not t[0].startswith("preview_")]
    pts = []
    for _, _, i, j, k in used:
        pts.extend((mesh.verts[i], mesh.verts[j], mesh.verts[k]))
    arr = np.array(pts)
    lo, hi = arr.min(0), arr.max(0)
    print(f"triangles {len(used)}  vertices {len(mesh.verts)}")
    print(f"bounds x {lo[0]:.2f}..{hi[0]:.2f}  y {lo[1]:.2f}..{hi[1]:.2f}  z {lo[2]:.2f}..{hi[2]:.2f}")
    print(f"chute underside {OUTLET_Z:.2f} m    header clearance {HEADER_Z - 0.14:.2f} m")
    print(f"bay clear width {2 * HX - COL_DEPTH:.2f} m    bay clear length {2 * HY - COL_DEPTH:.2f} m")


def main():
    mesh = build_hopper()
    add_scale_truck(mesh)
    obj_path = os.path.join(HERE, "loading_hopper.obj")
    write_obj(mesh, obj_path)
    report(mesh)
    print(f"wrote {obj_path}")
    target = (0.0, 0.2, 3.6)
    render(mesh, os.path.join(HERE, "preview.png"), eye=(6.2, -13.5, 2.4), target=target)
    render(
        mesh,
        os.path.join(HERE, "preview_bay.png"),
        eye=(0.0, -14.5, 2.2),
        target=(0.0, 0.0, 3.2),
        fov_deg=34,
    )
    # Model only, from the same angle as the photo, for a clean look at the mesh.
    clean = build_hopper()
    render(clean, os.path.join(HERE, "preview_model.png"), eye=(7.4, -12.8, 3.0), target=(0.2, 0.4, 4.0))
    render(
        clean,
        os.path.join(HERE, "preview_top.png"),
        eye=(-2.5, -1.5, 22.0),
        target=(-1.5, 0.0, 5.0),
        fov_deg=42,
    )


if __name__ == "__main__":
    main()
