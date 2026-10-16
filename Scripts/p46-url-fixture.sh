#!/bin/zsh
# P46e 深链夹具：一棵假 home，四个应用 + 只有其中一个有可读的残留清单。
#
# 为什么要单独一棵（不复用 P33b 那份）：这一族要拍的**不是残留怎么归类**，而是
# "一个从外面进来的字符串，界面上有没有把它认成某一行"。所以它的形状由点名决定：
#   UrlFoo     —— 深链单独点名的那一个。它必须有**几条看得见的残留**，
#                 否则"页面切到该项的残留清单"这句话在照片上无从核对。
#   OtherFoo   —— 从不被点名，只当基线：01 那一档 `MM_UNINSTALL_SELECT` 先选中它，
#                 02 之后选中条从它移到 UrlFoo，两张照片放一起才证明"是 URL 让它切的"，
#                 而不是"界面自己恰好选了这一行"。
#   ThirdFoo   —— 多选 URL 里排在第一个的那一个。钉的是**顺序**：
#                 访达右键多选时 `path=` 会重复多次，我们的合同是"点第一个"。
#   Space Foo  —— 名字里带空格。这一条是**只有实机能钉**的那半件事：
#                 单测里 `%20`→空格 是 `URLComponents` 的行为（已测），
#                 而"URL 原样穿过 `open`/LaunchServices 这一段还没被拆坏"是另一件事，
#                 只有把真 URL 交给真 app 才量得到。
#
# 假 brew 账本留空目录（沿用 P33b 那一条理由）：`MM_UNINSTALL_CONFIRM_FIXTURE_HOME`
# 会把来源识别的前缀指到 `$home/.homebrew`，没有这一档时来源那一行是「无法判定」——
# 这一族不在乎来源，但别让照片里多一个说不清的变量。
#
# 这一族**不启动任何 bundle**、不碰废纸篓、不请求权限：点名只是一次"看哪一个"的切换。
# 收尾由调用方删目录。
#
#   ./Scripts/p46-url-fixture.sh                  打印新建的夹具根目录
#   FIX=$(./Scripts/p46-url-fixture.sh)           交给 Scripts/p46-url-capture.sh
set -e

fixture_root=$(mktemp -d /tmp/macmaster-p46-url.XXXXXX)

# make_app <bundle 名> <包标识> <本体额外字节数（MiB）>
# 本体大小各不相同：照片上要能一眼认出选中的是哪一行（沿用 P33b 那一条理由）。
make_app() {
  local dir=$1 bundle_id=$2 mib=$3
  local app="$fixture_root/Applications/$dir.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
  plutil -insert CFBundleName -string "$dir" "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string "$dir" "$app/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string 1.0 "$app/Contents/Info.plist"
  plutil -insert CFBundleVersion -string 1 "$app/Contents/Info.plist"
  plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
  printf 'echo placeholder\n' > "$app/Contents/MacOS/$dir"
  chmod +x "$app/Contents/MacOS/$dir"
  dd if=/dev/zero of="$app/Contents/Resources/payload.bin" bs=1048576 count="$mib" status=none
}

make_app UrlFoo    com.example.urlfoo    2
make_app OtherFoo  com.example.otherfoo  3
make_app ThirdFoo  com.example.thirdfoo  1
make_app 'Space Foo' com.example.spacefoo 4

# make_residual <相对路径> <文件名> <字节数（MiB）>：一律真实字节，不用稀疏文件。
make_residual() {
  local rel=$1 file=$2 mib=$3
  local dir="$fixture_root/Library/$rel"
  mkdir -p "$dir"
  dd if=/dev/zero of="$dir/$file" bs=1048576 count="$mib" status=none
}

# UrlFoo 的三行残留：走包名对应那一条硬证据（`Caches`、`Application Support`），
# 加一行偏好 plist。三行是为了让"这是 UrlFoo 的清单"在照片上无可争辩。
make_residual Caches/com.example.urlfoo cache.bin 2
make_residual "Application Support/com.example.urlfoo" profile.bin 1
make_residual Preferences com.example.urlfoo.plist 1
# 别人的那一行：证明切到 UrlFoo 之后不会把 OtherFoo 的残留一起列出来。
make_residual Caches/com.example.otherfoo cache.bin 1

mkdir -p "$fixture_root/.homebrew"

print -r -- "$fixture_root"
