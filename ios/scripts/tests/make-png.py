#!/usr/bin/env python3
import struct
import sys
import zlib

USAGE = (
    "Usage: make-png.py <file> <width> <height> <opaque|alpha|clear|trns>\n"
    "       make-png.py <file> <width> <height> frame <side> <top>: an opaque frame around a clear middle,"
    " as a phone bezel"
)

KINDS = {
    "opaque": (2, b"\x00\x00\x00", b""),
    "alpha": (6, b"\x00\x00\x00\xff", b""),
    "clear": (6, b"\x00\x00\x00\x00", b""),
    "trns": (2, b"\x00\x00\x00", b"\x00\x00\x00\x00\x00\x00"),
}


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def frame_rows(width, height, side, top):
    opaque, clear = b"\x00\x00\x00\xff", b"\x00\x00\x00\x00"
    full = b"\x00" + opaque * width
    middle = b"\x00" + opaque * side + clear * (width - 2 * side) + opaque * side
    return full * top + middle * (height - 2 * top) + full * top


def main(arguments):
    if len(arguments) == 6 and arguments[3] == "frame":
        path, width, height = arguments[0], int(arguments[1]), int(arguments[2])
        color_type, transparent = 6, b""
        rows = frame_rows(width, height, int(arguments[4]), int(arguments[5]))
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
