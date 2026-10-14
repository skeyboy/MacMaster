#!/bin/zsh
# P38b：把"稿图与令牌同源"变成可重跑的量。
#   ./Scripts/p38b-mockup-render-check.sh [OUT目录]
# 做两件事：① 用 docs/design-system/render.sh 重渲染那三张带标题栏的稿图（第四张 components 无标题栏层，
#           留在循环里当反证：它每次渲染都字节不变，说明这一判据量的确实是标题栏而不是"任何一次渲染"）；
#           ② 量每张图里"内容白区起点"那一行的行号，与 tokens.css 现读的 --titlebar-h 对账。
# 判据：同一张图先后两跑之间，只有标题栏以下的内容整体平移，平移量 = 令牌差 × 2（渲染是 2x）。
# 为什么量白区起点而不是标题栏下沿那条 1px 分隔线：分隔线是 rgba(0,0,0,.14)，在 2x 下会被抗锯齿摊开，
# 实测它在两跑之间报的是 14 设备像素而不是 28——量错这一格就会把"令牌没生效"当成结论。
# 两条读数边界：① titlebar_px_at_2x 的绝对值不等于令牌（实测 108 对 expect=104，恒定 +4 偏置来自外壳顶边界
#   被读早 2 CSS 像素；OLD/NEW 的 sheet_top 同为 78 就是它恒量的证据）——只有两跑之间的位移可用；
# ② 这一判据只对浅色窗口框稿有效，长图合集与深色档（07-monitor / 05-states / 09-settings）量不出白区，
#   报 content_top=None 是"这一页没有那一档白区"，不是"令牌没生效"。
set -e
cd "$(git rev-parse --show-toplevel)"
OUT="${1:-docs/verification/p38b-rerender}"
mkdir -p "$OUT"
LOG="$OUT/render.log"
TOKENS=docs/design-system/tokens.css
D=$(python3 -c "import re;print(re.search(r'--titlebar-h:\s*(\d+)px', open('$TOKENS').read()).group(1))")
{
  print -r -- "# p38b mockup render check"
  print -r -- "# date: $(date '+%Y-%m-%d %H:%M:%S')"
  print -r -- "# repo: $(git rev-parse --short HEAD)$(git diff --quiet || echo -dirty) branch=$(git rev-parse --abbrev-ref HEAD)"
  print -r -- "# tokens.css --titlebar-h: ${D}px"
} > "$LOG"
for f in screens/shell/01-dashboard screens/mmcleaner/02-cleaner screens/mmdisk/04-disk screens/mmui/components; do
  case "$f" in
    screens/mmui/components) zsh docs/design-system/render.sh "$f.html" 1240 2100 >/dev/null ;;
    *) zsh docs/design-system/render.sh "$f.html" >/dev/null ;;
  esac
  png="docs/design-system/$f.png"
  python3 - "$png" "$D" >> "$LOG" <<'PY'
import sys, hashlib
from PIL import Image, ImageStat

path, token = sys.argv[1], int(sys.argv[2])
im = Image.open(path).convert("L")
w, h = im.size
n = min(h, 400)
rows = [ImageStat.Stat(im.crop((100, y, w - 100, y + 1))).mean[0] for y in range(n)]

# sheet_top = 渐变桌面底下第一行实色（稿面窗口外壳的顶）；
# content_top = 内容白区（253）第一次连续 8 行的起点。两者的差就是稿面标题栏的高度。
border = next((y for y in range(n) if rows[y] < 200), None)
white = next((y for y in range(n - 8)
              if all(rows[k] > 250 for k in range(y, y + 8))), None)
gap = None if border is None or white is None else white - border
digest = hashlib.sha256(open(path, 'rb').read()).hexdigest()[:8]
print(f"# {path.split('/')[-1]}: 2x={w}x{h} sheet_top={border} content_top={white}"
      f" titlebar_px_at_2x={gap} expect={token * 2}"
      + ("" if gap is not None else " NOTE=no-titlebar-layer-page")
      + f" digest={digest}")
PY
done
cat "$LOG"
