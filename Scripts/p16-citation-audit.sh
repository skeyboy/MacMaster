#!/bin/zsh
# P16 引用审计：把入库文档里每一处 `文件:行号` 引用逐条落到磁盘上验一遍。
#
# 为什么要这一支脚本：`release-readiness.md` §8 记的那条账说"别人 clone 之后那些引用是
# 断链"——`.gitignore` 排掉了三个参考仓库目录，而分析文档按那些路径引了源码位置。
# 这一轮把那句话变成了数，顺带查出两件只有逐条验才看得见的事：
#   ① 引用会漂。本项目此前已经中过一次（`release-readiness.md` §3 兼容表里那两个符号根本不存在），
#      症状是"文档写的是它以为的那一行"，而不是"编译不过"。行号超过文件末尾、整段引用落在空白上，
#      人和 grep 都不报错——只有把引用打开对一次才知道。
#   ② 断链分两种，代价完全不同：引**本仓库**的引用漂了就是错（必须改文档）；
#      引**参考仓库**的引用在 clone 之后一律不到，但它是可补的（把上游 URL + 钉住的 commit
#      写进一份入库的清单，读的人一条命令就能把那批引用变成可打开的）。
#      所以脚本按命中面分开计数，不混成一个"断链数"。清单在 `docs/analysis/reference-repos.md`。
#
# 四道硬判据（"硬失败"就是退出码；第五道符号面只提示，见下）：
#   命中面  引用路径按后缀能不能定位到真实文件：本仓库 / 参考仓库 / 苹果 SDK / 都不到。
#           都不到 = 硬失败：一条写错目录的引用和一个不存在的文件，对读的人是同一件事。
#   唯一面  同一条路径在本仓库命中两个文件 = 硬失败（引用不自证是哪一篇）。
#           这一条是本轮从参考仓库那边学来的：`main.swift` 在 Pearcleaner 里有两份，
#           按后缀找文件会静默落到其中一份上，而落错那份的行号恰好也"在范围内"。
#   行号面  区间结束行不许超过文件行数（硬失败）。
#   空白面  引用的那一段不许整段只有空白（单行引用就是那一行本身）——硬失败。
#           判据从"起始行非空"放宽到这里，是因为第一版把 24 条正常写法也判成了错：
#           `MMMonitor.swift:27-31` 这种区间，起始行正好是空行，说的还是那一段代码。
#           **宽严要按引用怎么被使用来定**，这一条和 P15 的③边界是同一族决定。
#
# 参考仓库不在 git 里，所以脚本对它们的态度是**有没有都照实说**：目录不在就记
# "这一条没试行号判据（参考仓库未克隆）"，不判它错。
#
# 第五道判据（符号面）**只提示，不进退出码**，理由写在第 4 步那一段。它的存在是因为这四道
# 硬判据各自都问"这段能不能打开"，而本轮手工核对抓出的另一类漂问的是另一个问题：
# "那一行上有没有文档主张的东西"。
#
#   ./Scripts/p16-citation-audit.sh                                    只出报告
#   ./Scripts/p16-citation-audit.sh docs/verification/p16-citations     报告同时落成证据
#
# 退出码：硬失败 > 0 时返回 1。它当的是"改完文档再跑一次"的门。
# 中间文件一律用 printf 而不是 `print -r` 写：`print -r` 不解释 `\t`，那些行会变成
# 带字面反斜杠的一整串，后面按制表符切的 `grep -c "^oob"<TAB>` 全部落空——**统计看着是 0，
# 其实是一行都没统计到**。这一条本轮由否证跑出来（否证临时行还留在 git 历史里）。
set -e

cd "$(dirname "$0")/.."
OUT=${1:-}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---- 1. 索引 ----
# `core.quotePath=off` 不是可选的：git 默认把非 ASCII 路径包成 "docs/.../\347\253\236…"，
# 于是本仓库那两份中文名文档既进不了索引（判据找不到文件）、又在抽取阶段被
# `[[ -f $md ]]` 静默跳过——报告照样打"31 个入库 .md"，实际抽了 29 个。
git -c core.quotePath=off ls-files > "$TMP/idx-self"

# 本仓库源码词汇表：给"符号面"那一档用（下面第 4 步）。只取跟踪文件，`.build/` 这些
# 构建中间产物不在这个集合里——否则一个早已删掉的符号还能从旧产物里被查出来。
#
# 两个已知的松处，都记在这里而不是藏着：
#   ① 词汇表是**原文 token**，注释与字符串也算。`cardBackground` 这个早已改名的符号在
#      `MMDesign.swift:41` 的注释里还活着（"上一版它叫 cardBackground"），所以它现在就在词汇表里，
#      文档若还写 `` `MMColor.cardBackground` `` 只会落进弱的那一层。要把注释剔掉得写一个
#      能分清 `//` 和字符串里斜杠的词法器，代价远大于这一层的价值；这一层本来就是提示。
#   ② **本脚本自己必须从词汇表里排除**。它的注释按设计就要列举死符号（就是上面那几个名字），
#      一旦提交进 git，这些名字会因为"审计脚本的注释里提到了它"而重新变成"还活着的符号"——
#      判据被自己的说明书喂活。这不是假设：本轮否证跑之前 `colorForSize` 在词汇表里是 0，
#      唯一的来源就是这份注释，提交之后就变 1 了。
git -c core.quotePath=off ls-files -z '*.swift' '*.m' '*.mm' '*.h' '*.go' '*.rs' '*.sh' '*.plist' \
  | /usr/bin/tr '\0' '\n' | grep -vx 'Scripts/p16-citation-audit.sh' | /usr/bin/sort -u \
  | /usr/bin/tr '\n' '\0' | xargs -0 cat 2>/dev/null | tr -c 'A-Za-z0-9_' '\n' | /usr/bin/sort -u > "$TMP/vocab-self"

: > "$TMP/idx-ref"
: > "$TMP/ref-manifest"
# `(N)` 不是风格问题。这三个目录都在 .gitignore 里（各自带独立 .git 与许可证，见
# docs/analysis/reference-repos.md 开头），所以**干净克隆里一个都没有**；而 zsh 默认
# NOMATCH——glob 抽不到东西时是**整条 for 语句报错**，`set -e` 直接把脚本打死，
# 下一行的 `[[ -d ]] || continue` 根本没机会跑。P20 在克隆树里第一次撞上：
# 报的是 `no matches found: docs/github-references/*`，一行报告都没有——
# 也就是说这份"发版前门禁"只在作者机器上跑得起来，而它早就知道自己会在别人机器上
# 少一个索引（"定位不到文件因而没试行号判据的"那一支就是为此写的），却从没走到过那一支。
for d in docs/github-references/*(N) docs/Mole docs/lemon-cleaner; do
  [[ -d $d ]] || continue
  if [[ -e $d/.git ]]; then
    head=$(git -C "$d" rev-parse --short HEAD 2>/dev/null || true)
    url=$(git -C "$d" remote get-url origin 2>/dev/null || true)
    n=$(git -C "$d" -c core.quotePath=off ls-files 2>/dev/null | wc -l | tr -d ' ')
    print -r -- "# ref: $d head=${head:-无工作树} tracked=$n remote=${url:-无}" >> "$TMP/ref-manifest"
    if (( n > 0 )); then
      git -C "$d" -c core.quotePath=off ls-files | sed "s|^|$d/|" >> "$TMP/idx-ref"
    fi
  else
    find "$d" -type f 2>/dev/null | sed "s|^$d/||" >> "$TMP/idx-ref"
    print -r -- "# ref: $d head=非git仓库 tracked=n/a remote=n/a" >> "$TMP/ref-manifest"
  fi
done

# 一份参考仓库都没有时，报告里要**看得见这件事**。不然"命参考仓库 0"这一格会被读成
# "文档没引参考仓库"，而真实情况是"没取到"——两者是完全不同的结论，而这一份报告是发版门禁。
if [[ ! -s $TMP/idx-ref ]]; then
  print -r -- "# ref: 一个参考仓库都不在（这些目录被 .gitignore 排掉了，干净克隆里本来就是空的）" >> "$TMP/ref-manifest"
  print -r -- "# ref: 取法 ./Scripts/clone-references.sh；钉住的 commit 见 docs/analysis/reference-repos.md §2" >> "$TMP/ref-manifest"
  print -r -- "# ref: 这一跑没跑任何参考仓库判据，那些引用全落进下面「定位不到文件」那一支" >> "$TMP/ref-manifest"
fi

# 苹果 SDK 头文件也建一份索引：`docs/analysis/guardian-device-usage.md` 引的是
# `AVCaptureDevice.h:323` 这一类**既不在本仓库也不在参考仓库**的位置。这类引用在本机
# 可验（版本号写进报告，换 Xcode 就得重跑），但在别人的 clone 里同样打不开——
# 所以它单独一档计数，不混进"都不到"，也不混进"参考仓库"。
: > "$TMP/idx-sdk"
SDKPATH=$(xcrun --show-sdk-path 2>/dev/null || true)
if [[ -n $SDKPATH && -d $SDKPATH/System/Library/Frameworks ]]; then
  # 索引里存绝对路径：后面要对这些文件做行号判据，前缀换成 SDK: 只是好看，代价是多一次还原。
  find "$SDKPATH/System/Library/Frameworks" -path '*Headers*' -name '*.h' 2>/dev/null > "$TMP/idx-sdk"
  print -r -- "# sdk: version=$(xcrun --show-sdk-version 2>/dev/null || echo 未知) headers=$(wc -l < "$TMP/idx-sdk" | tr -d ' ') root=$SDKPATH" >> "$TMP/ref-manifest"
else
  print -r -- "# sdk: 本机没有 xcrun 或 SDK，这一档索引为空（SDK 类引用会落进「都不到」）" >> "$TMP/ref-manifest"
fi

# ---- 2. 抽引用：入库的 .md 里每一处 `路径:行(-行)` ----
git -c core.quotePath=off ls-files '*.md' > "$TMP/mdlist"
: > "$TMP/cites"
docsScanned=0
while IFS= read -r md; do
  [[ -f $md ]] || continue
  docsScanned=$((docsScanned + 1))
  /usr/bin/awk -v doc="$md" '{
      line = $0
      # 斜杠要写成 \/：正则字面量里的 / 会被当成结束符（/usr/bin/awk 直接报 nonterminated character class）。
      # 逗号续列也要吃掉：`FileWatcher.swift:2,84-94` 是两处判据，只匹配头一段等于放过 `,84-94`
      # ——文档里这种写法有六处，全是"同一句话的第二条证据"，最容易漂却没人查。
      while (match(line, /[A-Za-z0-9_.\/+-]+\.(swift|go|rs|m|mm|h|hpp|c|cpp|ts|tsx|js|jsx|py|rb|sh|plist|entitlements|strings|xcconfig|pbxproj|toml|yaml|yml|md|txt|html|json):[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        p = tok; sub(/:.*/, "", p)
        rest = substr(tok, length(p) + 2)
        n = split(rest, pieces, ",")
        for (i = 1; i <= n; i++) {
          s = pieces[i]; sub(/-.*/, "", s)
          print doc "\t" FNR "\t" p "\t" s "\t" ":" pieces[i]
        }
      }
    }' "$md" >> "$TMP/cites"
done < "$TMP/mdlist"

# ---- 3. 命中面：逐条唯一引用去两个索引里定位 ----
/usr/bin/awk -F'\t' '
  function endsuf(full, p,   L) {
    if (full == p) return 1
    L = length(p)
    return (length(full) > L && substr(full, length(full) - L) == "/" p)
  }
  FILENAME ~ /idx-self$/ { s[++ns] = $0; next }
  FILENAME ~ /idx-ref$/  { r[++nr] = $0; next }
  FILENAME ~ /idx-sdk$/  { k[++nk] = $0; next }
  FILENAME ~ /cites$/ {
    key = $3 "\t" $5
    if (key in seen) { occ[key]++; next }
    seen[key] = 1; occ[key] = 1; firstdoc[key] = $1; line[key] = $2; start[key] = $4
    base = $3; sub(/.*\//, "", base)
    hs = ""; hs2 = ""; cs = 0
    for (i = 1; i <= ns; i++) if (endsuf(s[i], $3)) { cs++; if (hs == "") hs = s[i]; else hs2 = hs2 (hs2 == "" ? "" : ",") s[i] }
    hr = ""; cr = 0
    for (i = 1; i <= nr; i++) if (endsuf(r[i], $3)) { cr++; if (hr == "") hr = r[i] }
    hk = ""; ck = 0
    for (i = 1; i <= nk; i++) if (endsuf(k[i], $3)) { ck++; if (hk == "") hk = k[i] }
    cls = (cs > 0 ? "self" : (cr > 0 ? "ref" : (ck > 0 ? "sdk" : "nowhere")))
    # 输出：class 命中文件 第二个命中 本仓库命中数 参考命中数 文档 文档行 引用路径 行段 出现次数
    # 空字段一律写成 "-"：IFS 里的制表符是空白类分隔符，两个相邻的制表符会被 read 当成一个，
    # 留空就等于把后面所有列往左挪一位。
    print cls "\t" (hs != "" ? hs : (hr != "" ? hr : (hk != "" ? hk : "-"))) "\t" (hs2 != "" ? hs2 : "-") \
        "\t" cs "\t" cr "\t" firstdoc[key] "\t" line[key] "\t" $3 "\t" $5 "\t" occ[key]
  }
' "$TMP/idx-self" "$TMP/idx-ref" "$TMP/idx-sdk" "$TMP/cites" > "$TMP/class.tsv"

# ---- 4. 行号面 + 空行面（只对定位到真实文件的引用做）----
# class.tsv 的列序：class 命中文件 本仓库命中数 参考命中数 文档 文档行 引用路径 行段 出现次数
: > "$TMP/lines.tsv"
while IFS=$'\t' read -r cls hit hs2 cs cr doc dline p rng n; do
  if [[ $cls == nowhere || ! -f $hit ]]; then
    printf 'skip\t-\t%s%s\t%s:%s\n' "$p" "$rng" "$doc" "$dline" >> "$TMP/lines.tsv"; continue
  fi
  total=$(awk 'END { print NR }' "$hit")
  r=${rng#:}
  startline=${r%%-*}
  endline=${r##*-}
  # 越界判的是**区间**：起始行在文件里、结束行在文件外，同样是漂了。
  if (( startline < 1 || endline > total )); then
    printf 'oob\t%s%s\t共 %s 行\t%s:%s\n' "$hit" "$rng" "$total" "$doc" "$dline" >> "$TMP/lines.tsv"; continue
  fi
  cell=$(awk -v a="$startline" -v b="$endline" 'NR >= a && NR <= b && /[^ \t]/ { f = 1; exit } END { print f ? 1 : 0 }' "$hit")
  if [[ $cell == 0 ]]; then
    printf 'blank\t%s%s\t共 %s 行\t%s:%s\n' "$hit" "$rng" "$total" "$doc" "$dline" >> "$TMP/lines.tsv"; continue
  fi
  # ---- 符号面（只提示，不当门）----
  # 为什么要有这一支：本轮手工核对被点名的 12 行时，顺带发现**另一类漂**——行号有效、
  # 行也不空，可那一行上根本没有文档说的那个东西（`colorForSize`、`cardBackground`、
  # `runOptimization`、`UninstallerModel.headerSubtitle` 都不存在了）。空行判据对这类完全沉默，
  # 因为它只问"这段有没有字"。
  # 判据：文档那一行用反引号点名了标识符（含大写、≥5 字符，允许 `类型.成员` 这种写法），
  # 而**成员名**在引用区间 ±4 行的正文里没出现。再按"这个成员名在本仓库源码里到底存不存在"
  # 分两层：
  #   死符号面 成员名全仓词汇表查不到（改名/删除没同步文档，本轮手工抓出的四类都在这一层）——强信号；
  #   位置面 成员名还在，只是不在这几行——弱信号，多半是"引这一行说明一个行为"而不是"引这一行上的符号"，
  #          所以绝不当门（第一轮跑出 96 条，里面确实混着 `MMCard`/`onDisappear` 这种真在用的东西）。
  # 只查点号最后一段，不查整串：`MMColor.cardBackground` 这句话里真正被主张的是 `cardBackground`，
  # 而 `MMColor` 是个还活着的类型——按整串算"找到了"就等于放过了改名。反过来说，写 `` `MMOptimizer` ``
  # 这种没有成员的类型级主张，member 就是它本身，判据不变。
  # 不要求纯小写词：含大写的筛选正好留下 lowerCamelCase（`runOptimization`、`colorForSize` 都有大写），
  # 又把 `blank`/`scope` 这类普通词挡在外面——这一条是符号面能成立的前提。
  # 不当门的另一条：`onDisappear`、`IOBlockStorageDriver` 这类**苹果 API 与内核驱动名**天然不在
  # 我们的词汇表里，会落进"死符号"那一层，所以那一层的正确用法是"逐条看一眼"，不是"照单改"。
  if [[ $cls == self ]]; then
    symtext=$(sed -n "${dline}p" "$doc" | /usr/bin/awk '{
        while (match($0, /`[^`]+`/)) {
          t = substr($0, RSTART + 1, RLENGTH - 2); $0 = substr($0, RSTART + RLENGTH)
          last = t; sub(/.*\./, "", last)
          # 末段是文件扩展名的（`Package.swift`、`MMDisk.swift`）不是符号主张，挡掉；
          # 末段是小写动词的（`TreemapView.compute`）恰恰是主张最强的那一种，必须留下——
          # 所以这里不能用"末段含大写"当筛子，只能按扩展名白名单挡。
          if (t ~ /[A-Z]/ && t ~ /^[A-Za-z_][A-Za-z0-9_.]*$/ && length(t) >= 5 \
              && last !~ /^(swift|go|rs|m|mm|h|hpp|c|cpp|ts|tsx|js|jsx|py|rb|sh|plist|entitlements|strings|xcconfig|pbxproj|toml|yaml|yml|md|txt|html|json|log|lock)$/) printf "%s;", t
        }
      }')
    if [[ -n $symtext ]]; then
      window=$(awk -v a=$((startline - 4)) -v b=$((endline + 4)) 'NR >= a && NR <= b' "$hit")
      sfound=0; anyExists=0; known=""
      for S in ${(ps:;:)symtext}; do
        [[ -n $S ]] || continue
        member=${S##*.}
        if print -r -- "$window" | grep -qF -- "$member"; then sfound=1; break; fi
        if grep -qxF -- "$member" "$TMP/vocab-self"; then anyExists=1; known="$known$S;"
        else known="$known$S*"; fi
      done
      if (( sfound == 0 && anyExists == 0 )); then
        printf 'symdead\t%s\t%s%s\t%s:%s\n' "${known%;}" "$hit" "$rng" "$doc" "$dline" >> "$TMP/lines.tsv"; continue
      fi
      if (( sfound == 0 )); then
        printf 'sym\t%s\t%s%s\t%s:%s\n' "${known%;}" "$hit" "$rng" "$doc" "$dline" >> "$TMP/lines.tsv"; continue
      fi
    fi
  fi
  printf 'ok\t%s%s\t共 %s 行\t%s:%s\n' "$hit" "$rng" "$total" "$doc" "$dline" >> "$TMP/lines.tsv"
done < "$TMP/class.tsv"

# ---- 5. 报告 ----
report() {
  print -r -- "# p16 citation audit"
  print -r -- "# date: $(date '+%Y-%m-%d %H:%M:%S')"
  print -r -- "# repo: $(git rev-parse --short HEAD)$( [[ -n $(git status --porcelain -uno) ]] && echo -dirty ) branch=$(git rev-parse --abbrev-ref HEAD)"
  print -r -- "# docs scanned: $docsScanned 个真抽了 / $(git -c core.quotePath=off ls-files '*.md' | wc -l | tr -d ' ') 个入库 .md（两个数不等就是有文件没被读到）"
  print -r -- "# index: 本仓库 $(wc -l < "$TMP/idx-self" | tr -d ' ') 个跟踪文件 / 参考仓库 $(wc -l < "$TMP/idx-ref" | tr -d ' ') 个 / SDK 头文件 $(wc -l < "$TMP/idx-sdk" | tr -d ' ') 个"
  # 词汇表条数也自报：符号面两层的 0 只有在"词汇表非空"时才是结论。
  print -r -- "# vocab: 本仓库源码 token $(wc -l < "$TMP/vocab-self" | tr -d ' ') 个（已排除本脚本自身，见第 1 步②）"
  cat "$TMP/ref-manifest"

  print -r -- "# ---- 汇总 ----"
  print -r -- "# 引用条次（同一处再引一次也计）: $(wc -l < "$TMP/cites" | tr -d ' ')"
  print -r -- "# 唯一「路径+行段」: $(wc -l < "$TMP/class.tsv" | tr -d ' ')"
  print -r -- "#   命本仓库: $(grep -c "^self"$'\t' "$TMP/class.tsv" || true)"
  print -r -- "#   命参考仓库: $(grep -c "^ref"$'\t' "$TMP/class.tsv" || true)"
  # 分仓库计数：清单里那一格的数必须是这一条命令产出的，不能是抄进注释的（同一支脚本
  # 自己产出过两次数不一样的标签条数，那种"注释里的当前值"是这一族文档最先烂掉的地方）。
  awk -F'\t' '$1=="ref" {
      split($2, a, "/")
      if (a[1] != "docs") key = a[1]
      else key = (a[2] == "github-references" ? a[3] : a[2])
      c[key]++
    } END { for (k in c) printf "#     %s: %d\n", k, c[k] }' "$TMP/class.tsv" | /usr/bin/sort
  print -r -- "#   命苹果 SDK 头文件: $(grep -c "^sdk"$'\t' "$TMP/class.tsv" || true)"
  print -r -- "#   两头都不到: $(grep -c "^nowhere"$'\t' "$TMP/class.tsv" || true)"
  print -r -- "#   定位不到文件因而没试行号判据的（参考仓库没克隆时走这一支）: $(grep -c "^skip"$'\t' "$TMP/lines.tsv" || true)"
  print -r -- "# 本仓库里同一条路径命中两个文件（引用不自证是哪一篇）: $(awk -F'\t' '$1=="self" && $4>1' "$TMP/class.tsv" | wc -l | tr -d ' ')"
  print -r -- "# 行号越界: $(grep -c "^oob"$'\t' "$TMP/lines.tsv" || true)"
  print -r -- "# 整段空白的引用: $(grep -c "^blank"$'\t' "$TMP/lines.tsv" || true)"
  print -r -- "# 符号面·死符号（点名的成员名在本仓库源码词汇表里根本找不到；**只提示，不当门**——苹果 API 会混在这一层）: $(grep -c "^symdead"$'\t' "$TMP/lines.tsv" || true)"
  print -r -- "# 符号面·位置存疑（成员名还在，只是不在引用那几行上；噪声大，**只提示**）: $(grep -c "^sym"$'\t' "$TMP/lines.tsv" || true)"
  # 这一条是给上面两个 0 用的：0 必须是"跑过并且都过"，不能是"根本没跑"。
  print -r -- "# 行号判据实际跑过: $(grep -vc "^skip" "$TMP/lines.tsv" || true) 条（另 $(grep -c "^skip"$'\t' "$TMP/lines.tsv" || true) 条定位不到文件，没跑）"

  print -r -- "# ---- 明细：本仓库引用漂了（必须改文档）----"
  awk -F'\t' '$1=="self" && $4>1 { printf "#   歧义 %s:%s 同后缀命中 %s 与 %s（引于 %s:%s）\n", $8, $9, $2, $3, $6, $7 }' "$TMP/class.tsv"
  grep "^oob"$'\t' "$TMP/lines.tsv" | while IFS=$'\t' read -r k loc info src; do
    print -r -- "#   越界 $loc（$info）← 引于 $src"
  done || true
  grep "^blank"$'\t' "$TMP/lines.tsv" | while IFS=$'\t' read -r k loc info src; do
    print -r -- "#   整段空白 $loc（$info）← 引于 $src"
  done || true
  print -r -- "# ---- 明细：符号面·死符号（点名的符号全仓找不到，带 * 的就是找不到的那个）----"
  grep "^symdead"$'\t' "$TMP/lines.tsv" | while IFS=$'\t' read -r k syms loc src; do
    print -r -- "#   死符号 $loc ← 引于 $src；找不到：${syms//;/ /}"
  done || true
  print -r -- "# ---- 明细：符号面·位置存疑（符号存在但不在那几行；噪声大，只列前 40 条）----"
  grep "^sym"$'\t' "$TMP/lines.tsv" | head -40 | while IFS=$'\t' read -r k syms loc src; do
    print -r -- "#   位置 $loc ← 引于 $src；点名：${syms//;/ /}"
  done || true
  print -r -- "# ---- 明细：两头都不到（路径写错了，或者引的根本不是文件）----"
  awk -F'\t' '$1=="nowhere" { printf "#   不可达 %s:%s ← 引于 %s:%s（全文出现 %s 次）\n", $8, $9, $6, $7, $10 }' "$TMP/class.tsv"
  print -r -- "# ---- 明细：苹果 SDK 头文件（本机可验；别人 clone 一样打不开，SDK 版本见上面的 # sdk: 行）----"
  awk -F'\t' '$1=="sdk" { printf "#   SDK %s:%s → %s\n", $8, $9, $2 }' "$TMP/class.tsv"
  print -r -- "# ---- 明细：参考仓库引用（入库的清单写了取法即可达）----"
  awk -F'\t' '$1=="ref" { printf "#   参考 %s:%s → %s\n", $8, $9, $2 }' "$TMP/class.tsv"
}

report > "$TMP/report.txt"
cat "$TMP/report.txt"

hard=$(awk -F'\t' '$1=="self" && $4>1' "$TMP/class.tsv" | wc -l | tr -d ' ')
hard=$((hard + $(grep -c "^oob"$'\t' "$TMP/lines.tsv" || true)))
hard=$((hard + $(grep -c "^blank"$'\t' "$TMP/lines.tsv" || true)))
# 「都不到」也算硬失败：一条写错目录的引用（本轮抓出四处）和一个不存在的文件，
# 对读的人而言是同一件事——按文档写的路径打不开。命不上一律改。
hard=$((hard + $(grep -c "^nowhere"$'\t' "$TMP/class.tsv" || true)))
print -r -- "# 硬失败（本仓库引用漂了 + 都不到）: $hard"

if [[ -n $OUT ]]; then
  mkdir -p "$OUT"
  cat "$TMP/report.txt" > "$OUT/audit.log"
  print -r -- "# 证据已写入 $OUT/audit.log"
fi

if (( hard > 0 )); then exit 1; fi
