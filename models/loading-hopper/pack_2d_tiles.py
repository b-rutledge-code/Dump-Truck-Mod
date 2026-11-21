#!/usr/bin/env python3
"""Ownership-clip baked 2d_tiles, write tiledef + pack, emit Lua cell table.

Run:
  python3 pack_2d_tiles.py
"""

from __future__ import annotations

import json
import os
import struct
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import pz_iso

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "../../Contents/mods/DumpTruckGravelMod/42.20"))
SRC_DIR = os.path.join(HERE, "2d_tiles")
MANIFEST = os.path.join(SRC_DIR, "manifest.txt")
OUT_SRC = os.path.join(REPO, "media/texturepacks_src/hopper_2d")
PACK_PATH = os.path.join(REPO, "media/texturepacks/DumpTruckGravelMod.pack")
TILES_PATH = os.path.join(REPO, "media/hopper_2d.tiles")
LUA_PATH = os.path.join(REPO, "media/lua/shared/DumpTruck/LoadingHopper2dCells.lua")
GRATE_PATH = os.path.join(HERE, "grate_industry_01_37_blue.png")
# Vanilla overlay_grime_wall_01_* — multiply-baked into fz=0 object sprites.
VANILLA_GRIME_DIR = os.path.join(HERE, "_vanilla_grime")
# Base wash / streak multiply amounts (overlay alpha is a strength map only).
GRIME_WASH = 0.70
GRIME_STREAK = 0.65
# Concrete pads: soft even stain — no stretched wall-face blotches.
GRIME_CONCRETE_WASH = 0.28
GRIME_CONCRETE_NOISE = 0.12
# Diamond top row of the vanilla industry_01_37 floor frame (frame_offset 0,192).
GRATE_TOP = 192
PZ_PACK = os.path.normpath(
    os.path.join(HERE, "../../../../reference/pz-pack/target/release/pz-pack-tool")
)
# Dig2 thin deck slabs use addFloor; other stamps still honor this flag.
DECK_AS_FLOOR = True
FLOOR_SOLIDFLOOR = True


def is_edge_cell(gx, gy):
    """Walkway cells whose diamond shows ground in the render.

    The engine culls the squares behind a solid floor. Measured in the render, the
    see-through diamond pixels are exactly the outer ring (gx=-4, gy=-5, gy=4, gx=3),
    except (3, 3), which is fully covered. These cells get transparentFloor, and the
    game places a z=2 square below each one (LoadingHopperProof.lua).
    """
    return gx == -4 or gy == -5 or gy == 4 or (gx == 3 and gy != 3)

# Collision for the column feet lives on a separate tile so the visible post
# sprites carry no `solid`; the engine fades solid objects in front of the
# player. The blocker texture is 1x1 and transparent at the cell's south tip,
# so its rect never overlaps the player bounds used by that fade test.
BLOCKER_FRAME_OFFSET = (pz_iso.TILE_W // 2, pz_iso.TILE_H - 1)

def opaque_count(im: Image.Image) -> int:
    return sum(1 for px in im.getdata() if px[3] > 8)


def read_manifest(min_opaque: int = 64):
    cells = []
    skipped = 0
    with open(MANIFEST, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) == 4:
                gx, gy, fz, name = parts
                kind = "floor" if int(fz) == 3 else "object"
            elif len(parts) == 5:
                gx, gy, fz, kind, name = parts
            else:
                skipped += 1
                continue
            if kind not in ("floor", "object"):
                skipped += 1
                continue
            src = os.path.join(SRC_DIR, name)
            if not os.path.isfile(src):
                skipped += 1
                continue
            im = Image.open(src).convert("RGBA")
            if opaque_count(im) < min_opaque:
                skipped += 1
                continue
            cells.append((int(gx), int(gy), int(fz), kind, name))
    cells.sort(key=lambda c: (c[2], c[1], c[0], 0 if c[3] == "floor" else 1))
    print("manifest keep", len(cells), "skip_empty", skipped)
    return cells


def harden_alpha(im: Image.Image) -> Image.Image:
    """Object sprites: alpha is fully on or off. Partly transparent edge pixels blend with the ground and read as a halo."""
    a = np.array(im)
    a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
    return Image.fromarray(a, "RGBA")


def clip_alpha_with_mask(im: Image.Image, mask: Image.Image) -> Image.Image:
    r, g, b, a = im.split()
    a_bytes = bytearray(a.tobytes())
    m_bytes = mask.tobytes()
    for i in range(len(a_bytes)):
        if m_bytes[i] == 0:
            a_bytes[i] = 0
    a_new = Image.frombytes("L", a.size, bytes(a_bytes))
    return Image.merge("RGBA", (r, g, b, a_new))


def apply_ownership_clip(im: Image.Image, gx: int, gy: int, fz: int):
    hull = pz_iso.ownership_hull(gx, gy, fz)
    w, h = im.size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    if len(hull) >= 3:
        cx = sum(p[0] for p in hull) / len(hull)
        cy = sum(p[1] for p in hull) / len(hull)
        pad = float(pz_iso.MASK_PAD_PX)
        expanded = []
        for x, y in hull:
            dx, dy = x - cx, y - cy
            dist = (dx * dx + dy * dy) ** 0.5 or 1.0
            expanded.append((x + pad * dx / dist, y + pad * dy / dist))
        draw.polygon([(p[0], p[1]) for p in expanded], fill=255)

    before = opaque_count(im)
    px = im.load()
    m = mask.load()
    outside = 0
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 8 and m[x, y] == 0:
                outside += 1
    out = clip_alpha_with_mask(im, mask)
    after = opaque_count(out)
    outside_frac = (outside / before) if before else 0.0
    return out, {
        "opaque_before": before,
        "opaque_after": after,
        "outside_before": outside,
        "outside_frac": outside_frac,
        "role": pz_iso.cell_role(gx, gy, fz),
    }


def load_render():
    """Full-render RGBA, owner ids per pixel, and the layout origin."""
    render_dir = os.path.join(SRC_DIR, "_render")
    full = np.array(Image.open(os.path.join(render_dir, "full.png")).convert("RGBA"))
    own = np.load(os.path.join(render_dir, "full_own.npy"))
    with open(os.path.join(render_dir, "layout.json"), encoding="utf-8") as handle:
        layout = json.load(handle)
    owner_is_floor = np.array([row[3] == "floor" for row in layout["owners"]] + [False])
    is_floor = np.zeros(own.shape, dtype=bool)
    valid = own >= 0
    is_floor[valid] = owner_is_floor[own[valid]]
    return full, is_floor, layout["x0"], layout["y0"]


def floor_sprite(gx: int, gy: int, render):
    """Walkway tile: every deck-top pixel inside the cell's diamond, one pixel grown.

    The clipped sprite left joints between neighbouring tiles. Taking the
    full-diamond footprint from the full render makes each tile cover its
    square, and neighbours overlap with identical colours.
    """
    full, is_floor, x0, y0 = render
    h, w = full.shape[:2]
    left, top = pz_iso.sprite_rect(gx, gy, 3, x0, y0)
    tw, th = pz_iso.TILE_W, pz_iso.TILE_H
    corners = [(gx, gy), (gx + 1, gy), (gx + 1, gy + 1), (gx, gy + 1)]
    pts = [pz_iso.world_to_canvas(x, y, pz_iso.DECK_SURFACE_Z, x0, y0) for x, y in corners]
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    mask = mask.filter(ImageFilter.MaxFilter(3))
    m = np.array(mask.crop((left, top, left + tw, top + th))) > 0
    f = is_floor[top : top + th, left : left + tw]
    a = full[top : top + th, left : left + tw]
    keep = m & f & (a[..., 3] > 0)
    out = np.zeros((th, tw, 4), dtype=np.uint8)
    out[keep] = a[keep]
    ys, xs = np.nonzero(keep)
    if len(xs) == 0:
        raise RuntimeError("walkway cell %d,%d has no deck-top pixels" % (gx, gy))
    bx0, by0 = int(xs.min()), int(ys.min())
    bx1, by1 = int(xs.max()) + 1, int(ys.max()) + 1
    # Trim to the walking surface: the engine draws the trimmed texture, not the 128x256 frame.
    im = Image.fromarray(out[by0:by1, bx0:bx1], "RGBA")
    count = int(np.count_nonzero(keep))
    diamond_top = min(y for _x, y in pts) - top
    return im, {
        "opaque_before": count,
        "opaque_after": count,
        "outside_frac": 0.0,
        "role": pz_iso.cell_role(gx, gy, 3),
        "trim": (bx0, by0, bx1 - bx0, by1 - by0),
        "diamond_top": diamond_top,
    }


def grate_floor_sprite(walk: Image.Image, metrics):
    """Interior walkway: blue industry_01_37 grate on the baked walk footprint.

    Bars come from the same full-frame grate stamp on every cell so neighbours
    meet. Opaque underlay fills grate holes only on the walk. The stamp is then
    masked to the walk (grown one pixel) so mouth-ring cells do not paint over
    the bin opening.
    """
    bx0, by0, walk_w, walk_h = metrics["trim"]
    walk_arr = np.array(walk.convert("RGBA"))
    walk_opaque = walk_arr[..., 3] > 0
    if np.any(walk_opaque):
        under = walk_arr[walk_opaque][:, :3].mean(axis=0).astype(np.uint8)
    else:
        under = np.array([26, 45, 68], dtype=np.uint8)

    grate = np.array(Image.open(GRATE_PATH).convert("RGBA"))
    bh = pz_iso.TILE_H - GRATE_TOP
    bw = pz_iso.TILE_W
    diamond = grate[GRATE_TOP : GRATE_TOP + bh, 0:bw].copy()
    hull = Image.new("L", (bw, bh), 0)
    ImageDraw.Draw(hull).polygon(
        [(64, 0), (bw, bh // 2), (64, bh), (0, bh // 2)],
        fill=255,
    )
    hull = hull.filter(ImageFilter.MaxFilter(3))
    in_diamond = np.array(hull) > 0
    holes = in_diamond & (diamond[..., 3] < 8)
    diamond[holes, 0:3] = under
    diamond[holes, 3] = 255

    frame = np.zeros((pz_iso.TILE_H, pz_iso.TILE_W, 4), dtype=np.uint8)
    frame[GRATE_TOP : GRATE_TOP + bh, 0:bw] = diamond

    walk_mask = Image.new("L", (pz_iso.TILE_W, pz_iso.TILE_H), 0)
    walk_mask.paste(
        Image.fromarray((walk_opaque.astype(np.uint8) * 255), "L"),
        (bx0, by0),
    )
    walk_mask = walk_mask.filter(ImageFilter.MaxFilter(3))
    keep = np.array(walk_mask) > 0
    frame[~keep, 3] = 0

    ys, xs = np.nonzero(frame[..., 3] > 0)
    if len(xs) == 0:
        raise RuntimeError("grate walkway has no opaque pixels")
    tx0, ty0 = int(xs.min()), int(ys.min())
    tx1, ty1 = int(xs.max()) + 1, int(ys.max()) + 1
    clipped = frame[ty0:ty1, tx0:tx1]
    metrics["trim"] = (tx0, ty0, tx1 - tx0, ty1 - ty0)
    metrics["opaque_after"] = int(np.count_nonzero(clipped[..., 3] > 0))
    metrics["diamond_top"] = float(GRATE_TOP)
    return Image.fromarray(clipped, "RGBA"), metrics


def pad_png(im: Image.Image) -> Image.Image:
    if im.size == (pz_iso.TILE_W, pz_iso.TILE_H):
        return im
    if im.size == (pz_iso.TILE_W, pz_iso.TILE_W):
        canvas = Image.new("RGBA", (pz_iso.TILE_W, pz_iso.TILE_H), (0, 0, 0, 0))
        canvas.paste(im, (0, pz_iso.TILE_H - pz_iso.TILE_W), im)
        return canvas
    return im.resize((pz_iso.TILE_W, pz_iso.TILE_H), Image.Resampling.NEAREST)


def _grime_names():
    if not os.path.isdir(VANILLA_GRIME_DIR):
        return []
    names = [
        n
        for n in os.listdir(VANILLA_GRIME_DIR)
        if n.startswith("overlay_grime_wall_01_") and n.endswith(".png")
    ]
    names.sort(key=lambda s: int(s.rsplit("_", 1)[1].split(".", 1)[0]))
    return names


def _is_concrete_mask(hop: np.ndarray, opaque: np.ndarray) -> np.ndarray:
    """Low-chroma mid/high-luma greys = concrete pads (vs blue metal)."""
    rgb = hop[..., :3] / 255.0
    chroma = rgb.max(axis=2) - rgb.min(axis=2)
    lum = rgb.mean(axis=2)
    return opaque & (chroma < 0.14) & (lum > 0.28) & (lum < 0.88)


def apply_leg_grime(im: Image.Image, gx: int, gy: int) -> Image.Image:
    """Multiply vanilla wall grime onto every opaque fz=0 pixel.

    Metal: bottom-weighted wash + vertical rain-runoff streaks from tiled
    overlay_grime. Concrete: soft even multiply stain (gentle noise only) so
    pads stay readable. Overlay alpha is a strength map; sprite alpha stays hard.
    """
    names = _grime_names()
    if not names:
        print("WARN no vanilla grime in", VANILLA_GRIME_DIR)
        return im
    name = names[(gx + gy) % len(names)]
    grime = np.array(
        Image.open(os.path.join(VANILLA_GRIME_DIR, name)).convert("RGBA"),
        dtype=np.float32,
    )
    hop = np.array(im, dtype=np.float32)
    h, w = hop.shape[:2]
    if grime.shape[0] != h or grime.shape[1] != w:
        grime = np.array(
            Image.fromarray(grime.astype(np.uint8), "RGBA").resize(
                (w, h), Image.Resampling.BILINEAR
            ),
            dtype=np.float32,
        )

    opaque = hop[..., 3] > 8
    if not np.any(opaque):
        return im

    concrete = _is_concrete_mask(hop, opaque)
    metal = opaque & ~concrete

    g_a = grime[..., 3] / 255.0
    g_rgb = grime[..., :3] / 255.0
    gmask = g_a > (8.0 / 255.0)
    if np.any(gmask):
        mean_rgb = g_rgb[gmask].mean(axis=0)
        mean_a = float(g_a[gmask].mean())
    else:
        mean_rgb = np.array([25.0, 25.0, 25.0], dtype=np.float32) / 255.0
        mean_a = 0.4

    ys, xs = np.nonzero(opaque)
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    yy = np.arange(h, dtype=np.float32)[:, None]
    bottom = np.clip((yy - y0) / max(y1 - y0 - 1, 1), 0.0, 1.0) ** 0.85
    bottom_map = np.broadcast_to(bottom, (h, w)).copy()

    out = hop.copy()

    # --- Concrete: soft even stain (no stretched wall blotches) ---
    if np.any(concrete):
        # Fine stable noise from coordinates + cell seed (not wall UV).
        seed = ((gx * 17 + gy * 31) & 0xFFFF) / 65535.0
        yy_i = np.arange(h, dtype=np.float32)[:, None]
        xx_i = np.arange(w, dtype=np.float32)[None, :]
        noise = (
            np.sin((xx_i * 0.37 + yy_i * 0.21 + seed * 40.0)) * 0.5
            + np.sin((xx_i * 0.11 - yy_i * 0.29 + seed * 17.0)) * 0.5
        )
        noise = (noise + 1.0) * 0.5  # 0..1
        c_str = GRIME_CONCRETE_WASH * (0.55 + 0.45 * bottom_map)
        c_str = c_str * (1.0 - GRIME_CONCRETE_NOISE + GRIME_CONCRETE_NOISE * noise)
        c_str = np.clip(c_str, 0.0, 1.0)
        c_str = np.where(concrete, c_str, 0.0)
        # Slightly warm mud grey for concrete (still dark).
        c_rgb = mean_rgb * np.array([1.05, 0.95, 0.88], dtype=np.float32)
        c_rgb = np.clip(c_rgb, 0.0, 1.0)
        cs = c_str[..., None]
        out[..., :3] = np.where(
            concrete[..., None],
            hop[..., :3] * (1.0 - cs + cs * c_rgb.reshape(1, 1, 3)),
            out[..., :3],
        )

    # --- Metal: tiled wash + streak from vanilla grime ---
    if np.any(metal) and np.any(gmask):
        gys, gxs = np.nonzero(gmask)
        gy0, gy1 = int(gys.min()), int(gys.max()) + 1
        gx0, gx1 = int(gxs.min()), int(gxs.max()) + 1
        tile_a = g_a[gy0:gy1, gx0:gx1]
        tile_rgb = g_rgb[gy0:gy1, gx0:gx1]
        bw, bh = max(x1 - x0, 1), max(y1 - y0, 1)
        wash_a = np.array(
            Image.fromarray((np.clip(tile_a, 0, 1) * 255).astype(np.uint8), "L").resize(
                (bw, bh), Image.Resampling.BILINEAR
            ),
            dtype=np.float32,
        ) / 255.0
        wash_rgb = (
            np.array(
                Image.fromarray(
                    (np.clip(tile_rgb, 0, 1) * 255).astype(np.uint8), "RGB"
                ).resize((bw, bh), Image.Resampling.BILINEAR),
                dtype=np.float32,
            )
            / 255.0
        )
        wash_a = np.maximum(wash_a, mean_a * 0.45)

        wash_str = np.zeros((h, w), dtype=np.float32)
        wash_rgb_full = np.zeros((h, w, 3), dtype=np.float32)
        wash_str[y0:y1, x0:x1] = wash_a
        wash_rgb_full[y0:y1, x0:x1] = wash_rgb
        wash_str = wash_str * (0.40 + 0.60 * bottom_map)
        wash_str = np.clip(wash_str * GRIME_WASH, 0.0, 1.0)
        wash_str = np.where(metal, wash_str, 0.0)

        s = wash_str[..., None]
        out[..., :3] = np.where(
            metal[..., None],
            out[..., :3] * (1.0 - s + s * wash_rgb_full),
            out[..., :3],
        )

        streak_str = np.clip(
            wash_str / max(GRIME_WASH, 0.01) * GRIME_STREAK * (0.35 + 0.65 * bottom_map),
            0.0,
            1.0,
        )
        drip = np.zeros((h, w), dtype=np.float32)
        drip[y0:y1, x0:x1] = np.clip((wash_a - wash_a.mean()) * 2.0 + 0.5, 0.0, 1.0)
        streak_str = np.clip(streak_str * (0.55 + 0.7 * drip), 0.0, 1.0)
        streak_str = np.where(metal, streak_str, 0.0)
        ss = streak_str[..., None]
        out[..., :3] = np.where(
            metal[..., None],
            out[..., :3] * (1.0 - ss + ss * wash_rgb_full),
            out[..., :3],
        )
    elif np.any(metal):
        # Fallback: even darken metal if no grime frames.
        m_str = np.where(metal, GRIME_WASH * 0.45 * (0.4 + 0.6 * bottom_map), 0.0)
        ms = m_str[..., None]
        out[..., :3] = out[..., :3] * (1.0 - ms + ms * mean_rgb.reshape(1, 1, 3))

    out[..., 3] = hop[..., 3]
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def write_tomls(n: int):
    for i in range(n):
        stem = "hopper_2d_%d" % i
        path = os.path.join(OUT_SRC, stem + ".toml")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("[%s]\n" % stem)
            handle.write("pos = [0, 0]\n")
            handle.write("size = [%d, %d]\n" % (pz_iso.TILE_W, pz_iso.TILE_H))


def write_trimmed_tomls(trims):
    """Walkway sprites: texture is the deck-top bounding box, placed at its offset in the 128x256 frame."""
    for i, (bx0, by0, bw, bh) in trims.items():
        stem = "hopper_2d_%d" % i
        with open(os.path.join(OUT_SRC, stem + ".toml"), "w", encoding="utf-8") as handle:
            handle.write("[%s]\n" % stem)
            handle.write("pos = [0, 0]\n")
            handle.write("size = [%d, %d]\n" % (bw, bh))
            handle.write("frame_offset = [%d, %d]\n" % (bx0, by0))
            handle.write("frame_size = [%d, %d]\n" % (pz_iso.TILE_W, pz_iso.TILE_H))


def write_clear_tile(index: int):
    """1x1 transparent tile at the cell's south tip (blocker and hopper control anchor)."""
    stem = "hopper_2d_%d" % index
    Image.new("RGBA", (1, 1), (0, 0, 0, 0)).save(os.path.join(OUT_SRC, stem + ".png"))
    with open(os.path.join(OUT_SRC, stem + ".toml"), "w", encoding="utf-8") as handle:
        handle.write("[%s]\n" % stem)
        handle.write("pos = [0, 0]\n")
        handle.write("size = [1, 1]\n")
        handle.write("frame_offset = [%d, %d]\n" % BLOCKER_FRAME_OFFSET)
        handle.write("frame_size = [%d, %d]\n" % (pz_iso.TILE_W, pz_iso.TILE_H))


def write_tiles(cells):
    def s(text):
        return text.encode("utf-8") + b"\n"

    body = bytearray()
    body += s("hopper_2d")
    body += s("hopper_2d")
    n = len(cells) + 2
    cols = 8
    rows = max(1, (n + cols - 1) // cols)
    body += struct.pack("<iiii", cols, rows, 1, n)
    tile_props = []
    for i, (_gx, _gy, fz, kind, _name) in enumerate(cells):
        # Per-square lighting on the elevated empty-air levels renders black;
        # ForceAmbient tints with the outdoor ambient instead.
        props = [("ForceAmbient", "")]
        if i == 0:
            props.append(("CustomName", "Loading Hopper"))
        if kind == "floor" and DECK_AS_FLOOR and FLOOR_SOLIDFLOOR:
            props.append(("solidfloor", ""))
        if kind == "floor" and DECK_AS_FLOOR and is_edge_cell(_gx, _gy):
            props.append(("transparentFloor", ""))
        if kind == "object" and fz >= 1:
            props.append(("NeverCutaway", ""))
        tile_props.append(props)
    tile_props.append([("solid", "")])  # blocker, index len(cells)
    tile_props.append([])  # hopper control anchor, index len(cells) + 1
    for props in tile_props:
        body += struct.pack("<i", len(props))
        for key, val in props:
            body += s(key)
            body += s(val)
    out = bytearray()
    out += b"tdef"
    out += struct.pack("<ii", 1, 1)
    out += body
    with open(TILES_PATH, "wb") as handle:
        handle.write(out)


def write_lua(cells):
    lines = [
        "-- Generated by pack_2d_tiles.py — do not edit by hand.",
        "DumpTruck = DumpTruck or {}",
        "DumpTruck.Hopper2dDeckAsFloor = %s" % ("true" if DECK_AS_FLOOR else "false"),
        # Invisible tile on the bay-centre square: the hopper controls find the stock here.
        'DumpTruck.Hopper2dAnchorSprite = "hopper_2d_%d"' % (len(cells) + 1),
        "DumpTruck.Hopper2dCells = {",
    ]
    for i, (gx, gy, fz, kind, _name) in enumerate(cells):
        edge = ", edge = true" if kind == "floor" and is_edge_cell(gx, gy) else ""
        lines.append(
            '    { gx = %d, gy = %d, fz = %d, kind = "%s", sprite = "hopper_2d_%d"%s },'
            % (gx, gy, fz, kind, i, edge)
        )
    blocker = len(cells)
    for gx, gy in sorted(pz_iso.SOLID_XY):
        lines.append(
            '    { gx = %d, gy = %d, fz = 0, kind = "blocker", sprite = "hopper_2d_%d" },'
            % (gx, gy, blocker)
        )
    lines.append("}")
    lines.append("")
    with open(LUA_PATH, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def merge_pack():
    if not os.path.isfile(PZ_PACK):
        raise RuntimeError("pz-pack-tool missing at %s — cargo build --release" % PZ_PACK)
    work = os.path.join(HERE, "_pack_work")
    if os.path.isdir(work):
        for root, _dirs, files in os.walk(work, topdown=False):
            for name in files:
                os.remove(os.path.join(root, name))
            for name in _dirs:
                os.rmdir(os.path.join(root, name))
        os.rmdir(work)
    os.makedirs(work, exist_ok=True)
    if os.path.isfile(PACK_PATH):
        subprocess.check_call([PZ_PACK, "unpack", PACK_PATH, work])
    for name in os.listdir(OUT_SRC):
        src = os.path.join(OUT_SRC, name)
        dst = os.path.join(work, name)
        with open(src, "rb") as rh, open(dst, "wb") as wh:
            wh.write(rh.read())
    tmp_pack = PACK_PATH + ".tmp"
    subprocess.check_call([PZ_PACK, "pack", work, tmp_pack])
    os.replace(tmp_pack, PACK_PATH)
    print("wrote", PACK_PATH)


def ensure_mod_info_tiledef():
    path = os.path.join(REPO, "mod.info")
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    if "tiledef=hopper_2d" not in text:
        if not text.endswith("\n"):
            text += "\n"
        text += "tiledef=hopper_2d 4732\n"
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        print("added tiledef=hopper_2d 4732 to mod.info")


def main():
    if not os.path.isfile(MANIFEST):
        print("missing", MANIFEST, file=sys.stderr)
        sys.exit(1)
    cells = read_manifest()
    if not cells:
        print("empty manifest", file=sys.stderr)
        sys.exit(1)
    os.makedirs(OUT_SRC, exist_ok=True)
    for name in os.listdir(OUT_SRC):
        os.remove(os.path.join(OUT_SRC, name))

    fail = 0
    render = load_render()
    trims = {}
    for i, (gx, gy, fz, kind, name) in enumerate(cells):
        src = os.path.join(SRC_DIR, name)
        im = Image.open(src).convert("RGBA")
        im = pad_png(im)
        if kind == "floor":
            clipped, metrics = floor_sprite(gx, gy, render)
            if not is_edge_cell(gx, gy):
                clipped, metrics = grate_floor_sprite(clipped, metrics)
            trims[i] = metrics["trim"]
        else:
            clipped, metrics = apply_ownership_clip(im, gx, gy, fz)
            clipped = harden_alpha(clipped)
            if kind == "object" and fz == 0:
                clipped = apply_leg_grime(clipped, gx, gy)
        role = metrics["role"]
        if metrics["outside_frac"] > 0.15:
            print(
                "WARN outside_hull",
                name,
                "frac=%.3f" % metrics["outside_frac"],
                "out",
                metrics["outside_before"],
            )
        if not pz_iso.role_opaque_ok(role, metrics["opaque_after"]):
            print(
                "WARN role_budget",
                name,
                role,
                "opaque",
                metrics["opaque_after"],
            )
            fail += 1
        dst = os.path.join(OUT_SRC, "hopper_2d_%d.png" % i)
        clipped.save(dst)
        print(
            "clip",
            i,
            name,
            kind,
            role,
            "opq",
            metrics["opaque_before"],
            "->",
            metrics["opaque_after"],
            "out_frac",
            "%.3f" % metrics["outside_frac"],
        )

    write_tomls(len(cells))
    write_trimmed_tomls(trims)
    write_clear_tile(len(cells))
    write_clear_tile(len(cells) + 1)
    write_tiles(cells)
    write_lua(cells)
    ensure_mod_info_tiledef()
    merge_pack()
    print(
        "pack_2d_tiles done",
        len(cells),
        "sprites",
        "deck_as_floor",
        DECK_AS_FLOOR,
        "role_budget_warns",
        fail,
    )


if __name__ == "__main__":
    main()
