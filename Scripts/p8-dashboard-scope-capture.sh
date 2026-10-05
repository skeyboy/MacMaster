#!/bin/zsh
# P8「概览页的可清理必须跟着清理页那四个勾选」取证。
#
# 修的是什么：概览页此前走 `CacheScanner().scanAll()`，等于永远全开；用户在清理页
# 把「日志」「临时文件」关掉之后，概览那个「可清理」照样把它们算进去——同一个名字
# 在两个页面是两种口径（`release-readiness.md` §8 记的就是这一条）。
# 现在两处共用 `CacheScanScope.selected(...)`，概览还多了一档「未勾选类别」：
# 四个类别全关着时，画面上不能写"未扫描"（等下去也不会有数），也不能写"失败"。
#
# 注入手段是 UserDefaults，不是环境变量：那四个开关本来就是持久化设置，
# 概览页首帧采样完自己会调 `measureReclaimable()`，所以**改设置 → 起进程**就够了，
# 不需要点击（合成点击是红线）。代价是这把钥匙动的是 `com.macmaster.app` 真实域，
# 所以脚本用 trap 保证退出时一定 `defaults delete` 回注册默认值 true，
# 并把动过哪几个键写进每张照片的归因头。
#
#   ./Scripts/p8-dashboard-scope-capture.sh <app 路径> <输出目录> [light|dark]
#   ONLY=03 ./Scripts/p8-dashboard-scope-capture.sh …   # 只重拍"还原对照"那张
#   SETTLE=20 ./Scripts/p8-dashboard-scope-capture.sh … # 扫描比机器慢的时候加等待
#
# 哨兵判据（画面上必须出现的）：
#   01 只勾「日志」→「可释放空间」卡里只剩日志那一类，且顶栏「可立即释放」的
#      可清理分项明显小于 03；
#   02 四个全关 → 卡片文案是「未勾选类别」+ 那句"清理页四个类别都关着"，
#      不是「未扫描」也不是「测量失败」；
#   03 删回默认值（= 全开）→ 分类表恢复多行，作为 01/02 的对照。
# 三张是同一个构建、同一台机器，唯一差别就是那四个键。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
DOMAIN=com.macmaster.app
K_SYS=settings.cleaner.scanSystemCache
K_APP=settings.cleaner.scanAppCache
K_LOG=settings.cleaner.scanLogFiles
K_TMP=settings.cleaner.scanTempFiles
KEYS=($K_SYS $K_APP $K_LOG $K_TMP)
# 概览页这一轮扫的是真实缓存目录，比清理页那张慢一些；8 秒常常还没落地。
SETTLE=${SETTLE:-16}
# 「可释放空间」卡在概览页中部，窗口矮了就落在折叠线以下；尺寸写死，
# 免得 App 恢复上次退出的 frame，照片看着像"那一卡没了"。
SIZE=${SIZE:-1400x1000}

mkdir -p "$OUT"

# 无论走到哪一步退出，都把四个键删回注册默认值（true）。
# 宁可多删一次，也不要留一台"概览从此显示未勾选类别"的机器给用户。
restore() { for k in $KEYS; do defaults delete "$DOMAIN" "$k" 2>/dev/null || true; done; }
trap restore EXIT

# set_scope <systemCache> <appCache> <logs> <temp>
set_scope() {
  defaults write "$DOMAIN" $K_SYS -bool $1
  defaults write "$DOMAIN" $K_APP -bool $2
  defaults write "$DOMAIN" $K_LOG -bool $3
  defaults write "$DOMAIN" $K_TMP -bool $4
}

# shot <文件名> <归因说明>
shot() {
  local name=$1 note=$2
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  {
    print -r -- "# p8-dashboard-scope-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP"
    print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=dashboard MM_WINDOW_SIZE=$SIZE"
    # 状态在 UserDefaults 里，不在 env 里——归因头必须逐个键写出来，
    # 否则照片上那个数字与"哪几个开关被关过"就对不上了。
    print -r -- "# defaults: ${(j: :)KEYS} = $note"
  } >"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=dashboard MM_WINDOW_SIZE="$SIZE" \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$SETTLE"
  local wid
  wid=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
        | sed -n 's/^windowid=\([0-9]*\).*/\1/p' | head -1)
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 没有可见窗口（不产出空照片）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  print -r -- "# windowid=$wid pid=$pid settle=${SETTLE}s" >>"$log"
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid"
}

# 01 只勾日志：范围里只剩 logs 一类。
set_scope false false true false
shot 01-logs-only "false false true false（脚本写入，退出时由 trap 删除）"

# 02 四个全关：期望「未勾选类别」那一档，而不是数字 0 / 「未扫描」。
set_scope false false false false
shot 02-none-selected "false×4（脚本写入，退出时由 trap 删除）"

# 03 删回注册默认值（true）：同一构建的对照，证明前两档的差别只在那四个键上。
restore
shot 03-all-on "已删除，回到注册默认值 true"

print -r -- "→ $OUT"
