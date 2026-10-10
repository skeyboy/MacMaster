#!/bin/zsh
# P31a 运行状态夹具：一棵假 home，里面两个**真的能启动**的 .app。
#
# 为什么必须能启动：这一版没有"假快照钩子"，照片里的「运行中」要来自
# `NSWorkspace` 给的真话（理由写在 `Packages/MMUninstaller/Sources/MMUninstaller/RunningAppProbe.swift`
# 的 `snapshot()` 上）。把一棵 /tmp 下的假 bundle 真的跑起来，就能在不碰用户应用的前提下
# 拍到 `sameBundle` 那一档——设备号、路径、pid 全是系统给的。
#
# 为什么必须是 Cocoa 应用，而不是一个纯命令行的 sleep 循环：两件事都是 P31a 拿照片试出来的。
#   1) 不连窗口服务的进程照样会进 `NSWorkspace.runningApplications`（包名、路径、pid 都对），
#      但 macOS **不为它发** `didLaunchApplicationNotification`——退出通知倒是照发，
#      所以只试"退出能把界面刷新"会把这条差异藏起来。05 那一档拍的是"启动之后界面自己变了"，
#      用 sleep 循环永远拍不出来。
#   2) 连了窗口服务之后，进程报出的 bundleURL 与清单上那一份是同一种写法（都解析成 /private/tmp），
#      照片才落在「报出的位置就是这一份」那一档；sleep 那份报的是 /tmp/…，同一个文件
#      因为字符串写法不同被降到「只有包名对上」——那是取证脚本自己造的假档位。
# 所以这里编译的是 `-framework Cocoa` 的最小 NSApplication：不建窗口、不动鼠标键盘，
# 主循环交给运行循环。配合 `open -g`（不抢前台）就只有一个进程、一份 Dock 图钉。
#
# 四个 bundle，三种口径，各有分工：
#   Applications/RunningFoo.app  —— 脚本启动它 →「正在运行 · 进程 <pid>」，位置就是这一份
#   Applications/IdleFoo.app     —— 从不启动 → 同一张照片里它是「未检测到运行中的进程」；
#                                   05 那一档在窗口开好之后再启动它
#   Applications/ElsewhereFoo.app—— 从不启动，但**同包名的另一份拷贝**在别处跑着 →
#                                   「只有包名对上」那一档的实物
#   Elsewhere/ElsewhereFoo.app   —— 上面那份的拷贝：包名相同、位置不同，脚本启动的是这一份。
#                                   清单只扫 `$home/Applications`（`MMUninstaller.swift` 里
#                                   换掉 `appDirectoriesFactory` 的那一行），所以界面上只有
#                                   一行 ElsewhereFoo，而它背后那个进程报出的是另一个位置。
#                                   这一档以前只有单测，现在有照片——`bundleIdentifierOnly`
#                                   那句提醒说的就是画面上这一种情形。
#
#   ./Scripts/p31-running-fixture.sh          # 打印新建的夹具根目录
#   FIX=$(./Scripts/p31-running-fixture.sh)   # 交给 p31-running-capture.sh
set -e

fixture_root=$(mktemp -d /tmp/macmaster-running-fixture.XXXXXX)

# 900 秒看门狗是给"脚本被 SIGKILL、trap 没跑到"那一种情况兜底的：这些 bundle 有 Regular
# 激活策略，在 Dock 上看得见，不能比取证脚本活得更久。正常收尾由 p31-running-capture.sh
# 按它自己记下的 pid 结束，轮不到这个定时器。
cat > "$fixture_root/stub.m" <<'EOF'
#import <Cocoa/Cocoa.h>
int main(void) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSTimer scheduledTimerWithTimeInterval:900 repeats:NO block:^(NSTimer *t) {
      (void)t;
      [app terminate:nil];
    }];
    [app run];
  }
  return 0;
}
EOF

# make_app <夹具内父目录> <bundle 名> <可执行名> <包标识>
make_app() {
  local parent=$1 dir=$2 exec_name=$3 bundle_id=$4
  local app="$fixture_root/$parent/$dir.app"
  mkdir -p "$app/Contents/MacOS"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
  plutil -insert CFBundleName -string "$dir" "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string "$exec_name" "$app/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string 1.0 "$app/Contents/Info.plist"
  plutil -insert CFBundleVersion -string 1 "$app/Contents/Info.plist"
  plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
  clang -framework Cocoa -o "$app/Contents/MacOS/$exec_name" "$fixture_root/stub.m"
}

make_app Applications RunningFoo RunningFoo com.example.RunningFoo
make_app Applications IdleFoo IdleFoo com.example.IdleFoo
make_app Applications ElsewhereFoo ElsewhereFoo com.example.ElsewhereFoo
# 与 Applications 里那一份**同包名**的拷贝，只差位置。两份的可执行名也一样，
# 所以按 pid 找进程时必须连父目录一起认（见 p31-running-capture.sh 的 bundle_pid）。
make_app Elsewhere ElsewhereFoo ElsewhereFoo com.example.ElsewhereFoo

# 假 brew 账本留空目录：`MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 会把来源识别指向
# `$home/.homebrew`，没有这一档时来源那一行是「无法判定」——照片里两件事互不干扰。
mkdir -p "$fixture_root/.homebrew"

print -r -- "$fixture_root"
