#!/bin/zsh
# P53 外接卷夹具（跨卷删除落点专用）：造一块真能挂上的卷，但**挂载点在 /tmp 之下**。
#
# 为什么要另起一支而不是直接用 `Scripts/p49-external-volume-fixture.sh`：
#   P49 那支挂在 `/Volumes/$VOL`，它要量的正是"这块卷进不进候选根、进不进应用清单"，
#   挂在系统默认位置才是那一问的正确形状。P53 要量的是**另一问**——
#   `docs/analysis/uninstaller-app-body-risk.md` §6 第二条：跨卷那次删除的**落点**在哪块卷上、
#   拔盘之后「最近操作」那一行长成什么样。要真的删一次就必须让
#   `MM_UNINSTALL_CONFIRM_FIXTURE_HOME` 认这个根，而那个钩子只认 `/tmp` 之下的真实目录
#   （`UninstallFixtureHooks.canonicalHome` 先查前缀再 `realpath` 再查一次前缀——
#   用符号链接把 `/Volumes/...` 引到 `/tmp` 下面过不了第二道，软链会被解析回去）。
#   所以这里把挂载点本身放在 `/tmp` 下：`hdiutil attach -mountpoint`，路径是真的、卷是另一块卷。
#   这条改动的代价写进照片日志：**量到的是"源文件在第二块卷上"这一条，路径字面不是 `/Volumes/…`**。
#   `FileManager.trashItem` 决定落点看的是那个 URL 属于哪块卷，不是它挂在哪个目录名底下，
#   所以落点这一族读数仍然成立；但"界面上这一行印出来是 /Volumes/…"那一条不在这族的判据里（那是 P49 的）。
#
# 纪律（照 P49 那一支抄）：盘造在 /tmp 下，卷名唯一，只 detach 自己这一个挂载点，
# 且 detach 前必须确认那个路径**当前就是挂载点**（不是就什么都不动）；不 -force；
# 不碰用户真盘，没有 diskutil mountDisk / eraseFile。
#
#   ./Scripts/p53-cross-volume-fixture.sh create     造盘（幂等；已挂先卸）
#   ./Scripts/p53-cross-volume-fixture.sh mount      挂到 $MP，打印 realpath 与卷内清单
#   ./Scripts/p53-cross-volume-fixture.sh detach     卸载（保留 .dmg 与挂载点空目录）
#   ./Scripts/p53-cross-volume-fixture.sh probe      只读取数：挂没挂、落在哪儿、.Trashes 里有什么
#   ./Scripts/p53-cross-volume-fixture.sh clean      卸载 + 删整棵工作目录与挂载点
set -e

WORK=${WORK:-/tmp/mm-p53-volume}
VOL=${VOL_NAME:-MMVolumeP53}
MP=${MP:-/tmp/mm-p53-mnt}
IMG="$WORK/$VOL.dmg"
SEED=${SEED_APP:-AaaP53CrossVolume}

# 卷里的应用名一律以 Aaa 开头：列表按名字排，这一行落在最上面，不必为"让它进画面"滚列表。
make_bundle() {
  local parent=$1 name=$2
  local app="$parent/$name.app"
  mkdir -p "$app/Contents/MacOS"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "local.mmvolume.$(printf '%s' "$name" | tr 'A-Z' 'a-z').p53" "$app/Contents/Info.plist"
  plutil -insert CFBundleName -string "$name" "$app/Contents/Info.plist"
  plutil -insert CFBundleDisplayName -string "$name" "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string "$name" "$app/Contents/Info.plist"
  plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string 1.0 "$app/Contents/Info.plist"
  plutil -insert CFBundleVersion -string 1 "$app/Contents/Info.plist"
  # 本体里放一点实际字节：落点那一条要能用体积对账（废纸篓里那个是不是同一个 bundle）。
  print -r -- "p53 cross-volume fixture bundle" >"$app/Contents/Resources-note.txt"
}

# 挂载判定必须先 realpath 再比。
# 第一次实跑就栽过这一条：`mount` 印的是 `/dev/disk13s1 on /private/tmp/mm-p53-mnt (...)`，
# 而 `$MP` 写的是 `/tmp/mm-p53-mnt`——直接比字符串永远不匹配，于是 create 那一步
# "已挂先卸"没卸、mount 那一步重复挂了一次，更要紧的是 detach/clean 会当成"本来就没挂"
# 而把一块真的挂着的卷留在机器上。判据不能靠缺席的路径写法。
is_mounted() {
  [[ -d $MP ]] || return 1
  local real
  real=$(cd "$MP" && pwd -P)
  mount | grep -q " on $real ("
}

case ${1:-help} in
  create)
    if is_mounted; then
      hdiutil detach "$MP" >/dev/null
    fi
    mkdir -p "$WORK"
    rm -rf "$WORK/stage"
    make_bundle "$WORK/stage/Applications" "$SEED"
    # 夹具 home 也塞进同一块卷：残留根跟着 home 走，全部证据落在这块卷上，真 ~/Library 一点不碰。
    mkdir -p "$WORK/stage/Library/Caches/local.mmvolume.aaap53crossvolume.p53"
    print -r -- "residual" >"$WORK/stage/Library/Caches/local.mmvolume.aaap53crossvolume.p53/keepme.plist"
    hdiutil create -volname "$VOL" -srcfolder "$WORK/stage" -size 120m -fs APFS -format UDRW -ov -o "$IMG" \
      >"$WORK/create.log" 2>&1 || { print -u2 -- "✗ 造盘失败："; cat "$WORK/create.log"; exit 3; }
    print -r -- "✅ $IMG（卷内带 Applications/$SEED.app 与 Library/Caches/<bundleid>）"
    ;;
  mount)
    [[ -f $IMG ]] || { print -u2 -- "✗ 盘不存在：$IMG（先跑 create）"; exit 2; }
    mkdir -p "$MP"
    if ! is_mounted; then
      out=$(hdiutil attach "$IMG" -mountpoint "$MP" -nobrowse -noautoopen 2>&1) \
        || { print -u2 -- "✗ 挂载失败：$out"; exit 3; }
    fi
    # 「卷里有没有那个应用」这一条默认要查（造完盘第一次挂，缺东西就是夹具坏了）。
    # 但 P53 那一族在**删过之后**还要再挂一次，那时候本体已经在卷内 `.Trashes` 里、
    # `Applications/` 里当然是空的——那正是要看的状态，所以留 `EXPECT_APP=0` 这一档跳过。
    # 不跳过的话这里会以"夹具不完整"的姿态退出，读起来和真的挂载失败一模一样。
    if [[ ${EXPECT_APP:-1} == 1 ]]; then
      [[ -d "$MP/Applications/$SEED.app" ]] || { print -u2 -- "✗ 挂上了但卷里没有 Applications/$SEED.app"; exit 3; }
    else
      print -r -- "（EXPECT_APP=0：不查 Applications/$SEED.app——删除之后再挂一次时它本就该不在）"
    fi
    # 打印 realpath：钩子认的就是这一串，`/tmp` 会解析成 `/private/tmp`，抄错一个前缀钩子直接忽略。
    print -r -- "MP_REAL=$(cd "$MP" && pwd -P)"
    print -r -- "挂载点：$MP  inode 属卷：$(df -i "$MP" | awk 'NR==2 {print $1}')"
    print -r -- "卷内 Applications：$(ls -1 "$MP/Applications" 2>/dev/null | tr '\n' ' ')"
    ;;
  detach)
    is_mounted || { print -r -- "（$MP 本来就没挂）"; exit 0; }
    out=$(hdiutil detach "$MP" 2>&1) || { print -u2 -- "✗ 卸载失败（有进程占着这一卷？先关掉再试，脚本不 -force）：$out"; exit 4; }
    print -r -- "（已卸载 $MP）"
    ;;
  probe)
    print -r -- "盘：$IMG  $([[ -f $IMG ]] && echo 在 || echo 不存在)"
    print -r -- "挂载点：$MP  $(is_mounted && echo 已挂 || echo 未挂)"
    if is_mounted; then
      print -r -- "容量：$(df -k "$MP" | awk 'NR==2 {print $2" KB 已用 "$3" KB 可用 "$4}')"
      print -r -- "卷内 Applications：$(ls -1 "$MP/Applications" 2>/dev/null | tr '\n' ' ')"
      print -r -- "卷内 .Trashes：$(ls -1R "$MP/.Trashes" 2>/dev/null | tr '\n' ' ' || echo 读不到)"
    fi
    ;;
  clean)
    if is_mounted; then
      out=$(hdiutil detach "$MP" 2>&1) || { print -u2 -- "✗ 卸载失败，不删目录：$out"; exit 4; }
    fi
    [[ ${WORK%/} == /tmp/mm-p53-volume ]] || { print -u2 -- "✗ WORK 不是默认的 /tmp/mm-p53-volume，只卸载不删目录：$WORK"; exit 0; }
    rm -rf "$WORK"
    rmdir "$MP" 2>/dev/null || true
    print -r -- "✅ 已删 $WORK"
    ;;
  help|*)
    sed -n '1,40p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
