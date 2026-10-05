#!/bin/zsh
# 磁盘分析页「深度上限」截图夹具：造一棵刚好越过扫描深度上限的窄树。
#
# 为什么需要专门的深夹具：`MMDisk.swift` 里 `maxDepth = 20`（现读，按符号名找），
# `scanChildren` 在 `depth >= maxDepth` 那一支把剩下的目录做成
# `children: []` + `deepSize(...)` + `descendantsMeasured: false` 的封顶节点。
# 普通夹具（`disk-fixture.sh`）最深才两三层，永远走不到那支，于是
# 「子项 未枚举」这一档在截图里根本拍不到——而它正是防止画面上出现
# 「文件数 0」那种假话的那一支。
#
# 层数怎么算：scanChildren(path: 根, depth: 0) 枚举根的子女；
# 扫 `根/L01/…/L0k` 这一层时 depth = k；所以 k = 20 时（即 L20 的子女）目录被封顶，
# 夹具要有 L01…L20 这 20 层，再在里面放 L21 = 被封顶的那个节点。
# L21 底下再放两层带字节的文件：`deepSize(remainingDepth: 3)` 量得到体积，
# 于是画面上是"占用有数、子项没枚举"这一对，而不是两个都是空。
#
# 用法：./Scripts/disk-depth-fixture.sh            # 建夹具，打印根目录与被封顶节点路径
#       ./Scripts/disk-depth-fixture.sh --clean
set -e
ROOT=/tmp/macmaster-disk-depth-fixture
MAX_DEPTH=20                       # 与 MMDisk 的 maxDepth 对齐

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "$ROOT"
  print -r -- "已删除 $ROOT"
  exit 0
fi

rm -rf "$ROOT"
cursor="$ROOT"
# zsh 的花括号范围在参数展开之前做，{1..$MAX_DEPTH} 不会展开，所以用 seq。
# 累加路径的变量不能叫 `path`：zsh 里它是与 PATH 绑定的特殊数组，一赋值就把
# 命令搜索路径毁了（第一次实跑报的是 `command not found: seq`）。
for i in $(seq 1 "$MAX_DEPTH"); do
  cursor="$cursor/$(printf 'L%02d' "$i")"
  mkdir -p "$cursor"
  # 每层一个 64k 的实心文件：这一层非空（枚举会返回条目），
  # 而且下钻时"子项 2"这种计数在照片上是可数的，不是 0。
  mkfile 64k "$cursor/marker.bin" >/dev/null
done

CAPPED="$cursor/L21"                 # depth=20 那一支造出来的封顶节点
mkdir -p "$CAPPED"
mkfile 64k "$CAPPED/marker.bin" >/dev/null
mkdir -p "$CAPPED/L22" && mkfile 1m "$CAPPED/L22/inside-1m.bin" >/dev/null
mkdir -p "$CAPPED/L22/L23" && mkfile 1m "$CAPPED/L22/L23/deeper-1m.bin" >/dev/null

print -r -- "$ROOT"
print -r -- "封顶节点=$CAPPED"
du -sh "$ROOT"
