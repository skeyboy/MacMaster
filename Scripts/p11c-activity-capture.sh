#!/bin/zsh
# P11c「密钥与自启配置的改动时间」卡取证：这一卡的文案合同落成可重跑的照片档。
#
# 背景：这一卡从前叫「系统活动」，第一族是 `log show` 命中行。P11c 量了四种谓词
# （数据与结论写在 docs/analysis/fidelity-guardian.md §6.7）之后日志族整族撤下，
# 剩下的两族改了口径：detail 一律是路径、time 一律是该路径的 mtime 相对说法、
# 卡片脚注写明"mtime 不记读取"。同时修掉一个真机恒为 0 行的缺陷
# （`files.prefix(3)` 在过滤 `.plist` **之前**截断，而本机前 3 个条目都是 `.disabled`）。
#
# 全程零点击：这一屏不需要动手就能到齐三态（真机 / 夹具 rows / 夹具 empty 都有钩子）。
# 合成点击与滚轮会逃逸到用户的其它应用（老规矩），所以一律不用。
#
#   ./Scripts/p11c-activity-capture.sh <app 路径> <输出目录>
#   ./Scripts/p11c-activity-capture.sh /tmp/mm-app-p11c/MacMaster.app docs/verification/p11c-activity
#   ONLY=02 ./Scripts/p11c-activity-capture.sh …  只重拍一档
#
# 每份 .log 开头是归因头（脚本名 / 档 / 时间 / app 路径 / 本档注入的全部变量），
# 真机档另外追加 `# expect:` 行：那是用 stat 直接读到的 mtime，用来和照片对数——
# 卡片上那五个"X 前"必须能从 expect 行算出来，否则照片只是好看。
# 抓完即杀，且只 kill 自己起的 pid。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
# 12 秒：这一屏的真机档要等 launchd 快照与目录 stat 都落位（守护页一共四张卡，
# 只取景 activity 那一卡时另外三张被钩子挡掉，但加载仍然照跑）。
SETTLE=${SETTLE:-12}

mkdir -p "$OUT"

# shot <文件名> <等待秒> <环境变量...>
# 公共部分（模块 / 取景 / 外观）在这里统一注入，逐档特例写在 "$@" 上——
# 后面的同名变量会覆盖前面的，所以 MM_APPEARANCE=dark 这种特例干净。
shot() {
  local name=$1
  local settle=$2
  shift 2
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  print -r -- "# p11c-activity-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# codesign: $(codesign -dvv "$APP" 2>&1 | grep -oE 'flags=0x[0-9a-f]+[a-z()]*' | head -1)" >>"$log"
  print -r -- "# env: MM_APPEARANCE=light MM_OPEN_MODULE=guardian MM_GUARDIAN_CARDS=activity $*" >>"$log"
  env MM_APPEARANCE=light MM_OPEN_MODULE=guardian MM_GUARDIAN_CARDS=activity \
      "$@" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$settle"
  local wid
  wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
        | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 没有可见窗口（不产出空照片）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s"
}

# 真机上这一卡应当列出的那几行，现读到 mtime 再落成 `# expect:` 行。
# 刻意用与代码不同的读法（stat 而不是 attributesOfItem），两条路对上了才算数。
expect_lines() {
  local log=$1
  local p
  for p in "$HOME/.ssh" "$HOME/.gnupg" "$HOME/Library/Keychains"; do
    [[ -e $p ]] && print -r -- "# expect: $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$p")  $p" >>"$log"
  done
  local d="$HOME/Library/LaunchAgents"
  if [[ -d $d ]]; then
    for p in $(ls "$d" | grep '\.plist$' | head -3); do
      print -r -- "# expect: $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$d/$p")  $d/$p" >>"$log"
    done
    print -r -- "# expect: 本机 .plist 共 $(ls "$d" | grep -c '\.plist$') 个、目录条目共 $(ls "$d" | wc -l | tr -d ' ') 个" >>"$log"
  fi
}

# 01 真机浅色：两族的真值。照片上的每个"X 前"都要能从 expect 行推出来。
shot 01-real-machine "$SETTLE"
expect_lines "$OUT/01-real-machine.log"

# 02 夹具 rows 档：两族各一行，全是 com.example.* / （夹具值）。
#    它是"这一卡有没有把合成值和真值混在一起"的判据——夹具值必须一眼可辨。
shot 02-fixture-rows "$SETTLE" MM_GUARDIAN_ACTIVITY_FIXTURE=rows

# 03 夹具 empty 档：空态文案 + 脚注。这一档是"读不到"那一态唯一的可重跑照片。
shot 03-fixture-empty "$SETTLE" MM_GUARDIAN_ACTIVITY_FIXTURE=empty

# 04 最小窗口（1000×700）：绝对路径在窄窗下的中段省略、脚注换行不溢出卡外。
shot 04-fixture-rows-min-window "$SETTLE" MM_GUARDIAN_ACTIVITY_FIXTURE=rows MM_WINDOW_SIZE=1000x700

print -r -- "→ $OUT"
