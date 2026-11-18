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
LUA_PATH = os.path.join(REPO, "media/lua/client/DumpTruck/LoadingHopper2dCells.lua")
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
    return im, {
        "opaque_before": count,
        "opaque_after": count,
        "outside_frac": 0.0,
        "role": pz_iso.cell_role(gx, gy, 3),
        "trim": (bx0, by0, bx1 - bx0, by1 - by0),
    }


def pad_png(im: Image.Image) -> Image.Image:
    if im.size == (pz_iso.TILE_W, pz_iso.TILE_H):
        return im
    if im.size == (pz_iso.TILE_W, pz_iso.TILE_W):
        canvas = Image.new("RGBA", (pz_iso.TILE_W, pz_iso.TILE_H), (0, 0, 0, 0))
        canvas.paste(im, (0, pz_iso.TILE_H - pz_iso.TILE_W), im)
        return canvas
    return im.resize((pz_iso.TILE_W, pz_iso.TILE_H), Image.Resampling.NEAREST)


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
            trims[i] = metrics["trim"]
        else:
            clipped, metrics = apply_ownership_clip(im, gx, gy, fz)
            clipped = harden_alpha(clipped)
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
