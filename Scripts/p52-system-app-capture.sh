#!/bin/zsh
# P52b 取证：系统应用的本体转只读（`docs/analysis/uninstaller-app-body-risk.md` §4 建议 1）。
#
# 四档两两配对，判据一条"缺席"都不靠：
#   01 系统应用 + **不给** `MM_UNINSTALL_CONFIRM_MODE`（默认档 = appOnly，会尝试自动开确认面板）
#   03 系统应用 + 明确 `=none`（只拍列表与详情）
#       → 01 与 03 应当**同一张画面**：本体只读时那条自动开面板的路径被 `requestConfirmation` 拦住了。
#   02 普通应用 + 不给 mode（同一条默认档）
#   04 普通应用 + `=none`
#       → 02 与 04 应当**不同**：同一条默认档在普通应用上真的把确认面板弹出来了。
#   两对合起来才是完整的一条：01=03 说"这一档没弹面板"，02≠04 说"默认档本身是会弹的"。
#   只看 01=03 不够——那也可能是钩子根本没生效。
#   01 与 04 再配一对（系统应用只读说明 vs 普通应用两个删除按钮），要的是"删除入口收起来"这件事
#   在**两处**都成立：详情面板底部那一格换成了只读说明，底部操作栏右侧那两个按钮
#   （「仅卸载应用」/「移到废纸篓」）也跟着收掉——它们走的正是 `requestConfirmation`，
#   只收详情面板会留下一对点了没反应的死控件。
#   05 是窄窗档（1000 pt 硬最小宽度）：那句只读说明是这一屏新长的话，P25/P26 那一族教训
#      就是"中间省略把要紧的半句藏起来"，所以专门拍一张，由人眼读，不作像素判据。
#
# 另外三条：
#   · 夹具只放 /tmp（`MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 的钩子合同），用户的应用一个都不卷进来；
#   · 每档拍完自查两行应用**仍在磁盘上**——这一族拍到的是"入口给不给"，删掉了就什么都不是；
#   · 点名留痕按 P49 那一条做成正向断言（`已点名到 <路径>`），四档都要有。
#
#   ./Scripts/p52-system-app-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p52-system-app-capture.sh /tmp/mm-app-p52/MacMaster.app docs/verification/p52-system-app
#   ONLY=03 ./Scripts/p52-system-app-capture.sh …        只重拍 03 那一档
#   FIX=/tmp/macmaster-p52-fixture.XXXX ./Scripts/p52-system-app-capture.sh …  复用现成夹具
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
FIX=${FIX:-$(./Scripts/p52-system-app-fixture.sh)}
for required in Applications/ApplePages.app Applications/PlainTool.app \
                Library/Caches/com.apple.FixturePages Library/Caches/com.example.PlainTool; do
  [[ -e "$FIX/$required" ]] || { print -u2 -- "✗ 夹具不完整：$FIX 缺 $required（先跑 ./Scripts/p52-system-app-fixture.sh）"; exit 2; }
done

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p52 -s /tmp/mm-scratch-p52 重新构建再取证。"
  exit 4
fi

SETTLE=${SETTLE:-12}
mkdir -p "$OUT"
wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]] }

# 夹具里两行应用各自名下的"可扫残留"字节数。系统应用那一档画面上是"没有残留"，
# 而这两个数是它凭什么算证据：它名下的文件真在夹具里，扫不扫是决定，不是没得扫。
bundle_bytes() {
  local dir="$FIX/$1"
  find "$dir" -type f -exec stat -f %z {} + | awk '{t+=$1} END {print t+0}'
}
SYS_CACHE_BYTES=$(bundle_bytes "Library/Caches/com.apple.FixturePages")
PLAIN_CACHE_BYTES=$(bundle_bytes "Library/Caches/com.example.PlainTool")

main_window_id() {
  local pid=$1 log=$2 all wid n
  all=$(swift Scripts/window-ids.swift --pid "$pid" 2>>"$log" || true)
  print -r -- "# windows(pid=$pid): ${all//$'\n'/ | }" >>"$log"
  n=$(printf '%s\n' "$all" | grep -c 'layer=0 title=MacMaster bounds=' || true)
  [[ $n == 1 ]] || return 1
  wid=$(printf '%s\n' "$all" | sed -n 's/^windowid=\([0-9]*\) .*layer=0 title=MacMaster bounds=.*/\1/p')
  [[ -n $wid ]] || return 1
  print -r -- "$wid"
}

# shot <文件名> <bundleName> <确认档（空 = 不给这个钩子，走默认 appOnly）> [宽x高]
shot() {
  local name=$1 app=$2 mode=$3 size=${4:-1400x1000}
  wants $name || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  print -r -- "# p52-system-app-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP  fixture=$FIX" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  local -a modeEnv=()
  local modeNote
  if [[ -n $mode ]]; then
    modeEnv=(MM_UNINSTALL_CONFIRM_MODE="$mode")
    modeNote="MM_UNINSTALL_CONFIRM_MODE=$mode"
  else
    modeNote="MM_UNINSTALL_CONFIRM_MODE 未给（默认 appOnly，会尝试自动开确认面板）"
  fi
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=uninstaller MM_WINDOW_SIZE=$size MM_UNINSTALL_SELECT=$app $modeNote" >>"$log"
  print -r -- "# 夹具残留：com.apple.FixturePages 名下 ${SYS_CACHE_BYTES} B，com.example.PlainTool 名下 ${PLAIN_CACHE_BYTES} B" >>"$log"
  print -r -- "# 期望：ApplePages 那一行详情面板底部与底栏都没有删除按钮，只有一句只读说明；PlainTool 那一行两处都有"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=uninstaller MM_WINDOW_SIZE="$size" \
      MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$FIX" \
      MM_UNINSTALL_SELECT="$app" $modeEnv \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$SETTLE"
  local wid
  for i in {1..5}; do
    wid=$(main_window_id "$pid" "$log" || true)
    [[ -n $wid ]] && break
    sleep 3
  done
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 反复查了 5 次，标题为 MacMaster 的主窗口不是正好一扇（清单见 $log 的 # windows 行）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  # 拍完自查：两行应用都该还在磁盘上。这一族一条都没删，任何一行的消失都说明
  # 有一个删除动作真的走了出去，那这张照片记的就是"删除之后"，不作数。
  local gone=()
  for a in ApplePages PlainTool; do
    [[ -e "$FIX/Applications/$a.app" ]] || gone+=("$a")
  done
  if (( ${#gone[@]} > 0 )); then
    print -u2 -- "✗ $name：拍完之后这些应用已不在夹具里：${gone[*]}（这一族不该动盘，照片作废）"
    return 1
  fi
  print -r -- "# post-shot: 两行应用仍在磁盘（本族没有删除动作）" >>"$log"
  print -r -- "✅ $name windowid=$wid"
}

shot 01-system-app-default-no-sheet ApplePages "" || true
shot 02-plain-tool-default-sheet PlainTool "" || true
shot 03-system-app-confirm-none ApplePages none || true
shot 04-plain-tool-detail-buttons PlainTool none || true
shot 05-system-app-narrow-window ApplePages none 1000x1000 || true

typeset -a FAILED
for f in 01-system-app-default-no-sheet 02-plain-tool-default-sheet 03-system-app-confirm-none \
         04-plain-tool-detail-buttons 05-system-app-narrow-window; do
  wants $f || continue
  [[ -s "$OUT/$f.png" ]] || FAILED+=($f)
done

print -r -- ""
print -r -- "# 点名留痕核对（P49 那一条：正向断言，不看缺席）"
# 判据不写死 `$FIX/Applications/…`：应用侧留的是 `URL(fileURLWithPath:).path` 那一种形式，
# `/tmp` 会被解析成 `/private/tmp`，写死了就永远对不上，而且失败的样子和"没走到点名"一模一样
# （P49 的注释里记的就是这一族"断言太脆读起来像竞态复发"的坑）。
# 前缀留给 `.*`，但行尾锚定到 `/Applications/<名>.app$`：这一条仍然只有一种读法。
typeset -a PROBLEMS
for pair in "01-system-app-default-no-sheet:ApplePages" "02-plain-tool-default-sheet:PlainTool" \
            "03-system-app-confirm-none:ApplePages" "04-plain-tool-detail-buttons:PlainTool" \
            "05-system-app-narrow-window:ApplePages"; do
  name=${pair%%:*}; app=${pair##*:}
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  line=$(grep -m1 -E "MM_UNINSTALL_SELECT=$app 已点名到 .*/Applications/$app\.app$" "$lg" || true)
  if [[ -n $line ]]; then
    print -r -- "  ✓ $name：$line"
  else
    PROBLEMS+=("$name 没有「已点名到 …/Applications/$app.app」这一行（实际留痕：$(grep -m1 -E "^MM_UNINSTALL_SELECT=$app" "$lg" || echo 一条都没有)）")
  fi
done

print -r -- ""
print -r -- "# 画面交叉核对"
for png in "$OUT"/*.png(N); do
  print -r -- "  md5 $(md5 -q "$png")  $(basename $png)"
done
# 量法沿用 P46e/P49 那一条：单通道差 >8/255 的像素个数，门槛 8 留一个数量级余量。
# `same` 这一档是本族新加的用法：要的是**两档之间没有可辨差异**，
# 因为 01 与 03 只差一个"会不会尝试开面板"的钩子，而那一尝试被拦住了。
# md5 只列给人对账，不当判据（半透明横幅材质带 ±1/255 抖动）。
#
# 比对只量**内容区**（x ≥ SIDEBAR_X），侧栏整条不参与判据。这不是为了让判据变绿而缩小取景，
# 是侧栏那两格本来就在走：第一次实跑 01↔03 全帧差 215 个像素，逐行聚成三簇
# ——y 155~162（「系统清理 16.53 GB」那枚容量徽标）与 y 933~940 / 948~951
# （左下角「Macintosh HD 5%」＋进度条的填充宽度），全都在 x 159~203 那一条里，
# 内容区一个像素都不差。这两处跟着这台机器的可用空间走，P49 给概览页页脚写的
# "同一次运行的两张连拍都不会逐字节相同"在这里是同一族。
# 被裁掉的那一条不是不提：报告里照实打出 `侧栏` 那一列的数，读的人看得见裁掉了什么。
# 而"面板弹出来了"这件事在内容区是一个几百 k 像素的变化（02↔04 那一对实测 1.3 M），
# 裁掉侧栏不会把它一起裁掉。
typeset -a PIX_PAIRS=(
  "01-system-app-default-no-sheet|03-system-app-confirm-none|same"
  "02-plain-tool-default-sheet|04-plain-tool-detail-buttons|diff"
  "01-system-app-default-no-sheet|04-plain-tool-detail-buttons|diff"
)
pix_report=''
pix_rc=0
if ! python3 -c 'import PIL' >/dev/null 2>&1; then
  PROBLEMS+=("本机 python3 没有 PIL：像素比对没跑，这一族的画面判据不能空过")
else
  pix_report=$(python3 - "$OUT" "${PIX_PAIRS[@]}" <<'PY'
import os
import sys
from PIL import Image, ImageChops

SIDEBAR_X = 218


def count(img_a, img_b, left):
    d = ImageChops.difference(img_a, img_b).convert('RGB')
    r, g, b = d.split()
    hist = ImageChops.lighter(ImageChops.lighter(r, g), b).histogram()
    above = sum(hist[9:])
    peak = max(i for i in range(256) if hist[i])
    if left:
        d = d.crop((left, 0, d.size[0], d.size[1]))
        r, g, b = d.split()
        hist = ImageChops.lighter(ImageChops.lighter(r, g), b).histogram()
        return above, sum(hist[9:]), max(i for i in range(256) if hist[i])
    return above, above, peak


out = sys.argv[1]
for spec in sys.argv[2:]:
    a, b, kind = spec.split('|')
    fa = os.path.join(out, a + '.png')
    fb = os.path.join(out, b + '.png')
    if not (os.path.exists(fa) and os.path.exists(fb)):
        print('\t'.join((a, b, kind, 'missing', '-', '-', '-')))
        continue
    ia = Image.open(fa).convert('RGB')
    ib = Image.open(fb).convert('RGB')
    if ia.size != ib.size:
        print('\t'.join((a, b, kind, 'sizediff', '%s vs %s' % (ia.size, ib.size), '-', '-')))
        continue
    whole, content, peak = count(ia, ib, SIDEBAR_X)
    print('\t'.join((a, b, kind, str(content), str(peak), str(whole), str(whole - content))))
PY
) || pix_rc=$?
fi
pix_lines=$(wc -l <<<"$pix_report" | tr -d ' ')
if (( pix_lines < ${#PIX_PAIRS[@]} )); then
  PROBLEMS+=("像素比对只出了 $pix_lines 行，该出 ${#PIX_PAIRS[@]} 行（python 退出码 $pix_rc）——判据没跑完就是没过")
fi
while IFS=$'\t' read -r a b kind above maxd whole strip; do
  [[ -n $a ]] || continue
  case $above in
    missing) print -r -- "  – $a ↔ $b：有一张没拍出，交给「没拍出照片」那一条报"； continue ;;
    sizediff) PROBLEMS+=("$a ↔ $b 两张尺寸不同（$maxd）：不是一扇窗口的两种状态，比对无意义"); continue ;;
  esac
  print -r -- "  · $a ↔ $b：内容区 $above 个可辨像素｜侧栏条（不参与判据）$strip 个｜全帧 $whole 个｜最大幅度 $maxd"
  case $kind in
    same)
      if (( above == 0 )); then print -r -- "  ✓ $a ↔ $b：内容区可辨差异 0 个像素⟹ 面板确实没弹出来"
      else PROBLEMS+=("$a ↔ $b：内容区可辨差异 $above 个像素（最大幅度 $maxd）——这一对本该相同，不同就说明 01 那一档有别的东西变了（多半是面板弹出来了）"); fi ;;
    diff)
      if (( above > 0 )); then print -r -- "  ✓ $a ↔ $b：内容区可辨差异 $above 个像素"
      else PROBLEMS+=("$a ↔ $b：内容区可辨差异 0 个像素（最大幅度 $maxd）——这一对本该不同，相同就说明那一条钩子或那一项判定没在界面上起作用"); fi ;;
  esac
done <<< "$pix_report"

for p in "${PROBLEMS[@]}"; do print -u2 -- "⚠ $p"; done

if (( ${#PROBLEMS[@]} > 0 )); then
  print -u2 -- "✗ 核对没过，这一族不算取证完成"
  exit 1
fi

if (( ${#FAILED[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT（$APPEARANCE）"
print -r -- "夹具留在 $FIX（核对完照片就可以删）"
