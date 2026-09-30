#!/bin/zsh
# 组装可运行的 .app：SPM 只产出裸可执行文件，没有 bundle 就看不到窗口、也没有
# 正确的 Bundle Identifier 与 TCC 归属。这里做最小可用的一套：Release 编译 → 铺
# bundle 结构 → 写 Info.plist → ad-hoc 签名（签名必须做，否则每次启动都被当成
# 一个新应用，TCC 授权与废纸篓归属都会漂移）。
#
#   ./Scripts/make-app.sh                                  # 默认 build/MacMaster.app
#   ./Scripts/make-app.sh -o /tmp/mmb-x -s /tmp/mm-sc-x     # 隔离构建
#
# `-o/-s` 是给并发验证用的：多路施工时大家共用一个 `build/MacMaster.app` 和一份
# `.build`，后构建的会把前构建正在跑的实例的二进制换掉，前一个截图就成了"看着是真的
# 但来自别人代码"的证据。Bundle Identifier 故意保持不变——换了 TCC 归属就漂移，
# 授权状态不再可比，那才是更大的假象。
set -e

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_DIR="$ROOT/build"
SCRATCH=""
BIN_NAME="MacMaster"

while [[ $# > 0 ]]; do
    case "$1" in
        -o|--out) APP_DIR="$2"; shift 2 ;;
        -s|--scratch) SCRATCH="$2"; shift 2 ;;
        *) print -u2 -- "未知参数：$1"; exit 2 ;;
    esac
done

BUILD_ARGS=(-c release)
[[ -n "$SCRATCH" ]] && BUILD_ARGS+=(--scratch-path "$SCRATCH")
APP="$APP_DIR/$BIN_NAME.app"

mkdir -p "$APP_DIR"
swift build "${BUILD_ARGS[@]}"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN_SRC="${SCRATCH:-$ROOT/.build}/release/$BIN_NAME"
cp "$BIN_SRC" "$APP/Contents/MacOS/$BIN_NAME"
chmod +x "$APP/Contents/MacOS/$BIN_NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>MacMaster</string>
    <key>CFBundleIdentifier</key>
    <string>com.macmaster.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacMaster</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MacMaster</string>
</dict>
</plist>
PLIST

# ad-hoc：本机验证用。分发要换成正真证书 + notarization。
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null 2>&1

print -r -- "$APP"
