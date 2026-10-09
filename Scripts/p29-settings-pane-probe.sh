#!/bin/zsh
# P29 系统设置深链探针：把"这一串 pane 标识在今天这台 macOS 上到底能不能打开"变成一份读数。
#
# 为什么不能靠"看起来对"：`MMReveal.openSystemSettings(pane:)`（`MMDesign.swift:517-520`）
# 会把 pane 串拼在 `x-apple.systempreferences:` 后面，而 `NSWorkspace.open` **成功与否不返回
# 任何信息**（它只说"我把手交出去了"）。所以"点了没反应"这一类缺陷在代码里读不出来、
# 在单测里也测不到——只有把 URL 真交出去、再看系统设置那扇窗的标题落在哪一格，才知道成没成。
#
# 判据用窗口标题而不是退出码：`open` 对无效 URL 的返回并不总可靠，而"面板标题变成了
# 完全磁盘访问权限"这一件事才是用户真正会看到的。
#
# 但只看"跑完之后标题是什么"量不出东西：`docs/verification/p29-panes-v2/` 那一跑，
# A/B/C 三档全部读成 `title=完全磁盘访问权限`——A 已经把面板停在那一格，后面 B（旧写法）
# 和 C（双前缀，理应是坏串）无论有没有换手，读数都一样。**无效 URL 的表现就是"面板不动"，
# 而"面板不动"和"面板本来就在那一格"是同一种读数。**所以每一档都量两个数：交给 URL 之前的
# 标题、交给之后的标题，并且两档候选之间插一次已知能用的锚点面板（登录项）把面板从候选的目标
# 格上挪开，才让"没动"成为一次可分辨的读数。（再往前那一跑五档全读成"拿不到窗口标题"，
# 是另一件事：按进程名查窗口在这台机器上查不到，见下面 `titles()` 那一段。）
#
# 副作用与收口：`open -g` 让系统设置在**后台**打开（不抢前台焦点，不动用户当前的窗）。
# 起跑前先记系统设置有没有在跑；只有"这一支脚本把它起来的那一个 pid"才在收尾时收掉。
#
#   ./Scripts/p29-settings-pane-probe.sh docs/verification/p29-panes
set -e
cd "$(dirname "$0")/.."
OUT=${1:?需要输出目录}
# 冷启动系统设置要 5 秒以上（本轮实测：2 秒那一版五档全部读成"没有窗口"）。
SETTLE=${SETTLE:-6}
mkdir -p "$OUT"
LOG="$OUT/pane-urls.log"

repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi

# 注意：这里量的是"pane 串 + 我们那一句拼接"，不是产物，所以不带 mm_provenance_check。
# 这一条要在日志里说白，否则下一轮会把它当成"跑在某个二进制上"的证据。
{
  print -r -- "# p29-settings-pane-probe.sh  $(date '+%Y-%m-%d %H:%M:%S %z')"
  print -r -- "# repo: $repoTag branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
  print -r -- "# 被测的是 URL 字符串本身（open 交给系统的 Settings.app），与任何 .app 产物无关"
  print -r -- "# macos: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
} >"$LOG"

beforePIDs=$(pgrep -x "System Settings" | tr '\n' ' ')
print -r -- "# 起跑前在跑的系统设置 pid: ${beforePIDs:-（没有，收尾时要把起来的那个收掉）}" >>"$LOG"

# 读系统设置那个窗当前的全部非空标题（去重）。按 pid 查而不是按进程名：
# `kCGWindowOwnerName` 在这台机器上取不到 "System Settings" 这一串（本轮实测：
# `window-ids.swift "System Settings"` 零行，而同一窗口按 `--pid` 就出来了），
# 按名字过滤会静默落到"没有窗口"那一支，读数看着像"面板打不开"，其实是查错了对象。
titles() {
  local pid
  pid=$(pgrep -x "System Settings" | head -1)
  [[ -z "$pid" ]] && { print -r -- "（系统设置没在跑）"; return; }
  local t
  t=$(swift Scripts/window-ids.swift --pid "$pid" 2>/dev/null \
      | sed -nE 's/.*title=(.*) bounds=.*/\1/p' | grep -v '^$' | sort -u | tr '\n' '|' | sed 's/|$//')
  print -r -- "${t:-（有进程无窗口标题）}(pid=$pid)"
}

# probe <名字> <交给 open 的完整 URL>：改面板前后的标题各读一次，结论按"换没换"给。
probe() {
  local name=$1 url=$2 rc
  local before after verdict
  before=$(titles)
  # `set -e` 底下不能直接 `open ...; rc=$?`：open 一失败脚本就退了，rc 永远记不到。
  open -g "$url" 2>>"$LOG" && rc=0 || rc=$?
  sleep "$SETTLE"
  after=$(titles)
  if [[ "$before" == "$after" ]]; then
    verdict="面板没动"
  else
    verdict="面板换了"
  fi
  print -r -- "$name
  url    = $url
  rc     = $rc
  改之前 = $before
  改之后 = $after
  结论   = $verdict" >>"$LOG"
}

# 锚点：已知能用的面板，用来在两次候选之间把面板从候选的目标格上挪开。
ANCHOR_URL="x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
anchor() {
  open -g "$ANCHOR_URL" 2>>"$LOG" || print -r -- "  锚点 open 非零退出 rc=$?" >>"$LOG"
  sleep "$SETTLE"
  print -r -- "锚点（挪开面板）→ $(titles)" >>"$LOG"
}

probe "A 现代写法（守护页/卸载页在用）" \
     "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
probe "D 登录项面板（锚点本身）" "$ANCHOR_URL"
anchor
probe "B 旧版写法（清理页那一串的字面量，去掉双前缀）" \
     "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
anchor
probe "C 今天真实拼出来的（双前缀）" \
     "x-apple.systempreferences:x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
anchor
probe "E 通知面板" \
     "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

# 收尾：只收掉这一支脚本起来的那一个 pid（起跑前已在跑的不动它）。
if [[ -z ${beforePIDs// /} ]]; then
  for pid in $(pgrep -x "System Settings"); do kill "$pid" 2>/dev/null || true; done
  print -r -- "# 收尾：已收掉本脚本启动的系统设置 pid=$(pgrep -x 'System Settings' | tr '\n' ' ')" >>"$LOG"
else
  print -r -- "# 收尾：系统设置在起跑前就在跑，不动它" >>"$LOG"
fi

cat "$LOG"
