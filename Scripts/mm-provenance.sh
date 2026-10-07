#!/bin/zsh
# 产物归因：把"照片拍的是哪一份源码构建出来的二进制"变成一个能算、能比、能拒的数。
#
# 为什么要这一支（P22 那一轮撞出来的）：取证日志一直有两行归因——`# repo:` 是**跑脚本的树**、
# `MMGitCommit` 是**被签名的产物**。P22 收口时发现这两行**逐字相同也不能说明照片是最终的**：
# 那九张照片是在"搬一个私有辅助函数"之前拍的，函数搬完之后重新构建，
# 而 commit 短sha 加 `-dirty` 对"工作区改了哪几行"完全不敏感——同一个 `-dirty` 底下
# 可以是两份不同的源码。画面也逐像素一样（搬的那个函数不影响任何一屏），
# 所以没有任何一张照片能自己看出来。
#
# 于是把归因从"哪一次提交"改成"哪一份源码内容"：
#   mm_source_digest   当前树里**进了编译的那部分**的内容指纹
#   mm_provenance_check 拿产物的 plist 比这个指纹，不等就拒绝出片
# 检查放在**出片之前**而不是事后审计：事后没人再有一棵"当时那棵树"可比（提交之后工作区就干净了），
# 而 mtime 排序（源 < 产物 < 照片）在 clone 之后也一定不成立——git 检出会把照片的 mtime 改成检出时刻。
# 所以这一件事只有"当场拒"这一种成立形态。
#
# 为什么是共享文件而不是各写一遍：这个数的**正确性就等于两边算得一模一样**。
# 打包侧和取证侧各抄一份哈希配方，抄漏一个路径或差一个 `--binary`，
# 结果要么是假的不等（每次都拒，然后人把这个检查关掉），要么是假的相等（检查白装）。
#
# 已知松处，写在明处：
#   ① 覆盖的是 `git ls-files -- Sources Packages Resources Package.swift` 去掉
#      `Packages/*/Tests/**` 之后那 **92 个**编译输入（本轮现数，加总可对上）：
#      壳层 `Sources/` 6 + 各包 `Sources/` 75 + 九个包各自的 `Package.swift` 9 +
#      根 `Package.swift` 1 + `Resources/AppIcon.icns` 1。icns 在里面是故意的——它就是
#      关于页照片上那个图标（P10 那一族），换掉它而产物不变，照片就成了假证。
#      测试源码**不在**里面：改判据不改产物，为此拒拍等于逼人把门禁关掉。
#      不在里面的还有 `make-app.sh` 自己的构建参数与签名——那几样另有 `MMGitCommit`、
#      `# codesign:`、`# plist:` 三行管。这一支主张的是"编译进 bundle 的那一份输入同源"。
#   ② 未跟踪文件按**换行**分隔读名字：文件名里带换行的会算错。本仓库没有这种名字，
#      真有了的话这条会算出两份不同的指纹（偏保守：多拒一次，不会放过不等）。
#   ③ `git diff HEAD` 不含 `--ignore-all-space`，所以只改缩进、搬代码也会变指纹。这是要的：
#      P22 那一次改的正是"位置"，不是"内容语义"。
#   ④ 指纹算的是**当前**工作区。同一棵树上改两次、中间没重新构建，第二次就会拒——
#      这正是它要拦的那件事，不是误伤。

# mm_source_digest <仓库根>：打印 `<短sha>+<内容指纹8位>`。不是 git 仓库时返回 1。
MM_SOURCE_PATHS=(Sources Packages Resources Package.swift ':(exclude)Packages/*/Tests/**')
mm_source_digest() {
  local root=${1:?用法: mm_source_digest <仓库根>}
  local head content
  head=$(git -C "$root" rev-parse --short HEAD 2>/dev/null) || return 1
  # 已跟踪部分：相对 HEAD 的**全部**改动（暂存的和没暂存的都算，因为编译读的是工作区）。
  # 未跟踪部分：新加 yet 没 git add 的源文件同样进编译，必须一起进指纹——
  # 这正是 P21 那一份 `DiskRisk.swift` 落地当天的形状。
  content=$(
    {
      git -C "$root" diff HEAD --binary -- "${MM_SOURCE_PATHS[@]}"
      git -C "$root" ls-files --others --exclude-standard -- "${MM_SOURCE_PATHS[@]}" \
        | while IFS= read -r f; do cat "$root/$f"; done
    } | shasum -a 256 | cut -c1-8
  )
  printf '%s+%s' "$head" "$content"
}

# mm_provenance_check <仓库根> <app 路径>：不等则返回 1。
# 结论写进两个全局，供调用方原样打进日志——**拒的时候也要把两个数留在纸上**，
# 不然人只能重跑一遍才知道差在哪。
MM_TREE_DIGEST=''
MM_APP_DIGEST=''
mm_provenance_check() {
  local root=${1:?用法: mm_provenance_check <仓库根> <app>}
  local app=${2:?用法: mm_provenance_check <仓库根> <app>}
  MM_TREE_DIGEST=$(mm_source_digest "$root") || return 2
  # 没有这一键 = 这份产物不是当前 make-app.sh 构建的（更早的产物、或裸 `swift build` 的产物）。
  # 这种情况**不放过**：P22 的教训正是"看不出来"，而"没有指纹"是一种更彻底的看不出来。
  MM_APP_DIGEST=$(plutil -extract MMSourceDigest raw "$app/Contents/Info.plist" 2>/dev/null) \
    || { MM_APP_DIGEST='（产物无 MMSourceDigest 键）'; return 1; }
  [[ $MM_TREE_DIGEST == "$MM_APP_DIGEST" ]]
}

# 供调用方打印的一行。为什么单独一个函数：五个脚本各排一次格式，
# 就会有一个排得跟别人不一样，而这一行是要拿 grep 对账的。
mm_provenance_line() {
  print -r -- "# digest: tree=$MM_TREE_DIGEST app=$MM_APP_DIGEST"
}
