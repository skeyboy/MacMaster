#!/bin/zsh
# 组装可运行的 .app：SPM 只产出裸可执行文件，没有 bundle 就看不到窗口、也没有
# 正确的 Bundle Identifier 与 TCC 归属。这里做最小可用的一套：Release 编译 → 铺
# bundle 结构 → 写 Info.plist → ad-hoc 签名（签名必须做，否则每次启动都被当成
# 一个新应用，TCC 授权与废纸篓归属都会漂移）。
#
#   ./Scripts/make-app.sh                                  # 默认 build/MacMaster.app
#   ./Scripts/make-app.sh -o /tmp/mmb-x -s /tmp/mm-sc-x     # 隔离构建
#   HARDENED=1 ./Scripts/make-app.sh ...                    # 额外打 --options runtime（见文末签名段）
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

# 版本号的唯一真源在这里：设置页「关于」读的是 bundle 的 Info.plist（`SettingsView.swift` 的
# `versionText`，现读 :298——按符号名找，别按行号找），
# 而那份 plist 是本脚本写的。发版时 `VERSION=1.1.0 BUILD=7 ./Scripts/make-app.sh`，
# 不要到下面的 plist 里改字面量——那会让" About 显示的版本"和"打包脚本产出的版本"分家。
VERSION=${VERSION:-1.0.0}
BUILD=${BUILD:-1}

# 候选产物要能自证它是哪棵树构建的：P12/P13/P15/P19 四轮核验的产物版本号全是 1.0.0(1)，逐字相同，
# 只看 bundle 分不出"带某一轮改动的那一份"和"没带的那一份"——而取证日志的归因头记的是
# **脚本那棵树**，不是**被测二进制那棵树**，这两件事在"改完取证脚本再跑一遍旧产物"时会分开。
# 所以把 commit 打进 plist（自定义键，系统忽略）。-uno：打包时工作区里全是本轮新写的
# 未跟踪证据文件，算进脏活就永远 -dirty（同一个理由见 p7-release-check.sh 的归因头）。
GIT_COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git -C "$ROOT" status --porcelain -uno 2>/dev/null) ]]; then GIT_COMMIT="$GIT_COMMIT-dirty"; fi

mkdir -p "$APP_DIR"
swift build "${BUILD_ARGS[@]}"

# 同一份 plist 里再打一个**内容**指纹（P22 之后才有）。为什么 `-dirty` 不够、
# 以及取证侧怎么用它当场拒拍，全写在 `Scripts/mm-provenance.sh` 的头部注释里。
# 算的时机在编译**之后**：算早了的话，编译那几十秒里被改的源码会被记成"改之前的那一份"，
# 而二进制是照改之后编出来的——这一支自己就成了它要拦的那个形状。
source "$ROOT/Scripts/mm-provenance.sh"
SRC_DIGEST=$(mm_source_digest "$ROOT" || echo 未知)

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN_SRC="${SCRATCH:-$ROOT/.build}/release/$BIN_NAME"
cp "$BIN_SRC" "$APP/Contents/MacOS/$BIN_NAME"
chmod +x "$APP/Contents/MacOS/$BIN_NAME"

# 图标：由 ./Scripts/make-icon.sh 画出来并核过十档的 icns，仓库里带着。
# 这里只在文件真的存在时才写 CFBundleIconFile——键在而文件没了，Finder 会退回通用图标，
# 而 plist 看上去"有图标"，那是比"没这一键"更难查的假象。
ICON_KEY=""
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEY='    <key>CFBundleIconFile</key>
    <string>AppIcon</string>'
else
    print -u2 -- "提示：缺 Resources/AppIcon.icns，本次产物不写 CFBundleIconFile（跑 ./Scripts/make-icon.sh 生成）"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>MacMaster</string>
${ICON_KEY}
    <key>CFBundleIdentifier</key>
    <string>com.macmaster.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacMaster</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>MMGitCommit</key>
    <string>$GIT_COMMIT</string>
    <key>MMSourceDigest</key>
    <string>$SRC_DIGEST</string>
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
# 这里不能只把输出丢掉就完事：脚本开了 set -e，签名一失败就静默退出 1，
# 而 SwiftPM 已经打印过 "Build complete!"，看上去像构建成功、产物其实没签好。
# 实测踩过的一次：-o 传成了 .../MacMaster.app，里面套了一层同名 bundle，--deep 直接失败。
#
# HARDENED=1 额外打 `--options runtime`。这**不是任何一种发布形态**（发布要证书 + 公证），
# 它只是 P11 实测轮的量具：同一份二进制上让 codesign 的 flags 多出 0x100(runtime)，
# 好把"带这个标志到底打断什么"从预测变成照片。默认关闭，产物的形态与以前逐字节相同。
SIGN_FLAGS=(--force --deep --sign - --timestamp=none)
[[ "${HARDENED:-0}" == "1" ]] && SIGN_FLAGS+=(--options runtime)
if ! codesign "${SIGN_FLAGS[@]}" "$APP"; then
    print -r -- "codesign 失败：$APP（上面是原错误输出）" >&2
    exit 1
fi

# 打完自己读回来：写 --options runtime 的人以为写了，和真的带 0x100(runtime)，
# 中间隔着 codesign 是否吃下这个参数——不吃它只警告不报错。
runtime_flags=$(codesign -dv "$APP" 2>&1 | grep -o 'flags=0x[0-9a-f]*([a-z,]*)' | head -1)
print -r -- "签名档次：${runtime_flags:-（读不到 flags）}（HARDENED=${HARDENED:-0}）"

print -r -- "产物源码指纹：$SRC_DIGEST（同一键写进 plist 的 MMSourceDigest；取证脚本当场比这一个数，不等就拒拍）"
print -r -- "$APP"
