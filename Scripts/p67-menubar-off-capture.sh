#!/bin/zsh
# P6.7 取证：「菜单栏监控」开关的关闭态。
#
# 立项原因：`MM_MONITOR_FIXTURE` 的 `menubarOff` 档自 #50 起就一直被解析、被文档引用
# （`docs/analysis/fidelity-monitor.md` §5 第 11 行写着"关闭态已覆盖"），但**没有任何一处消费它**——
# `grep -rn menubarOff` 只命中解析文件自己。P6.7 的夹具竞态审计（起因是优化器夹具从未生效那个 bug）
# 顺手把它捞了出来。现在它真的去 `disable()`（摘掉 NSStatusItem），开关才可能显示 off。
#
# 为什么要两档一起拍：只拍关态证明不了"是钩子关的"，也可能一直是关的。
# ①=对照组（同一份快照、开关开着）②=menubarOff。两张唯一的差别应当就是右上角那颗开关。
# 快照都注 `populated`：不注夹具的话两张照片里的 CPU/内存数字本来就在变，
# 差别就不止开关一处了——这正是"半生效夹具 = 假通过"要避免的那种证据。
#
# 全程零合成点击（红线：合成点击会逃逸到用户的其它应用），只 kill 自己起的 pid。
#
#   ./Scripts/make-app.sh
#   ./Scripts/p67-menubar-off-capture.sh build/MacMaster.app docs/verification/p67-menubar-off [light|dark]
#   ONLY=02 ./Scripts/p67-menubar-off-capture.sh ...   # 只跑某一档
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}

# P45 补的归因头＋内容指纹门禁（配方同 p69），理由见 p64-capture.sh 同段注释。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p45 -s /tmp/mm-scratch-p45 重新构建再取证。"
  exit 4
fi

mkdir -p "$OUT"

# shot <文件名> <等待秒> <环境变量...>
shot() {
  local name=$1 settle=$2; shift 2
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  print -r -- "# p67-menubar-off-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=monitor $*" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=monitor "$@" \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
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
  print -r -- "windowid=$wid" >>"$log"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s"
}

shot 01-monitor-menubar-on  6 MM_MONITOR_FIXTURE=populated
shot 02-monitor-menubar-off 6 MM_MONITOR_FIXTURE=populated,menubarOff

# 判据在照片里，不在日志里：02 的右上角开关应当是灰的、01 是蓝的，
# 而两张卡的数字应当逐像素相同（同一份 populated 夹具）。
# 顺带把这条记下来：开关读的是 `statusItem != nil`，所以"摘掉状态项"是唯一能拍出关态的办法。
print -r -- "→ $OUT（$APPEARANCE）"
print -r -- "对账：两张图的内存/Swap/温度数字必须完全相同，只差右上角那颗开关。"
print -r -- "      若两张一模一样 → menubarOff 又变成空档了；若数字也不同 → 夹具没钉住，回到 §fixtureFrozen 查。"
