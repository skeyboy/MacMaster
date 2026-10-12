#!/bin/zsh
# P34b「偏好文件」取证：优化页第五 tab 的四个夹具档 + **真机档** + 窄窗档 + 非法值守卫档。
#
# 立项原因：`prefs:*` 四档是本轮新加的能力，一条照片都没有；而这一族的界面句子
# （"检查过 N 个"、"其中 M 个我们没能读"、"剩下的 K 个没看"）全是**计数拼出来的**，
# 计数错在界面上看不出来，只会在照片里长成一句假话。P6.6 那次的教训是两张不同档的
# PNG md5 完全相同——钩子白跑了一趟而照片看着没问题，所以这一族末尾自带 md5 交叉核对。
#
# 真机档（01）在这一族里不是"顺带拍的"，它是 P34a §11.1 那句的答案：
# 探针那一档是**裸二进制**读到的 11 条"读不到"，而界面是 .app 进程在读。
# 两个进程给不同答复的话，§5 那句"M 个我们没看到"的 M 就不是同一个数。
# 这一族只许拍"检查过 N 个 + 读不到 M 个"这种计数与归因，不拍任何结论性标语。
#
# 全程零合成点击：夹具在 OptimizerView 的 `.task` 里注入（`MMOptimizer.swift:104`），
# tab 由 `MM_OPEN_TAB=preferences` 决定，每一档都是应用自己在正常渲染里走到那个状态。
# 按 pid 抓自己的窗口，抓完即杀，只 kill 自己起的进程。
# 这一族不写盘、不删任何偏好文件、不请求 FDA——页面上也没有可点的删除入口。
#
# 非法值守卫档（07）的判据在 stderr，不在照片：照片只证明"没有半生效"。
#
#   ./Scripts/p34b-prefs-capture.sh <app 路径> <输出目录> [light|dark]
#   ./Scripts/p34b-prefs-capture.sh /tmp/mm-app-p34b/MacMaster.app docs/verification/p34b-prefs
#   ONLY=02 ./Scripts/p34b-prefs-capture.sh …        只重拍 02 那一档
#   SETTLE=8 …                                        改等待（默认 6 s：真扫一趟 182 ms，足够）
set -e

cd "$(dirname "$0")/.."
APP=${1:?需要 .app 路径}
OUT=${2:?需要输出目录}
APPEARANCE=${3:-light}
SETTLE=${SETTLE:-6}

# 归因头 + 内容指纹门禁（配方见 mm-provenance.sh）：不等就一张都不出。
repoTag=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
if [[ -n $(git status --porcelain -uno 2>/dev/null) ]]; then repoTag="$repoTag-dirty"; fi
appRepoTag=$(plutil -extract MMGitCommit raw "$APP/Contents/Info.plist" 2>/dev/null || echo 无)
source "$(dirname "$0")/mm-provenance.sh"
if ! mm_provenance_check "$PWD" "$APP"; then
  print -u2 -- "⚠ 产物与当前源码树不同源，这一族一张都不出："
  mm_provenance_line >&2
  print -u2 -- "  先 ./Scripts/make-app.sh -o /tmp/mm-app-p34b -s /tmp/mm-scratch-p34b 重新构建再取证。"
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

# shot <文件名> <MM_OPTIMIZER_FIXTURE 的值，空=不注入> [窗口宽x高]
# 返回非 0 = 这一档没拍到；调用处一律 `|| true` 兜住 `set -e`，最后由 png 存在性统一判失败。
shot() {
  local name=$1 fixture=$2 size=${3:-1400x900}
  wants $name || return 0
  local log="$OUT/$name.log"
  # 先删旧图：这一档没拍成时必须**什么都没有**，不许留下上一轮那张冒充本轮证据。
  rm -f "$OUT/$name.png"
  print -r -- "# p34b-prefs-capture.sh $name  $(date '+%Y-%m-%d %H:%M:%S %z')  app=$APP" >"$log"
  print -r -- "# repo: $repoTag   # app-repo: $appRepoTag" >>"$log"
  mm_provenance_line >>"$log"
  print -r -- "# env: MM_APPEARANCE=$APPEARANCE MM_OPEN_MODULE=optimizer MM_OPEN_TAB=preferences MM_WINDOW_SIZE=$size${fixture:+ MM_OPTIMIZER_FIXTURE=$fixture}" >>"$log"
  print -r -- "# 夹具：${fixture:-（未注入，走生产真扫）}" >>"$log"
  env MM_APPEARANCE="$APPEARANCE" MM_OPEN_MODULE=optimizer MM_OPEN_TAB=preferences \
      MM_WINDOW_SIZE="$size" ${fixture:+MM_OPTIMIZER_FIXTURE="$fixture"} \
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
  print -r -- "✅ $name windowid=$wid settle=${SETTLE}s tab=preferences ${fixture:+fixture=$fixture}"
}

# 01 **真机档**（生产路径，不注夹具）：页头那句"检查过 N 个偏好文件；其中 M 个我们没能读"
#    与「这一族我们没看到」那一栏。这一张同时是 §11.1 的答案：.app 进程对那 11 条的答复。
#    判据：M 与探针的 11 是否一致写在照片与 .log 里，人工对读；不一致就是"进程类别决定读数"，
#    §5 那句得改写成带条件的说法。
shot 01-prefs-real-gui "" || true
# 02 夹具 broken 档：两条坏行（0 字节 + 解析失败）各自行下方那句提醒不同，
#    外加一条"根不是字典"——它**不列行**，只让脚注出现。这一档证明两栏不共用图标。
shot 02-prefs-fixture-broken "prefs:broken" || true
# 03 夹具 unreadable 档：只有「这一族我们没看到」那一栏有内容，坏的那一栏是空的。
#    这一档存在的理由是把"没看到"与"坏了"分开排版——两栏若共用一个说法，这里就露出来。
shot 03-prefs-fixture-unreadable "prefs:unreadable" || true
# 04 夹具 empty 档：扫过了、没有坏行。空态那句话必须带"这一台机器、这一条判据"的限定。
shot 04-prefs-fixture-empty "prefs:empty" || true
# 05 夹具 partial 档：时间预算截断。真机上永远撞不到（默认预算是本机一趟的 11 倍），
#    所以这句话只有夹具能拍到；页头那句"剩下的 K 个没看"与计数必须自洽。
shot 05-prefs-fixture-partial "prefs:partial" || true
# 06 窄窗 1000x760：宽度是硬最小值（P25/P26 那一族的教训——截断把要紧的话藏起来）。
#    这一帧要看两件事：五个 tab 的分段控件（maxWidth 340）挤不挤，
#    以及坏行那条长路径是走中间截断还是把提醒挤出画面。
shot 06-prefs-narrow-window "prefs:broken" 1000x760 || true
# 07 夹具守卫：非法取值 → 整批作废并写 stderr（判据在 .log 里）。
#    照片应当停在未注入的样子（真扫那一屏），与 01 同形而**不等于**同一次扫描。
shot 07-prefs-fixture-invalid-voided "prefs:brokenn" || true

typeset -a FAILED
for f in 01-prefs-real-gui 02-prefs-fixture-broken 03-prefs-fixture-unreadable \
         04-prefs-fixture-empty 05-prefs-fixture-partial 06-prefs-narrow-window \
         07-prefs-fixture-invalid-voided; do
  wants $f || continue
  [[ -s "$OUT/$f.png" ]] || FAILED+=($f)
done

# md5 交叉核对（P6.6 的坑：两张不同档的 PNG 完全相同 = 钩子白跑，照片却看着没问题）。
# 三条判据，都是断言不是提示：
#   · 02~06 每一档都**必须**与 01（未注入的真扫）不同——相同就是夹具没生效；
#   · 02~06 彼此之间也必须两两不同（06 与 02 同夹具但窗口不同，不同是必然的）；
#   · 07（非法取值）的判据**在 stderr 那一行留痕里**，不在像素里：整批作废之后它走的
#     就是 01 那条生产路径，两张是否逐字节相同取决于 `contentsOfDirectory` 的返回顺序，
#     那不是承诺，所以这里只把相同与否当信息打出来，不当判据。
print -r -- ""
print -r -- "# md5 交叉核对"
typeset -A M
for png in "$OUT"/*.png(N); do
  m=$(md5 -q "$png")
  M[$(basename "$png" .png)]=$m
  print -r -- "  $m  $(basename $png)"
done
typeset -a PROBLEMS
for t in 02-prefs-fixture-broken 03-prefs-fixture-unreadable 04-prefs-fixture-empty \
         05-prefs-fixture-partial 06-prefs-narrow-window; do
  [[ -n ${M[$t]} && -n ${M[01-prefs-real-gui]} ]] || continue
  [[ ${M[$t]} != ${M[01-prefs-real-gui]} ]] || PROBLEMS+=("$t 与 01 相同：这一档的夹具没生效")
done
for name in ${(@k)M}; do
  for other in ${(@k)M}; do
    [[ $name < $other ]] || continue
    case "$name $other" in
      *01-prefs-real-gui*|*07-prefs-fixture-invalid-voided*) continue ;;
    esac
    [[ ${M[$name]} != ${M[$other]} ]] || PROBLEMS+=("$name ↔ $other 两张完全相同")
  done
done
# 07 的判据：留痕那一行必须在。
if [[ -s "$OUT/07-prefs-fixture-invalid-voided.log" ]]; then
  if grep -q '含非法取值' "$OUT/07-prefs-fixture-invalid-voided.log"; then
    print -r -- "  ✓ 07 的 stderr 有留痕：$(grep -m1 '含非法取值' "$OUT/07-prefs-fixture-invalid-voided.log")"
  else
    PROBLEMS+=("07 的 stderr 没有「含非法取值」那一行：守卫没留痕")
  fi
fi
if [[ -n ${M[01-prefs-real-gui]} && -n ${M[07-prefs-fixture-invalid-voided]} ]]; then
  [[ ${M[01-prefs-real-gui]} == ${M[07-prefs-fixture-invalid-voided]} ]] \
    && print -r -- "  ℹ 07 与 01 逐字节相同（不作判据：整批作废后两者走同一条生产路径）"
fi
for p in "${PROBLEMS[@]}"; do print -u2 -- "⚠ $p"; done

if (( ${#FAILED[@]} > 0 )); then
  print -u2 -- "✗ 这些档位没拍出照片：${FAILED[*]}"
  print -r -- "→ $OUT"
  exit 1
fi

print -r -- "→ $OUT（$APPEARANCE）"
