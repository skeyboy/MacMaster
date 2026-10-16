#!/usr/bin/env python3
# P52b 照片对照：两两比一张"同一档位的两种形态"，数出内容区里通道差 > 阈值的像素个数。
# 用法：p52-photo-diff.py A.png B.png [裁剪左 上 右 下]，坐标按 2x Retina 像素。
# 阈值固定 8/255：比这个小的差属抗锯齿与亚像素位移，不该读成"版式变了"。
import sys
from PIL import Image, ImageChops

THRESHOLD = 8


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    a = Image.open(sys.argv[1]).convert("RGB")
    b = Image.open(sys.argv[2]).convert("RGB")
    if a.size != b.size:
        print(f"尺寸不等，直接判不等：{a.size} vs {b.size}")
        return 0
    if len(sys.argv) == 7:
        box = tuple(int(v) for v in sys.argv[3:7])
        a, b = a.crop(box), b.crop(box)
    diff = ImageChops.difference(a, b)
    over = sum(1 for p in diff.getdata() if max(p) > THRESHOLD)
    total = diff.size[0] * diff.size[1]
    print(f"{sys.argv[1]} vs {sys.argv[2]}  区域 {diff.size}  差>{THRESHOLD}/255 的像素 {over} / {total}"
          f"  占比 {over * 100.0 / total:.4f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
