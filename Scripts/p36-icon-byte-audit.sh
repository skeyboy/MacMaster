#!/bin/zsh
# 把 `make-icon.sh --check` 的两道判据各跑一遍正反两路，顺便量清字节那一判到底管到哪一层。
#
# 为什么要这一支：`release-readiness.md` §7.23 记的债是——`--check` 那一支不生成源图，
# 取源图那一句拿到空值，`[[ -n "$src_bytes" ]]` 于是恒假，**字节比对从来没有跑过**，
# 而末行成功输出打的是反向解出来那一档的字节数，读起来像比对过。修法是让 `--check`
# 现生成一份源图（不碰 `Resources/AppIcon.icns`）。修完必须两头都验：
#   ① 正向放行——现有 icns 在当前源码下该过；
#   ② 负向真拒——只有一道判据**能够**失败，它才是一道判据（旧脚本的病就是恒不失败）。
# ③ 再量一格这一判的边界：同一张图换一种 PNG 编码，`iconutil -c icns` 会把它归一回
#   同一个产物（现测：源图 270,169 与重编码后的 270,689 打出的 icns 逐字相同）。
#   所以这一判管的是**像素内容漂没漂**，不是"容器里那几个字节是谁编的"。
#
# 全程只读编译输入：跑完当场比 `Resources/AppIcon.icns` 的 sha256，动了就退非零。
#
# 用法：
#   ./Scripts/p36-icon-byte-audit.sh > docs/verification/p36-icon-byte/audit.log
#
# 退出码：0 三头都对；2 正向被拒；3 负向放行（判据还是恒不失败）；4 负向拒了但不是字节判据拒的；
#         5 归一那一头被拒（说明这一判比的不是像素）；6 这一改动到了编译输入。
set -e
cd "$(dirname "$0")/.."
source Scripts/mm-provenance.sh

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mm-icon-byte-audit.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
ICNS_BEFORE=$(shasum -a 256 Resources/AppIcon.icns | awk '{print $1}')

printf '# p36-icon-byte-audit.sh  %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
printf '# repo: %s branch=%s\n' "$(git rev-parse --short HEAD)$(git diff --quiet || echo -dirty)" \
  "$(git rev-parse --abbrev-ref HEAD)"
printf '# digest: %s\n' "$(mm_source_digest .)"

# ---- ① 正向：现有 icns 该过，而且这一支这次真的有源可比 ----
rm -rf build/AppIcon.check.iconset
if ! out=$(./Scripts/make-icon.sh --check 2>&1); then
  print -u2 -- "✗ 正向那一跑被拒了：\n$out"
  exit 2
fi
printf '# [1] --check 正向\n%s\n' "$out"
if [[ ! -f build/AppIcon.check.iconset/icon_512x512@2x.png ]]; then
  print -u2 -- "✗ --check 跑完还是没有源图目录——字节那一判又一次没有可比对象"
  exit 2
fi
printf '# [1] 现生成的源图：%s 字节（build/AppIcon.check.iconset/icon_512x512@2x.png）\n' \
  "$(wc -c <build/AppIcon.check.iconset/icon_512x512@2x.png | tr -d ' ')"

# ---- ② 负向：像素漂了的 icns 必须被字节判据拒 ----
TREE="$WORK/pixel-drift"
mkdir -p "$TREE/Scripts" "$TREE/Resources"
cp Scripts/make-icon.sh "$TREE/Scripts/make-icon.sh"
python3 - "$TREE" <<'PY'
import pathlib, sys
tree = pathlib.Path(sys.argv[1])
src = pathlib.Path("Scripts/make-icon.swift").read_text()
assert "0x84 / 255.0" in src
(tree / "Scripts" / "make-icon.swift").write_text(src.replace("0x84 / 255.0", "0x85 / 255.0", 1))
PY
(cd "$TREE" && ./Scripts/make-icon.sh >/dev/null 2>&1)          # 用改了颜色的源生成一棵漂了的 icns
cp Scripts/make-icon.swift "$TREE/Scripts/make-icon.swift"       # 换回仓库里那一份真源
if (cd "$TREE" && ./Scripts/make-icon.sh --check >"$WORK/neg.out" 2>&1); then
  print -u2 -- "✗ 像素漂了的 icns 竟然放行——字节这一判还是没跑"
  exit 3
fi
printf '# [2] --check 负向（应当拒）\n%s\n' "$(cat "$WORK/neg.out")"
if ! grep -q "1024 档字节数不一致" "$WORK/neg.out"; then
  print -u2 -- "✗ 是拒了，但不是字节判据拒的"
  exit 4
fi

# ---- ③ 这一判的边界：纯重编码（像素不变）会被 iconutil 归一 ----
NORM="$WORK/encode-drift"
mkdir -p "$NORM/Scripts" "$NORM/Resources" "$NORM/build"
cp Scripts/make-icon.sh Scripts/make-icon.swift "$NORM/Scripts/"
swift Scripts/make-icon.swift "$NORM/build/AppIcon.iconset" >/dev/null
enc_before=$(wc -c <"$NORM/build/AppIcon.iconset/icon_512x512@2x.png" | tr -d ' ')
sips -s format png -o "$NORM/build/AppIcon.iconset/icon_512x512@2x.png" \
  "$NORM/build/AppIcon.iconset/icon_512x512@2x.png" >/dev/null
enc_after=$(wc -c <"$NORM/build/AppIcon.iconset/icon_512x512@2x.png" | tr -d ' ')
iconutil -c icns "$NORM/build/AppIcon.iconset" -o "$NORM/Resources/AppIcon.icns"
if ! (cd "$NORM" && ./Scripts/make-icon.sh --check >/dev/null 2>&1); then
  print -u2 -- "✗ 像素没变的纯重编码被拒了——那这一判比的就不是像素"
  exit 5
fi
printf '# [3] 纯重编码：源 PNG %s → %s 字节，重打出的 icns 与仓库那份' \
  "$enc_before" "$enc_after"
if [[ "$(shasum -a 256 "$NORM/Resources/AppIcon.icns" | awk '{print $1}')" == "$ICNS_BEFORE" ]]; then
  print -r -- '逐字相同；--check 在这一头放行'
else
  print -r -- '不同；--check 在这一头放行（说明归一没归到同一个字节流）'
fi

# ---- ④ 这一跑有没有动到编译输入 ----
ICNS_AFTER=$(shasum -a 256 Resources/AppIcon.icns | awk '{print $1}')
if [[ "$ICNS_AFTER" != "$ICNS_BEFORE" ]]; then
  print -u2 -- "✗ 这一跑改动了编译输入 Resources/AppIcon.icns"
  exit 6
fi
printf '# [4] Resources/AppIcon.icns 全程未变：%s\n' "$ICNS_AFTER"
printf '# verdict: --check 的字节判据正向放行、像素漂移时拒绝；纯重编码会被 iconutil 归一——这一判管像素内容，不管容器里那几个字节是谁编的\n'
