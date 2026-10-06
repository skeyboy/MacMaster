#!/bin/zsh
# 磁盘分析页「受保护目录跳过披露」的截图夹具：把受保护的名字放到**三个不同深度**。
#
# 为什么需要专门的夹具：普通夹具（`disk-fixture.sh`）只有一个根目录那一层的 `Library`，
# 而扫描的跳过判定在每一层都做（`scanChildren` / `deepSize` 里的 `protectedNames`），
# 披露却曾经只数根目录那一层。用那棵夹具拍出来的徽章是"未纳入 1 个受保护目录"，
# 少报与不少报**长得一模一样**——这一族的 bug 用哨兵夹具永远拍不出来，
# 所以才要一棵第二层、第三层各埋一处的树（`~/Pictures/Photos Library.photoslibrary`
# 在真机上就正好是第二层那一处）。
#
# 大小口径：这三处目录里的字节都不进统计（它们被整体跳过），所以徽章之外的数字
# 与它们无关；Documents/Movies 那两块的数保持和 `disk-fixture.sh` 同一档，
# 便于和 p68-disk / p21-disk 那两族照片对照。
#
#   ./Scripts/disk-protected-fixture.sh          # 建夹具，打印根目录与三处受保护目录
#   ./Scripts/disk-protected-fixture.sh --clean  # 删掉
set -e
ROOT=/tmp/macmaster-disk-protected-fixture

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "$ROOT"
  print -r -- "已删除 $ROOT"
  exit 0
fi

rm -rf "$ROOT"
mk() { mkdir -p "$(dirname "$ROOT/$1")"; mkfile "$2" "$ROOT/$1" >/dev/null; }

# 第一层（根的子女）：旧的根目录口径也能报出来的一处。
mk "Library/Caches/com.example.app/cache.bin"            64m
# 第二层：旧口径报不出来的那一处，真机上的对应物是 ~/Pictures/Photos Library.photoslibrary。
mk "Pictures/Photos Library.photoslibrary/originals/master.jpeg" 24m
# 第三层：同上，报不出来。
mk "Documents/Work/Library/Logs/app.log"                 8m
# 不被跳过的两块：给徽章旁边的数字一个可预期的尺寸，档位与 disk-fixture.sh 一致。
mk "Documents/report-2026.pdf"                           16m
mk "Movies/clip-1080p.mov"                                8m
mk "Downloads/dmg-image.dmg"                             48m

print -r -- "$ROOT"
print -r -- "受保护目录（相对根）：Library、Documents/Work/Library、Pictures/Photos Library.photoslibrary"
du -sh "$ROOT"
