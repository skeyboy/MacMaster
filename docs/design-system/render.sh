#!/bin/zsh
# 渲染设计稿 HTML → PNG（2x）。
#   ./render.sh screens/01-dashboard.html            # 1160x780 单窗口屏
#   ./render.sh screens/05-states.html 1120 900      # 组件态合集
#   ./render.sh components.html 1240 2100            # 设计系统基线
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRC="$1"; W="${2:-1160}"; H="${3:-780}"
OUT="${SRC%.html}.png"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size="${W},${H}" --screenshot="${OUT}" "file://$(pwd)/${SRC}" 2>/dev/null
print -r -- "${OUT}"
