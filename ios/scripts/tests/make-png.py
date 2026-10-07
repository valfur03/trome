#!/usr/bin/env python3
import struct
import sys
import zlib

USAGE = "Usage: make-png.py <file> <width> <height> <opaque|alpha|clear|trns>"

KINDS = {
    "opaque": (2, b"\x00\x00\x00", b""),
    "alpha": (6, b"\x00\x00\x00\xff", b""),
    "clear": (6, b"\x00\x00\x00\x00", b""),
    "trns": (2, b"\x00\x00\x00", b"\x00\x00\x00\x00\x00\x00"),
}


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def main(arguments):
    if len(arguments) != 4 or arguments[3] not in KINDS:
        sys.exit(USAGE)
    path, width, height, kind = arguments[0], int(arguments[1]), int(arguments[2]), arguments[3]
    color_type, pixel, transparent = KINDS[kind]
    rows = (b"\x00" + pixel * width) * height
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
    if transparent:
        png += chunk(b"tRNS", transparent)
    png += chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
    with open(path, "wb") as file:
        file.write(png)


if __name__ == "__main__":
    main(sys.argv[1:])
