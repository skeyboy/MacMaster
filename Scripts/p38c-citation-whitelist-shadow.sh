#!/bin/zsh
# P38c：量"把 css/log 补进 p16 的抽取白名单，门禁会报出什么"——只量，不改那把尺子。
#   ./Scripts/p38c-citation-whitelist-shadow.sh [归档目录]
#   归档默认 docs/verification/p38c-shadow-whitelist，产出一份 shadow.log（覆盖写，台账只涨一件——
#   与 p16 那份 audit.log 同一口径；换目录不会让总数跳，写两遍只会多一件永远对不上的副本）。
#
# 为什么是影子跑而不是直接编辑 Scripts/p16-citation-audit.sh：
# 那一行扩展名白名单（现读第 130 行）定的是"三个总数"的口径，口径变更要单独一轮做。
# 本轮只回答它的前置问题——那批门外的坐标真进了门，有几条会当场变成失败。
# 所以影子副本落在 build/（.gitignore 里），仓库跟踪的那把尺子一个字节都不动。
#
# 为什么一定要跑两遍：差值只有在**同一棵树、同一个索引**上才归因得给白名单。
# 拿入库的 audit.log 当基线，混的就是"上一轮到这一轮之间新写的那些坐标"，
# 而那批坐标本身就落在门外——两个原因分不开，这个数就没有决策价值。
#   base = 跟踪脚本的原样副本（它必须逐字复现入库终跑，差值才可信）
#   ext  = 只把 (swift|go|rs|… 换成 (css|log|swift|go|rs|… 的副本
#
# 三条本轮自己踩过的坑，前两条现在写在脚本的检查里，不靠记性：
#   ① 副本的目录深度：p16 第 43 行靠 `cd "$(dirname "$0")/.."` 找仓库根。第一跑把副本放进
#      build/p38c-shadow/，根就被算成 build/，`git ls-files` 从这个被 gitignore 的目录里抽到 0 个文件，
#      于是**两份报告每一格都是 0、退出码 0、还印一行"硬失败 0"**——长得和"这批坐标全部可达"一模一样。
#      抓住它的是门禁自己那两行自报（`docs scanned: 0 个真抽了 / 0 个入库 .md`）；预检与后检各一道。
#   ①′ 那一跑还在磁盘上留了残渣：OUT 被当成相对"根 = build/"的路径，于是写出 `build/build/p38c-shadow/**`，
#      而本脚本的 `rm -rf $SHADOW` 只覆盖 `build/p38c-shadow`，**清不到那个嵌套目录**。它不进 git，
#      但会把 `find build -name '*.log'` 的台账读数顶高两份——发现它的正是算台账那一遍（读出 23，预期 21）。
#   ② 包装层的明细 grep：报告的失败行长相是三个空格开头的 `#   歧义 …`，第一版写成 `^#[^ ]`，
#      于是它一边印"硬失败 1"一边印"没有一条失败条目"。**结论行现在由报告自己的"硬失败"那一格算**，
#      不再从明细行数反推——反推出来的那一句当场就是错的。
set -e
set -o pipefail
cd "$(git rev-parse --show-toplevel)"
ROOT=$PWD
OUT="${1:-docs/verification/p38c-shadow-whitelist}"

# 归档就按"这份 stdout 一字不动地落盘"来做：重跑自己、把输出 tee 进 shadow.log（覆盖写）。
# 为什么不把报告代码搬进一个函数再重定向一遍：那等于给同一串结论养第二份副本面，
# 而这一轮正在数的就是"副本面有几处会漂"。
if [[ -z ${P38C_IN:-} ]]; then
  mkdir -p "$OUT"
  P38C_IN=1 zsh "$0" "$@" | tee "$OUT/shadow.log"
  exit
fi

SHADOW=build/p38c-shadow
GATE=Scripts/p16-citation-audit.sh
# 副本必须正好待在深度 1 的目录里（见上面坑①），所以深度这一道写成硬检查。
SHIM_DIR=build
if [[ "$SHIM_DIR" == */* || "$(cd "$SHIM_DIR/.." && pwd)" != "$ROOT" ]]; then
  print -r -- "# 预检失败：副本目录 $SHIM_DIR 的上一层不是仓库根（$ROOT），p16 会把索引建空" >&2
  exit 1
fi

rm -rf "$SHADOW"
mkdir -p "$SHADOW/base-out" "$SHADOW/ext-out"

cp "$GATE" "$SHIM_DIR/p38c-shadow-base.sh"
python3 - "$GATE" "$SHIM_DIR/p38c-shadow-ext.sh" <<'PY'
import sys
src = open(sys.argv[1]).read()
old = "+\\.(swift|go|rs|"          # 抽取正则里那个扩展名分组开头
new = "+\\.(css|log|swift|go|rs|"
# 只允许命中抽取那一处：符号面（现读第 220 行）那份名单以 `^(swift|` 开头、且早就含 log，
# 前缀 `+\.` 把它挡在外面。命中次数不是 1 就说明那把尺子的长相变了，当场停而不是改副本。
assert src.count(old) == 1, "白名单锚点命中 %d 次，影子跑拒绝继续" % src.count(old)
open(sys.argv[2], "w").write(src.replace(old, new))
PY

run() {  # $1=脚本 $2=输出目录 $3=归档名
  local rc=0
  P16_SYM_DETAIL=4000 zsh "$1" "$2" > "$SHADOW/$3.stdout" 2>&1 || rc=$?
  if grep -q '^# docs scanned: 0 ' "$SHADOW/$3.stdout"; then
    print -r -- "# 后检失败：$3 这一跑一个 .md 都没抽到——报告里那些 0 全是「没跑」，不是「没坏」" >&2
    exit 1
  fi
  print -r -- "$SHADOW/$3.rc=$rc"
}

BASE_RC=$(run "$SHIM_DIR/p38c-shadow-base.sh" "$SHADOW/base-out" base)
EXT_RC=$(run "$SHIM_DIR/p38c-shadow-ext.sh" "$SHADOW/ext-out" ext)
# 两份副本用完就删：留在 build/ 里，下一轮谁在 depth 1 又写一支脚本，会以为影子已经跑好了。
rm -f "$SHIM_DIR/p38c-shadow-base.sh" "$SHIM_DIR/p38c-shadow-ext.sh"

# ---- 汇总：只比门外那两族带来的差 ----
sum() {
  grep -E '^# +(引用条次|唯一「路径|命本仓库|命参考仓库|命苹果 SDK|两头都不到|定位不到文件|本仓库里同一条路径|行号越界|整段空白的引用|符号面·|行号判据实际跑过|硬失败|docs scanned|index|vocab)' "$1"
}

print -r -- ""
print -r -- "# ==== 同树成对影子跑：白名单加 css/log 前后的门禁读数 ===="
print -r -- "# date: $(date '+%Y-%m-%d %H:%M:%S')"
print -r -- "# repo: $(git rev-parse --short HEAD)$( [[ -n $(git status --porcelain -uno) ]] && echo -dirty ) branch=$(git rev-parse --abbrev-ref HEAD)"
print -r -- "# gate: $GATE（原样副本 + 只补 css/log 的副本，同一棵树各跑一遍）"
print -r -- "# ---- base（跟踪脚本原样副本）$BASE_RC ----"
sum "$SHADOW/base.stdout"
print -r -- "# ---- ext（白名单 +css,+log）$EXT_RC ----"
sum "$SHADOW/ext.stdout"

print -r -- "# ---- 差值（ext − base）----"
python3 - "$SHADOW/base.stdout" "$SHADOW/ext.stdout" <<'PY'
import re, sys
def grab(p):
    d = {}
    for line in open(p):
        m = re.match(r"#\s+(.*?)[:：]\s*([\d/a-z ]*?)(?:\s*（|\s*$)", line.rstrip())
        if not m:
            continue
        tail = re.findall(r"([\d]+)", line)
        if tail:
            d[m.group(1).strip()] = int(tail[0])
    return d
b, e = grab(sys.argv[1]), grab(sys.argv[2])
for k in e:
    if k.startswith(("date", "repo", "sdk", "ref", "tokens")):
        continue
    if k in b and b[k] != e[k]:
        print(f"#   {k}: {b[k]} -> {e[k]}  (Δ {e[k]-b[k]:+d})")
    elif k not in b:
        print(f"#   {k}: (base 里没有这一格) -> {e[k]}")
PY

print -r -- "# ---- ext 里那些门外的坐标，逐条落到哪一档（只有失败/提示条目才出现在明细里）----"
# 明细行的长相是 `#   歧义 …`／`#   越界 …`（三个空格），不是 `#歧义`。第一版这里写成 `^#[^ ]`，
# 结果上面刚印完"硬失败 1"，这一格就印"没有一条失败条目"——**包装层的自相矛盾，门那边没有**。
grep -E '^# +(越界|整段空白|不可达|歧义|死符号|位置|参考|SDK) .*\.(css|log):' "$SHADOW/ext.stdout" \
  || print -r -- "#   （ext 明细里没有一条 .css/.log 的失败或提示条目）"
HARD=$(grep -E '^# +硬失败' "$SHADOW/ext.stdout" | grep -oE '[0-9]+$')
if [[ -n $HARD && $HARD != 0 ]]; then
  print -r -- "# 结论：ext 当场报 $HARD 条硬失败——门一开就红，得先按上面的明细把文档改到进门不红，再动那把尺子"
else
  print -r -- "# 结论：ext 硬失败 0——这批门外坐标进门不会让门变红"
fi
print -r -- "# ---- 门外这批坐标各自的落点（命中面清点，不是判据）----"
python3 - <<'PY'
import re, subprocess, os
files = subprocess.run(["git", "-c", "core.quotePath=off", "ls-files"],
                       capture_output=True, text=True).stdout.split("\n")
tracked = [f for f in files if f.endswith((".css", ".log"))]
idx = subprocess.run(["git", "-c", "core.quotePath=off", "ls-files", "*.md"],
                     capture_output=True, text=True).stdout.split("\n")
pat = re.compile(r"([A-Za-z0-9_./+-]+\.(?:css|log)):[0-9]+(?:-[0-9]+)?(?:,[0-9]+(?:-[0-9]+)?)*")
cites = {}
for d in idx:
    if not d or not os.path.isfile(d):
        continue
    for m in pat.finditer(open(d, errors="replace").read()):
        cites.setdefault(m.group(1), 0)
        cites[m.group(1)] += 1
def resolve(p):
    # 照抄门禁的 endsuf 口径（p16 第 146-150 行）：带斜杠的要整段后缀相等，
    # 裸文件名的比对最后一个组件。差别在这里会直接变成"可达/不可达"。
    if "/" in p:
        return [f for f in tracked if f == p or f.endswith("/" + p)]
    return [f for f in tracked if f.split("/")[-1] == p]
for p, n in sorted(cites.items(), key=lambda kv: (-kv[1], kv[0])):
    hit = sorted(resolve(p))
    if not hit:
        print(f"#   {p}  ← 引 {n} 次｜命中面：找不到同后缀的跟踪文件（进门就是不可达）")
    elif len(hit) > 1:
        # 多命中不逐份列：这一族的结论只有一句——门禁判它"不自证是哪一篇"，列 16 行反而把这一句淹掉。
        print(f"#   {p}  ← 引 {n} 次｜同后缀跟踪文件 {len(hit)} 个 → 唯一面判「不自证是哪一篇」；首个落点 {hit[0]}")
    else:
        total = sum(1 for _ in open(hit[0], errors="replace"))
        print(f"#   {p}  ← 引 {n} 次｜落点 {hit[0]}（共 {total} 行，唯一）")
PY
print -r -- "# 两份完整报告与全部逐条明细留在 build/p38c-shadow/{base,ext}.stdout（gitignore 目录，重跑必得）"
