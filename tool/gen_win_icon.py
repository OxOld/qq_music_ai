# -*- coding: utf-8 -*-
"""用启动图标同一设计稿生成 Windows 桌面图标 app_icon.ico（多尺寸）"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_icon import build_master  # noqa: E402  复用同一设计

from PIL import Image  # noqa: E402

OUT = r"C:\Projects\qq_music_ai\windows\runner\resources\app_icon.ico"


def main():
    master = build_master()  # 1024 圆角渐变 + 白色音符
    base = master.resize((256, 256), Image.LANCZOS)
    base.save(
        OUT,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
               (64, 64), (128, 128), (256, 256)],
    )
    print("ICO written:", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
