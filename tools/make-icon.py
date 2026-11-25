#!/usr/bin/env python3
"""OPUlation's app icon: her two compound eyes on crushed velvet, glossy, under heavy shadowed
lids with flared lashes and winged liner. (head(), lips(), ocelli() and friends draw the fuller face.)

    python3 tools/make-icon.py [out.png]      (default: the iOS app icon)

Needs pycairo, numpy and Pillow. Output is 1024x1024 RGB with no alpha, as App Store Connect requires."""
import math, random, sys
import cairo, numpy as np
from PIL import Image

S = 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else "ios/OPUlation/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
rng = random.Random(7)

PLUM_DEEP = (0.09, 0.01, 0.06)
PLUM = (0.30, 0.04, 0.17)
WINE = (0.52, 0.06, 0.24)
PINK = (1.0, 0.41, 0.73)
HOT = (1.0, 0.22, 0.58)
AMBER = (1.0, 0.71, 0.28)
CREAM = (0.97, 0.88, 0.84)
INK = (0.16, 0.04, 0.09)
LIP = (0.86, 0.04, 0.22)


def velvet():
    """crushed velvet: a plum glow, broad crushed patches where the pile catches the light, fine grain"""
    y, x = np.mgrid[0:S, 0:S] / S
    r = np.hypot(x - 0.5, y - 0.5)
    base = np.clip(1.0 - r * 1.25, 0, 1) ** 1.2
    def noise(k, seed):
        g = np.random.default_rng(seed).random((k + 1, k + 1))
        return np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)) / 255.0
    folds = 0.6 * noise(5, 1) + 0.4 * noise(9, 2)
    crush = noise(14, 3)
    sheen = (0.5 + 0.5 * np.sin((x * 0.7 + y) * 4.5 + folds * 5)) ** 2                  # broad soft sheen
    patches = np.clip((crush - 0.45) * 3, 0, 1)                                        # crushed, light-catching patches
    grain = np.random.default_rng(4).random((S, S))
    grain = np.asarray(Image.fromarray((grain * 255).astype(np.uint8)).resize((S // 2, S // 2)).resize((S, S), Image.BILINEAR)) / 255.0
    v = 0.30 + 0.55 * base
    v *= 0.80 + 0.35 * sheen * (0.5 + patches) + 0.10 * (grain - 0.5)
    deep, mid, hi = np.array(PLUM_DEEP), np.array(PLUM), np.array(WINE)
    t = np.clip(v, 0, 1)[..., None]
    col = np.where(t < 0.6, deep + (mid - deep) * (t / 0.6), mid + (hi - mid) * ((t - 0.6) / 0.4))
    return np.clip(col, 0, 1)


def to_surface(rgb):
    a = np.zeros((S, S, 4), np.uint8)
    a[..., 2], a[..., 1], a[..., 0] = (rgb[..., 0] * 255), (rgb[..., 1] * 255), (rgb[..., 2] * 255)
    a[..., 3] = 255
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, S, S)
    np.frombuffer(surf.get_data(), np.uint8).reshape(S, S, 4)[:] = a
    surf.mark_dirty()
    return surf


def ellipse(c, cx, cy, rx, ry, rot=0.0):
    c.save(); c.translate(cx, cy); c.rotate(rot); c.scale(rx, ry); c.arc(0, 0, 1, 0, 2 * math.pi); c.restore()


def radial(c, cx, cy, r0, r1, stops):
    g = cairo.RadialGradient(cx, cy, r0, cx, cy, r1)
    for o, col, a in stops: g.add_color_stop_rgba(o, *col, a)
    return g


def head(c):
    # soft glow behind her, then the head itself, cream with a pink flush
    c.set_source(radial(c, 512, 520, 200, 560, [(0, PINK, 0.35), (1, PINK, 0)])); c.paint()
    ellipse(c, 512, 540, 430, 420)
    c.set_source(radial(c, 470, 430, 40, 520, [(0, (1, 0.95, 0.93), 1), (0.7, CREAM, 1), (1, (0.90, 0.70, 0.72), 1)]))
    c.fill_preserve(); c.set_source_rgba(*INK, 0.9); c.set_line_width(6); c.stroke()


def eye(c, cx, cy, rx, ry, tilt, lid, flip, lash=1.0):
    """a compound eye: glossy facets, then a heavy shadowed lid over the top, then lashes"""
    # eyeshadow bleeding up from the lid
    c.save(); ellipse(c, cx, cy - ry * 0.35, rx * 1.18, ry * 0.95, tilt)
    c.set_source(radial(c, cx, cy - ry * 0.45, rx * 0.2, rx * 1.15, [(0, (0.55, 0.08, 0.45), 0.85), (1, (0.55, 0.08, 0.45), 0)]))
    c.fill(); c.restore()
    # the eye, clipped
    c.save(); ellipse(c, cx, cy, rx, ry, tilt); c.clip()
    c.set_source(radial(c, cx, cy, 10, rx * 1.1, [(0, (0.45, 0.02, 0.18), 1), (1, (0.18, 0.0, 0.07), 1)])); c.paint()
    hr = 17
    for row in range(-16, 17):
        for col in range(-16, 17):
            x = cx + col * hr * 1.73 + (row % 2) * hr * 0.865
            y = cy + row * hr * 1.5
            d = math.hypot((x - cx) / rx, (y - cy) / ry)
            if d > 1.02: continue
            lit = rng.random() < 0.55
            base = HOT if lit else (0.62, 0.05, 0.30)
            shade = 1.0 - 0.45 * d ** 2
            c.new_path()
            for k in range(6):
                a = math.pi / 6 + k * math.pi / 3
                (c.move_to if k == 0 else c.line_to)(x + hr * 0.9 * math.cos(a), y + hr * 0.9 * math.sin(a))
            c.close_path(); c.set_source_rgb(*(v * shade for v in base)); c.fill()
    # gloss: a big soft sheen and a sharp catchlight
    ellipse(c, cx - rx * 0.32 * flip, cy + ry * 0.05, rx * 0.42, ry * 0.30, -0.5 * flip)
    c.set_source(radial(c, cx - rx * 0.32 * flip, cy + ry * 0.05, 4, rx * 0.42, [(0, (1, 1, 1), 0.55), (1, (1, 1, 1), 0)])); c.fill()
    ellipse(c, cx - rx * 0.30 * flip, cy + ry * 0.0, 26, 18, -0.4 * flip); c.set_source_rgba(1, 1, 1, 0.92); c.fill()
    ellipse(c, cx - rx * 0.12 * flip, cy + ry * 0.22, 10, 8); c.set_source_rgba(1, 1, 1, 0.75); c.fill()
    # the heavy lid: everything above a drooping curve, shadowed toward its edge
    top = cy - ry - 10; edge = cy - ry + lid * 2 * ry
    c.new_path(); c.move_to(cx - rx - 20, top); c.line_to(cx + rx + 20, top)
    c.line_to(cx + rx + 20, edge - ry * 0.10 * flip)
    c.curve_to(cx + rx * 0.4, edge + ry * 0.12, cx - rx * 0.4, edge + ry * 0.12, cx - rx - 20, edge + ry * 0.10 * flip)
    c.close_path()
    g = cairo.LinearGradient(cx, top, cx, edge + ry * 0.1)
    g.add_color_stop_rgb(0, 1.0, 0.88, 0.86); g.add_color_stop_rgb(0.5, 0.96, 0.62, 0.78); g.add_color_stop_rgb(0.85, 0.80, 0.30, 0.62); g.add_color_stop_rgb(1, 0.55, 0.10, 0.40)
    c.set_source(g); c.fill_preserve()
    c.set_source_rgba(1, 0.85, 0.95, 0.25); c.set_line_width(2); c.stroke()  # shimmer on the lid
    c.restore()
    # outline, with a pink rim so she glows off the velvet
    ellipse(c, cx, cy, rx + 6, ry + 6, tilt); c.set_source_rgba(*PINK, 0.55); c.set_line_width(10); c.stroke()
    ellipse(c, cx, cy, rx, ry, tilt); c.set_source_rgba(*INK, 1); c.set_line_width(7); c.stroke()
    # lash line along the lid edge, and long curled lashes sweeping outward
    def lid_pt(t):  # t in [0,1] from inner to outer corner (outer = away from centre)
        x0, x1 = (cx + rx * 0.98, cx - rx * 0.98) if flip > 0 else (cx - rx * 0.98, cx + rx * 0.98)
        u = t if flip < 0 else 1 - t
        # same bezier as the lid edge, sampled
        p0 = (cx - rx - 20, edge + ry * 0.10 * flip); p1 = (cx - rx * 0.4, edge + ry * 0.12)
        p2 = (cx + rx * 0.4, edge + ry * 0.12); p3 = (cx + rx + 20, edge - ry * 0.10 * flip)
        s = u; m = 1 - s
        return (m**3 * p0[0] + 3*m*m*s * p1[0] + 3*m*s*s * p2[0] + s**3 * p3[0],
                m**3 * p0[1] + 3*m*m*s * p1[1] + 3*m*s*s * p2[1] + s**3 * p3[1])
    c.save(); ellipse(c, cx, cy, rx + 4, ry + 4, tilt); c.clip()
    c.new_path(); pts = [lid_pt(i / 40) for i in range(41)]
    c.move_to(*pts[0]); [c.line_to(*p) for p in pts[1:]]
    c.set_source_rgba(*INK, 1); c.set_line_width(14); c.set_line_cap(cairo.LINE_CAP_ROUND); c.stroke()
    c.restore()
    out = -flip  # lashes sweep away from the face's centre
    for i in range(7):
        k = i / 6                                   # 0 = mid-lid, 1 = outer corner
        x, y = lid_pt(0.5 + 0.5 * k)
        L = (50 + 95 * k ** 1.2) * lash
        th0 = 0.55 + 0.45 * k                       # leaves the lid edge outward and up...
        th1 = th0 + 0.7                             # ...and curls further up at the tip
        mx, my = x + out * L * 0.55 * math.cos(th0), y - L * 0.55 * math.sin(th0)
        ex, ey = mx + out * L * 0.5 * math.cos(th1), my - L * 0.5 * math.sin(th1)
        c.new_path(); c.move_to(x, y); c.curve_to(mx, my, mx, my, ex, ey)
        c.set_source_rgba(*INK, 1); c.set_line_width(7 + 5 * k); c.set_line_cap(cairo.LINE_CAP_ROUND); c.stroke()
    # a wing of liner off the outer corner
    x, y = lid_pt(1.0)
    c.new_path(); c.move_to(x - out * 30, y + 2); c.curve_to(x + out * 30 * lash, y - 4, x + out * 60 * lash, y - 18 * lash, x + out * 85 * lash, y - 42 * lash)
    c.set_source_rgba(*INK, 1); c.set_line_width(12); c.stroke()


def antennae(c):
    for s in (-1, 1):
        x0, y0 = 512 + s * 46, 190
        c.new_path(); c.move_to(x0, y0)
        c.curve_to(x0 + s * 30, y0 - 70, x0 + s * 120, y0 - 110, x0 + s * 170, y0 - 70)
        c.curve_to(x0 + s * 210, y0 - 40, x0 + s * 175, y0 + 5, x0 + s * 145, y0 - 15)
        c.set_source_rgba(*INK, 1); c.set_line_width(9); c.set_line_cap(cairo.LINE_CAP_ROUND); c.stroke()
        # feathery arista plumes, like a boa
        for k in range(14):
            t = 0.12 + k * 0.06
            bx = x0 + s * (25 + 150 * t); by = y0 - 62 - 48 * math.sin(math.pi * t)
            for side in (-1, 1):
                c.new_path(); c.move_to(bx, by)
                c.curve_to(bx + s * 8, by + side * 18, bx + s * 22, by + side * 28, bx + s * 30, by + side * 34)
                c.set_source_rgba(*(PINK if k % 2 else AMBER), 0.95); c.set_line_width(4); c.stroke()
        ellipse(c, x0 + s * 145, y0 - 15, 14, 14); c.set_source_rgb(*AMBER); c.fill()


def lips(c):
    cx, cy = 512, 848
    w, h = 118, 58
    def outline():
        c.new_path(); c.move_to(cx - w, cy)
        c.curve_to(cx - w * 0.75, cy - h * 0.9, cx - w * 0.25, cy - h * 1.25, cx, cy - h * 0.55)   # left cupid's bow
        c.curve_to(cx + w * 0.25, cy - h * 1.25, cx + w * 0.75, cy - h * 0.9, cx + w, cy)
        c.curve_to(cx + w * 0.7, cy + h * 1.45, cx - w * 0.7, cy + h * 1.45, cx - w, cy)          # full lower lip
        c.close_path()
    outline()
    g = cairo.LinearGradient(cx, cy - h, cx, cy + h * 1.2)
    g.add_color_stop_rgb(0, 0.95, 0.12, 0.32); g.add_color_stop_rgb(0.55, LIP[0], LIP[1], LIP[2]); g.add_color_stop_rgb(1, 0.52, 0.0, 0.14)
    c.set_source(g); c.fill_preserve(); c.set_source_rgba(*INK, 1); c.set_line_width(6); c.stroke()
    # the parting, slightly open
    c.new_path(); c.move_to(cx - w * 0.95, cy + 2)
    c.curve_to(cx - w * 0.4, cy + h * 0.32, cx + w * 0.4, cy + h * 0.32, cx + w * 0.95, cy + 2)
    c.set_source_rgba(0.30, 0.0, 0.08, 1); c.set_line_width(9); c.stroke()
    # gloss
    ellipse(c, cx + 22, cy + h * 0.62, 44, 12, -0.08); c.set_source_rgba(1, 1, 1, 0.75); c.fill()
    ellipse(c, cx - 50, cy - h * 0.48, 22, 7, 0.25); c.set_source_rgba(1, 1, 1, 0.55); c.fill()


def blush_and_mark(c):
    for s in (-1, 1):
        ellipse(c, 512 + s * 300, 740, 92, 46, s * 0.15)
        c.set_source(radial(c, 512 + s * 300, 740, 4, 96, [(0, HOT, 0.42), (1, HOT, 0)])); c.fill()
    ellipse(c, 655, 812, 13, 12); c.set_source_rgb(*INK); c.fill()  # beauty mark


def ocelli(c):
    """her three simple eyes, as rhinestones on the crown"""
    for x, y, r in ((512, 232, 22), (472, 280, 17), (552, 280, 17)):
        ellipse(c, x, y, r + 5, r + 5); c.set_source_rgb(*INK); c.fill()
        ellipse(c, x, y, r, r)
        c.set_source(radial(c, x - r * 0.3, y - r * 0.3, 1, r * 1.2, [(0, (1, 0.95, 1), 1), (0.4, PINK, 1), (1, (0.55, 0.0, 0.3), 1)])); c.fill()
        for k in range(4):  # sparkle
            a = k * math.pi / 2 + math.pi / 4
            c.new_path(); c.move_to(x - r * 0.35, y - r * 0.35)
            c.line_to(x - r * 0.35 + 0.9 * r * math.cos(a), y - r * 0.35 + 0.9 * r * math.sin(a))
            c.set_source_rgba(1, 1, 1, 0.9); c.set_line_width(2.5); c.stroke()


def main():
    surf = to_surface(velvet())
    c = cairo.Context(surf); c.set_antialias(cairo.ANTIALIAS_BEST)
    # just her eyes on the velvet, with a pink haze behind them
    c.set_source(radial(c, 512, 540, 120, 560, [(0, PINK, 0.30), (1, PINK, 0)])); c.paint()
    for cx, tilt, flip in ((318, 0.12, +1), (706, -0.12, -1)):   # mirror images: same heavy lids
        eye(c, cx, 530, 172, 222, tilt, 0.44, flip, lash=0.72)
    buf = np.frombuffer(surf.get_data(), np.uint8).reshape(S, S, 4)
    rgb = buf[..., [2, 1, 0]].copy()
    Image.fromarray(rgb, "RGB").save(OUT, optimize=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
