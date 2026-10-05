#!/bin/zsh
# P12：把 release-readiness §7.2 那句"含义未查"量成事实——
# `sandbox_extension_issue_file_to_process failed for …: 1 (Operation not permitted)`
# 这行从 P7 起每一份取证日志里都有（P7 三份 + v1.0.0 三份 + P12 三份），
# 而它一直挂在"ad-hoc 构建从 /tmp 起进程"这个说法上，没人做过单变量对照。
#
# 要回答的问题只有一个：**这行是签名档次带来的，还是启动路径带来的？**
# 发版说明里这一格取决于它——如果是签名带来的，用户装上以后每次启动都会看见；
# 如果是 /tmp 带来的，那正常安装位置根本没有这行，我们这几天的日志才是取证方式自己的产物。
#
# 做法：同一份 bundle 原样拷到用户目录，两个位置各起 7 秒，只比 stderr 里那一行出现的次数。
# 唯一变量是路径——同一次构建、同一份签名（拷完再 `codesign --verify --deep --strict` 自证一次）。
#
#   ./Scripts/p12-sandbox-warning-probe.sh /tmp/mm-app-v1/MacMaster.app docs/verification/p12-v1
#
# 只 kill 自己启动的 pid（记在日志里）。探针目录用完删掉，不留在用户机器上。
set -e
cd "$(dirname "$0")/.."

APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
PROBE_DIR="$HOME/.mm-p12-probe"
SETTLE=${SETTLE:-7}
mkdir -p "$OUT"

rm -rf "$PROBE_DIR"
mkdir -p "$PROBE_DIR"
cp -R "$APP" "$PROBE_DIR/"
PROBE_APP="$PROBE_DIR/$(basename "$APP")"
codesign --verify --deep --strict "$PROBE_APP"   # 拷贝没弄坏签名；弄坏了就直接失败，别拿坏产物去比

# run <输出名> <app 路径>：起进程 → 等 SETTLE 秒 → 数那一行出现几次 → 收掉自己起的 pid。
run() {
  # 三行分开声明：zsh 下 `local name=$1 log="$OUT/$name.log"` 里那个 $name 取到的是**外层**的同名变量
  # （即空），两档日志会一起写进 `$OUT/.log`——第一次实跑就是这么把证据写丢的。
  local name=$1
  local app=$2
  local log="$OUT/$name.log"
  {
    print -r -- "# p12-sandbox-warning-probe.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')"
    print -r -- "# app=$app"
    print -r -- "# 签名：$(codesign -dv "$app" 2>&1 | grep -oE 'flags=0x[0-9a-f]+\([a-z,]+\)|Signature=[^ ]*' | tr '\n' ' ')"
    print -r -- "# 命令：$app/Contents/MacOS/MacMaster（不带任何 MM_* env）"
  } >"$log"
  "$app/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$SETTLE"
  local alive="已退出"
  if kill -0 "$pid" 2>/dev/null; then alive="仍在运行"; kill "$pid" 2>/dev/null || true; fi
  wait "$pid" 2>/dev/null || true
  local hits
  hits=$(grep -c "sandbox_extension_issue_file_to_process" "$log" || true)
  {
    print -r -- "# 进程 $SETTLE 秒后：$alive（pid=$pid，本脚本自己起的）"
    print -r -- "# sandbox_extension_issue_file_to_process 出现次数：$hits"
  } >>"$log"
  print -r -- "→ $name：$hits 次（$alive）"
}

run 05-sandbox-warning-tmp "$APP"
run 04-sandbox-warning-home "$PROBE_APP"

rm -rf "$PROBE_DIR"
print -r -- "→ 探针目录已删除：$PROBE_DIR"
