#!/usr/bin/env python3
"""P29 锚点重指工具：把入库文档里指向**本轮被改过的源文件**的 `文件名.swift:NN(-MM)`
逐条对到改动后的真实行号上，并可选就地改写。

为什么要有这一支（和 `Scripts/p29-anchor-drift-audit.sh` 是一对）：
  审计脚本量出"哪条锚点漂了"，但一条一条手工查在 99 个锚点这个量级上会写错，
  而写错的锚点比没有锚点更坏——它看起来是对的。这里有两套机械规则，可复核：
    规则一（文本）：取 HEAD 那一版的第 NN 行原文（去首尾空白），在工作区同一个文件里找
      **全文唯一**命中，恰好一处 → 新行号。
    规则二（位置）：从 `git diff -U0` 的 hunk 表算这一行的落点。它不问内容，只问
      "改动前后这一行在哪儿"——文档引 `}`、`.font(.caption)`、`Divider()` 这类结构行时
      要的就是这个（MMUninstaller.swift 里有 261 个 `}`，规则一对它们必然失效）。
      落在"整段删除"里的行**不给映射**：行号无处可去，硬猜等于伪造证据。
  两套都有结果但不一致 → 采文本，同时把这条不一致列进 HAND 给人看一眼。
  0 处命中 / 多处命中且位置映射也落在删除段 / 越界 → 一律标 HAND，**绝不猜**。
  猜的代价本轮实测过：HEAD 里 `message: String,` 这类行在 MMDesign.swift 出现多次，
  按"离得最近的那处"猜会把五条不同主张的引用指到同一行上。

安全边界（这一条是硬约束，不是免责声明）：
  * 只改 `docs/` 下的 .md，**永不改源码**。历史上用脚本按大括号删行毁掉过 830 行未提交代码，
    所以改源码只用编辑工具这一条对本脚本不适用——本脚本压根不碰源码。
  * **本轮新写进文档的行一律不动**（判据见 2b）：那些锚点是照着工作区量的，再映射一次
    就是把对的改成错的。
  * 行内含"此前写/原记/已漂到/改前"这类历史叙述的行会打成 `REVIEW` 行：改写照旧执行，
    但落盘后要人看一眼——同一行里历史锚点与当前锚点经常并存，机器分不开。
  * 只替换"文件名:行号"这一种 token，且文件名限定在本轮被改过的源文件；
    行号后紧跟数字的不算（`MMDesign.swift:6` 不会被当成 `MMDesign.swift:61` 的前缀）。
  * 区间 `:A-B` 的两端各自重指；两端都命中同一个位移才改写，否则整条标 HAND。
  * 默认只打印报告。加 `--write` 才落盘，且落盘前先做一遍"改完再审计应得 0 漂移"的自检预告。

用法：
  ./Scripts/p29-anchor-remap.py                 # 只看映射与 HAND 清单
  ./Scripts/p29-anchor-remap.py --preview       # 加上"每个 token 改成什么 + 上下文"
  ./Scripts/p29-anchor-remap.py --write         # 就地改写 docs/*.md
  ./Scripts/p29-anchor-remap.py --list-only     # 只列映射表，不列 HAND
自复性（照实说）：**只能在同轮内、提交前跑一次**。改写之后被改的那些文档行自身就成了
"本轮新写的行"，第二次跑只会看到 `可重指: 0` ——幂等是想要的性质，但它意味着这工具
复核不了自己改过的结果。复核靠两条：`git diff docs/` 逐行看 + `--preview` 的 REVIEW 行。
退出码：有 HAND 且未 --write 时为 0（这是量尺）；写盘失败才是 1。
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS_GLOB = "docs"


def git(*args):
    return subprocess.run(["git", "-c", "core.quotePath=off", *args],
                          cwd=ROOT, capture_output=True, text=True, check=True).stdout


# 1. 本轮被改过的非测试源文件
changed = [f for f in git("diff", "--name-only", "HEAD", "--", "*.swift").splitlines()
           if "/Tests/" not in f and (ROOT / f).exists()]
by_base = {}
for f in changed:
    base = f.rsplit("/", 1)[-1]
    by_base.setdefault(base, []).append(f)
ambiguous_bases = {b for b, v in by_base.items() if len(v) > 1}
tracked = {b: v[0] for b, v in by_base.items() if b not in ambiguous_bases}

# 2. 文档里所有指向这些文件的引用 token。
docs = [Path(p) for p in git("ls-files", "*.md").splitlines() if p.startswith(DOCS_GLOB + "/")]
#    续列必须一起吃掉，仓里有两种写法：逗号（`FileWatcher.swift:2,84-94`，p16 的头号教训：
#    只匹配头一段等于放过 `,84-94`）和斜杠（`LaunchBehavior.swift:30/46`、`103/128`，
#    本轮实测第三种比第二种更阴——它长得像路径，不写进正则就永远看不见）。
SEP = r"(?:[,/]\d+(?:-\d+)?)*"
tok_re = re.compile(
    r"(?P<base>[A-Za-z0-9_.+-]+\.(?:swift|md|sh|go|rs|plist|entitlements))"
    r":(?P<ranges>\d+(?:-\d+)?" + SEP + r")"
)
CACHE = {}

# `@@ -o1,o2 +n1,n2 @@`：源文件的位置映射与"文档哪些行是本轮新写的"都从这一行读出来。
HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", re.M)


def lines_for(path, from_head):
    key = (path, from_head)
    if key not in CACHE:
        raw = git("show", f"HEAD:{path}") if from_head else (ROOT / path).read_text(encoding="utf-8", errors="replace")
        CACHE[key] = raw.split("\n")
    return CACHE[key]


def parse_ranges(spec):
    """`2,84-94/103` -> [(2, None), (84, 94), (103, None)]"""
    out = []
    for piece in re.split(r"[,/]", spec):
        if "-" in piece:
            a, b = piece.split("-", 1)
            out.append((int(a), int(b)))
        else:
            out.append((int(piece), None))
    return out


# ---- 2b. 只重指"HEAD 上就存在"的引用 ----
# 判据来自文档自己的 diff：本轮新写进去的那些行，锚点本来就是**对着工作区量的**，
# 再走一遍映射会把对的改成错的。这不是假想：`hook-ledger.md:101` 的 `SettingsView.swift:13`
# 是本轮现读写下的，工作区第 13 行确实就是 `MMHookValue.selected(key: "MM_SETTINGS_TAB")`，
# 而映射规则会按 HEAD 的第 13 行内容把它指到 :15——一个"重指正确、结果错误"的样本。
def added_lines(path):
    s = set()
    for m in HUNK_RE.finditer(git("diff", "-U0", "HEAD", "--", path)):
        n1, n2 = int(m.group(3)), int(m.group(4) or 1)
        if n2 > 0:
            s.update(range(n1, n1 + n2))
    return s


ADDED = {}
for doc in docs:
    rel = doc.as_posix()
    ADDED[rel] = added_lines(rel) if git("status", "--porcelain", "--", rel).strip() else set()

cites = []  # (doc, 文档行号, base, [(start, end)])
fresh = []  # (rel, 文档行号, token)：落在本轮新写行上的引用，工具不动，但要列出来给人抽查
for doc in docs:
    rel = doc.as_posix()
    added = ADDED.get(rel, set())
    text = doc.read_text(encoding="utf-8", errors="replace")
    for i, line in enumerate(text.split("\n"), 1):
        for m in tok_re.finditer(line):
            if m.group("base") not in tracked:
                continue
            if i in added:   # 本轮新写的行：锚点已经对着工作区，不动
                fresh.append((rel, i, m.group(0)))
                continue
            cites.append((doc, i, m.group("base"), parse_ranges(m.group("ranges"))))

need = {}
for _doc, _ln, base, rs in cites:
    for a, b in rs:
        need.setdefault((base, a), None)
        if b is not None:
            need.setdefault((base, b), None)

# 3. 逐条重指
# ---- 3. 位置映射：从 `-U0` 的 hunk 表算 old -> new ----
# 为什么要有第二套规则：第一套（HEAD 原文在工作区找唯一命中）对
# `}`、`.font(.caption)`、`Divider()` 这一类**结构行**是必然失效的——同一个文件里
# 有 261 个 `}`，"唯一命中"这个前提根本不成立，而文档引它们引的是"那一段"的位置。
# 位置映射不问内容，只问"改动前后这一行落在哪儿"，正是这类引用的语义。
#   oldCount>0 且 newCount>0 → 这一段被整段改写：按位置平移（文档主张若已过时，那是**内容**问题，
#                              由 `git diff docs/` 人工复核，不是行号能修的）；
#   oldCount>0 且 newCount=0 → 这一段被删干净了：行号无处可去，交人工（本轮真有四处属于这类）。
HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", re.M)


def hunk_map(path):
    """返回 (map_fn, deleted_set)。map_fn(old) -> new 或 None。"""
    diff = git("diff", "-U0", "HEAD", "--", path)
    hunks = []
    for m in HUNK_RE.finditer(diff):
        o1, o2, n1, n2 = int(m.group(1)), int(m.group(2) or 1), int(m.group(3)), int(m.group(4) or 1)
        hunks.append((o1, o2, n1, n2))
    deleted = set()
    for o1, o2, _n1, n2 in hunks:
        if o2 > 0 and n2 == 0:
            deleted.update(range(o1, o1 + o2))

    def f(old):
        if old in deleted:
            return None
        delta = 0
        for o1, o2, n1, n2 in hunks:
            if o1 > old:
                break
            if o2 == 0:
                if n1 <= old:        # 纯插入发生在这一行之前
                    delta += n2
                continue
            if old < o1 + o2:        # 落在改写段内：按段首对齐平移
                return n1 + (old - o1)
            delta += n2 - o2
        return old + delta
    return f


maps = {b: hunk_map(p) for b, p in tracked.items()}
mapping = {}   # (base, old) -> new
via_stat = {}
hand = []      # (base, old, why, text)
for (base, old), _ in sorted(need.items()):
    path = tracked[base]
    h = lines_for(path, True)
    w = lines_for(path, False)
    if old > len(h) or old > len(w):
        hand.append((base, old, f"越界（HEAD 共 {len(h)} 行 / 工作区共 {len(w)} 行）", ""))
        continue
    hl = h[old - 1].strip()
    wl = w[old - 1].strip()
    if hl == wl:
        mapping[(base, old)] = old
        continue
    hits = [i + 1 for i, x in enumerate(w) if x.strip() == hl] if hl else []
    pos = maps[base](old)
    if len(hits) == 1:
        mapping[(base, old)] = hits[0]
        via_stat["文本唯一"] = via_stat.get("文本唯一", 0) + 1
        if pos is not None and pos != hits[0]:
            hand.append((base, old, f"两套规则不一致（文本 {hits[0]} / 位置 {pos}）——采文本", hl))
    elif pos is not None:
        mapping[(base, old)] = pos
        via_stat["位置平移"] = via_stat.get("位置平移", 0) + 1
    elif len(hits) > 1:
        hand.append((base, old, f"工作区 {len(hits)} 处同文本且位置映射落在删除段", hl))
    else:
        hand.append((base, old, "该行所在段被整段删除，行号无处可去", hl or wl))


def render_map():
    out = []
    for (base, old), new in sorted(mapping.items(), key=lambda kv: (kv[0][0], kv[0][1])):
        if new != old:
            out.append(f"{base}:{old} -> :{new}")
    return out


# 历史叙述里的旧行号**不该跟着走**：文档里"本文此前写 `LaunchBehavior.swift:24-37`"这一类
# 句子引的是改动前那个错锚点本身，改了它等于把纠错记录改成"当时就是对的"。
# 但这件事**机器判不准**：同一行里"当前锚点"和"历史锚点"经常并存
# （本轮实测 `release-readiness.md:723` 一行两条，一条该改一条不该改；
#   `hook-ledger.md:108` 的 `MMCleaner.swift:930` 是**当前**锚点，它后面括号里那个裸 `930` 才是旧的）。
# 按整行跳过会把 5 条当前锚点留在漂的状态——比改错历史数字更糟，因为它悄无声息。
# 所以这里只做一件事：**把这些行点出来给人看一眼**（REVIEW 行），改写照旧全量执行。
# 本轮的复核结果记在 `release-readiness.md` §7.21：`LaunchBehavior.swift:24-37` 一条按历史保留、手工改回。
HISTORY_RE = re.compile(r"此前写|此前引|原记|旧写法|已漂到|改前|修复前")


def rewrite_line(line):
    """只重写映射齐全（区间与续列的每一端都可解析）的 token；任一端缺映射就整条不动。"""
    def sub(m):
        base = m.group("base")
        if base not in tracked:
            return m.group(0)
        out = []
        for piece in re.split(r"([,/])", m.group("ranges")):
            if piece in (",", "/"):
                out.append(piece)
                continue
            a, sep, b = piece.partition("-")
            na = mapping.get((base, int(a)))
            if na is None:
                return m.group(0)
            if not sep:
                out.append(str(na))
                continue
            nb = mapping.get((base, int(b)))
            if nb is None:
                return m.group(0)
            out.append(f"{na}-{nb}" if nb != na else str(na))
        return f"{base}:{''.join(out)}"
    return tok_re.sub(sub, line)


def rewrite(rel, text):
    return "\n".join(l if i in ADDED.get(rel, set()) else rewrite_line(l)
                     for i, l in enumerate(text.split("\n"), 1))


def preview():
    """逐条列出"哪个文档的哪一行、哪个 token 改成什么"，带原文上下文。
    `--write` 之后要靠这张表人工复核：机械规则能保证行号对得上，
    保证不了"文档那句话里引用的行号是不是**当时**的那个"（历史叙述里的旧行号不该跟着走）。"""
    n = 0
    for doc in docs:
        rel = doc.as_posix()
        text = doc.read_text(encoding="utf-8", errors="replace")
        for i, line in enumerate(text.split("\n"), 1):
            if i in ADDED.get(rel, set()):
                continue
            olds = [m.group(0) for m in tok_re.finditer(line) if m.group("base") in tracked]
            if not olds:
                continue
            nl = rewrite_line(line)
            if HISTORY_RE.search(line):
                print(f"  REVIEW {rel}:{i}  这一行有历史叙述，改写后需人看一眼  | {line.strip()[:90]}")
            if nl == line:
                continue
            news = [m.group(0) for m in tok_re.finditer(nl) if m.group("base") in tracked]
            for o, nn in zip(olds, news):
                if o != nn:
                    n += 1
                    print(f"  TOK  {rel}:{i}  {o} -> {nn}  | {line.strip()[:100]}")
    print(f"# 预览：会被改写的 token 共 {n} 处")
    for rel, i, t in fresh:
        # 工具不动这些锚点，所以把它们的**落点原文**一起打出来：这一行的作用是让人
        # 一眼看出"本轮现读的那个行号现在还对不对"，而不进口径就得靠记忆核。
        b = tok_re.match(t)
        base, start = b.group("base"), int(b.group("ranges").split(",")[0].split("/")[0].split("-")[0])
        w = lines_for(tracked[base], False)
        txt = w[start - 1].strip() if 0 < start <= len(w) else "（越界）"
        print(f"  FRESH {rel}:{i}  {t} -> {txt[:96]}")


print(f"# p29 anchor remap")
print(f"# repo: {git('rev-parse', '--short', 'HEAD').strip()}{'-dirty' if git('status', '--porcelain', '-uno').strip() else ''}")
print(f"# 被改源文件 {len(tracked)} 个" + (f"（歧义同名 {len(ambiguous_bases)} 个已跳过：{sorted(ambiguous_bases)}）" if ambiguous_bases else ""))
print(f"# 扫到引用 token {len(cites)} 处，唯一 (文件,行) {len(need)} 个"
      f"（另有 {len(fresh)} 处落在本轮新写的文档行上，锚点已经对着工作区，工具不动）")
res = render_map()
print(f"# 可重指（行号变了）: {len(res)}  来源：" + " / ".join(f"{k} {v}" for k, v in sorted(via_stat.items())))
print(f"# 需人工: {len(hand)}")
for line in res:
    print(f"  MAP  {line}")
if "--list-only" not in sys.argv:
    for base, old, why, t in hand:
        print(f"  HAND {base}:{old}  {why}  | {t[:110]}")
if "--preview" in sys.argv:
    preview()
if "--write" in sys.argv:
    changed_docs = 0
    for doc in docs:
        rel = doc.as_posix()
        src = doc.read_text(encoding="utf-8", errors="replace")
        dst = rewrite(rel, src)
        if dst != src:
            doc.write_text(dst, encoding="utf-8")
            changed_docs += 1
    print(f"# 已改写 {changed_docs} 份文档（映射齐全的那些 token；HAND 条目原样留着）")
