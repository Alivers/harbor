#!/usr/bin/env python3
"""Draws Harbor's app icon and writes Resources/AppIcon.icns.

A stacked pair of shipping containers over two waves, on a sea-green squircle that follows the
macOS icon grid (an 824 pt body on a 1024 pt canvas). Requires Pillow: python3 -m pip install pillow
"""
import io
import math
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SCALE = 4  # draw large, then downsample, for smooth edges
SIZE = 1024 * SCALE


def s(value):
    return int(round(value * SCALE))


def squircle(center, radius, exponent=5.0, steps=720):
    """Points of a superellipse, the continuous-corner shape of macOS icons."""
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, n = math.cos(t), math.sin(t)
        x = math.copysign(abs(c) ** (2 / exponent), c)
        y = math.copysign(abs(n) ** (2 / exponent), n)
        points.append((center[0] + radius * x, center[1] + radius * y))
    return points


def vertical_gradient(size, top, bottom):
    gradient = Image.new("RGBA", (1, size))
    for y in range(size):
        f = y / (size - 1)
        gradient.putpixel((0, y), tuple(int(round(top[i] + (bottom[i] - top[i]) * f)) for i in range(3)) + (255,))
    return gradient.resize((size, size))


def container(draw, box, rib_color):
    """A white shipping container with evenly spaced, recessed vertical ribs."""
    left, top, right, bottom = box
    draw.rounded_rectangle(box, radius=s(22), fill=(255, 255, 255, 255))
    inset = s(30)
    ribs = max(4, round((right - left) / s(62)))
    step = ((right - left) - 2 * inset) / ribs
    for i in range(ribs):
        x = left + inset + i * step + step * 0.3
        draw.rounded_rectangle((x, top + inset, x + step * 0.4, bottom - inset), radius=s(8), fill=rib_color)


def wave(image, y, amplitude, width, color, phase=0.0):
    """A sine stroke with round ends, drawn as one filled shape so it has no seams."""
    layer = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(layer)
    left, right, steps = s(160), s(864), 600
    centre = [(left + (right - left) * i / steps, y + amplitude * math.sin(phase + 4 * math.pi * i / steps)) for i in range(steps + 1)]
    r = width / 2
    for x, yy in centre:
        draw.ellipse((x - r, yy - r, x + r, yy + r), fill=255)
    image.paste(color[:3] + (255,), (0, 0), layer.point(lambda v: v * color[3] // 255))


def render():
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    body = squircle((SIZE / 2, SIZE / 2), s(412))

    # Soft drop shadow under the body, as on other macOS icons.
    shadow = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(shadow).polygon([(x, y + s(14)) for x, y in body], fill=90)
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(18)))
    canvas.paste((0, 0, 0, 255), (0, 0), shadow)

    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(body, fill=255)

    art = vertical_gradient(SIZE, (64, 196, 158), (18, 118, 104))
    draw = ImageDraw.Draw(art)
    # A gentle highlight across the top third.
    glow = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(glow).ellipse((s(-60), s(-520), s(1084), s(430)), fill=46)
    art.paste((255, 255, 255, 255), (0, 0), glow.filter(ImageFilter.GaussianBlur(s(60))))

    rib = (40, 160, 130, 255)
    container(draw, (s(330), s(250), s(694), s(408)), rib)
    container(draw, (s(236), s(428), s(788), s(626)), rib)
    wave(art, s(704), s(16), s(34), (255, 255, 255, 255))
    wave(art, s(784), s(14), s(30), (255, 255, 255, 140), phase=math.pi * 0.6)

    canvas.paste(art, (0, 0), mask)
    # A hairline edge keeps the shape crisp on light backgrounds.
    edge = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(edge).polygon(body, outline=60, width=s(2))
    canvas.paste((0, 60, 50, 255), (0, 0), ImageChops.multiply(edge, mask))
    return canvas.resize((1024, 1024), Image.LANCZOS)


def icns(master):
    """An .icns file holding PNG renditions; every size macOS asks for is included."""
    chunks = [("icp4", 16), ("icp5", 32), ("ic11", 32), ("icp6", 64), ("ic12", 64), ("ic07", 128),
              ("ic08", 256), ("ic13", 256), ("ic09", 512), ("ic14", 512), ("ic10", 1024)]
    body = b""
    for kind, size in chunks:
        png = io.BytesIO()
        master.resize((size, size), Image.LANCZOS).save(png, format="PNG", optimize=True)
        data = png.getvalue()
        body += kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    return b"icns" + struct.pack(">I", len(body) + 8) + body


def main():
    root = Path(__file__).resolve().parent.parent
    master = render()
    out = root / "Resources" / "AppIcon.icns"
    out.parent.mkdir(exist_ok=True)
    out.write_bytes(icns(master))
    if "--png" in sys.argv:
        master.save(root / "Resources" / "AppIcon.png")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
