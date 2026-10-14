#!/bin/zsh
# P39：全站设计稿"像素基线与稿同源"审计——工作树一个字节都不动。
#   ./Scripts/p39-mockup-staleness-audit.sh [OUT目录]
# 手法：把 docs/design-system 整体复制到 scratch（build/p39-stale/ds），在副本里用同一个
#       docs/design-system/render.sh 重渲染，逐张与 git show HEAD: 那一份 .png 比 sha256。
#       副本用完就丢，所以这一支可以反复跑，不会把未改动的稿图刷成新像素。
# 画布尺寸从入库 png 的像素尺寸反推（渲染固定 2x）。这一反推在 2026-10-14 实测过：
#       六张里五张按反推尺寸渲染后与 HEAD 逐字节相同，第六张（03c）不同——它不同不是尺寸错，
#       是它的 .html 被 0c61fbf 改过、.png 还停在 45ffe02，即"基线比稿旧"。
# 判据：sha 相同 = 这张图的像素确实出自现在这份稿；不同 = stale，并报差异 bbox 供归因。
# 读数边界：bbox 只说差异覆盖到哪，不说差异是 footer 还是文案——归因要看那一页 html 与 png 各自的 git log。
set -e
cd "$(git rev-parse --show-toplevel)"
OUT="${1:-docs/verification/p39-stale-audit}"
SCRATCH="build/p39-stale/ds"
mkdir -p "$OUT"
LOG="$OUT/staleness.log"
rm -rf build/p39-stale
mkdir -p "$SCRATCH"
cp -R docs/design-system/. "$SCRATCH/"

{
  print -r -- "# p39 mockup staleness audit (pixel baseline vs its own .html)"
  print -r -- "# date: $(date '+%Y-%m-%d %H:%M:%S')"
  print -r -- "# repo: $(git rev-parse --short HEAD)$(git diff --quiet || echo -dirty) branch=$(git rev-parse --abbrev-ref HEAD)"
  print -r -- "# render: docs/design-system/render.sh（headless Chrome，force-device-scale-factor=2）"
  print -r -- "# canvas: 由入库 png 的像素尺寸 /2 反推；渲染在副本 ${SCRATCH} 里跑，工作树不动"
} > "$LOG"

python3 - "$SCRATCH" >> "$LOG" <<'PY'
import hashlib, io, os, subprocess, sys
from PIL import Image, ImageChops

os.chdir(sys.argv[1])
pages = sorted(subprocess.run(['find', 'screens', '-name', '*.html'],
                              capture_output=True, text=True).stdout.split())
rows = []
for html in pages:
    png = html[:-5] + '.png'
    head = subprocess.run(['git', 'show', f'HEAD:docs/design-system/{png}'], capture_output=True)
    if head.returncode != 0:
        rows.append((html, '-', 'no-baseline', None, None))
        continue
    with Image.open(png) as im:
        w, h = im.size
    r = subprocess.run(['zsh', 'render.sh', html, str(w // 2), str(h // 2)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        rows.append((html, f'{w}x{h}', 'render-failed', None, r.stderr.strip()[:60]))
        continue
    old = hashlib.sha256(head.stdout).hexdigest()[:8]
    new = hashlib.sha256(open(png, 'rb').read()).hexdigest()[:8]
    bbox = None
    if old != new:
        a = Image.open(io.BytesIO(head.stdout)).convert('RGB')
        b = Image.open(png).convert('RGB')
        bbox = 'size-diff' if a.size != b.size else ImageChops.difference(a, b).getbbox()
    rows.append((html, f'{w // 2}x{h // 2}', f'{old}/{new}', old == new, bbox))

stale, synced = [], []
for html, size, dig, ok, bbox in rows:
    if ok is None:
        print(f'# NO-BASELINE\t{html}\t{dig}')
        continue
    (synced if ok else stale).append(html)
    print(f"# {'IN-SYNC' if ok else 'STALE'}\t{html}\tcanvas={size}\tdigest_old/new={dig}"
          f"\tbbox={bbox if bbox is not None else '-'}")
print('# ---- 汇总 ----')
print(f'# 可比对的稿图对（.html 有同名 .png，且 HEAD 里有那一份 png）: {len(synced) + len(stale)}')
print(f'# 其中 IN-SYNC（重渲染后与入库那份逐字节相同）: {len(synced)}')
print(f'# 其中 STALE（像素出自旧稿，本轮或下一轮必须重渲染）: {len(stale)}')
for x in stale:
    print(f'#   STALE: {x}')
PY
rm -rf build/p39-stale
cat "$LOG"
