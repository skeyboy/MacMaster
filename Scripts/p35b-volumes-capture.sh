#!/bin/zsh
# P35b「候选根」取证：磁盘页面包屑条上那一枚"这台机器还有 N 卷可以切换分析"（A 档）
# 与概览页页脚那句"N 个卷"（B 档，口径从挂载点条数换成候选根数）的逐档分支。
#
# 立项原因：本机**只有一个候选根**（一块内部盘，P35a §3 实测默认档 14 条里 13 条不可浏览），
# 所以"还有 N 卷"这一句和"未能读取卷列表"那一句，在这一台上不挂别的卷就永远不出现。
# P35a §11.5 当时接受的是"正分支只有单测、界面上那一行将只有实拍负分支"；
# 本轮把它补成照片：判据留在 `MMCore/VolumeRoots.swift` 的纯函数里（单测钉规则），
# 画面由 `MM_VOLUME_FIXTURE` 这一支合成快照出（照片钉"这句话放得下、也确实是这么写的"）。
# **合成值只证明界面会写字，不证明这台机器有两块盘**——每一档的 .log 里都自带一行
# 「已生效：这是合成快照」的留痕，就是把这句话写在证据里。
# 〔P49 更正：这半句今天只对 `zero`/`fail` 两档还成立。`two` 那一档的形状已经在这台机器上
# 真出现过——`Scripts/p49-external-volume-fixture.sh` 用 `hdiutil` 挂一块 APFS 镜像卷，候选根就变 2，
# 实拍七档见 `Scripts/p49-external-volume-capture.sh` 与 `docs/verification/p49-external-volume/`。
# 本脚本这八张仍是合成档，那两行免责声明照旧一句都不许删；改的是"只有合成档"这个前提。〕
#
# 八档各拍什么（01~06 在磁盘页 = A 档，07~08 在概览页 = B 档）：
#   01 真机档（不注夹具）：候选根 = 1 ⟹ 那一格**缺席**。这一张是负分支的实拍。
#   02 夹具 two：「这台机器还有 1 卷可以切换分析」。N 的分母是 count−1，错一位就多卖一块盘。
#   03 夹具 zero：读到了挂载点、没有一条能扫 ⟹ 也是缺席，但和 01 是两条不同的分支。
#      像素上与 01 同形是设计如此，所以这一档的判据**在 .log 的留痕行里**，不在照片里。
#   04 夹具 fail：一行都没读到 ⟹「未能读取卷列表，这里不猜数字」。
#   05 夹具 two + 窄窗 1000x760：这一族最长的一句挤不挤得下（P25/P26 那一族的口径）。
#   06 非法取值 tw0：回落真枚举 + stderr 留痕。判据同样在 .log。
#   07 概览页真机档：页脚「N 个卷」这一格改口径之后还在。
#   08 概览页 fail 档：「— 个卷」，只有夹具能拍到。
#
# 全程零合成点击：扫描根由 MM_DISK_SCAN 传（只认 /tmp 之下），夹具由 MM_VOLUME_FIXTURE 传，
# 每一档都是应用自己在正常渲染里走到那个状态。按 pid 抓自己的窗口，抓完即杀，只 kill 自己起的进程。
# 这一族不写盘、不删任何东西、不请求权限、不 mount/diskutil。
#
#   ./Scripts/p35b-volumes-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p35b-volumes-capture.sh /tmp/mm-app-p35b/MacMaster.app docs/verification/p35b-volumes
#   ONLY=02 ./Scripts/p35b-volumes-capture.sh …        只重拍 02 那一档
#   SETTLE=10 …                                         改等待（默认 8 s：夹具 175 MB 一趟扫得完）
#
# 夹具：./Scripts/disk-fixture.sh（磁盘页一直在用的那棵小树，本次不新增夹具）。
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SETTLE=${SETTLE:-8}
FIXTURE=/tmp/macmaster-disk-fixture

[[ -d $FIXTURE ]] || { print -u2 -- "夹具不存在：先跑 ./Scripts/disk-fixture.sh"; exit 2; }

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p35b -s /tmp/mm-scratch-p35b 重新构建再取证。"
  exit 4
fi

mkdir -p "$OUT"
wants() { [[ -z ${ONLY:-} || $1 == ${ONLY}* ]] }

main_window_id() {
  local pid=$1 log=$2 all wid n
  all=$(swift Scripts/window-ids.swift --pid "$pid" 2>>"$log" || true)
  print -r -- "# windows(pid=$pid): ${all//$'\n'/ | }" >>"$log"
  n=$(printf '%s\n' "$all" | grep -c 'layer=0 title=MacMaster bounds=' || true)
  [[ $n == 1 ]] || return 1
  wid=$(printf '%s\n' "$all" | sed -n 's/^windowid=\([0-9]*\) .*layer=0 title=MacMaster bounds=.*/\1/p')
  [[ -n $wid ]] || return 1
  print -r -- "$wid"
}

# shot <文件名> <MM_VOLUME_FIXTURE 的值，空=不注入> [窗口宽x高] [页：disk|overview]
# disk 页要 MM_DISK_SCAN 才有面包屑条可看；overview 页是正常启动那一屏，
# 所以 **不带** MM_OPEN_MODULE/MM_OPEN_TAB/MM_DISK_SCAN 三个钩子——B 档那句"N 个卷"
# 在 DashboardView 的 statusBar 里（`MainWindow.swift:277`），只有停在概览页才拍得到。
# 返回非 0 = 这一档没拍到；调用处一律 `|| true` 兜住 `set -e`，最后由 png 存在性统一判失败。
shot() {
  local name=$1 fixture=$2 size=${3:-1400x900} page=${4:-disk}
  wants $name || return 0
  local log="$OUT/$name.log"
  rm -f "$OUT/$name.png"
  local -a hooks
  local hookNote=""
  if [[ $page == disk ]]; then
    hooks=(MM_OPEN_MODULE=disk MM_OPEN_TAB=tree MM_DISK_SCAN="$FIXTURE")
    hookNote=" MM_OPEN_MODULE=disk MM_OPEN_TAB=tree MM_DISK_SCAN=$FIXTURE"
  else
    page=overview
    hookNote="（不带模块钩子：概览页是正常启动那一屏）"
  fi
  print -r -- "# p35b-volumes-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_WINDOW_SIZE=$size$hookNote${fixture:+ MM_VOLUME_FIXTURE=$fixture}" >>"$log"
  print -r -- "# 页：$page   # 夹具：${fixture:-（未注入，读这台机器的挂载表）}" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_WINDOW_SIZE="$size" \
      $hooks ${fixture:+MM_VOLUME_FIXTURE="$fixture"} \
      "$APP/Contents/MacOS/MacMaster" >>"$log" 2>&1 &
  local pid=$!
  sleep "$SETTLE"
  local wid
  for i in {1..5}; do
    wid=$(main_window_id "$pid" "$log" || true)
    [[ -n $wid ]] && break
    sleep 3
  done
  if [[ -z "$wid" ]]; then
    print -u2 -- "⚠ $name：pid=$pid 反复查了 5 次，标题为 MacMaster 的主窗口不是正好一扇（清单见 $log 的 # windows 行）"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  screencapture -o -x -l"$wid" "$OUT/$name.png"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  print -r -- "✅ $name windowid=$wid settle=${SETTLE}s ${fixture:+fixture=$fixture}"
}

# 01 真机档：候选根 = 1 ⟹ 那一格不出现。画面与既有磁盘页基线的差别应当**只有**没有新徽标这一件事。
shot 01-disk-real-one-root "" || true
# 02 夹具 two：正分支那一句话。判据：徽标出现、写的是"还有 1 卷"（不是"2 卷"、不是"2 块硬盘"）。
shot 02-disk-fixture-two "two" || true
# 03 夹具 zero：一条都扫不了 ⟹ 仍然缺席。判据在 .log 的留痕行（见末尾核对）。
shot 03-disk-fixture-zero "zero" || true
# 04 夹具 fail：读不到 ⟹「未能读取卷列表，这里不猜数字」。
shot 04-disk-fixture-fail "fail" || true
# 05 夹具 two 窄窗：1000 pt 是硬最小宽度，这一句是这一族最长的新文案，先看它截不断。
shot 05-disk-fixture-two-narrow "two" 1000x760 || true
# 06 夹具守卫：非法取值 → 回落真枚举 + stderr 留痕（判据在 .log 里）。
shot 06-disk-fixture-invalid-voided "tw0" || true
# 07 概览页真机档（B 档）：页脚那句"N 个卷"的**口径**在这一档换掉了，
#    画面上仍是"1 个卷"（本机候选根 = 1，与旧的挂载点条数恰好都是 1——
#    P35a §9-B 明说"今天两者都是 1，所以画面上看不出来"）。
#    这一张存在的理由是"改口径之后这一格还在、还在概览页的位置上"，不是证明口径变了。
shot 07-overview-real-count "" 1400x900 overview || true
# 08 概览页 fail 档：一行都没读到 → 页脚「— 个卷」。这一格**只有夹具能拍到**：
#    真机上 Foundation 的枚举从来不给空（P35a §2）。
#    判据：照片上有占位符，且 .log 里有留痕行。这两条同时成立才算这档走到了 fail。
shot 08-overview-fixture-fail "fail" 1400x900 overview || true

typeset -a FAILED
for f in 01-disk-real-one-root 02-disk-fixture-two 03-disk-fixture-zero \
         04-disk-fixture-fail 05-disk-fixture-two-narrow 06-disk-fixture-invalid-voided \
         07-overview-real-count 08-overview-fixture-fail; do
  wants $f || continue
  [[ -s "$OUT/$f.png" ]] || FAILED+=($f)
done

# ── 核对：三件事，前两件事是断言，第三件是信息 ─────────────────────────
# ① 留痕：凡注入了夹具的档，.log 里必须有「已生效：这是合成快照」那一行；
#    注入了非法值的档必须有「含非法取值」那一行。这是把"夹具真的走了这一档"与
#    "钩子被忽略、画面恰好同形"分开的唯一机械办法（P6.6 那两张 md5 相同的照片就是这个坑）。
# ② 会画东西的三档（02/04/05）必须与 01 不同：相同就是夹具没生效。
#    02 与 05 同夹具、窗口不同，必须两两不同。
# ③ 03/06 与 01 同形是**设计如此**（03 那一档什么都不写；06 作废后走的就是 01 那条生产路径），
#    所以它们的判据在 ① 的留痕行里，这里只把相同与否当信息打出来。
print -r -- ""
print -r -- "# 留痕核对"
typeset -a PROBLEMS
# ⓪ 页别核对：07/08 落在概览页、01~06 落在磁盘页，靠的是 shot 的第四个参数。
#     这一条是本轮自己踩出来的：第一版漏传了那个参数，07 拍出来是**磁盘页**，
#     而且与 06 逐字节相同（同一页、同一夹具、同一窗宽、盘上没有任何会走的字段），
#     md5 交叉核对当时只比了 03/06 对 01，一句都没响。所以"哪一页"要单独钉，
#     不能指望像素差异替它说话。
for pair in "01-disk-real-one-root:disk" "02-disk-fixture-two:disk" "03-disk-fixture-zero:disk" \
            "04-disk-fixture-fail:disk" "05-disk-fixture-two-narrow:disk" \
            "06-disk-fixture-invalid-voided:disk" \
            "07-overview-real-count:overview" "08-overview-fixture-fail:overview"; do
  name=${pair%%:*}; page=${pair##*:}
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  if grep -q "^# 页：$page" "$lg"; then
    print -r -- "  ✓ $name：页别 = $page"
  else
    PROBLEMS+=("$name 的 .log 没写「# 页：$page」：这一档落到了别的页面上（参数没传到）")
  fi
done
for pair in "02-disk-fixture-two:two" "03-disk-fixture-zero:zero" "04-disk-fixture-fail:fail" \
            "05-disk-fixture-two-narrow:two" "08-overview-fixture-fail:fail"; do
  name=${pair%%:*}; tier=${pair##*:}
  lg="$OUT/$name.log"
  [[ -s $lg ]] || continue
  if grep -q "MM_VOLUME_FIXTURE=$tier 已生效" "$lg"; then
    print -r -- "  ✓ $name：留痕行在（合成快照，非这台机器的读数）"
  else
    PROBLEMS+=("$name 的 .log 没有「MM_VOLUME_FIXTURE=$tier 已生效」那一行：夹具没走到这一档")
  fi
done
# 07 是**反向**判据：这一档没注入夹具，日志里若出现 MM_VOLUME_FIXTURE 就说明
# 环境变量从外面漏进来了（ shell 残留 / 复用同一份 env），那这张就不是真机档。
if [[ -s "$OUT/07-overview-real-count.log" ]]; then
  if grep -q 'MM_VOLUME_FIXTURE' "$OUT/07-overview-real-count.log"; then
    PROBLEMS+=("07（概览真机档）的 .log 里出现了 MM_VOLUME_FIXTURE：这一档不该注入夹具")
  else
    print -r -- "  ✓ 07：没有钩子留痕，读的是这台机器的挂载表"
  fi
fi
if [[ -s "$OUT/06-disk-fixture-invalid-voided.log" ]]; then
  if grep -q '含非法取值' "$OUT/06-disk-fixture-invalid-voided.log"; then
    print -r -- "  ✓ 06 的 stderr 有留痕：$(grep -m1 '含非法取值' "$OUT/06-disk-fixture-invalid-voided.log")"
  else
    PROBLEMS+=("06 的 stderr 没有「含非法取值」那一行：守卫没留痕")
  fi
fi

print -r -- ""
print -r -- "# md5 交叉核对"
typeset -A M
for png in "$OUT"/*.png(N); do
  m=$(md5 -q "$png")
  M[$(basename "$png" .png)]=$m
  print -r -- "  $m  $(basename $png)"
done
for t in 02-disk-fixture-two 04-disk-fixture-fail 05-disk-fixture-two-narrow; do
  [[ -n ${M[$t]} && -n ${M[01-disk-real-one-root]} ]] || continue
  [[ ${M[$t]} != ${M[01-disk-real-one-root]} ]] || PROBLEMS+=("$t 与 01 相同：这一档的夹具没生效")
done
if [[ -n ${M[02-disk-fixture-two]} && -n ${M[05-disk-fixture-two-narrow]} ]]; then
  [[ ${M[02-disk-fixture-two]} != ${M[05-disk-fixture-two-narrow]} ]] \
    || PROBLEMS+=("02 ↔ 05 两张完全相同：窗口宽度没起作用")
fi
# 06 是磁盘页、07 是概览页 —— 两页不可能逐字节相同。相同只能是 07 没落到概览页
# （本轮第一版就是这么错的：`# 页：` 那一条核对补上之后，这一条是它的第二道闸）。
if [[ -n ${M[06-disk-fixture-invalid-voided]} && -n ${M[07-overview-real-count]} ]]; then
  [[ ${M[06-disk-fixture-invalid-voided]} != ${M[07-overview-real-count]} ]] \
    || PROBLEMS+=("06 ↔ 07 两张完全相同：07 拍的不是概览页")
fi
# 07 / 08 之间**不做** md5 断言：概览页页脚有"数据更新于 …"与"上次采样 …"两个时刻在走的字段，
# 同一次运行的两张连拍都不会逐字节相同，所以"不同"不证明任何事，"夹具没生效"也证明不了。
# 这两档的机械判据只有 ① 那一组留痕行，加上人工对读那一句是「1 个卷」还是「— 个卷」。
for name in 03-disk-fixture-zero 06-disk-fixture-invalid-voided; do
  [[ -n ${M[$name]} && -n ${M[01-disk-real-one-root]} ]] || continue
  if [[ ${M[$name]} == ${M[01-disk-real-one-root]} ]]; then
    print -r -- "  ℹ $name 与 01 逐字节相同（设计如此：这一格本来就不写；判据在留痕行）"
  else
    print -r -- "  ℹ $name 与 01 不同（真扫本身的帧间差异，不作判据）"
  fi
done
for p in "${PROBLEMS[@]}"; do print -u2 -- "⚠ $p"; done

if (( ${#PROBLEMS[@]} > 0 )); then
  print -u2 -- "✗ 核对没过，这一族不算取证完成"
  exit 1
fi

if (( ${#FAILED[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT（$APPEARANCE）"
