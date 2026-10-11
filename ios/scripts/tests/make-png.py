#!/usr/bin/env python3
import struct
import sys
import zlib

USAGE = (
    "Usage: make-png.py <file> <width> <height> <opaque|alpha|clear|trns>\n"
    "       make-png.py <file> <width> <height> frame <side> <top> [<outer radius> <inner radius>]: an opaque frame"
    " around a clear middle, as a phone bezel, with round corners when the radii are given"
)

KINDS = {
    "opaque": (2, b"\x00\x00\x00", b""),
    "alpha": (6, b"\x00\x00\x00\xff", b""),
    "clear": (6, b"\x00\x00\x00\x00", b""),
    "trns": (2, b"\x00\x00\x00", b"\x00\x00\x00\x00\x00\x00"),
}


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def inside(x, y, left, top, right, bottom, radius):
    """Whether the centre of pixel (x, y) is in the rounded rect [left, right) x [top, bottom)."""
    px, py = x + 0.5, y + 0.5
    if not (left <= px < right and top <= py < bottom):
        return False
    cx = min(max(px, left + radius), right - radius)
    cy = min(max(py, top + radius), bottom - radius)
    return (px - cx) ** 2 + (py - cy) ** 2 <= radius ** 2


def frame_rows(width, height, side, top, outer=0, inner=0):
    opaque, clear = b"\x00\x00\x00\xff", b"\x00\x00\x00\x00"

    def row(y):
        return b"\x00" + b"".join(
            opaque if inside(x, y, 0, 0, width, height, outer)
            and not inside(x, y, side, top, width - side, height - top, inner) else clear
            for x in range(width)
        )

    corner_rows = max(outer, top + inner)
    middle = row(corner_rows)
    rows = [row(y) if y < corner_rows or y >= height - corner_rows else middle for y in range(height)]
    return b"".join(rows)


def main(arguments):
    if len(arguments) in (6, 8) and arguments[3] == "frame":
        path, width, height = arguments[0], int(arguments[1]), int(arguments[2])
        color_type, transparent = 6, b""
        rows = frame_rows(width, height, *(int(a) for a in arguments[4:]))
    elif len(arguments) == 4 and arguments[3] in KINDS:
        path, width, height, kind = arguments[0], int(arguments[1]), int(arguments[2]), arguments[3]
        color_type, pixel, transparent = KINDS[kind]
        rows = (b"\x00" + pixel * width) * height
    else:
        sys.exit(USAGE)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
    if transparent:
        png += chunk(b"tRNS", transparent)
    png += chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
    with open(path, "wb") as file:
        file.write(png)


if __name__ == "__main__":
    main(sys.argv[1:])
