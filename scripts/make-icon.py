#!/usr/bin/env python3
"""Draws the Vehicle Maintenance Log app icon: a stitched cream logbook with a brass wrench."""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 1024
K = 4
W = S * K


def lerp(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def rounded_rect_points(x0, y0, x1, y1, r, step):
    """Points every `step` pixels along a rounded rectangle's outline."""
    pts = []
    segs = [
        ("line", (x0 + r, y0), (x1 - r, y0)),
        ("arc", (x1 - r, y0 + r), -90, 0),
        ("line", (x1, y0 + r), (x1, y1 - r)),
        ("arc", (x1 - r, y1 - r), 0, 90),
        ("line", (x1 - r, y1), (x0 + r, y1)),
        ("arc", (x0 + r, y1 - r), 90, 180),
        ("line", (x0, y1 - r), (x0, y0 + r)),
        ("arc", (x0 + r, y0 + r), 180, 270),
    ]
    for seg in segs:
        if seg[0] == "line":
            (ax, ay), (bx, by) = seg[1], seg[2]
            n = max(1, int(math.hypot(bx - ax, by - ay) / step))
            pts += [(ax + (bx - ax) * i / n, ay + (by - ay) * i / n) for i in range(n)]
        else:
            (cx, cy), a0, a1 = seg[1], seg[2], seg[3]
            n = max(1, int(math.radians(a1 - a0) * r / step))
            for i in range(n):
                a = math.radians(a0 + (a1 - a0) * i / n)
                pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def stitch(draw, box, r, color):
    dash, gap, width = int(0.020 * W), int(0.014 * W), int(0.0065 * W)
    pts = rounded_rect_points(*box, r, 2)
    run, drawing, segment = 0.0, True, []
    for i in range(1, len(pts)):
        run += math.dist(pts[i - 1], pts[i])
        if drawing:
            segment.append(pts[i])
        if run >= (dash if drawing else gap):
            if drawing and len(segment) > 1:
                draw.line(segment, fill=color, width=width, joint="curve")
            drawing, run, segment = not drawing, 0.0, [pts[i]]


def wrench(cx, cy, length, color):
    """A combination wrench standing upright, open jaw at the top."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    clear = (0, 0, 0, 0)
    top, bottom = cy - length / 2, cy + length / 2
    hw = 0.030 * W
    head = 0.078 * W
    tail = 0.050 * W
    d.rounded_rectangle([cx - hw, top + head, cx + hw, bottom - tail], radius=hw, fill=color)
    d.ellipse([cx - head, top, cx + head, top + 2 * head], fill=color)
    jaw = 0.032 * W
    d.rectangle([cx - jaw, top - 2, cx + jaw, top + head], fill=clear)
    d.ellipse([cx - jaw, top + head - jaw, cx + jaw, top + head + jaw], fill=clear)
    d.ellipse([cx - tail, bottom - 2 * tail, cx + tail, bottom], fill=color)
    hole = 0.022 * W
    d.ellipse([cx - hole, bottom - tail - hole, cx + hole, bottom - tail + hole], fill=clear)
    return layer


def main(path):
    bg = Image.new("RGBA", (W, W))
    d = ImageDraw.Draw(bg)
    top, bot = (0x2C, 0x66, 0x4D), (0x14, 0x36, 0x28)
    for y in range(W):
        d.line([(0, y), (W, y)], fill=lerp(top, bot, y / W) + (255,))

    cream = (0xF3, 0xEA, 0xD6, 255)
    spine = (0xDD, 0xCF, 0xB2, 255)
    brass = (0xC4, 0x92, 0x38, 255)
    bright = (0xE0, 0xB0, 0x52, 255)

    cx, cy = W // 2, int(0.51 * W)
    bw, bh = int(0.50 * W), int(0.64 * W)
    x0, y0 = cx - bw // 2, cy - bh // 2
    x1, y1 = x0 + bw, y0 + bh
    r = int(0.06 * W)
    sw = int(0.075 * W)

    book = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    bd = ImageDraw.Draw(book)
    bd.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=cream)
    bd.rounded_rectangle([x0, y0, x0 + sw + r, y1], radius=r, fill=spine)
    bd.rectangle([x0 + sw, y0, x0 + sw + r, y1], fill=cream)
    bd.line([(x0 + sw, y0 + int(0.01 * W)), (x0 + sw, y1 - int(0.01 * W))], fill=(0xC9, 0xB9, 0x98, 255), width=int(0.006 * W))
    inset = int(0.032 * W)
    stitch(bd, (x0 + sw + inset, y0 + inset, x1 - inset, y1 - inset), r - inset // 2, brass)

    pcx = (x0 + sw + x1) // 2
    tool = wrench(pcx, cy, 0.44 * W, bright).rotate(-38, resample=Image.BICUBIC, center=(pcx, cy))
    book = Image.alpha_composite(book, tool)
    book = book.rotate(6, resample=Image.BICUBIC, center=(cx, cy))

    alpha = book.split()[3]
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 110), (int(0.01 * W), int(0.025 * W)), mask=alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(0.022 * W)))

    out = Image.alpha_composite(bg, shadow)
    out = Image.alpha_composite(out, book)
    out.resize((S, S), Image.LANCZOS).convert("RGB").save(path)


if __name__ == "__main__":
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else "Keyring/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
