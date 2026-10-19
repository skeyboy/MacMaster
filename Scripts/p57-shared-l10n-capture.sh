#!/bin/zsh
#
# p57-shared-l10n-capture.sh — 共享层（MMUI）文案的双语实机照片（P57c）
#
# 这一族拍的是"P57 接进 `L`/`LF` 的那几句在真窗口里跟着语言档变了没有"。
# 只挑得到钩子路径的三面，其余登记成未拍（理由写在 fidelity-shell.md 的 P57 段）：
#   ✓ 合并块名：MMUI 布局层自己生成的那块（`ui.treemap.others`）
#   ✓ 回执条的两个按钮：`action.undo` + `ui.action.reveal_trash`（MMUndoToast）
#   ✗ `ui.treemap.a11y`（辅助功能标签，画面上根本不出现）、
#     `ui.category.*`（MMCategory 全仓零调用点）、
#     `ui.progress.*`（要真在跑的扫描才有那两格）、
#     `ui.action.open_system_settings`（要读不到的位置）、
#     `ui.menu.settings`（主菜单栏那一项，展开它只能合成点击——禁用）。
#
# 两块"其余"的口径不同，所以两棵夹具都要：
#   · 子项 > 96（`childCap(at: 0)` = maxChildren）→ MMUI 布局层合并，名字走表（跟语言）；
#   · 子项 > 200（`renderWindow`）→ MMDisk 模块页也合并一份，名字是模块页自己拼的中文。
#   250 那一棵让两块同框：英文档下它们一个英文一个中文，这正是"模块页那一轮还没接"的实物证据。
#
# 为什么合并块不能只靠单测：P57 把"这块不能下钻"的判据从**名字前缀**改成了显式标志，
# 而名字现在跟语言走。判据改对了没有，画面上的那块在英文档里读什么、点下去会不会进空目录，
# 只有实机照片能说。
#
# 语言档只能靠启动钩子：原生 Picker 禁用，这一路上不许合成点击。
# `MM_LANGUAGE` 会写回 UserDefaults（P56b 记的坑），所以收尾必须 `defaults delete` 那一个 key，
# 最后不带变量补拍一张——那张证的是"档已复位"，没有它下一族拍到的英文会被读成"这台机器一直是英文"。
#
# 纪律：只 kill 自己启动的 pid（记 pid，见 shot 函数）；夹具与脚本入库，中间产物留 /tmp。
#
#   ./Scripts/make-app.sh -o /tmp/mm-app-p57 -s /tmp/mm-scratch-p57        # 产物必须与源码同源
#   ./Scripts/p57-shared-l10n-capture.sh /tmp/mm-app-p57/MacMaster.app \
#       docs/verification/p57-shared-l10n-bilingual 2>&1 \
#       | tee docs/verification/p57-shared-l10n-bilingual/00-family-run.log
#   ONLY=02-en ./Scripts/p57-shared-l10n-capture.sh …    只重拍某一档
#   KEEP_FIXTURE=1 …                                      不重建夹具（默认每次重建）
#
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SETTLE=${SETTLE:-10}
TOAST_SETTLE=${TOAST_SETTLE:-5}
FIXTURE=/tmp/macmaster-p57-treemap-fixture
OVER_CAP=$FIXTURE/wide-150
OVER_WINDOW=$FIXTURE/wide-250

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p57 -s /tmp/mm-scratch-p57 重新构建再取证。"
  exit 4
fi

if [[ -z ${KEEP_FIXTURE:-} ]]; then
  ./Scripts/p57-treemap-fixture.sh >/dev/null
fi
[[ -d $OVER_CAP && -d $OVER_WINDOW ]] || {
  print -u2 -- "夹具不完整：$OVER_CAP / $OVER_WINDOW（先跑 ./Scripts/p57-treemap-fixture.sh）"; exit 2; }
cap_count=$(ls "$OVER_CAP" | wc -l | tr -d ' ')
window_count=$(ls "$OVER_WINDOW" | wc -l | tr -d ' ')

mkdir -p "$OUT"

# shot <名> <语言档|-> <等待秒> <期望> <环境变量...>
shot() {
  local name=$1 lang=$2 settle=$3 expect=$4; shift 4
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  print -r -- "# p57-shared-l10n-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   $(mm_provenance_line)" >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=disk${lang:+ MM_LANGUAGE=$lang} $*" >>"$log"
  print -r -- "# 夹具：$OVER_CAP 子项=$cap_count｜$OVER_WINDOW 子项=$window_count（cap=96、renderWindow=200）" >>"$log"
  print -r -- "# 期望：$expect" >>"$log"
  local pid
  if [[ -n $lang ]]; then
    env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=disk MM_LANGUAGE="$lang" "$@" \
        "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  else
    env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=disk "$@" \
        "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  fi
  pid=$!
  sleep "$settle"
  local wid i
  for i in {1..5}; do
    wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
          | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
    [[ -n $wid ]] && break
    sleep 3
  done
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 查了 5 次没有可见窗口（不产出空照片）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s"
}

shot 01-zh-cap        zh  $SETTLE "方块图里那块合并块读「其余 $((cap_count - 96)) 项」（MMUI 布局层生成，走表）" \
  MM_DISK_SCAN="$OVER_CAP" || true
shot 02-en-cap        en  $SETTLE "同一棵同一块，英文档应读「$((cap_count - 96)) more items」" \
  MM_DISK_SCAN="$OVER_CAP" || true
shot 03-zh-window     zh  $SETTLE "两块合并同框：模块页那块读中文「其余 $((window_count - 200)) 项」，布局层那块读中文" \
  MM_DISK_SCAN="$OVER_WINDOW" || true
shot 04-en-window     en  $SETTLE "英文档：模块页那块**仍是中文**（这一轮没接），布局层那块应是英文——中英混排是已知面，不是拍坏了" \
  MM_DISK_SCAN="$OVER_WINDOW" || true

# 只给一条路径：回执条这一档不需要确认面板，把扫描根写进 SELECT 列表只会多一行没人读的逗号。
SEL="$OVER_CAP/branch-001"
shot 05-zh-toast      zh  $TOAST_SETTLE "底部回执条：绿色对勾 +「撤回」「打开废纸篓」两个按钮（都来自 MMUndoToast）" \
  MM_DISK_SCAN="$OVER_CAP" MM_DISK_SELECT="$SEL" MM_SHOW_TOAST=1 || true
shot 06-en-toast      en  $TOAST_SETTLE "同一条回执条英文档：Undo / Open Trash；条上其余那句是模块页文案，仍应是中文" \
  MM_DISK_SCAN="$OVER_CAP" MM_DISK_SELECT="$SEL" MM_SHOW_TOAST=1 || true
shot 07-en-toast-narrow en 5 "最窄宽度 1000pt：英文按钮比中文长，看会不会把「Open Trash」截掉" \
  MM_DISK_SCAN="$OVER_CAP" MM_DISK_SELECT="$SEL" MM_SHOW_TOAST=1 MM_WINDOW_SIZE=1000x800 || true

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)
print -r -- "# 语言档落在 UserDefaults：域=$BUNDLE_ID key=app.language（跑完会 delete）"
if [[ -n $BUNDLE_ID ]]; then
  defaults delete "$BUNDLE_ID" app.language 2>/dev/null || print -r -- "  （该域本来没有 app.language，delete 空手而归）"
  print -r -- "# 复位后 defaults read：$(defaults read "$BUNDLE_ID" app.language 2>&1 | tr '\n' ' ')"
else
  print -u2 -- "⚠ 读不到 $APP 的 CFBundleIdentifier：`defaults delete` 没跑，语言档可能还留在 UserDefaults"
fi
shot 08-zh-after-reset "" $SETTLE "不带 MM_LANGUAGE：应回到中文档（这张证的是复位，不是新状态）" \
  MM_DISK_SCAN="$OVER_CAP" || true

typeset -a PROBLEMS FAILED
print -r -- ""
print -r -- "# 留痕（正向断言）：每一张都要自己说出用的是哪一档"
for f in 01-zh-cap 02-en-cap 03-zh-window 04-en-window 05-zh-toast 06-en-toast 07-en-toast-narrow; do
  lg="$OUT/$f.log"
  [[ -s $lg ]] || { FAILED+=($f); continue; }
  case $f in
    *zh-*) lang=zh-Hans ;;
    *) lang=en ;;
  esac
  line=$(grep -m1 -F "MM_LANGUAGE=$lang 已生效" "$lg" || true)
  if [[ -n $line ]]; then
    print -r -- "  ✓ $f：$line"
  else
    PROBLEMS+=("$f 没有「MM_LANGUAGE=$lang 已生效」这一行——照片无从认档（日志头 120 字：$(head -c 120 "$lg" | tr '\n' ' ')）")
  fi
done
# 08 反过来：不该有留痕行，有就说明复位没生效、又是钩子在驱动。
if [[ -s "$OUT/08-zh-after-reset.log" ]] && grep -qF 'MM_LANGUAGE=' "$OUT/08-zh-after-reset.log"; then
  PROBLEMS+=("08 那张不带变量的照片里出现了 MM_LANGUAGE 留痕 ⟹ defaults delete 没把档复位")
fi
# 钩子自己的凭据行：合并块与回执条都得在日志里留下数字，只有一句"我扫了"不算。
for f in 05-zh-toast 06-en-toast 07-en-toast-narrow; do
  [[ -s "$OUT/$f.log" ]] || continue
  trace=$(grep -m1 -F "MM_SHOW_TOAST 已画出「移入废纸篓」回执条" "$OUT/$f.log" || true)
  if [[ -n $trace ]]; then print -r -- "  ✓ $f 回执条凭据：$trace"
  else PROBLEMS+=("$f 没有「MM_SHOW_TOAST 已画出…回执条」这一行 ⟹ 选中项没建立，照片里那条回执条无从凭信"); fi
done

print -r -- ""
print -r -- "# 画面交叉核对（同屏双语必须不同，否则语言档在画面上没起作用）"
for png in "$OUT"/*.png(N); do print -r -- "  md5 $(md5 -q "$png")  $(basename "$png")"; done
typeset -a PIX_PAIRS=("01-zh-cap|02-en-cap|diff" "03-zh-window|04-en-window|diff"
                      "05-zh-toast|06-en-toast|diff")
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
    d = d.crop((left, 0, d.size[0], d.size[1]))
    r, g, b = d.split()
    hist = ImageChops.lighter(ImageChops.lighter(r, g), b).histogram()
    return above, sum(hist[9:]), peak


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
pix_lines=$(printf '%s\n' "$pix_report" | grep -c . || true)
if (( pix_lines < ${#PIX_PAIRS[@]} )); then
  PROBLEMS+=("像素比对只出了 $pix_lines 行，该出 ${#PIX_PAIRS[@]} 行（python 退出码 $pix_rc）——判据没跑完就是没过")
fi
while IFS=$'\t' read -r a b kind above maxd whole strip; do
  [[ -n $a ]] || continue
  case $above in
    missing) PROBLEMS+=("$a ↔ $b：有一张没拍出，比对无从进行"); continue ;;
    sizediff) PROBLEMS+=("$a ↔ $b 两张尺寸不同（$maxd）：不是一扇窗口的两种档，比对无意义"); continue ;;
  esac
  print -r -- "  · $a ↔ $b：内容区 $above 个可辨像素｜侧栏条（不参与判据）$strip 个｜全帧 $whole 个｜最大幅度 $maxd"
  if (( above > 0 )); then
    print -r -- "  ✓ $a ↔ $b：内容区有可辨差异 $above 个像素"
  else
    PROBLEMS+=("$a ↔ $b：内容区可辨差异 0 个像素（最大幅度 $maxd）——这一对本该不同：语言档没在界面上起作用")
  fi
done <<< "$pix_report"

for f in 01-zh-cap 02-en-cap 03-zh-window 04-en-window 05-zh-toast 06-en-toast 07-en-toast-narrow 08-zh-after-reset; do
  [[ -z ${ONLY:-} || $f == ${ONLY}* ]] || continue
  [[ -s "$OUT/$f.png" ]] || FAILED+=($f)
done

if (( ${#PROBLEMS[@]} > 0 )); then
  for p in "${PROBLEMS[@]}"; do print -u2 -- "⚠ $p"; done
  print -u2 -- "✗ 核对没过，这一族不算取证完成"
  exit 1
fi
if (( ${#FAILED[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT（$APPEARANCE）｜合并块两块 × 双语 + 回执条 × 双语 + 窄窗 + 复位"
print -r -- "夹具：$FIXTURE（留 /tmp，不入库）"
