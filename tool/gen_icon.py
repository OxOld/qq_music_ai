# -*- coding: utf-8 -*-
"""生成 QQ 音乐 AI 歌单 启动图标（Android 全套 mipmap + 自适应图标）
所有几何以 1024 设计稿为单位，统一乘缩放系数，避免错位。
"""
from PIL import Image, ImageDraw
import math, os

RES = r"C:\Projects\qq_music_ai\android\app\src\main\res"
MASTER = 2048  # 超采样，最后缩回 1024
K = MASTER / 1024.0

GREEN_TOP = (62, 216, 140)
GREEN_BOT = (24, 158, 98)

def gradient_square(size, radius):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        c = tuple(int(a + (b - a) * t) for a, b in zip(GREEN_TOP, GREEN_BOT))
        d.line([(0, y), (size, y)], fill=c + (255,))
    if radius > 0:
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, size - 1, size - 1], radius=radius, fill=255)
        img.paste(grad, (0, 0), mask)
    else:
        img = grad
    return img

def ellipse_pts(cx, cy, rx, ry, rot_deg, n=64):
    a = math.radians(rot_deg)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + x * math.cos(a) - y * math.sin(a),
                    cy + x * math.sin(a) + y * math.cos(a)))
    return pts

def draw_note(d, k, dx=0.0, dy=0.0):
    """双八分音符 ♫：两符头 + 符干 + 斜梁（1024 设计稿坐标）"""
    W = lambda v: v * k
    h1 = (400 + dx, 690 + dy)   # 左符头圆心
    h2 = (660 + dx, 640 + dy)   # 右符头圆心
    rx, ry, rot = 86, 62, -20
    beam_y1, beam_y2 = 330 + dy, 280 + dy   # 梁顶 左/右
    beam_t = 62
    stem_w = 32
    white = (255, 255, 255, 255)

    x1 = h1[0] + rx * 0.62      # 符干左列 x（贴符头右缘）
    x2 = h2[0] + rx * 0.62 + stem_w

    # 符头
    d.polygon(ellipse_pts(W(h1[0]), W(h1[1]), W(rx), W(ry), rot), fill=white)
    d.polygon(ellipse_pts(W(h2[0]), W(h2[1]), W(rx), W(ry), rot), fill=white)
    # 符干
    d.rectangle([W(x1), W(beam_y1), W(x1 + stem_w), W(h1[1] - 6)], fill=white)
    d.rectangle([W(x2 - stem_w), W(beam_y2), W(x2), W(h2[1] - 6)], fill=white)
    # 符尾梁
    d.polygon([(W(x1), W(beam_y1)), (W(x2), W(beam_y2)),
               (W(x2), W(beam_y2 + beam_t)), (W(x1), W(beam_y1 + beam_t))],
              fill=white)

def draw_sparkle(d, k, cx, cy, r_out, alpha=255):
    r_in = r_out * 0.32
    pts = []
    for i in range(8):
        ang = -math.pi / 2 + i * math.pi / 4
        r = (r_out if i % 2 == 0 else r_in) * k
        pts.append((cx * k + r * math.cos(ang), cy * k + r * math.sin(ang)))
    d.polygon(pts, fill=(255, 255, 255, alpha))

# 音符包围盒中心 ≈ (529.5, 516)，平移到画布中心 (512, 512)
DX, DY = -18, -4

def build_master():
    s = MASTER
    img = gradient_square(s, int(s * 0.22))
    d = ImageDraw.Draw(img)
    draw_note(d, K, DX, DY)
    draw_sparkle(d, K, 792 + DX, 205 + DY, 84)
    draw_sparkle(d, K, 882 + DX, 330 + DY, 38, alpha=215)
    return img.resize((1024, 1024), Image.LANCZOS)

def build_foreground():
    """自适应前景：内容必须整体落在中心安全圆内（半径 ~33% 画布）。
    内容包围盒（设计稿）：x 296-920, y 121-752，中心 (608, 436.5)。
    渲染坐标 = 设计坐标 x r，要落到画布中心需 offset = 512/r - 608。
    取 r=0.64：max 半径 443.9 x 0.64 = 284px = 27.7% < 30% ✓"""
    s = MASTER
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    r = 0.64
    k = K * r
    dx = 512 / r - 608   # +192
    dy = 512 / r - 436.5  # +363.5
    draw_note(d, k, dx, dy)
    draw_sparkle(d, k, 792 + dx, 205 + dy, 84)
    draw_sparkle(d, k, 882 + dx, 330 + dy, 38, alpha=215)
    return canvas.resize((1024, 1024), Image.LANCZOS)

def main():
    master = build_master()
    master.save(r"C:\Projects\qq_music_ai\icon_master_1024.png")

    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    fg     = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

    fg_master = build_foreground()

    for dpi, px in legacy.items():
        p = os.path.join(RES, f"mipmap-{dpi}")
        os.makedirs(p, exist_ok=True)
        master.resize((px, px), Image.LANCZOS).save(os.path.join(p, "ic_launcher.png"))
        master.resize((px, px), Image.LANCZOS).save(os.path.join(p, "ic_launcher_round.png"))

    for dpi, px in fg.items():
        p = os.path.join(RES, f"mipmap-{dpi}")
        fg_master.resize((px, px), Image.LANCZOS).save(os.path.join(p, "ic_launcher_foreground.png"))
        gradient_square(px, 0).save(os.path.join(p, "ic_launcher_background.png"))

    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
           '</adaptive-icon>\n')
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w", encoding="utf-8") as f:
            f.write(xml)
    print("DONE")

if __name__ == "__main__":
    main()
