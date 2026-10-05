#!/bin/zsh
# P7「清理页空扫描范围」取证：拍到那一屏在没有任何人工点击的情况下唯一 reachable 的
# 说法分档，并顺手证明"设置里四个开关全关"这件事是怎么落到界面上的。
#
# 为什么这一档值得单独拍：`CleanerModel.scan` 走的是 `settings.scope`，四类全关时
# `CacheScanner` 直接返回**空清单且 isComplete=true**，于是页面落进 `categories.isEmpty`
# 那一支。以前那一支无条件写着「没有可清理的内容」——可本轮一个类别都没检查，
# 这句话是假话（`fidelity-cleaner.md` §2 I4 记的就是这一支）。现在它按三种成因分档。
#
# 这一档的注入手段不是环境变量而是 UserDefaults：那四个开关本来就是持久化设置，
# 页面 `.task` 进页即扫，所以**改设置 → 起进程**就够了，不需要点击（合成点击是红线）。
# 代价是这把钥匙动的是 `com.macmaster.app` 这个真实域，所以脚本用 trap 保证退出时
# 一定 `defaults delete` 回注册默认值，并把动过哪几个键写进日志。
#
#   ./Scripts/p7-empty-scope-capture.sh <app 路径> <输出目录> [light|dark]
#   ONLY=02 ./Scripts/p7-empty-scope-capture.sh …   # 只重拍"恢复默认"那张
#
# 哨兵判据（画面上必须出现的）：01 是标题「没有勾选任何扫描类别」+ 那句"四个类别开关
# 都关着"；02 回到正常分类表（证明这一对照片的差别只在那四个键上）。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
DOMAIN=com.macmaster.app
KEYS=(settings.cleaner.scanSystemCache settings.cleaner.scanAppCache
      settings.cleaner.scanLogFiles settings.cleaner.scanTempFiles)
SETTLE=${SETTLE:-8}

mkdir -p "$OUT"

# 无论走到哪一步退出，都把四个键删回注册默认值（true）。宁可多删一次，
# 也不要留一台"清理页从此什么都不扫"的机器给下一轮取证。
restore() { for k in $KEYS; do defaults delete "$DOMAIN" "$k" 2>/dev/null || true; done; }
trap restore EXIT

defaults_write_off() { for k in $KEYS; do defaults write "$DOMAIN" "$k" -bool false; done; }

# shot <文件名> <等待秒> <说明>
shot() {
  local name=$1 settle=$2 note=$3
  [[ -z ${ONLY:-} || $name == ${ONLY}* ]] || return 0
  local log="$OUT/$name.log"
  {
    print -r -- "# p7-empty-scope-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP"
    print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=cleaner"
    # 这一档的状态在 UserDefaults 里，不在 env 里——归因头必须把它也写出来，
    # 否则照片上那一屏与"哪四个键被关过"就对不上了。
    print -r -- "# defaults: ${(j: :)KEYS} = $note"
  } >"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=cleaner \
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
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${settle}s"
}

# 01 四类全关：期望「没有勾选任何扫描类别」，而不是"没有可清理的内容"。
defaults_write_off
shot 01-empty-scope "$SETTLE" "false（脚本写入，退出时由 trap 删除）"

# 02 删回默认值（= true）再拍一张：同一台机器、同一个构建，唯一差别是那四个键。
restore
shot 02-restored "$SETTLE" "已删除，回到注册默认值 true"

print -r -- "→ $OUT"
