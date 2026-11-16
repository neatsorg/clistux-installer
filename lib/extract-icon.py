#!/usr/bin/env python3
# Windows の exe から、いちばん大きいアイコンを PNG として取り出す(アプリのメニューに出すため)。
# 使い方: extract-icon.py 入力.exe 出力.png
# アイコンは PNG か、32bit の BMP(DIB)で入っている。BMP は PNG に変換する(標準ライブラリだけで)。
import struct
import sys
import zlib

RT_ICON, RT_GROUP_ICON = 3, 14


def main(path, out):
    d = open(path, 'rb').read()
    pe = struct.unpack_from('<I', d, 0x3C)[0]
    nsec = struct.unpack_from('<H', d, pe + 6)[0]
    optsize = struct.unpack_from('<H', d, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from('<H', d, opt)[0]
    ddir = opt + (96 if magic == 0x10B else 112)
    rsrc_rva = struct.unpack_from('<I', d, ddir + 2 * 8)[0]
    sections = []
    for i in range(nsec):
        s = pe + 24 + optsize + 40 * i
        vsize, va, rawsize, raw = struct.unpack_from('<IIII', d, s + 8)
        sections.append((va, max(vsize, rawsize), raw))

    def off(rva):
        for va, size, raw in sections:
            if va <= rva < va + size:
                return rva - va + raw
        raise ValueError('rva')

    base = off(rsrc_rva)

    def entries(o):
        named, ids = struct.unpack_from('<HH', d, o + 12)
        for i in range(named + ids):
            name, target = struct.unpack_from('<II', d, o + 16 + 8 * i)
            yield name, target

    def leaf(target):
        # 最初の言語のデータ
        while target & 0x80000000:
            target = next(entries(base + (target & 0x7FFFFFFF)))[1]
        rva, size = struct.unpack_from('<II', d, base + target)
        o = off(rva)
        return d[o:o + size]

    types = dict(entries(base))
    icons = {name: t for name, t in entries(base + (types[RT_ICON] & 0x7FFFFFFF))}
    best = None
    for _, gt in entries(base + (types[RT_GROUP_ICON] & 0x7FFFFFFF)):
        g = leaf(gt)
        count = struct.unpack_from('<H', g, 4)[0]
        for i in range(count):
            w, h, _, _, _, bits, size, icon_id = struct.unpack_from('<BBBBHHIH', g, 6 + 14 * i)
            w = w or 256
            if icon_id in icons and (best is None or (w, bits) > best[0]):
                best = ((w, bits), icon_id)
    if not best:
        return 1
    data = leaf(icons[best[1]])
    if not data.startswith(b'\x89PNG'):
        data = dib_to_png(data)
        if data is None:
            return 1
    open(out, 'wb').write(data)
    return 0


def dib_to_png(dib):
    # 32bit の BGRA で、下の行から並ぶ。高さはマスクの分を含めて2倍で書かれている。
    hsize, w, h2, _, bits = struct.unpack_from('<IiiHH', dib, 0)
    if bits != 32:
        return None
    h = abs(h2) // 2
    pixels = dib[hsize:hsize + w * h * 4]
    rows = []
    for y in range(h):
        src = pixels[(h - 1 - y) * w * 4:(h - y) * w * 4]
        row = bytearray(src)
        row[0::4], row[2::4] = src[2::4], src[0::4]   # BGRA → RGBA
        rows.append(b'\0' + bytes(row))

    def chunk(tag, body):
        return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xFFFFFFFF)

    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b''))


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1], sys.argv[2]))
    except Exception:
        sys.exit(1)
