#!/bin/zsh
# 磁盘分析页的截图夹具：在 /tmp 下造一棵大小可预期的小树。
# 为什么只准放 /tmp：MMDisk 的 MM_DISK_SCAN / MM_DISK_SELECT 钩子本身就拒绝 /tmp 之外的路径
# （见 Packages/MMDisk/Sources/MMDisk/MMDisk.swift 的守卫），夹具放别处钩子会直接忽略，
# 于是截图停在空态、看起来却像"Treemap 拍过了"。
#
# 用法：./Scripts/disk-fixture.sh            # 建夹具，打印根目录
#       ./Scripts/disk-fixture.sh --clean    # 删掉夹具
set -e
ROOT=/tmp/macmaster-disk-fixture

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "$ROOT"
  print -r -- "已删除 $ROOT"
  exit 0
fi

rm -rf "$ROOT"
# 大小档位拉开一个数量级，Treemap 的块面积差才看得出来；扩展名覆盖分类色（媒体/文档/日志/其他）。
mk() { mkdir -p "$(dirname "$ROOT/$1")"; mkfile "$2" "$ROOT/$1"; }
mk "Library/Caches/com.example.app/cache.bin"            64m
mk "Library/Caches/com.example.app/small.bin"             4m
mk "Library/Developer/Xcode/DerivedData/index.dbstore"   32m
mk "Documents/report-2026.pdf"                           16m
mk "Movies/clip-1080p.mov"                                8m
mk "Pictures/photo.jpg"                                   2m
mk "Library/Logs/app.log"                                 1m
mk "Downloads/dmg-image.dmg"                             48m
# 一个只有零碎小文件的目录：测"很多小块"时 Treemap 会不会把间隙画成一条虚色
mkdir -p "$ROOT/Documents/notes"
for i in {1..40}; do print -r -- "note $i" > "$ROOT/Documents/notes/note-$i.txt"; done

print -r -- "$ROOT"
du -sh "$ROOT"
