#!/bin/zsh
# P49 外接卷夹具：真造一块挂得上的卷，把「外接卷上的 /Applications」从单测升级成真机读数。
#
# 立项原因是两条写在证据里的"本机办不到"：
#   · `docs/analysis/uninstally-adoption.md` §3「两件没做的」第②件——验收那句"实机截图看它出现在
#     列表里"当时判成「本机没有第二块可挂载的非启动卷」，外接卷进清单只剩单测证据（夹具档
#     `VolumeFixtureTier.two`）；
#   · `Scripts/p35b-volumes-capture.sh` 脚本头自己写着「合成值只证明界面会写字，不证明这台机器
#     有两块盘」，而它的立项前提是本机候选根恒为 1。
# 这两个都是**当时读的现场**，不是物理限制：`hdiutil create` 出来的镜像卷在 Foundation 默认档
# 枚举里就是一条正常可浏览卷。挂载态实测（`docs/verification/p49-external-volume/volumes.log`，
# 跑的是 `Scripts/p35a-volumes-probe.sh`）：默认档从 14 条涨到 15 条，新那条 `/Volumes/MMVolumeP49`
# 报 browsable=是 / isDirectory=是 / total=125788160 B / avail 普通=124514304 B——
# 候选根那三道闸（`browsable && isDirectory && total>0`）全过，容量数与启动卷那一对完全不同，
# 所以去重键也不会把它并掉。于是 `nonBootVolumePaths` 给出它、`applicationDirectories` 拼出
# `<卷>/Applications`、`AppScanner` 从那里列出应用，**全程不带 `MM_VOLUME_FIXTURE`**。
#
# 为什么用 UDRW + APFS 而不是只读压缩镜像：取证中途还要往卷里 `seed` 一个 app（"监听范围 =
# 列举范围"那条不变量想要实物），只读镜像做不到。hdiutil 这两条子命令本机都打一行 deprecated
# 警告、指向 `diskutil image create/eject`，行为照旧、退出码 0；这里仍用 hdiutil 是因为脚本要
# 能在旧系统上跑（`diskutil image` 那一套不是到处都有）。
#
# 纪律：盘造在 /tmp 下，卷名带 p49 且不重复，只 detach 这一个挂载点，收尾必卸。
# 不碰用户真盘——没有 diskutil mountDisk / eraseFile / 任何针对别的卷的操作，也不 -force 弹盘。
#
#   ./Scripts/p49-external-volume-fixture.sh create        造盘（幂等；已挂载先卸）
#   ./Scripts/p49-external-volume-fixture.sh mount         挂载，打印挂载点
#   ./Scripts/p49-external-volume-fixture.sh seed <名字>   往卷里的 Applications 放一个最小 .app
#   ./Scripts/p49-external-volume-fixture.sh detach        卸载（保留 .dmg）
#   ./Scripts/p49-external-volume-fixture.sh clean         卸载 + 删整棵工作目录
#   ./Scripts/p49-external-volume-fixture.sh info          挂没挂、挂在哪儿、卷里有什么
#   VOL_NAME=… WORK=… ./Scripts/p49-external-volume-fixture.sh …   同族要并排跑时换名
set -e

WORK=${WORK:-/tmp/mm-p49-volume}
VOL=${VOL_NAME:-MMVolumeP49}
IMG="$WORK/$VOL.dmg"
MOUNT="/Volumes/$VOL"
SEED_APP=${SEED_APP:-AaaP49VolumeFixture}

# make_bundle <父目录> <bundle 名>：一个只有 Info.plist 的最小 .app。
# 不链可执行文件、不签名——AppScanner 那一路只直接读 plist（`Bundle(path:)` 刻意不用，
# 理由写在它的文件头），签名读不到时 developer/teamID 就是空串，照片上那是"未签名第三方"
# 的正常一档，不是夹具的缺陷。
make_bundle() {
  local parent=$1 name=$2
  local app="$parent/$name.app"
  mkdir -p "$app/Contents/MacOS"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "local.mmvolume.$(printf '%s' "$name" | tr 'A-Z' 'a-z').fixture" "$app/Contents/Info.plist"
  plutil -insert CFBundleName -string "$name" "$app/Contents/Info.plist"
  plutil -insert CFBundleDisplayName -string "$name" "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string "$name" "$app/Contents/Info.plist"
  plutil -insert CFBundlePackageType -string APPL "$app/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string 1.0 "$app/Contents/Info.plist"
  plutil -insert CFBundleVersion -string 1 "$app/Contents/Info.plist"
}

is_mounted() { [[ -d $MOUNT ]] }

mount_vol() {
  [[ -f $IMG ]] || { print -u2 -- "✗ 盘不存在：$IMG（先跑 create）"; exit 2; }
  if is_mounted; then print -r -- "（已挂在 $MOUNT）"; return 0; fi
  local out
  out=$(hdiutil attach "$IMG" 2>&1) || { print -u2 -- "✗ 挂载失败：$out"; exit 3; }
  is_mounted || { print -u2 -- "✗ 挂载命令没报错，但 $MOUNT 不在——attach 输出：$out"; exit 3; }
  print -r -- "$MOUNT"
}

detach_vol() {
  is_mounted || { print -r -- "（未挂载）"; return 0; }
  # 只认这一个名字，且必须是真挂载点；宁可停下让人来看，不 -force 弹别人的盘。
  [[ $(basename "$MOUNT") == $VOL ]] || { print -u2 -- "✗ 挂载点名字不是 $VOL，拒绝卸载：$MOUNT"; exit 4; }
  local out
  out=$(hdiutil detach "$MOUNT" 2>&1) || { print -u2 -- "✗ 卸载失败（有进程占着这一卷？先关掉再试，脚本不 -force）：$out"; exit 4; }
  print -r -- "（已卸载 $MOUNT）"
}

case ${1:-help} in
  create)
    if is_mounted; then detach_vol; fi
    mkdir -p "$WORK"
    rm -rf "$WORK/stage"
    # 名字首字母排序决定它在列表里的位置：Aaa… 让这一行落在最上面，照片一眼能看到，
    # 不必为了"让它进画面"去滚列表（也没有任何点击可用）。
    make_bundle "$WORK/stage/Applications" "$SEED_APP"
    hdiutil create -volname "$VOL" -srcfolder "$WORK/stage" -size 120m -fs APFS -format UDRW -ov -o "$IMG" \
      >"$WORK/create.log" 2>&1 || { print -u2 -- "✗ 造盘失败："; cat "$WORK/create.log"; exit 3; }
    print -r -- "✅ $IMG（卷内已带 Applications/$SEED_APP.app；create.log 里那行 deprecated 警告是 hdiutil 自己的，不影响）"
    ;;
  mount)  mount_vol ;;
  seed)
    [[ -n ${2:-} ]] || { print -u2 -- "用法：seed <bundle 名>"; exit 2; }
    is_mounted || { print -u2 -- "✗ 先 mount 才能往卷里放东西"; exit 2; }
    make_bundle "$MOUNT/Applications" "$2"
    print -r -- "✅ $MOUNT/Applications/$2.app"
    ;;
  detach) detach_vol ;;
  clean)
    detach_vol
    # 只删自己造的这一棵；WORK 被换过又恰好指向别处时宁可不动，也不要 rm -rf 一个猜出来的路径。
    [[ ${WORK%/} == /tmp/mm-p49-volume ]] || { print -u2 -- "✗ WORK 不是默认的 /tmp/mm-p49-volume，只卸载不删目录：$WORK"; exit 0; }
    rm -rf "$WORK"
    print -r -- "✅ 已删 $WORK"
    ;;
  info)
    print -r -- "盘：$IMG  $([[ -f $IMG ]] && echo 在 || echo 不存在)"
    print -r -- "挂载点：$MOUNT  $(is_mounted && echo 已挂 || echo 未挂)"
    if is_mounted; then
      print -r -- "容量：$(df -k "$MOUNT" | awk 'NR==2 {print $2" KB 已用 "$3" KB 可用 "$4}')"
      print -r -- "卷内 Applications：$(ls -1 "$MOUNT/Applications" 2>/dev/null | tr '\n' ' ')"
    fi
    ;;
  help|*)
    sed -n '1,40p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
