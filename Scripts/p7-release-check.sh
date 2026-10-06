#!/bin/zsh
# P7 发布前自检：把"这个构建能不能跑、版本对不对、签名是什么档次"变成一条命令 + 两张照片。
#
# 为什么要有这个脚本，而不直接 codesign + 肉眼跑一次：
# 1. 版本号从 `make-app.sh` 的 `VERSION` 走到 bundle，再走到设置页「关于」，
#    中间任何一环漂了，界面上显示的就不是打包时给的数——这条链只能靠照片闭合，
#    读 plist 只证明了前半段。
# 2. 签名档次（ad-hoc / Developer ID / 是否 hardened runtime）决定这个 .app 能不能发给别人，
#    每次手敲 `codesign -dv` 容易只看第一行，把 `flags=0x2(adhoc)` 当成"签好了"。
#
#   ./Scripts/p7-release-check.sh /tmp/mm-app-p7b/MacMaster.app docs/verification/p7-release-build
#
# 只 kill 自己启动的 pid；抓窗口一律带 --pid（同机可能跑着别的实例，按名字抓会抓到别人的窗）。
set -e

cd "$(dirname "$0")/.."
# 归因头要能说出自己是哪棵树：这一支脚本每轮换一个新证据目录（v1.0.0 / p12-v1 / p13-v1 …），
# 只有日期的话没人能对得上"这三张照片出自哪一次改动"。-uno：本轮自己写的未跟踪文件不算脏活。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${APPEARANCE:-light}
SETTLE=${SETTLE:-6}

mkdir -p "$OUT"

sig=$(codesign -dv --verbose=4 "$APP" 2>&1 \
      | grep -oE 'Identifier=[^ ]*|flags=0x[0-9a-f]+\([a-z]+\)|Signature=[^ ]*|TeamIdentifier=.*' | tr '\n' ' ')
ver=$(plutil -p "$APP/Contents/Info.plist" 2>/dev/null \
      | sed -nE 's/.*"CFBundleShortVersionString" => "(.*)".*/\1/p')
bld=$(plutil -p "$APP/Contents/Info.plist" 2>/dev/null \
      | sed -nE 's/.*"CFBundleVersion" => "(.*)".*/\1/p')
# 被测二进制自己是哪棵树构建的（make-app.sh 打进 plist）。这一行和上面那行 `# repo:`
# 是两件事：`# repo:` 是**跑这条检查的脚本树**，`MMGitCommit` 是**被签名的那份产物**。
gitc=$(plutil -p "$APP/Contents/Info.plist" 2>/dev/null \
      | sed -nE 's/.*"MMGitCommit" => "(.*)".*/\1/p')
# 图标键也收进同一行：缺 CFBundleIconFile 时 Dock 是通用白纸，而 plist 别处一切正常，
# 事后没人想得起来"这次构建到底带没带图标"。
icon=$(plutil -p "$APP/Contents/Info.plist" 2>/dev/null \
      | sed -nE 's/.*"CFBundleIconFile" => "(.*)".*/\1/p')
# spctl 对未公证的产物一定非零退出，这不是错误，是这一档的结论本身，所以不能让它中断脚本。
# 结论整行收下来（`|| true` 之外还要 `tr` 成一行）：BSD 下按行取下标拿到过孤零零一个 "/"。
assess=$(spctl -a -t exec -vv "$APP" 2>&1 | tr '\n' ' ' || true)

# shot <文件名> <附加 env>：起实例 → 等渲染 → 按 pid 抓自己那一个窗口 → 收掉。
shot() {
  local name=$1; shift
  local log="$OUT/$name.log"
  {
    print -r -- "# p7-release-check.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP"
    print -r -- "# env: MM_APPEARANCE=$APPEARANCE ${(j: :)@}"
    print -r -- "# repo: $repoTag branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
    print -r -- "# codesign: $sig"
    print -r -- "# plist: CFBundleShortVersionString=$ver CFBundleVersion=$bld CFBundleIconFile=${icon:-（无）} MMGitCommit=${gitc:-（无这一键）}"
    print -r -- "# spctl: $assess"
  } >"$log"
  env MM_APPEARANCE="$APPEARANCE" "$@" "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
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
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid"
}

# 01 概览页：不带任何模块钩子，拍的就是"这台机器上的真实数据 + 默认落地页"。
shot 01-dashboard
# 02 设置 · 关于：版本号唯一能被人读到的地方，照片上必须出现打包时给的 $ver。
shot 02-about MM_SHOW_SETTINGS=1 MM_SETTINGS_TAB=about
# 03 概览页 × 最小窗口：发版要的是"拖到最窄也不坏"，而 note 行是全站最容易先截断的地方。
#     1000x600 就是那层地板本身（`MacMasterApp.swift:36` 的 `.frame(minWidth: 1000, minHeight: 600)`，
#     默认窗 1100x700 在 `:42`），再小的请求会被夹回来。
shot 03-dashboard-min MM_WINDOW_SIZE=1000x600

print -r -- "→ $OUT（判据：02 上「关于」那行显示 $ver($bld)，照片里没有就是版本没走到界面，不是「差不多」；"
print -r -- "  同一张上的图标应是 AppIcon 本体（蓝底三颗星，CFBundleIconFile=${icon:-（无）}），不是 SF Symbol 占位符）"
