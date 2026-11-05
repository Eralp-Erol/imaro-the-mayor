#!/usr/bin/env python3
"""YER TUTUCU iOS ikonu üreteci (B-061). Gerçek ikon DEĞİLDİR.

Gerçek uygulama ikonu sahibin görsel kararıdır; bu betik yalnız Xcode/Godot export hattının ikon istemesi
yüzünden cihaza kurulumu engellemesin diye açıkça "YER TUTUCU, SAHİP İKONU BEKLİYOR" yazan tek bir 1024x1024
kare üretir (sarı/siyah şerit + yazı: kasıtlı olarak marka/sanat tercihi taşımaz, asla gerçek ikon sanılmaz).

Kullanım: tools/ios-placeholder-icon.py [çıktı.png]   (varsayılan: build/ios/placeholder-icon.png)
`tools/export.sh ios` bunu export öncesi kendisi çağırır; çıktı build/ altındadır (gitignored, repoya PNG girmez).
Alfa kanalı YOKTUR (App Store/Xcode ikonları şeffaf olamaz). Yalnız standart kütüphane; Python 3.
Gerçek ikon geldiğinde: export_presets.cfg [preset.2.options] `icons/icon_1024x1024` yolunu onunla değiştir.
"""
import os
import struct
import sys
import zlib

SIZE = 1024
YELLOW = (250, 204, 21)
BLACK = (24, 24, 24)
BAND = (24, 24, 24)
TEXT = (250, 204, 21)

# 5x7 bitmap yazı tipi, yalnız gereken harfler.
GLYPHS = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    " ": ["00000"] * 7,
}

# (metin, ölçek, üst y)
LINES = [("YER TUTUCU", 15, 330), ("SAHIP IKONU", 12, 500), ("BEKLIYOR", 12, 620)]


def text_pixels() -> dict:
    """{y: [(x0, x1), ...]} dolu yatay aralıklar."""
    spans: dict = {}
    for text, scale, top in LINES:
        width = len(text) * 6 * scale - scale
        left = (SIZE - width) // 2
        for ci, ch in enumerate(text):
            glyph = GLYPHS[ch]
            for gy, row in enumerate(glyph):
                for gx, bit in enumerate(row):
                    if bit != "1":
                        continue
                    x0 = left + (ci * 6 + gx) * scale
                    for y in range(top + gy * scale, top + (gy + 1) * scale):
                        spans.setdefault(y, []).append((x0, x0 + scale))
    return spans


def build_rows() -> bytes:
    spans = text_pixels()
    top_text = min(spans)
    bot_text = max(spans)
    band_top, band_bot = top_text - 60, bot_text + 60
    raw = bytearray()
    for y in range(SIZE):
        row = bytearray()
        in_band = band_top <= y <= band_bot
        text_spans = spans.get(y, [])
        for x in range(SIZE):
            if in_band:
                color = BAND
                for x0, x1 in text_spans:
                    if x0 <= x < x1:
                        color = TEXT
                        break
            else:
                color = YELLOW if ((x + y) // 64) % 2 == 0 else BLACK
            row.extend(color)
        raw.append(0)  # PNG süzgeç tipi 0
        raw.extend(row)
    return bytes(raw)


def chunk(tag: bytes, data: bytes) -> bytes:
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(path: str) -> None:
    raw = build_rows()
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8 bit, RGB (alfa yok)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(png)
    os.replace(tmp, path)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "build/ios/placeholder-icon.png"
    write_png(out)
    print("YER TUTUCU ikon yazıldı (gerçek ikon DEĞİL, sahip ikonu bekliyor): " + out)
