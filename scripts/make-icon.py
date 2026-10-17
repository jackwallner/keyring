#!/usr/bin/env python3
"""Draws the Keyring app icon: a cream leather key tag on a brass ring."""
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
    segs = []
    # straight edges and quarter arcs, clockwise from top-left after the corner
    segs.append(("line", (x0 + r, y0), (x1 - r, y0)))
    segs.append(("arc", (x1 - r, y0 + r), -90, 0))
    segs.append(("line", (x1, y0 + r), (x1, y1 - r)))
    segs.append(("arc", (x1 - r, y1 - r), 0, 90))
    segs.append(("line", (x1 - r, y1), (x0 + r, y1)))
    segs.append(("arc", (x0 + r, y1 - r), 90, 180))
    segs.append(("line", (x0, y1 - r), (x0, y0 + r)))
    segs.append(("arc", (x0 + r, y0 + r), 180, 270))
    for seg in segs:
        if seg[0] == "line":
            (ax, ay), (bx, by) = seg[1], seg[2]
            length = math.hypot(bx - ax, by - ay)
            n = max(1, int(length / step))
            for i in range(n):
                t = i / n
                pts.append((ax + (bx - ax) * t, ay + (by - ay) * t))
        else:
            (cx, cy), a0, a1 = seg[1], seg[2], seg[3]
            length = math.radians(a1 - a0) * r
            n = max(1, int(length / step))
            for i in range(n):
                a = math.radians(a0 + (a1 - a0) * i / n)
                pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def main(path):
    bg = Image.new("RGBA", (W, W))
    d = ImageDraw.Draw(bg)
    top, bot = (0x2C, 0x66, 0x4D), (0x14, 0x36, 0x28)
    for y in range(W):
        d.line([(0, y), (W, y)], fill=lerp(top, bot, y / W) + (255,))

    cx = W // 2
    tw, th = int(0.38 * W), int(0.56 * W)
    tx0, ty0 = cx - tw // 2, int(0.31 * W)
    r, ch = int(0.075 * W), int(0.12 * W)
    cream = (0xF3, 0xEA, 0xD6, 255)
    brass = (0xC4, 0x92, 0x38, 255)

    tag = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    td = ImageDraw.Draw(tag)
    td.rounded_rectangle([tx0, ty0 + ch, tx0 + tw, ty0 + th], radius=r, fill=cream)
    flat = int(tw * 0.24)
    td.polygon([(tx0, ty0 + ch + r), (tx0 + int(tw * 0.05), ty0 + ch - int(0.01 * W)), (cx - flat, ty0 + int(0.015 * W)),
                (cx + flat, ty0 + int(0.015 * W)), (tx0 + tw - int(tw * 0.05), ty0 + ch - int(0.01 * W)), (tx0 + tw, ty0 + ch + r)], fill=cream)
    td.rounded_rectangle([cx - flat - int(0.02 * W), ty0, cx + flat + int(0.02 * W), ty0 + int(0.07 * W)], radius=int(0.03 * W), fill=cream)

    inset = int(0.032 * W)
    dash, gap = int(0.020 * W), int(0.014 * W)
    pts = rounded_rect_points(tx0 + inset, ty0 + ch + inset, tx0 + tw - inset, ty0 + th - inset, r - inset // 2, 2)
    run, drawing, segment = 0.0, True, []
    width = int(0.0065 * W)
    for i in range(1, len(pts)):
        run += math.dist(pts[i - 1], pts[i])
        if drawing:
            segment.append(pts[i])
        limit = dash if drawing else gap
        if run >= limit:
            if drawing and len(segment) > 1:
                td.line(segment, fill=brass, width=width, joint="curve")
            drawing, run, segment = not drawing, 0.0, [pts[i]]

    hr, hy = int(0.04 * W), ty0 + int(0.075 * W)
    td.ellipse([cx - hr, hy - hr, cx + hr, hy + hr], fill=(0, 0, 0, 0))
    tag = tag.rotate(-10, resample=Image.BICUBIC, center=(cx, hy))

    R, rw = int(0.15 * W), int(0.028 * W)
    rcx, rcy = cx, hy - R + rw // 2
    ring = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([rcx - R, rcy - R, rcx + R, rcy + R], outline=(0xE0, 0xB0, 0x52, 255), width=rw)

    alpha = tag.split()[3]
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 110), (int(0.01 * W), int(0.025 * W)), mask=alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(0.022 * W)))

    out = Image.alpha_composite(bg, ring)
    out = Image.alpha_composite(out, shadow)
    out = Image.alpha_composite(out, tag)
    front = Image.new("L", (W, W), 0)
    ImageDraw.Draw(front).pieslice([rcx - R - rw, rcy - R - rw, rcx + R + rw, rcy + R + rw], start=95, end=128, fill=255)
    out = Image.alpha_composite(out, Image.composite(ring, Image.new("RGBA", (W, W), (0, 0, 0, 0)), front))
    out.resize((S, S), Image.LANCZOS).convert("RGB").save(path)


if __name__ == "__main__":
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else "Keyring/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
