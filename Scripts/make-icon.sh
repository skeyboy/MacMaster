#!/bin/zsh
# 出 Resources/AppIcon.icns：跑 make-icon.swift 生成十张 iconset → iconutil 打包 → **反向解一次核对**。
#
#   ./Scripts/make-icon.sh                 # 写 Resources/AppIcon.icns
#   ./Scripts/make-icon.sh --check         # 只核对现有 icns，不重新生成
#
# 为什么要那一步"反向解一次"（`iconutil -c iconset`）：icns 是个容器，
# `sips -g pixelWidth` 只会报它挑中的那一档，看不出"十档是不是都在里面"。
# 少一档的后果是 Dock 缩到 16pt 时系统只能拿大图硬缩，看着发糊——而 plist 与
# codesign 全都正常，没有任何一处会报错。所以判据只能是"解出来的档数与字节数对得上"。
set -e
cd "$(dirname "$0")/.."

ICNS="Resources/AppIcon.icns"
WORK="build/AppIcon.iconset"
CHECK_ONLY=0
[[ "$1" == "--check" ]] && CHECK_ONLY=1

if (( CHECK_ONLY )); then
  [[ -f "$ICNS" ]] || { print -u2 -- "没有 $ICNS，先跑 ./Scripts/make-icon.sh"; exit 1; }
else
  rm -rf "$WORK"
  mkdir -p "$WORK" Resources
  swift Scripts/make-icon.swift "$WORK"
  iconutil -c icns "$WORK" -o "$ICNS"
  print -r -- "✓ 已生成 $ICNS（$(wc -c <"$ICNS" | tr -d ' ') 字节）"
fi

# 反向核对：十档全在，且最大那档字节数与源 PNG 一致。
RT="build/AppIcon.roundtrip.iconset"
rm -rf "$RT"
iconutil -c iconset "$ICNS" -o "$RT"
n=$(ls "$RT" | wc -l | tr -d ' ')
if (( n != 10 )); then
  print -u2 -- "✗ 反向解出 $n 档，应为 10 档"
  exit 1
fi
src_bytes=$(wc -c <"$WORK/icon_512x512@2x.png" 2>/dev/null | tr -d ' ' || true)
rt_bytes=$(wc -c <"$RT/icon_512x512@2x.png" | tr -d ' ')
if [[ -n "$src_bytes" ]] && [[ "$src_bytes" != "$rt_bytes" ]]; then
  print -u2 -- "✗ 1024 档字节数不一致：源 $src_bytes / 解出 $rt_bytes"
  exit 1
fi
print -r -- "✓ 反向解出 10 档；1024 档 $rt_bytes 字节"
print -r -- "档位：$(ls "$RT" | tr '\n' ' ')"
