#!/bin/zsh
# P33b「归属复核」夹具：一棵假 home，把**同一个绝对路径**做成两个应用各自清单里的一行，
# 而且这两行该给出的结论相反——这正是 B 档那条判据的形状（判据挂在证据强度上，不挂在路径上）。
#
# 为什么要有这一族（现读依据，不是凭空想的一种）：
#   审计 `docs/analysis/uninstaller-deep-residual-scope.md` §5 的建议顺序是 **B + A**，
#   而 P33a 的取证 `docs/verification/p33a-contains-scope/contains-scope.log` 记的那三条
#   默认勾选的跨应用项走的是**祖先**那一层（上层目录归别的应用）。
#   §4 另外记了一个完整形态——`Caches/com.example.steamgame` 被归到 **Steam** 名下、
#   页脚「已选 1 项残留 · 524 KB」、默认勾选：它的上层只有 `Caches`，谁都不主张。
#   这一族只做祖先那一层的话，§4 那一幕一个字都不会变，所以复核有**两条线索**，
#   夹具把两族都钉进来（同层那一族是写夹具时从探针返值里当场发现 B 漏掉的，不是事后补的装饰）。
#   本机真 home 只能观察、不能摆布：那几条的形状由别人装的应用决定，重跑一次就可能变。
#   所以这一族把它们钉成一棵可重跑的假 home，照片才敢当"实现之后界面怎么说"的证据。
#
# 为什么不复用 P32a/P32b 那一份 Steam 夹具（这一点在写代码前核过）：
#   那一族的 07/08 两档拍的正是 `SteamGame` 的残留清单，看起来像是现成的邻居形状，
#   但它里面那一条 `Library/Caches/com.example.steamgame` 走的是**包名完全对应**
#   （`ResidualNameMatcher.swift:77`）——按 B 档合同，硬证据一律不降级，
#   所以那两张照片在改动前后一个字都不会变。拿它们当"修好了"的证据就是假绿。
#   会变的是 09（选中 **Steam** 那一张，也就是审计 §4 引用的那一幕）——
#   同一条路径在 Steam 名下只有弱证据，于是这一族确实该翻成「谨慎」＋不勾选。
#   它由 `Scripts/p32b-steam-launcher-capture.sh` 在**它自己的夹具**上重拍一份到
#   `docs/verification/p33b-nesting/p32b-crosscheck/`，不在这里重造：
#   祖先那一层（P33a §3 本机实测那三条的形状）Steam 夹具里没有，必须另摆一棵。
#
# 这一族的三个应用名不是随手起的：
#   `Fork`        归一化压缩后正好 4 个字符（`ResidualNameMatcher.swift:88` 那道
#                 `count >= 4` 的下界）。再短一个字（`App`）包含匹配就不成立，
#                 这一族要拍的那一行当场消失——所以名字本身也是判据的一部分。
#   `IDEFoo`      厂商目录主人：`Caches/IDEFoo` 走硬证据认领自己，是它上层那一层的主人。
#   `AssetsFork`  既是主人的邻居、又是 `Caches/IDEFoo/AssetsFork` 那一条的**正主**：
#                 同一个路径在它自己的清单里是"名称与包名对应"（硬，勾选），
#                 在 Fork 的清单里是"名称包含应用名（非包名对应）"（弱，取消勾选）。
#
# 每一处残留各自钉住的一条（`shot` 的档位在 `Scripts/p33b-nesting-capture.sh`）：
#   Library/Caches/Fork                      硬证据（名称与包名对应）—— 改动前后都该是勾选，
#                                             它是对照组：B 只动那一种弱证据。
#   Library/Caches/ForkExtras                弱证据，但上层只有 `Caches`、没有别人主张，
#                                             而 `ForkExtras` 也不是任何应用的包名或精确名
#                                             —— 维持勾选。钉住"降级要的是别人给得出更硬的证据，
#                                             弱对弱不算"这半句。
#   Library/Caches/IDEFoo                    主人的那一行（03 那一档要看到"主人的行一个都没少勾"）。
#   Library/Caches/IDEFoo/AssetsFork         ★ 第一条线索：对 Fork 只有弱证据，而 AssetsFork
#                                             给它的是「名称与包名对应」（硬）。这一条同时躺在
#                                             IDEFoo 里，两条线索都成立，于是它钉住的是**先后**：
#                                             提醒写「这一项本身归 AssetsFork」而不是绕到祖先。
#                                             它在 AssetsFork 自己的清单里仍是勾选那一行（04）。
#   Library/Caches/IDEFoo/ts-go-fork-embedded
#                                            ★ 第二条线索：名字带 fork、上层归 IDEFoo，
#                                             而 IDEFoo 与 AssetsFork 对这一项本身都给不出硬证据
#                                             —— 这一条是 P33a §3 本机实测那三条的形状。
#   Library/Application Support/IDEFoo       主人的第二行（同上，走类别那一档的谨慎）。
#
# 为什么降级行只有两条（这一族一度有四条）：能装进画面的行数由屏幕决定，不由我想拍几条决定。
#   这台机 1920×1080，`MM_WINDOW_SIZE=1400x1250` 实测被夹到 1400×1050（`sips` 量的，见
#   `docs/verification/p33b-nesting/01-fork-nested-downgraded.png` 的像素尺寸），
#   而详情面板上方那一段（四张统计卡 + 运行状态卡 + 基本信息八行）固定占掉约 700 pt，
#   四条降级行放不下——第四条连标题都在折线以下。"两条线索各拍一条"是这一族非拍不可的最小集，
#   于是砍掉的两条形状各有归属：`Caches/AssetsFork`（同层线索、无嵌套）就是 §4 那一幕，
#   改由 p32b 交叉验证那一档拍原图；`Caches/IDEFoo/com.example.assetsfork`
#   （硬证据是「包名完全对应」而非「名称与包名对应」）与前者只差证据串的种类，
#   由 `ResidualOwnershipReviewTests.testHardEvidenceUnderForeignAncestorStaysSafe`
#   与 `testSameLevelBundleIdClaimBecomesCaution` 钉住，不必占一帧照片。
#
# 尺寸一律真实字节（`dd`），不用稀疏文件——沿用 Steam 夹具那条理由：本体大小走 `st_size`
# （`FileTreeWalker.swift:65`），残留大小走 `st_blocks × 512`（`ResidualScanner.swift:317-342`），
# 稀疏文件在后者上会显示成接近 0，"我们没收到这一项"与"收到了但算成 0"就分不开。
#
# 这一族**不启动任何 bundle**，也没有进程生命周期要管：照片要的是"它躺在磁盘上、界面怎么报"。
# 所以和 Steam 夹具一样没有看门狗，收尾交给调用方删目录。
#
#   ./Scripts/p33b-nesting-fixture.sh                  打印新建的夹具根目录
#   FIX=$(./Scripts/p33b-nesting-fixture.sh)           交给 Scripts/p33b-nesting-capture.sh
set -e

fixture_root=$(mktemp -d /tmp/macmaster-p33b-nesting.XXXXXX)

# make_app <bundle 名> <包标识> <本体额外字节数（MiB）>
# 三个都是普通 bundle：真实可执行文件 + 一段真实字节，目的是让列表里三行的"本体"各不相同，
# 照片上能一眼认出选中的是哪一行。
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

make_app Fork       com.example.fork        2
make_app IDEFoo     com.example.idefoo      3
make_app AssetsFork com.example.assetsfork  1

# make_residual <相对路径> <文件名> <字节数（MiB）>
make_residual() {
  local rel=$1 file=$2 mib=$3
  local dir="$fixture_root/Library/$rel"
  mkdir -p "$dir"
  dd if=/dev/zero of="$dir/$file" bs=1048576 count="$mib" status=none
}

# Fork 自己的硬证据行：名称与包名对应，改动前后都该是「安全」＋勾选。
make_residual Caches/Fork data.bin 2
# 弱证据但上层没人主张：`Caches` 这一层不属于任何应用，所以维持勾选。
make_residual Caches/ForkExtras cache.bin 1

# 主人的目录，以及躺在它里面的两条：一条两条线索同时成立（同层优先），
# 一条是"只有祖先"那一族（P33a §3 本机实测的形状）。
make_residual Caches/IDEFoo main-cache.bin 4
make_residual Caches/IDEFoo/AssetsFork plugin.bin 3
make_residual Caches/IDEFoo/ts-go-fork-embedded cache.bin 1

# 主人的第二行：证明"复核只发生在被扫的那一份清单上，主人自己的清单一个字节都没少勾"。
make_residual "Application Support/IDEFoo" profile.bin 2

# 假 brew 账本留空目录：`MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 会把来源识别的前缀指向
# `$home/.homebrew`（`MMUninstaller.swift:234` 附近那对 factory），没有这一档时来源那一行
# 是「无法判定」。这一族不在乎来源，但照片上那一行不该莫名其妙变成另一种样子，
# 所以把它固定成"账本存在、里面没有"。
mkdir -p "$fixture_root/.homebrew"

print -r -- "$fixture_root"
