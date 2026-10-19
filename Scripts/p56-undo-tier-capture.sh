#!/bin/zsh
#
# p56-undo-tier-capture.sh — 双语 × 五档撤回徽标的实机照片（P56c）
#
# 这一族要拍的是两件事，它们共用一张卡：
#   ① I16 把「废纸篓已清空」那一句拆成了五档（`UndoTierResolver`，MMCore）。
#      P53 已经用**真拔盘**拍过旧措辞（`docs/verification/p53-cross-volume-trash/04-*.png`），
#      本轮措辞改了，同一格必须重拍——而且这一轮要五档都在同一张卡里同框，
#      因为「撤不回来」和「不知道成因」的差别只有并列才看得出来。
#   ② 壳层文案接了 `L`/`LF`（P56b）。切换只能靠启动钩子（原生 Picker 是禁用的，
#      而这一条路上不允许合成点击），所以双语各拍一张，靠 `MM_LANGUAGE` 的留痕行认档。
#
# 五档怎么摆出来的（**合成台账**，不是真删五次）：
#   档位由「落点在不在 + 落点那块卷的身份在不在挂载集合」两问决定，这两问都只读台账里的字段，
#   所以写五条已知答案的记录就能把五档同框摆出来；逐档判据由 `UndoTierTests` 的 17 条钉死，
#   这一族负责的是"界面真的按那一档画了字"，不负责证明判据本身对不对。
#   ⚠ 这是合成：`trashVolumeUUID` 那三个字段里没有一条是这台机器真的删过什么得到的。
#     真实跨卷那一支（落点真在第二块卷上、真拔盘）在 P53 那一族，本轮不动它。
#
# 台账是用户真实的文件，所以三条纪律照 P53 抄：
#   ① 跑之前 `pgrep -x MacMaster`：有别的实例在跑就整族不跑（台账整文件覆写，会互相盖掉）；
#   ② 跑之前原样备份并记 sha，跑完（含中途失败，EXIT trap）恢复并复算 sha；
#     本轮开始前如果这文件不存在，恢复 = 删掉它；
#   ③ 备份留在 /tmp 且**不入库**：里面是用户删过的绝对路径。
#
# 还有一条 P56b 文档里写下的坑：`MM_LANGUAGE` 会**写回 UserDefaults**（不是只在本进程生效）。
# 所以这一族收尾必须 `defaults delete` 那一个 key，并且最后补拍一张"不带变量的中文档"——
# 那张照片是"档已复位"的证据，没有它，下一族拍到的英文会被读成"这台机器一直是英文"。
#
# 纪律：只 kill 自己启动的 pid；不用合成点击；夹具与脚本入库，中间产物留 /tmp。
#
#   ./Scripts/make-app.sh -o /tmp/mm-app-p56 -s /tmp/mm-scratch-p56      # 产物必须与源码同源
#   ./Scripts/p56-undo-tier-capture.sh /tmp/mm-app-p56/MacMaster.app \
#       docs/verification/p56-undo-tier-bilingual 2>&1 \
#       | tee docs/verification/p56-undo-tier-bilingual/00-family-run.log
#   ONLY=02-en ./Scripts/p56-undo-tier-capture.sh …     只重拍某一档
#   KEEP_LEDGER=1 …                                     跑完不恢复台账（只为肉眼看界面，用完手工恢复）
#
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
TRASH_FIXTURE=/tmp/mm-p56-trash
LEDGER="$HOME/Library/Application Support/MacMaster/trash-history.json"
BACKUP=/tmp/mm-p56-ledger-backup.json
SETTLE=${SETTLE:-9}

# 落点"读得到"这一问走的就是 `fileExists(atPath:)`（`UndoAvailability.swift:114`），
# 所以夹具只需要一个真的存在的路径，不需要它真的在废纸篓里。
mkdir -p "$TRASH_FIXTURE/.Trashes/501"
print -r -- "p56 合成落点，不是用户删过的东西" >"$TRASH_FIXTURE/.Trashes/501/preserved.txt"

BOOT_UUID=$(diskutil info / 2>/dev/null | awk -F': ' '/Volume UUID/ {print $2}')
[[ -n $BOOT_UUID ]] || { print -u2 -- "✗ 读不到启动卷的 Volume UUID，合成台账就没有'还挂着的卷'这一档"; exit 2; }
DETACHED_UUID=P56-FAKE-DETACHED-000000000000

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p56 -s /tmp/mm-scratch-p56 重新构建再取证。"
  exit 4
fi

ledger_sha() { [[ -f $LEDGER ]] && shasum -a 256 "$LEDGER" | cut -c1-16 || print -r -- 无文件; }
ledger_entries() {
  [[ -f $LEDGER ]] || { print -r -- 0; return; }
  python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$LEDGER" 2>/dev/null || print -r -- 读不出
}

# ── 合成台账：五条记录，从上到下正好是五档 ──
write_fixture_ledger() {
  LEDGER=$LEDGER BOOT_UUID=$BOOT_UUID DETACHED_UUID=$DETACHED_UUID \
  TRASH_LIVE=$TRASH_FIXTURE/.Trashes/501/preserved.txt \
  python3 - <<'PY'
import json, os, time, uuid

# Date 在这个编码策略下是**reference date 秒**（2001-01-01 起算），不是 1970：
# 写成 ISO8601 字符串会当场解码失败，那正是"读不到台账"的样子（UndoTierTests 里踩过）。
REF = 978307200
now = time.time() - REF
boot = os.environ["BOOT_UUID"]
detached = os.environ["DETACHED_UUID"]
live = os.environ["TRASH_LIVE"]
ledger = os.environ["LEDGER"]

def op(age, size, trash_path, vol_uuid, undone=False, nfiles=1):
    files = [{"originalPath": "/tmp/mm-p56-original/%d/thing-%d.txt" % (size, i),
              "trashPath": trash_path, "size": size, "trashVolumeUUID": vol_uuid}
             for i in range(nfiles)]
    if vol_uuid is None:                      # 新增字段之前的老记录：整个键不存在
        for f in files:
            del f["trashVolumeUUID"]
    return {"version": 1, "operation": {
        "id": str(uuid.uuid4()), "timestamp": now - age, "files": files,
        "failures": [], "isUndone": undone}}

rows = [
    op(60,        1288490188, live,        boot),                 # 落点在且还挂着 → 撤回按钮
    op(600,        524288000, None,        boot, undone=True),    # 已撤回
    op(1800,      1258291200, "/tmp/mm-p56-gone/on-other-vol",
                detached),                                        # 那块卷不在挂载集合 → 盘已取下
    op(7200,         92274688, "/tmp/mm-p56-gone/in-trash",
                boot),                                            # 卷还挂着而落点没了 → 废纸篓已清空
    op(86400,        4194304, "/tmp/mm-p56-gone/legacy",
                None),                                            # 老记录没有卷身份 → 无法撤回
]
os.makedirs(os.path.dirname(ledger), exist_ok=True)
with open(ledger, "w") as fh:
    json.dump(rows, fh, ensure_ascii=False)
print("合成台账已写入：五条记录，档位自上而下 = restorable/undone/volumeDetached/trashEmptied/unknown")
PY
}

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

# shot <名> <语言档|-> <宽x高> <期望>
shot() {
  local name=$1 lang=$2 size=$3 expect=$4
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  print -r -- "# p56-undo-tier-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   $(mm_provenance_line)" >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=dashboard MM_WINDOW_SIZE=$size${lang:+ MM_LANGUAGE=$lang}" >>"$log"
  print -r -- "# 台账：sha=$(ledger_sha) 条目=$(ledger_entries)（本轮为合成五档，见脚本头）" >>"$log"
  print -r -- "# 启动卷 UUID=$BOOT_UUID｜合成'已取下的那块卷' UUID=$DETACHED_UUID" >>"$log"
  print -r -- "# 期望：$expect" >>"$log"
  local pid
  if [[ -n $lang ]]; then
    env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=dashboard MM_WINDOW_SIZE="$size" \
        MM_LANGUAGE="$lang" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  else
    env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=dashboard MM_WINDOW_SIZE="$size" \
        "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  fi
  pid=$!
  sleep "$SETTLE"
  local wid i
  for i in {1..5}; do
    wid=$(main_window_id "$pid" "$log" || true)
    [[ -n $wid ]] && break
    sleep 3
  done
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 查了 5 次，标题为 MacMaster 的主窗口不是正好一扇（见 $log 的 # windows 行）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid"
}

typeset -a PROBLEMS FAILED
LEDGER_RESTORE_NEEDED=0
LEDGER_WAS_ABSENT=0

restore_ledger() {
  if [[ ${KEEP_LEDGER:-0} == 1 ]]; then
    print -r -- "KEEP_LEDGER=1：台账没恢复，现在里面是本轮那五条合成记录（$(ledger_entries) 条）。看完记得手工恢复：cp -p $BACKUP $LEDGER"
    return 0
  fi
  (( LEDGER_RESTORE_NEEDED )) || return 0
  if pgrep -x MacMaster >/dev/null 2>&1; then
    print -u2 -- "⚠ 还有 MacMaster 实例在跑，台账恢复先不执行（否则它一保存就把恢复盖回去）：先关掉再手工恢复"
    return 0
  fi
  if (( LEDGER_WAS_ABSENT )); then
    rm -f "$LEDGER"
    print -r -- "✅ 台账已恢复成本轮开始前的「不存在」"
    LEDGER_RESTORE_NEEDED=0
    return 0
  fi
  cp -p "$BACKUP" "$LEDGER"
  if [[ $(ledger_sha) == "$LEDGER_SHA_BEFORE" ]]; then
    print -r -- "✅ 台账已恢复：sha=$(ledger_sha) 与本轮开始前逐字相同（条目=$(ledger_entries)）"
  else
    print -u2 -- "⚠ 台账恢复后 sha=$(ledger_sha)，本轮开始前是 $LEDGER_SHA_BEFORE——请人工对账，备份仍在 $BACKUP"
  fi
}
trap restore_ledger EXIT

if pgrep -x MacMaster >/dev/null 2>&1; then
  print -u2 -- "✗ 已经有 MacMaster 实例在跑（$(pgrep -xl MacMaster | tr '\n' ' ')）：台账是整文件覆写，先退出那一个。"
  exit 3
fi
mkdir -p "$OUT"
LEDGER_SHA_BEFORE=$(ledger_sha)
if [[ ! -f $LEDGER ]]; then
  LEDGER_WAS_ABSENT=1
else
  cp -p "$LEDGER" "$BACKUP" || { print -u2 -- "✗ 台账备份失败，整族不跑"; exit 3; }
fi
LEDGER_RESTORE_NEEDED=1
print -r -- "# 台账（本轮开始前）：sha=$LEDGER_SHA_BEFORE 条目=$(ledger_entries) 路径=$LEDGER"
write_fixture_ledger
print -r -- "# 台账（写入夹具后）：sha=$(ledger_sha) 条目=$(ledger_entries)"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)
print -r -- "# 语言档落在 UserDefaults：域=$BUNDLE_ID key=app.language（跑完会 delete）"

shot 01-zh-wide    zh 1400x1100 "整页中文：这张卡五行自上而下＝「撤回」按钮 / 已撤回 / 盘已取下 / 废纸篓已清空 / 无法撤回" \
  || FAILED+=(01-zh-wide)
shot 02-en-wide    en 1400x1100 "同一张卡整页英文：Undo / Undone / Disk Removed / Trash Emptied / Can't Undo（措辞以表 :510-515 为准）" \
  || FAILED+=(02-en-wide)
shot 03-zh-narrow  zh 1000x900  "最窄宽度、中文：主标题 + 徽标同屏不许截掉徽标那四个字" \
  || FAILED+=(03-zh-narrow)
shot 04-en-narrow  en 1000x900  "最窄宽度、英文：英文比中文长，最可能截的就是这一档" \
  || FAILED+=(04-en-narrow)

# 复位：删掉 key，再不带变量拍一张——这张是"档真的回到中文"的证据。
if [[ -n $BUNDLE_ID ]]; then
  defaults delete "$BUNDLE_ID" app.language 2>/dev/null || print -r -- "  （该域本来没有 app.language，delete 空手而归）"
  print -r -- "# 复位后 defaults read：$(defaults read "$BUNDLE_ID" app.language 2>&1 | tr '\n' ' ')"
else
  PROBLEMS+=("读不到 $APP 的 CFBundleIdentifier：`defaults delete` 没跑，语言档可能还留在 UserDefaults")
fi
shot 05-zh-after-reset "" 1400x1100 "不带 MM_LANGUAGE：应回到中文档（这一张证的是复位，不是新状态）" \
  || FAILED+=(05-zh-after-reset)

# ── 判据 ──
print -r -- ""
print -r -- "# 留痕（正向断言，不看缺席）：每一张都要自己说出用的是哪一档"
for f in 01-zh-wide 02-en-wide 03-zh-narrow 04-en-narrow; do
  lg="$OUT/$f.log"
  [[ -s $lg ]] || continue
  case $f in
    *-zh-*) lang=zh-Hans ;;
    *-en-*) lang=en ;;
  esac
  line=$(grep -m1 -F "MM_LANGUAGE=$lang 已生效" "$lg" || true)
  if [[ -n $line ]]; then
    print -r -- "  ✓ $f：$line"
  else
    PROBLEMS+=("$f 没有「MM_LANGUAGE=$lang 已生效」这一行——照片无从认档（该行日志头 120 字：$(head -c 120 "$lg" | tr '\n' ' ')）")
  fi
done
# 05 反过来：这一张**不该**有留痕行，因为有留痕就说明复位没生效、又是钩子在驱动。
if [[ -s $OUT/05-zh-after-reset.log ]] && grep -qF 'MM_LANGUAGE=' "$OUT/05-zh-after-reset.log"; then
  PROBLEMS+=("05 那张不带变量的照片里出现了 MM_LANGUAGE 留痕 ⟹ defaults delete 没把档复位")
fi

print -r -- ""
print -r -- "# 画面交叉核对"
for png in "$OUT"/*.png(N); do print -r -- "  md5 $(md5 -q "$png")  $(basename $png)"; done
typeset -a PIX_PAIRS=("01-zh-wide|02-en-wide|diff" "02-en-wide|05-zh-after-reset|diff"
                      "03-zh-narrow|04-en-narrow|diff")
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
    missing) print -r -- "  – $a ↔ $b：有一张没拍出，交给「没拍出照片」那一条报"; continue ;;
    sizediff) PROBLEMS+=("$a ↔ $b 两张尺寸不同（$maxd）：不是一扇窗口的两种状态，比对无意义"); continue ;;
  esac
  print -r -- "  · $a ↔ $b：内容区 $above 个可辨像素｜侧栏条（不参与判据）$strip 个｜全帧 $whole 个｜最大幅度 $maxd"
  if (( above > 0 )); then
    print -r -- "  ✓ $a ↔ $b：内容区有可辨差异 $above 个像素"
  else
    PROBLEMS+=("$a ↔ $b：内容区可辨差异 0 个像素（最大幅度 $maxd）——这一对本该不同：语言档没在界面上起作用")
  fi
done <<< "$pix_report"

for f in 01-zh-wide 02-en-wide 03-zh-narrow 04-en-narrow 05-zh-after-reset; do
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

print -r -- "→ $OUT（$APPEARANCE）｜五档同框 + 双语 + 复位各一张"
print -r -- "合成落点夹具：$TRASH_FIXTURE（留 /tmp，不入库）"
