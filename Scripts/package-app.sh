#!/bin/zsh
# 把 make-app.sh 的 .app 打成对外附件：zip + dmg + SHA256SUMS，并在打包当场验一遍。
#
#   ./Scripts/package-app.sh                              # build/MacMaster.app → build/dist/
#   ./Scripts/package-app.sh /tmp/mm-app/MacMaster.app /tmp/dist
#   VERSION=1.1.0 BUILD=7 ./Scripts/package-app.sh
#
# 为什么单独一支脚本，而不是把那几行 ditto/hdiutil 写在 workflow 的 run: 里：
# CI 与本机必须产出**同一形态**的附件，否则"本地验过的那一份"和"别人下载的那一份"
# 是两个东西——这正是 `release-readiness.md` §10 第 0 步立起来要防的那类账。
#
# 为什么要打完再验一遍（而不是直接上传）：`ditto -c -k` 会丢扩展属性与可执行位的形态、
# dmg 的 `/Applications` 符号链接会随打包方式变成普通目录，这两种坏法**在打包当场看不出来**，
# 只在别人双击时炸。所以这里把 zip 解回临时目录、dmg 挂回临时挂载点，各自读一次真实结构。
set -e

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP=${1:-"$ROOT/build/MacMaster.app"}
OUT=${2:-"$ROOT/build/dist"}
VERSION=${VERSION:-1.0.0}
BUILD=${BUILD:-1}
BIN_NAME="MacMaster"

[[ -d "$APP" ]] || { print -u2 -- "没有这个 bundle：$APP（先跑 ./Scripts/make-app.sh）"; exit 2; }
APP="$(cd "$APP" && pwd)"
PLIST="$APP/Contents/Info.plist"
[[ -f "$PLIST" ]] || { print -u2 -- "缺 Info.plist：$PLIST"; exit 2; }

# 版本号只认 plist，不认调用方传进来的字符串：CI 会把 inputs 里的 VERSION 传进来，
# 如果它和产物 plist 不一致，那就是"发出去的版本号是编出来的"——当场停，别上传。
plist_version=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
plist_build=$(plutil -extract CFBundleVersion raw "$PLIST")
git_commit=$(plutil -extract MMGitCommit raw "$PLIST" 2>/dev/null || echo 读不到)
src_digest=$(plutil -extract MMSourceDigest raw "$PLIST" 2>/dev/null || echo 读不到)
min_system=$(plutil -extract LSMinimumSystemVersion raw "$PLIST")
bundle_id=$(plutil -extract CFBundleIdentifier raw "$PLIST")

if [[ "$plist_version" != "$VERSION" || "$plist_build" != "$BUILD" ]]; then
    print -u2 -- "版本号不一致：请求 $VERSION ($BUILD)，产物 plist 是 $plist_version ($plist_build)"
    print -u2 -- "要么用 VERSION=$plist_version BUILD=$plist_build 重新打包，要么用同一档重跑 make-app.sh"
    exit 3
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
STEM="$BIN_NAME-$VERSION-$BUILD"
ZIP="$OUT/$STEM.zip"
DMG="$OUT/$STEM.dmg"
SUMS="$OUT/$STEM-SHA256SUMS.txt"

# ---- 1. 签名与 Gatekeeper 现状（原样记进日志，不当失败条件）----
# ad-hoc 签名产物被 spctl 拒是**已知结论**（§10 第 3 步那三行之一），不是本轮的意外；
# 这里把它打出来是为了让 CI 日志能自证"发出去的这一版和文档里说的那一版是同一档"。
# 判定只看退出码，不看输出串：`--verbose=2` 会往 stdout 打两行结论，
# 把它整段塞进变量再比"等于 通过"，第一次实跑就把一份验过的产物判成了不通过。
codesign_detail=$(codesign --verify --deep --strict --verbose=2 "$APP" 2>&1) && codesign_check="通过" || codesign_check="不通过"
codesign_flags=$(codesign -dv "$APP" 2>&1 | grep -o 'flags=0x[0-9a-f]*([a-z,]*)' | head -1)
spctl_line=$(spctl -a -t install -vvv "$APP" 2>&1 | head -2 | tr '\n' ' ')

[[ "$codesign_check" == "通过" ]] || { print -u2 -- "codesign --verify 不通过：$APP"; exit 4; }

# ---- 2. zip：ditto 保符号链接与可执行位，解回来查一遍 ----
rm -rf "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

ZIP_CHECK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/mm-zip-check.XXXXXX")
ditto -x -k "$ZIP" "$ZIP_CHECK_TMP"
UNZIPPED="$ZIP_CHECK_TMP/$BIN_NAME.app"
[[ -d "$UNZIPPED" ]] || { print -u2 -- "zip 解不开出 bundle：$ZIP"; exit 4; }
if [[ ! -x "$UNZIPPED/Contents/MacOS/$BIN_NAME" ]]; then
    print -u2 -- "zip 里的可执行文件没有可执行位：$UNZIPPED/Contents/MacOS/$BIN_NAME"
    exit 4
fi
unzip_version=$(plutil -extract CFBundleShortVersionString raw "$UNZIPPED/Contents/Info.plist")
[[ "$unzip_version" == "$VERSION" ]] || { print -u2 -- "zip 里那份 plist 版本是 $unzip_version"; exit 4; }
codesign --verify --deep --strict "$UNZIPPED" 2>/dev/null || { print -u2 -- "zip 里那份签名校验不通过"; exit 4; }
rm -rf "$ZIP_CHECK_TMP"

# ---- 3. dmg：拖拽安装档（应用 + /Applications 替身），挂回来查一遍 ----
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/mm-dmg-stage.XXXXXX")
cp -R "$APP" "$STAGE/$BIN_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$BIN_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

MOUNT=$(mktemp -d "${TMPDIR:-/tmp}/mm-dmg-mount.XXXXXX")
hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT" "$DMG"
[[ -d "$MOUNT/$BIN_NAME.app/Contents/MacOS" ]] || { print -u2 -- "dmg 挂上了但没有 bundle：$DMG"; exit 4; }
[[ -L "$MOUNT/Applications" ]] || { print -u2 -- "dmg 里的 /Applications 替身丢了，用户拖不动"; exit 4; }
dmg_version=$(plutil -extract CFBundleShortVersionString raw "$MOUNT/$BIN_NAME.app/Contents/Info.plist")
[[ "$dmg_version" == "$VERSION" ]] || { print -u2 -- "dmg 里那份 plist 版本是 $dmg_version"; exit 4; }
codesign --verify --deep --strict "$MOUNT/$BIN_NAME.app" 2>/dev/null || { print -u2 -- "dmg 里那份签名校验不通过"; exit 4; }
hdiutil detach -quiet "$MOUNT"
rm -rf "$MOUNT"
hdiutil verify -quiet "$DMG" || { print -u2 -- "dmg 校验和不过：$DMG"; exit 4; }

# ---- 4. 记账：附件清单 + sha256（写进 release 正文，别人下载完能自己比）----
print -r -- "# package-app.sh $STEM"
print -r -- "# repo: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 未知)$( [[ -n $(git -C "$ROOT" status --porcelain -uno 2>/dev/null) ]] && echo -dirty )"
print -r -- "# app: $APP"
print -r -- "# plist: CFBundleShortVersionString=$plist_version CFBundleVersion=$plist_build CFBundleIdentifier=$bundle_id LSMinimumSystemVersion=$min_system MMGitCommit=$git_commit"
print -r -- "# digest: $src_digest"
print -r -- "# codesign: $codesign_flags verify=$codesign_check（$(printf '%s' "$codesign_detail" | tr '\n' ' ')）"
print -r -- "# spctl: $spctl_line"

( cd "$OUT" && shasum -a 256 "$STEM.zip" "$STEM.dmg" > "$STEM-SHA256SUMS.txt" )
print -r -- "# assets:"
( cd "$OUT" && ls -l "$STEM.zip" "$STEM.dmg" "$STEM-SHA256SUMS.txt" | awk '{print "#   " $9 " " $5 " bytes"}' )
print -r -- "# sha256:"
( cd "$OUT" && cat "$STEM-SHA256SUMS.txt" | sed 's/^/#   /' )
print -r -- "$OUT"
