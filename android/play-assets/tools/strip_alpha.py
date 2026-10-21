#!/usr/bin/env python3
"""Rewrites 8-bit RGBA PNGs as 24-bit RGB PNGs (Play rejects alpha). Usage: strip_alpha.py file.png..."""
import struct
import sys
import zlib


def chunks(data):
    i = 8
    while i < len(data):
        n, t = struct.unpack(">I4s", data[i:i + 8])
        yield t, data[i + 8:i + 8 + n]
        i += 12 + n


def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))


def unfilter(raw, w, h, bpp):
    stride, out, prev = w * bpp, [], bytearray(w * bpp)
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b, c = prev[x], (prev[x - bpp] if x >= bpp else 0)
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out.append(line)
        prev = line
    return out


def strip(path):
    data = open(path, "rb").read()
    cs = dict((t, d) for t, d in chunks(data) if t in (b"IHDR",))
    w, h, depth, ctype = struct.unpack(">IIBB", cs[b"IHDR"][:10])
    if ctype != 6 or depth != 8:
        return
    raw = zlib.decompress(b"".join(d for t, d in chunks(data) if t == b"IDAT"))
    rows = unfilter(raw, w, h, 4)
    rgb = b"".join(b"\0" + b"".join(bytes(r[i:i + 3]) for i in range(0, len(r), 4)) for r in rows)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rgb, 9)) + chunk(b"IEND", b""))


for p in sys.argv[1:]:
    strip(p)
