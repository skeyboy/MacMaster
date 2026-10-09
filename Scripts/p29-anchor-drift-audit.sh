#!/bin/zsh
# P29 锚点漂移审计：改完源码、还没提交的那一段窗口里，把入库文档里指向**被改文件**的
# `文件名.swift:NN` 逐条对一次——HEAD 那一版的第 NN 行和工作区的第 NN 行文字不同，
# 就说明这条锚点在改动前后指的是两件事，它漂了。
#
# 为什么引用门禁（`Scripts/p16-citation-audit.sh`）不够：它那四道硬判据问的是
# "文件在不在 / 越不越界 / 空不空 / 歧不歧"，**没有一条问"它指的是不是当初那一行"**。
# 行号仍然在文件内、那一行仍然有字，说的是另一件事——§7.17 记过一次"门禁报 2、实漂 88"。
# 这一支脚本补的就是那第五问，只在"本轮改了源码"的窗口里有意义（全绿克隆上跑必得 0）。
#
# 输出还带一条**建议新锚点**：把 HEAD 那一行的原文拿到工作区文件里找唯一命中，
# 恰好一处 → 报 `NN -> MM`（可以直接照抄）；0 处或多处 → 报 `UNRESOLVED`，交人工。
# 脚本一律**不改文档**：自动改行号看起来省了一轮，代价是漂得比手工更安静。
#
#   ./Scripts/p29-anchor-drift-audit.sh              只看报告
#   ./Scripts/p29-anchor-drift-audit.sh docs/verification/p29-anchor-drift   同时落证据
#
# 退出码恒为 0：这一支是量尺，不是门。真正的门是 p16。
# 已知覆盖缺口（照实说，不当已收口）：只认**带文件名**的引用；文档里裸写的 `:NN`、
# 以及 `NN-MM` 区间只按起始行比对（结束行漂了但起始行没漂的，这一版看不见）。
set -e

cd "$(dirname "$0")/.."
OUT=${1:-}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---- 1. 本轮被改过的源码文件（含新增未跟踪的：它们还没有 HEAD 版本，另行标注）----
git diff --name-only HEAD -- '*.swift' | grep -v '^Packages/.*/Tests/' > "$TMP/files"
testsChanged=$(git diff --name-only HEAD -- '*.swift' | grep -c '^Packages/.*/Tests/' || true)
newFiles=$(git ls-files --others --exclude-standard '*.swift' | grep -v '/Tests/' || true)

print -r -- "# p29 anchor drift audit"
print -r -- "# date: $(date '+%Y-%m-%d %H:%M:%S')"
print -r -- "# repo: $(git rev-parse --short HEAD)$( [[ -n $(git status --porcelain -uno) ]] && echo -dirty )"
print -r -- "# 被改源码文件（非测试）: $(wc -l < "$TMP/files" | tr -d ' ') 个；测试文件 $testsChanged 个（文档极少引测试行号，不扫）"
if [[ -n $newFiles ]]; then
  print -r -- "# 新增未跟踪源文件（无 HEAD 版本，只可能被引错方向）: ${newFiles//$'\n'/ }"
fi

# ---- 2. 入库 .md 里指向这些文件的引用 ----
git -c core.quotePath=off ls-files '*.md' > "$TMP/mdlist"
: > "$TMP/cites"
while IFS= read -r md; do
  [[ -f $md ]] || continue
  while IFS=$'\t' read -r f _; do
    base=${f:t}
    /usr/bin/awk -v doc="$md" -v src="$f" -v base="$base" '{
        line = $0
        while (match(line, base ":[0-9]+")) {
          tok = substr(line, RSTART, RLENGTH)
          line = substr(line, RSTART + RLENGTH)
          sub(base ":", "", tok)
          print src "\t" doc "\t" FNR "\t" tok
        }
      }' "$md" >> "$TMP/cites"
  done < "$TMP/files"
done < "$TMP/mdlist"

# 同一条「源文件+源行号+文档+文档行」只判一次（一行里重复引用不必各报一遍）
/usr/bin/sort -u -t$'\t' -k1,1 -k2,2 -k3,3 -k4,4 "$TMP/cites" > "$TMP/cites-u"

# ---- 3. 逐条比对 ----
: > "$TMP/drift"
while IFS=$'\t' read -r f doc dline n; do
  [[ -f $f ]] || continue
  total=$(awk 'END { print NR }' "$f")
  if (( n > total )); then
    printf 'UNRESOLVED\tdoc=%s:%s\tsrc=%s:%s\treason=越界（工作区共 %s 行）\n' "$doc" "$dline" "$f" "$n" "$total" >> "$TMP/drift"
    continue
  fi
  head_line=$(git show "HEAD:$f" 2>/dev/null | sed -n "${n}p")
  wt_line=$(sed -n "${n}p" "$f")
  [[ "$head_line" != "$wt_line" ]] || continue
  # 尝试自动重锚：HEAD 那行的原文在工作区里找唯一命中
  t=${head_line#"${head_line%%[![:space:]]*}"}   # 去左空白
  t=${t%"${t##*[![:space:]]}"}                   # 去右空白
  if [[ -z $t ]]; then
    printf 'UNRESOLVED\tdoc=%s:%s\tsrc=%s:%s\treason=HEAD 那行是空行\twt=%s\n' "$doc" "$dline" "$f" "$n" "$wt_line" >> "$TMP/drift"
    continue
  fi
  hits=$(grep -cF -- "$t" "$f" || true)
  if [[ $hits == 1 ]]; then
    new=$(grep -nF -- "$t" "$f" | sed -n '1p' | cut -d: -f1)
    printf 'DRIFT\tdoc=%s:%s\tmove=%s:%s -> %s:%s\treason=唯一命中原文\t| %s\n' "$doc" "$dline" "$f" "$n" "$f" "$new" "$t" >> "$TMP/drift"
  else
    printf 'UNRESOLVED\tdoc=%s:%s\tsrc=%s:%s\treason=工作区里 %s 处命中（%s 处以上需人工认）\t| %s\n' "$doc" "$dline" "$f" "$n" "$hits" "$hits" "$t" >> "$TMP/drift"
  fi
done < "$TMP/cites-u"

drift=$(grep -c '^DRIFT' "$TMP/drift" || true)
unres=$(grep -c '^UNRESOLVED' "$TMP/drift" || true)
cites=$(wc -l < "$TMP/cites-u" | tr -d ' ')

print -r -- "# 扫到的引用条次（唯一「文档+文档行+源文件+源行号」）: $cites"
print -r -- "# 漂移（HEAD 行 ≠ 工作区行）: $drift"
print -r -- "# 其中不可自动重锚: $unres"
print -r -- "# 按文档计数:"
awk -F'\t' '{ d = $2; sub(/^doc=/, "", d); sub(/:.*/, "", d); print $1 "\t" d }' "$TMP/drift" \
  | /usr/bin/sort | /usr/bin/uniq -c | /usr/bin/sort -rn
print -r -- "# ---- 明细：可照抄的重锚（new 取自 HEAD 行原文在工作区的唯一命中）----"
grep '^DRIFT' "$TMP/drift" | while IFS=$'\t' read -r k doc move reason text; do
  printf '#   %s  %s  %s%s\n' "$doc" "$move" "$reason" "$text"
done || true
print -r -- "# ---- 明细：需人工 ----"
grep '^UNRESOLVED' "$TMP/drift" | while IFS=$'\t' read -r k doc src reason extra; do
  printf '#   %s  %s  %s  %s\n' "$doc" "$src" "$reason" "$extra"
done || true

if [[ -n $OUT ]]; then
  mkdir -p "$OUT"
  cat "$TMP/drift" > "$OUT/drift.tsv"
  print -r -- "# 明细已写入 $OUT/drift.tsv"
fi
