#!/bin/zsh
# 出 Resources/AppIcon.icns：跑 make-icon.swift 生成十张 iconset → iconutil 打包 → **反向解一次核对**。
#
#   ./Scripts/make-icon.sh                 # 写 Resources/AppIcon.icns
#   ./Scripts/make-icon.sh --check         # 核对现有 icns：不重写它，但现生成一份源图用来比字节
#
# 为什么要那一步"反向解一次"（`iconutil -c iconset`）：icns 是个容器，
# `sips -g pixelWidth` 只会报它挑中的那一档，看不出"十档是不是都在里面"。
# 少一档的后果是 Dock 缩到 16pt 时系统只能拿大图硬缩，看着发糊——而 plist 与
# codesign 全都正常，没有任何一处会报错。所以判据只能是"解出来的档数与字节数对得上"。
# 两道判据在两种模式下都得真跑：字节那一判要有源可比，`--check` 就把源图现生成到
# `build/AppIcon.check.iconset`（不碰 `Resources/AppIcon.icns`）。以前这一支没有源，
# 取字节那一句恒为空、后面 `-n` 判断直接跳过，实际只剩"十档齐全"一道——缺口记在
# `release-readiness.md` §7.23 与 §10 第 2 步。
set -e
cd "$(dirname "$0")/.."

ICNS="Resources/AppIcon.icns"
WORK="build/AppIcon.iconset"
CHECK_ONLY=0
[[ "$1" == "--check" ]] && CHECK_ONLY=1

if (( CHECK_ONLY )); then
  [[ -f "$ICNS" ]] || { print -u2 -- "没有 $ICNS，先跑 ./Scripts/make-icon.sh"; exit 1; }
  rm -rf "build/AppIcon.check.iconset"
  mkdir -p "build/AppIcon.check.iconset"
  swift Scripts/make-icon.swift "build/AppIcon.check.iconset" >/dev/null
  WORK="build/AppIcon.check.iconset"
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
SRC="$WORK/icon_512x512@2x.png"
if [[ ! -f "$SRC" ]]; then
  print -u2 -- "✗ 取不到 1024 档源图 $SRC，字节这一判没有可比对象"
  exit 1
fi
src_bytes=$(wc -c <"$SRC" | tr -d ' ')
rt_bytes=$(wc -c <"$RT/icon_512x512@2x.png" | tr -d ' ')
if [[ "$src_bytes" != "$rt_bytes" ]]; then
  print -u2 -- "✗ 1024 档字节数不一致：源 $src_bytes / 解出 $rt_bytes"
  exit 1
fi
print -r -- "✓ 反向解出 10 档；1024 档 $rt_bytes 字节"
print -r -- "档位：$(ls "$RT" | tr '\n' ' ')"
