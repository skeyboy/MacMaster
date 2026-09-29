#!/bin/zsh
# 组装可运行的 .app：SPM 只产出裸可执行文件，没有 bundle 就看不到窗口、也没有
# 正确的 Bundle Identifier 与 TCC 归属。这里做最小可用的一套：Release 编译 → 铺
# bundle 结构 → 写 Info.plist → ad-hoc 签名（签名必须做，否则每次启动都被当成
# 一个新应用，TCC 授权与废纸篓归属都会漂移）。
set -e

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/MacMaster.app"
BIN_NAME="MacMaster"

swift build -c release

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
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
