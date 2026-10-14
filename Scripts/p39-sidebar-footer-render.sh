#!/bin/zsh
# P39：侧栏 footer 改稿后的重渲染 + 两条像素判据（footer 画没画、页面切没切）。
#   ./Scripts/p39-sidebar-footer-render.sh [OUT目录]
# 为什么需要它：0c61fbf 那笔"十张稿统一侧栏 footer"只改了 .html，一张 .png 都没重渲染；
#   本轮（P39）补稿之外还必须让像素跟着走，而"跟着走了"不能靠人眼看一遍就下结论。
# 三条量：
#   ① red_bar_clusters —— 在画面左侧 620 设备像素的带里，扫"红色族"（R≥150 且 R−max(G,B)≥90）的行，
#      按连续行聚成簇，只保留高 6..10 行、宽 >150 的簇。footer 的容量条就是"一条宽 >150、高约 8 的红条"，
#      所以簇数应等于该份稿里 class="vol-bar" 的个数（09-settings 那种只有按钮、没有容量条的 footer 不计）。
#      为什么不数红色像素总数：稿里徽标、红按钮也是同一个红，总数分不开"画了 footer"和"画了别的红"。
#      两条读数边界，都是首跑（2026-10-14）用真图量出来的：
#      · 颜色不能写死成 (255,59,48)：04b 那一页有 .scrim 模态遮罩，footer 的红被中性压暗成
#        (184,42,34)（实测 R/G/B 比例与令牌一致，就是乘了个 alpha），按精确色匹配会把它读成"没画"。
#        所以判据改成红族比值判定——代价是同一带里的内容红条也会被选中，靠下面那条高度过滤甩掉。
#      · 高度必须限在 6..10 设备行：07 的每核占用条（12 行）与 02b 内容区的红条（14、15 行）
#        宽度都 >150，只有"容量条只有 8 行高"这一形状特征能把它们和 footer 分开。
#   ② sheet_clipped —— 画面最后一行若仍有 ≥400 设备像素的纯白横条，说明白卡被画布切在边上。
#      这一条就是这么抓到的：components 在 1240×2100 画布上，HEAD 那张的最后一行就是白的（本来就在切）。
#   ③ digest_old/new —— 渲染是确定性的（未改动的页重渲染后与 HEAD 逐字节相同，2026-10-14 实测 16/20 页），
#      所以这里报出的字节差异只可能来自稿本身的变化。
set -e
cd "$(git rev-parse --show-toplevel)"
OUT="${1:-docs/verification/p39-rerender}"
mkdir -p "$OUT"
LOG="$OUT/render.log"
# 页名与画布（CSS 像素，渲染固定 2x）。components 那一行是本轮从 2100 抬到 2240 的：
# 抬起前白卡底边落在设备 y=4380，画布只有 4200，页尾被切走一块。
PAGES=(
  "screens/mmui/components.html 1240 2240"
  "screens/mmdisk/04b-disk-confirm.html 1200 2130"
  "screens/mmdisk/04e-disk-rescan.html 1200 1640"
  "screens/mmuninstaller/03c-uninstaller-trash.html 1160 1900"
  "screens/mmuninstaller/03e-uninstaller-watch.html 1160 1900"
  "screens/mmmonitor/07-monitor.html 1160 6518"
  "screens/mmcleaner/02b-cleaner-installers.html 1160 1104"
  "screens/mmuninstaller/03-uninstaller.html 1160 780"
  "screens/mmuninstaller/03b-uninstaller-orphans.html 1160 1320"
)
{
  print -r -- "# p39 sidebar-footer render + pixel checks"
  print -r -- "# date: $(date '+%Y-%m-%d %H:%M:%S')"
  print -r -- "# repo: $(git rev-parse --short HEAD)$(git diff --quiet || echo -dirty) branch=$(git rev-parse --abbrev-ref HEAD)"
  print -r -- "# pages: ${#PAGES}（6 张本轮改稿 + 3 张纯补渲染，见 p39-mockup-staleness-audit.sh 那四条 STALE）"
} > "$LOG"

for spec in "${PAGES[@]}"; do
  read -r src w h <<< "${spec}"
  png="docs/design-system/${src%.html}.png"
  html="docs/design-system/${src}"
  old=$(git show "HEAD:${png}" 2>/dev/null | shasum -a 256 | awk '{print substr($1,1,8)}')
  zsh docs/design-system/render.sh "$src" "$w" "$h" >/dev/null
  new=$(shasum -a 256 "$png" | awk '{print substr($1,1,8)}')
  expect=$(grep -c 'class="vol-bar' "$html" || true)
  python3 - "$png" "$src" "$old" "$new" "$expect" >> "$LOG" <<'PY'
import sys
from PIL import Image
path, src, old, new, expect = sys.argv[1:6]
im = Image.open(path).convert('RGB')
w, h = im.size
X = 620
WHITE = (255, 255, 255)
from PIL import ImageChops
band = im.crop((0, 0, X, h))
R, G, B = band.split()
red_dom = ImageChops.subtract(R, ImageChops.lighter(G, B)).point(lambda v: 255 if v >= 90 else 0).convert('1')
bright = R.point(lambda v: 255 if v >= 150 else 0).convert('1')
mask = ImageChops.darker(bright, red_dom)
rows = []
for y in range(h):
    colors = mask.crop((0, y, X, y + 1)).getcolors(2) or []
    rows.append(next((n for n, v in colors if v), 0))
clusters, y = [], 0
while y < h:
    if rows[y] > 150:
        y0 = y
        while y < h and rows[y] > 150:
            y += 1
        if 6 <= y - y0 <= 10:
            clusters.append((y0, y - 1))
    else:
        y += 1
last = im.crop((0, h - 1, w, h))
clipped = any(c == WHITE and n >= 400 for n, c in (last.getcolors(w) or []))
print(f"# {src}\tcanvas={w}x{h}\tdigest_old/new={old}/{new}\t"
      f"red_bar_clusters={len(clusters)} vol-bar_in_html={expect} "
      f"{'MATCH' if len(clusters) == int(expect) else 'MISMATCH'}\t"
      f"cluster_rows={clusters[:6]}{'...' if len(clusters) > 6 else ''}\tsheet_clipped={clipped}")
PY
done
cat "$LOG"
