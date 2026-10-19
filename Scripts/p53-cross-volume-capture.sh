#!/bin/zsh
# P53 前置量：跨卷那次删除**落在哪块卷上**，以及拔掉盘之后「最近操作」那一行长成什么样。
#
# 这是 `docs/analysis/uninstaller-app-body-risk.md` §6 第二条欠的那张实拍——
# 建议 2 的文案（「卸了外接盘里的应用，残留/撤回怎么走」）落地前必须先有它。
# 判据来自代码（现读）：
#   · `Packages/MMCore/Sources/MMCore/FileTrashService.swift:45` 落点由 `FileManager.trashItem`
#     自己决定并把 `resultingItemURL` 写进台账；
#   · `:123` 移走那一刻就把落点所在卷的 `volumeUUIDString` 记进台账（`volumeUUIDStep` 在 `:45`）；
#   · 界面那一侧（**I16 已落地，P56 现读重指**）：`Sources/MacMaster/MainWindow.swift:707` 按
#   `tier(mountedVolumeUUIDs:)` 分五档，`:730` 起是 `undoTrailing`——有按钮、已撤回、
#   **盘已取下**、废纸篓已清空、无法撤回各一支。
#   I16 之前这里只有一句「废纸篓已清空」，所以本族当年（P53）拍到的正是那句假话；
#   现在这一族重拍的是**改判之后**：拔盘那一档应当印「盘已取下」，而 05 重挂后按钮回来。
#   台账里那条记录有没有卷身份，决定它落 `volumeDetached` 还是 `unknown`——所以 04 这一档
#   同时是"删除当时取到的 UUID 活到了拔盘之后"的证。
#
# 五档（顺序不能打乱，卷的挂/卸就在中间）：
#   01 卸载页列表（挂载中，删除**前**）：外接卷那一行进得来、详情面板给删除按钮
#   02 卸载页 self-echo（真删一次，`MM_UNINSTALL_SELF_ECHO=1`）：拍到那条 15 秒 toast
#   —— 读落点：台账头一条的 `trashPath` + 卷内 `.Trashes` 目录 ——
#   03 概览「最近操作」（挂载中）：这一行该有「撤回」按钮
#   04 概览同一张卡（**已拔盘**）：预期按钮消失、换成「盘已取下」（I16 之前的措辞是「废纸篓已清空」）
#   05 概览同一张卡（**重新挂上**）：预期按钮回来 ⟹ 从头到尾没人倒过废纸篓
#
# 机械判据在哪一侧：03/04/05 这一族**不拿像素当判据的主体**。
# 概览页是活数页（`storageCard` 的可用空间、`loadCard` 的即时负载、「最近操作」那行的相对时间
# "刚刚 / 2 分钟前"都随墙钟变），同一页隔几分钟的两张连拍必然有可辨差异——
# P49 给概览页页脚写过同一条。所以：
#   · 「拔盘之后按钮消失」由台账 + 文件系统这一侧证死：
#     `test -e "$trashPath"` 就是 `canUndo` 里那一句的同一口径（同一个 uid、同一台机、
#     同样的 TCC 姿态），挂载中为真、拔盘为假、重挂又为真；
#   · 像素只跑一条 `01↔02`（卸载页在夹具下是静态页）与一条 `03↔04`（只在"落点在这块卷上"
#     那一支才要求有差异）；其余只列数不作判据。
#   · 徽标那四个字具体印成什么，由人眼读照片——这一族的照片就是给人读这一句的。
#
# ⚠ 这一族**会往用户真实的删除历史台账里写一条**，而且是先量出来才知道躲不掉：
#   原本打算用 `HOME=/tmp/…` 把整个进程隔到假 home，实测**无效**——
#   macOS 的 Foundation 在 `.userDomainMask` 这一路不认 `HOME`：
#   `env HOME=/tmp/mm-p53-probe-home swift …` 打出来仍是 `NSHomeDirectory=/Users/lee`。
#   所以台账（`~/Library/Application Support/MacMaster/trash-history.json`）躲不过。
#   代价用两条压到可核对的最小：
#     ① 跑之前先 `pgrep -x MacMaster`：有别的实例在跑就**整族不跑**。
#        台账是整文件覆写（`TrashHistoryStore.save` 用 `.atomic` 全量重写），
#        两个进程各持一份内存历史，后写的那一份会把前一份盖掉——这条比"多一条记录"贵得多。
#     ② 跑之前把台账原样备份并记 sha，跑完（含中途失败，走 EXIT trap）恢复并复算 sha。
#        恢复的是"我自己这一笔写进去之前"的字节，不是删用户的东西。
#        备份文件留在 /tmp 且**不入库**：里面是用户删过的绝对路径。
#   卷那一侧只动夹具（`/tmp` 下那块 .dmg），用户的应用与真盘一点不碰。
#
# 纪律（照 P52/P49 抄）：只 kill 自己启动的 pid；只 detach 自己那一个挂载点且不 -force；
# 不用合成点击（原生按钮点不了，所以 05 那一步"撤回回来"是靠落点仍在 + 人眼读照片，不是真按一次）；
# 夹具与脚本入库，中间产物留 /tmp。
#
#   ./Scripts/p53-cross-volume-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p53-cross-volume-capture.sh /tmp/mm-app-p53/MacMaster.app docs/verification/p53-cross-volume-trash \
#     2>&1 | tee docs/verification/p53-cross-volume-trash/00-family-run.log
#   ONLY=04 ./Scripts/p53-cross-volume-capture.sh …      只重拍 04 那一档
#   SKIP_LEDGER=1 …                                      跳过写台账的那两档（02/03/04/05 全不跑）
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
MP=${MP:-/tmp/mm-p53-mnt}
SEED=${SEED_APP:-AaaP53CrossVolume}
FIXTURE=./Scripts/p53-cross-volume-fixture.sh
LEDGER="$HOME/Library/Application Support/MacMaster/trash-history.json"
BACKUP=/tmp/mm-p53-ledger-backup.json
SETTLE=${SETTLE:-10}
DELETE_WAIT=${DELETE_WAIT:-60}

[[ -d $MP ]] || { print -u2 -- "✗ 挂载点不存在：$MP（先 ./Scripts/p53-cross-volume-fixture.sh create && … mount）"; exit 2; }
MP_REAL=$(cd "$MP" && pwd -P)
# 用户废纸篓的 realpath：读不到就留空，落点判定里那一档自动不参与（见下面那段注释）。
HOME_TRASH=$(cd "$HOME/.Trash" 2>/dev/null && pwd -P) || HOME_TRASH=
[[ -e "$MP_REAL/Applications/$SEED.app" ]] || {
  print -u2 -- "✗ 卷里没有 Applications/$SEED.app（挂载点里看到的是：$(ls -1 "$MP_REAL/Applications" 2>/dev/null | tr '\n' ' ')）"
  print -u2 -- "  这一族每次都从「那个应用还在卷上」起步，而跑完台账会恢复成本轮开始前的字节（外面看不出删过什么）："
  print -u2 -- "  要重拍任何一档，先 ./Scripts/p53-cross-volume-fixture.sh create && ./Scripts/p53-cross-volume-fixture.sh mount 重建夹具。"
  exit 2; }

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p53 -s /tmp/mm-scratch-p53 重新构建再取证。"
  exit 4
fi

# 台账三件读数：sha、字节、条目数。全部现读，写进每一份 log 的头。
ledger_sha() { [[ -f $LEDGER ]] && shasum -a 256 "$LEDGER" | cut -c1-16 || print -r -- 无文件; }
ledger_bytes() { [[ -f $LEDGER ]] && stat -f %z "$LEDGER" || print -r -- 0; }
ledger_entries() {
  [[ -f $LEDGER ]] || { print -r -- 0; return; }
  python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$LEDGER" 2>/dev/null || print -r -- 读不出
}
# 台账头一条（`record(.inserted)` 插在 0 号位，所以最新那条就是 head[0]）。
ledger_head() {
  [[ -f $LEDGER ]] || { print -r -- "（台账不存在）"; return; }
  python3 - "$LEDGER" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if not d:
    print("（台账是空的）")
    sys.exit(0)
op = d[0]["operation"]
print("id=%s isUndone=%s moved=%d failures=%d" % (
    op.get("id"), op.get("isUndone"), len(op.get("files") or []), len(op.get("failures") or [])))
for f in (op.get("files") or []):
    print("  originalPath=%s" % f.get("originalPath"))
    print("  trashPath=%s" % f.get("trashPath"))
    print("  size=%s" % f.get("size"))
for f in (op.get("failures") or []):
    print("  FAILURE path=%s message=%s code=%s" % (f.get("path"), f.get("message"), f.get("code")))
PY
}

mkdir -p "$OUT"
wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]]; }

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

# shot <文件名> <MM_OPEN_MODULE> <期望说明> [额外 KEY=VAL ...]
#   额外参数里给 WAIT_DELETE=1 时：不等固定秒数，改成轮询「本体是否已从卷上消失」，
#   一消失立刻拍——那一格是 15 秒的 toast，固定 sleep 拍法要么拍早了（还没删）
#   要么拍晚了（toast 已经走完），而且耗时本身要能写进日志。
shot() {
  local name=$1 module=$2 expect=$3; shift 3
  wants $name || return 0
  local log="$OUT/$name.log"
  local -a extra=("$@")
  local SIZE=1400x1000
  [[ $module == dashboard ]] && SIZE=1400x1100
  rm -f "$OUT/$name.png"
  # 拔盘之后 `$MP_REAL` 整个不存在，`df`/`mount` 那两格会读空——空着读起来像脚本坏了，
  # 所以这里显式写成「未挂载」，04 那一档的日志才只有一种读法。
  local volDev mountLine
  # 两处都要 `|| true`：`grep`/`df` 在拔盘之后按定义读不到东西，而它们的退出码
  # 会顺着赋值语句把 `set -e` 点着——那一档就变成"脚本挂了"而不是"盘拔了"。
  if [[ -d $MP_REAL ]]; then volDev=$(df -P "$MP_REAL" 2>/dev/null | awk 'NR==2 {print $1}') || volDev=读不到
  else volDev=未挂载; fi
  mountLine=$(mount | grep -F " on $MP_REAL (" | head -1) || mountLine=未挂载
  print -r -- "# p53-cross-volume-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   $(mm_provenance_line)" >>"$log"
  print -r -- "# 卷：$MP_REAL（$volDev）｜主目录卷：$(df -P "$HOME" | awk 'NR==2 {print $1}')｜挂载行：${mountLine:-未挂载}" >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=$module MM_WINDOW_SIZE=$SIZE ${extra[*]}" >>"$log"
  print -r -- "# 台账（拍前）：sha=$(ledger_sha) 条目=$(ledger_entries) 字节=$(ledger_bytes)" >>"$log"
  print -r -- "# 期望：$expect" >>"$log"
  local pid waited=0
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE="$module" MM_WINDOW_SIZE="$SIZE" \
      ${extra[@]} \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  pid=$!
  if [[ -n ${extra[(r)WAIT_DELETE=1]} ]]; then
    # 轮询到本体消失，最长 $DELETE_WAIT 秒
    while (( waited < DELETE_WAIT )); do
      [[ -e "$MP_REAL/Applications/$SEED.app" ]] || break
      sleep 2; (( waited += 2 ))
    done
    print -r -- "# 删除等待：${waited}s（本体已从卷上消失 = $([[ -e "$MP_REAL/Applications/$SEED.app" ]] && echo 否 || echo 是)）" >>"$log"
    sleep 2
  else
    sleep "$SETTLE"
  fi
  local wid i
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
  print -r -- "# 台账（拍后）：sha=$(ledger_sha) 条目=$(ledger_entries) 字节=$(ledger_bytes)" >>"$log"
  print -r -- "✅ $name windowid=$wid"
}

# 卷内废纸篓的读数：`.Trashes` 是卷自己那一侧的落点，只有挂上才读得到。
# 实测这一族的第一个坑就在这里：`.Trashes` 的权限是 `d-wx--x--t`（属主 501，**没有 r 位**），
# 所以 `ls -1R .Trashes` 直接 "Permission denied"，而 `test -e .Trashes/501/<名>.app` 是真的——
# 缺 r 挡的是"列目录"，x 位留着"按名字走进去"。`canUndo` 问的正是后者
# （`FileTrashService.swift:310-315` 用 `fileExists(atPath:)`），所以那一格照样判"可撤回"。
# 因此这里两个都要印：整目录的权限位（解释为什么列不出来）+ 按 uid 子目录点名（证东西真在里面）。
volume_trash_listing() {
  local label=$1 trashpath=${2:-}
  print -r -- "--- .Trashes（$label）---"
  if [[ ! -d "$MP_REAL/.Trashes" ]]; then
    print -r -- "（$MP_REAL/.Trashes 不存在）"
    return
  fi
  ls -ldn "$MP_REAL/.Trashes" 2>&1 | sed 's/^/  权限位：/'
  # 上一轮实测的坑：`for d in "$MP_REAL"/.Trashes/*(N/)` 一条都不出——glob 要读父目录，
  # 而 `.Trashes` 恰好没有 r 位。缺 r 挡的是"列目录"，x 位留着"按名字走进去"，
  # 所以这里点名 uid 那一级（外加 root 那一档，换机器时废纸篓可能落在它名下）。
  local uid_dir uid
  uid=$(id -u)
  for uid_dir in "$MP_REAL/.Trashes/$uid" "$MP_REAL/.Trashes/root"; do
    [[ -d $uid_dir ]] || continue
    print -r -- "  $(basename "$uid_dir")：$(ls -1 "$uid_dir" 2>&1 | tr '\n' ' ')"
  done
  if [[ -n $trashpath ]]; then
    print -r -- "  点名落点：$(ls -ldn "$trashpath" 2>&1 | tr '\n' ' ')"
    print -r -- "  落点实占：$(du -sk "$trashpath" 2>&1 | awk 'NR==1 {print $1" KB"}')"
  fi
}

typeset -a PROBLEMS
typeset -a FAILED
LEDGER_RESTORE_NEEDED=0
LEDGER_WAS_ABSENT=0
LANDS=未知
TRASH_PATH=''
ORIGINAL_PATH=''

restore_ledger() {
  (( LEDGER_RESTORE_NEEDED )) || return 0
  if pgrep -x MacMaster >/dev/null 2>&1; then
    print -u2 -- "⚠ 还有 MacMaster 实例在跑，台账恢复先不执行（否则它一保存就把恢复盖回去）：先关掉再手工恢复"
    return 0
  fi
  # 本轮开始前根本没有这个文件：那这一路唯一的正确恢复就是把它删回不存在。
  if (( LEDGER_WAS_ABSENT )); then
    rm -f "$LEDGER"
    print -r -- "✅ 台账已恢复成本轮开始前的「不存在」（本轮开始前它就不在，见脚本头部那条说明）"
    LEDGER_RESTORE_NEEDED=0
    return 0
  fi
  local before after
  before=$(ledger_sha)
  cp -p "$BACKUP" "$LEDGER"
  after=$(ledger_sha)
  LEDGER_RESTORE_NEEDED=0
  if [[ $after == "$LEDGER_SHA_BEFORE" ]]; then
    print -r -- "✅ 台账已恢复：sha=$after 与本轮开始前逐字相同（字节=$(ledger_bytes)，条目=$(ledger_entries)）"
  else
    print -u2 -- "⚠ 台账恢复后 sha=$after，本轮开始前是 $LEDGER_SHA_BEFORE（before-restore=$before）——请人工对账：备份仍在 $BACKUP"
  fi
}
trap restore_ledger EXIT

# ── 前置：写台账这一族必须独占那个文件 ──
LEDGER_SHA_BEFORE=$(ledger_sha)
LEDGER_ENTRIES_BEFORE=$(ledger_entries)
if pgrep -x MacMaster >/dev/null 2>&1; then
  print -u2 -- "✗ 已经有 MacMaster 实例在跑（$(pgrep -xl MacMaster | tr '\n' ' ')）：台账是整文件覆写，两个实例各写各的会互相盖掉。先退出那一个再跑这一族。"
  exit 3
fi
if [[ ! -f $LEDGER ]]; then
  print -u2 -- "⚠ 台账当前不存在（$(ledger_entries) 条）：本轮会新建它，恢复办法是跑完删掉这个文件。"
  LEDGER_WAS_ABSENT=1
  LEDGER_RESTORE_NEEDED=1
else
  cp -p "$LEDGER" "$BACKUP" || { print -u2 -- "✗ 台账备份失败，整族不跑"; exit 3; }
  LEDGER_RESTORE_NEEDED=1
fi
print -r -- "# 台账（本轮开始前）：sha=$LEDGER_SHA_BEFORE 条目=$LEDGER_ENTRIES_BEFORE 字节=$(ledger_bytes) 路径=$LEDGER"
print -r -- "# 备份：$BACKUP（含用户删过的绝对路径，只留 /tmp，不入库）"

if [[ ${SKIP_LEDGER:-0} == 1 ]]; then
  print -r -- "SKIP_LEDGER=1：只拍 01（删除前的列表），不写台账。"
  shot 01-uninstall-list-before uninstaller "外接卷那一行进得来、详情面板给删除按钮" \
       MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$MP_REAL" MM_UNINSTALL_SELECT="$SEED" MM_UNINSTALL_CONFIRM_MODE=none \
    || FAILED+=(01-uninstall-list-before)
  exit 0
fi

# ── 01 / 02：卸载页（挂载中）──
shot 01-uninstall-list-before uninstaller "外接卷那一行进得来、详情面板给删除按钮（两档删除入口都在）" \
     MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$MP_REAL" MM_UNINSTALL_SELECT="$SEED" MM_UNINSTALL_CONFIRM_MODE=none \
  || FAILED+=(01-uninstall-list-before)
shot 02-uninstall-self-echo-delete uninstaller "self-echo 真删一次：那一行从列表消失、底部出现 15 秒「移入废纸篓」toast" \
     MM_UNINSTALL_CONFIRM_FIXTURE_HOME="$MP_REAL" MM_UNINSTALL_SELECT="$SEED" MM_UNINSTALL_CONFIRM_MODE=none \
     MM_UNINSTALL_SELF_ECHO=1 WAIT_DELETE=1 \
  || FAILED+=(02-uninstall-self-echo-delete)

# ── 读落点：这一条是本族第一问的答案 ──
# 先从台账里把这一笔的两个路径取出来，再打印卷那一侧的读数：
# `volume_trash_listing` 要点名落点（`.Trashes` 没有 r 位，glob 不出来，只能按名字问），
# 而那个名字就在台账里，所以顺序不能反。
ORIGINAL_PATH=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));f=d[0]["operation"]["files"];print(f[0]["originalPath"] if f else "")' "$LEDGER" 2>/dev/null || true)
TRASH_PATH=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));f=d[0]["operation"]["files"];print(f[0].get("trashPath") or "")' "$LEDGER" 2>/dev/null || true)

{
  print -r -- "# 落点读数 $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag   $(mm_provenance_line)"
  print -r -- "台账（本轮开始前）：sha=$LEDGER_SHA_BEFORE 条目=$LEDGER_ENTRIES_BEFORE"
  print -r -- "台账（现在）：sha=$(ledger_sha) 条目=$(ledger_entries) 字节=$(ledger_bytes)"
  print -r -- "台账头一条："
  ledger_head | sed 's/^/  /'
  print -r -- "主目录卷=$(df -P "$HOME" | awk 'NR==2 {print $1}')  挂载卷=$(df -P "$MP_REAL" | awk 'NR==2 {print $1}')  ⟹ 跨卷成立=$([[ $(df -P "$HOME" | awk 'NR==2 {print $1}') != $(df -P "$MP_REAL" | awk 'NR==2 {print $1}') ]] && echo 是 || echo 否)"
  volume_trash_listing "挂载中" "$TRASH_PATH"
  print -r -- "卷内 Applications：$(ls -1 "$MP_REAL/Applications" 2>/dev/null | tr '\n' ' ')"
} >"$OUT/00-landing-reading.log" 2>&1

if [[ -z $TRASH_PATH ]]; then
  PROBLEMS+=("台账头一条里没有 trashPath（originalPath=$ORIGINAL_PATH）：删除没走通，03/04/05 三档没有对象可拍。头一条全文：$(ledger_head | tr '\n' '｜')")
  print -u2 -- "✗ 删除没走通，后面的拔盘三档不拍"
  exit 1
fi
# 落点归属：只按字面前缀比，且**主目录废纸篓那一档要先量得到路径才参与判定**。
# 拿 `case` 的模式位去放 `$(cd ~/.Trash && pwd -P)` 是个陷阱：本机没有「完全磁盘访问」时
# 那条 `cd` 直接失败，命令代换给出空串，模式就退化成 `""*`＝`*`，什么路径都能被判成"落在用户废纸篓"。
if [[ $TRASH_PATH == "$MP_REAL"* ]]; then
  LANDS='卷内的 .Trashes'
elif [[ -n $HOME_TRASH && $TRASH_PATH == "$HOME_TRASH"* ]]; then
  LANDS='用户主目录的 .Trash'
else
  LANDS="别处（$TRASH_PATH）"
fi
print -r -- "# 落点判定：$LANDS" >>"$OUT/00-landing-reading.log"
print -r -- "# 落点在不在这一问的复现（test -e 与 FileTrashService.swift:310-315、UndoAvailability.swift:114 同一条问句）：挂载中=$([[ -e $TRASH_PATH ]] && echo 真 || echo 假)" >>"$OUT/00-landing-reading.log"
[[ $ORIGINAL_PATH == "$MP_REAL/Applications/$SEED.app" ]] || PROBLEMS+=("台账头一条的 originalPath=$ORIGINAL_PATH 不是本轮那个夹具应用（$MP_REAL/Applications/$SEED.app）——那一行不是我们这一笔写的，03/04/05 拍的是用户别的历史")
[[ -e $TRASH_PATH ]] || PROBLEMS+=("落点 $TRASH_PATH 当场就读不到：03 那一档拍出来会是徽标而不是按钮，后面 04 的「变了」就没有对照")

# ── 03：挂载中，这张卡该有按钮 ──
shot 03-dashboard-undo-button dashboard "这一行右侧是「撤回」按钮（落点 $TRASH_PATH 当场可读）" \
  || FAILED+=(03-dashboard-undo-button)

# ── 拔盘 ──
print -r -- "--- 拔盘 $(date '+%H:%M:%S') ---" >>"$OUT/00-landing-reading.log"
$FIXTURE detach >>"$OUT/00-landing-reading.log" 2>&1 || PROBLEMS+=("detach 失败（有进程占着这一卷？脚本不 -force）")
print -r -- "拔盘后：挂载行=$(mount | grep -F " on $MP_REAL (" | head -1 || echo 已无)" >>"$OUT/00-landing-reading.log"
print -r -- "拔盘后 test -e 落点=$([[ -e $TRASH_PATH ]] && echo 真 || echo 假)  ⟹ 档位该是 $([[ -e $TRASH_PATH ]] && echo 可撤回（按钮） || echo 「盘已取下」徽标（台账那条带卷身份，见 FileTrashService.swift:123）)" >>"$OUT/00-landing-reading.log"

shot 04-dashboard-after-detach dashboard "同一张卡、同一行：预期「撤回」按钮换成「盘已取下」徽标（I16 改判后），而谁也没倒过垃圾" \
  || FAILED+=(04-dashboard-after-detach)

# ── 重新挂上 ──
print -r -- "--- 重新挂上 $(date '+%H:%M:%S') ---" >>"$OUT/00-landing-reading.log"
EXPECT_APP=0 $FIXTURE mount >>"$OUT/00-landing-reading.log" 2>&1 || PROBLEMS+=("重新挂载失败")
volume_trash_listing "重新挂上后" "$TRASH_PATH" >>"$OUT/00-landing-reading.log"
print -r -- "重挂后 test -e 落点=$([[ -e $TRASH_PATH ]] && echo 真 || echo 假)" >>"$OUT/00-landing-reading.log"

shot 05-dashboard-remounted dashboard "落点又读得到 ⟹ 按钮回来；这一档证的是「从头到尾没人倒过废纸篓」" \
  || FAILED+=(05-dashboard-remounted)

# ── 判据 ──
print -r -- ""
print -r -- "# 点名留痕（P49 那一条：正向断言，不看缺席）"
for name in 01-uninstall-list-before 02-uninstall-self-echo-delete; do
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  line=$(grep -m1 -E "MM_UNINSTALL_SELECT=$SEED 已点名到 .*/Applications/$SEED\.app$" "$lg" || true)
  if [[ -n $line ]]; then
    print -r -- "  ✓ $name：$line"
  else
    PROBLEMS+=("$name 没有「已点名到 …/Applications/$SEED.app」这一行（实际留痕：$(grep -m1 -E "^MM_UNINSTALL_SELECT=$SEED" "$lg" || echo 一条都没有)）")
  fi
done

# 落点这一侧的机械判据：拔盘前后那一句 `test -e` 必须翻面（只在"落点在这块卷上"那一支成立）。
if [[ $LANDS == 卷内* ]]; then
  if grep -q "^拔盘后 test -e 落点=真" "$OUT/00-landing-reading.log"; then
    PROBLEMS+=("落点在卷上但拔盘后仍读得到 $TRASH_PATH：挂载没真的断开，04 那张照片拍的还是挂载中的状态")
  else
    # 这里不能用反引号包 `canUndo`：双引号里的反引号是命令代换，实测打印时直接
    # `command not found: canUndo`，句子里那个词被吃掉（照片与 log 会少一个主语）。
    print -r -- "  ✓ 拔盘后落点读不到 ⟹ 档位走 notReadable 那一支，而落点那块卷的身份不在挂载集合 ⟹ 画面上是「盘已取下」徽标"
  fi
  if grep -q "^重挂后 test -e 落点=假" "$OUT/00-landing-reading.log"; then
    PROBLEMS+=("重新挂上后落点反而读不到（$TRASH_PATH）：那 05 就不是「按钮回来」那一档，落点可能被谁清掉了")
  else
    print -r -- "  ✓ 重新挂上后落点又读得到 ⟹ 从头到尾没人倒过废纸篓（I16 之前这一格印「废纸篓已清空」，正是这一条把它改判掉的）"
  fi
else
  print -r -- "  · 落点判为「$LANDS」：拔盘不会让那一行消失，03/04/05 三档在本族只是记录，不作翻面判据"
fi

print -r -- ""
print -r -- "# 画面交叉核对"
for png in "$OUT"/*.png(N); do print -r -- "  md5 $(md5 -q "$png")  $(basename $png)"; done
# `01↔02`：卸载页在夹具下是静态页（列表只有那一行），self-echo 删掉它 + 冒出 toast，
# 画面上必然有可辨差异——这一条是"删除真的走到了界面"的像素侧证。
# `03↔04`：只在落点于卷上那一支要求有差异（按钮 → 徽标）。概览页是活数页，
# 所以**不要求**"只有那一行变了"，也不跑 03↔05 的 same——隔几分钟的两张连拍本来就不同（见头部）。
typeset -a PIX_PAIRS=("01-uninstall-list-before|02-uninstall-self-echo-delete|diff")
[[ $LANDS == 卷内* ]] && PIX_PAIRS+=("03-dashboard-undo-button|04-dashboard-after-detach|diff")
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
  if (( above > 0 )); then
    print -r -- "  ✓ $a ↔ $b：内容区有可辨差异 $above 个像素"
  else
    PROBLEMS+=("$a ↔ $b：内容区可辨差异 0 个像素（最大幅度 $maxd）——这一对本该不同，相同就说明那一档动作没在界面上起作用")
  fi
done <<< "$pix_report"

for f in 01-uninstall-list-before 02-uninstall-self-echo-delete 03-dashboard-undo-button \
         04-dashboard-after-detach 05-dashboard-remounted; do
  wants $f || continue
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

print -r -- "→ $OUT（$APPEARANCE）｜落点=$LANDS（$TRASH_PATH）"
print -r -- "卷还挂着（$MP_REAL），落点那个 bundle 仍在卷内 .Trashes 里；核对完照片就收尾："
print -r -- "  ./Scripts/p53-cross-volume-fixture.sh clean"
print -r -- "台账由 EXIT trap 恢复到本轮开始前的字节（sha=$LEDGER_SHA_BEFORE），备份仍在 $BACKUP"
