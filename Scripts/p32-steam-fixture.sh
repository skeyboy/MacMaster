#!/bin/zsh
# P32a「Steam 启动器型 bundle」夹具：一棵假 home，把**启动器**与**游戏本体**放在两个位置上，
# 让我们能在真界面上看清"卸载页现在拿这一族应用说出什么"。
#
# 为什么要有这一族（参考项目的原话，本轮现读）：
#   Mole `docs/github-references/Mole/lib/uninstall/steam.sh:5`
#     "Its bundle size is the launcher's size, not the installed game"
#   —— 这类 bundle 的本体只有几百字节（一个 shell 脚本 + 两份 plist），
#      游戏在 `~/Library/Application Support/Steam/steamapps/common/<游戏名>/`，几十 GB。
#   我们这一侧现在对 steam 一无所知（`Sources/` 与 `Packages/` 大小写不敏感 grep 0 命中，
#   这一条 P30b 已现读复核），所以它会被当成"一个很小的普通应用"显示。
#   这一族拍的就是"当成普通应用"具体长什么样：名字、大小、来源、残留清单、确认框里的合计。
#
# 本机没有 Steam（现读：`/Applications/Steam.app` 与 `~/Library/Application Support/Steam`
# 两处都不存在），所以这一族**全部靠夹具**，没有任何一档能"点名本机真在跑的应用"来对照。
# 这也决定了夹具要写成参考项目认定它的那几种形态，而不是我们凭空想的一种。
#
# 三种启动器形态，各自对应参考项目的一条依据：
#   Applications/SteamGame.app   —— `CFBundleExecutable` 与 bundle 同名，脚本就是那个可执行文件。
#                                   Mole 的识别合同走这一档（`steam.sh:23-62`：读 Info.plist 的
#                                   `CFBundleExecutable`，取不到才退回 bundle 文件名）。
#   Applications/SteamRunSh.app  —— 可执行文件叫 `run.sh`、`CFBundleExecutable` 也写 `run.sh`。
#                                   Pearcleaner 走的是另一条：`Logic/AppPathsFetch.swift:447-463`
#                                   的 `getSteamGameId` 把路径**写死**成 `Contents/MacOS/run.sh`，
#                                   再去 grep `steam://run/`。两份参考对"脚本叫什么"没有共识，
#                                   所以夹具两种都要有，实现时才知道该跟谁。
#   Applications/SteamNoId.app   —— **整份 Info.plist 里没有 CFBundleIdentifier**。
#                                   这不是刁难：Mole 在 `lib/uninstall/batch.sh:928` 与
#                                   `lib/clean/apps.sh:257` 都注释过 Steam 启动器 bundle
#                                   "出货时就没有包标识"。没有它，我们这一侧的
#                                   `AppScanner.bundleIdentifier`（`AppScanner.swift:63-67`）
#                                   返回空串，来源识别与残留匹配的证据面一起变窄。
#   Applications/PlainTool.app   —— 对照组：一个普通 bundle，本体里塞了 8 MiB 的真实字节。
#                                   照片上它和启动器排同一张表，"大小"那一列自己就会说话。
#   Applications/Steam.app       —— 启动器**自己**（包名 `com.valvesoftware.Steam`）。
#                                   它要回答的是另一个问题：卸载它时，
#                                   `~/Library/Application Support/Steam`（真机里装着
#                                   `steamapps/common/` 下所有已装游戏）会不会被我们
#                                   当成一条"残留"端出来。这一档在 08 那张照片上。
#   Applications/Steam Shortcuts/DeepShortcut.app
#                                —— 藏在子目录里的 bundle。我们的应用根
#                                   （`AppScanner.swift:28` `defaultSearchDirectories`，
#                                   非递归枚举）应当**看不见**它；这一档是用来钉住
#                                   "清单里那几行是全集还是子集"这句话的，
#                                   也是 Pearcleaner 把 `~/Desktop`（`Logic/Locations.swift:62`）
#                                   列为扫描根之后我们与它的第一处行为差异。
#
# 游戏本体放在参考项目的同一个位置（不是我们编的）：
#   Library/Application Support/Steam/steamapps/common/SteamGame/GameData.bin  —— 24 MiB 真实字节
#   Library/Application Support/Steam/appmanifest_1091500.acf                  —— Steam 的账本，
#       Pearcleaner `AppPathsFetch.swift:343-355` 用文件名里的号与启动器脚本里的号对撞，
#       所以我们把号写成能对上的：三份启动器的 `steam://` 分别是 1091500 / 220 / 440，
#       账本也有对应的三份 acf。
#   另两处是"我们的残留引擎现在确实够得到"的形状，用来对照上面那处"够不到"：
#   Library/Application Support/SteamGame/settings.dat —— `Application Support` 的**直接子项**，
#       名称与 bundle 精确对应，严格档就该收它（`ResidualScanner.swift:208` 那条 entry）。
#   Library/Caches/com.example.steamgame/ —— 包名精确对应的缓存目录（只有带包标识的那一份有）。
#
# 尺寸一律写真实字节，不用稀疏文件：本体大小走 `st_size`（`FileTreeWalker.swift:65`），
# 而残留大小走 `st_blocks × 512`（`ResidualScanner.swift:317-342`）。稀疏文件在后者上会显示成
# 接近 0，那会把"我们没扫到游戏"与"扫到了但算成 0"混成一张照片。
#
#   ./Scripts/p32-steam-fixture.sh            # 打印新建的夹具根目录
#   FIX=$(./Scripts/p32-steam-fixture.sh)     # 交给 p32-steam-capture.sh
#
# 夹具没有看门狗（与 P31 那一份的区别）：这里的 bundle **不该被启动**——它们是可执行
# shell 脚本，`open` 它们会真的去叫 `steam://`，而本机没有 Steam 只会弹一个报错。
# 这一族要的是"它躺在磁盘上、界面怎么报"，所以没有进程生命周期要管，
# 也就不需要 900 秒自杀定时器；收尾交给调用方删目录。
set -e

fixture_root=$(mktemp -d /tmp/macmaster-steam-fixture.XXXXXX)

# make_launcher <夹具内父目录> <bundle 名> <可执行文件名> <包标识（空=整条不写）> <steam appid>
# 脚本内容照 Mole 的合同写：shebang + 注释 + **恰好一行**有效命令 `open steam://run/<号>`
# （`docs/github-references/Mole/lib/uninstall/steam.sh:23-62`：≤4096 字节、首行是 shebang、
# 非空非注释的有效行必须正好一行且匹配那条 URL）。
# 写成"正好一行"不是形式主义：参考项目正是靠这个约束把"注释里举例的 URL"和
# "多命令脚本"挡在识别之外，我们若要判同一件事，边界就得同样收得住。
make_launcher() {
  local parent=$1 dir=$2 exec_name=$3 bundle_id=$4 appid=$5
  local app="$fixture_root/$parent/$dir.app"
  mkdir -p "$app/Contents/MacOS"
  plutil -create xml1 "$app/Contents/Info.plist"
  [[ -n $bundle_id ]] && plutil -insert CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
  plutil -insert CFBundleName -string "$dir" "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string "$exec_name" "$app/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string 1.0 "$app/Contents/Info.plist"
  plutil -insert CFBundleVersion -string 1 "$app/Contents/Info.plist"
  plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
  cat > "$app/Contents/MacOS/$exec_name" <<EOF
#!/bin/bash
# generated by Steam
open steam://run/$appid
EOF
  chmod +x "$app/Contents/MacOS/$exec_name"
}

make_launcher Applications SteamGame  SteamGame  com.example.steamgame 1091500
make_launcher Applications SteamRunSh run.sh    ""                      440
# 包名与位置都对得上、但可执行文件是普通名字的一份：用来把"没有包标识"这一件事
# 单独隔离出来（另外两份各自还多了一个变量：可执行文件叫 run.sh / 有包标识）。
make_launcher Applications SteamNoId  SteamNoId ""                      220

# 对照组：普通 bundle，本体里放真实字节。尺寸用 dd 写满，不是稀疏文件（理由在顶上）。
plain="$fixture_root/Applications/PlainTool.app"
mkdir -p "$plain/Contents/MacOS" "$plain/Contents/Resources"
plutil -create xml1 "$plain/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string com.example.PlainTool "$plain/Contents/Info.plist"
plutil -insert CFBundleName -string PlainTool "$plain/Contents/Info.plist"
plutil -insert CFBundleExecutable -string PlainTool "$plain/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0 "$plain/Contents/Info.plist"
printf 'echo placeholder\n' > "$plain/Contents/MacOS/PlainTool"
chmod +x "$plain/Contents/MacOS/PlainTool"
dd if=/dev/zero of="$plain/Contents/Resources/payload.bin" bs=1048576 count=8 status=none

# 启动器**自己**那一份（`/Applications/Steam.app`，包名照真机 `com.valvesoftware.Steam`）。
# 它和上面三份不是一类问题：上面三份是"某个游戏的启动器"，这一份是"所有游戏的总入口"，
# 而它的名字正好等于 `~/Library/Application Support/Steam` 那一个目录——
# 我们的残留引擎在严格档就会按"名称与包名对应"收下它（`ResidualScanner.swift:208` 那条 entry
# 是 `Application Support` 的直接子项，深度 0 就够）。真机上那一个目录里装着
# `steamapps/common/` 下**全部已装游戏**，所以这一档要拍的问题是：
# "卸载 Steam 本体时，我们会把整个游戏库作为一条'残留'端出来吗？"
make_launcher Applications Steam Steam com.valvesoftware.Steam 0

# 子目录里的那一份：非递归的应用根不该看见它。
make_launcher "Applications/Steam Shortcuts" DeepShortcut DeepShortcut com.example.DeepShortcut 730

# 游戏本体与 Steam 的账本（位置与文件名字照参考项目）。
game="$fixture_root/Library/Application Support/Steam/steamapps/common/SteamGame"
mkdir -p "$game"
dd if=/dev/zero of="$game/GameData.bin" bs=1048576 count=24 status=none
print -r -- "1091500" > "$game/steam_appid.txt"
mkdir -p "$fixture_root/Library/Application Support/Steam/steamapps"
for id in 1091500 220 440; do
  cat > "$fixture_root/Library/Application Support/Steam/steamapps/appmanifest_$id.acf" <<EOF
"appmanifest"
{
    "appid"        "$id"
    "name"         "SteamGame"
    "sizeOnDisk"   "25165824"
}
EOF
done

# 严格档现在够得到的两处：直接子项精确名 + 包名精确对应的缓存与偏好。
mkdir -p "$fixture_root/Library/Application Support/SteamGame"
dd if=/dev/zero of="$fixture_root/Library/Application Support/SteamGame/settings.dat" bs=1024 count=1024 status=none
mkdir -p "$fixture_root/Library/Caches/com.example.steamgame"
dd if=/dev/zero of="$fixture_root/Library/Caches/com.example.steamgame/cache.bin" bs=1024 count=512 status=none
# Preferences 这一层要自己建：`plutil -create` 只建文件、不建父目录（第一次实跑就折在这里）。
mkdir -p "$fixture_root/Library/Preferences"
plutil -create xml1 "$fixture_root/Library/Preferences/com.example.steamgame.plist"
plutil -insert launches -integer 3 "$fixture_root/Library/Preferences/com.example.steamgame.plist"

# 假 brew 账本留空目录：`MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 会把来源识别的前缀指向
# `$home/.homebrew`（`MMUninstaller.swift:234`），没有这一档时来源那一行是「无法判定」——
# 照片里"来源"与"这是启动器"两件事互不干扰，才能各说各的。
mkdir -p "$fixture_root/.homebrew"

print -r -- "$fixture_root"
