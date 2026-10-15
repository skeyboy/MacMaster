#!/usr/bin/env python3
"""P41 量尺配套重指：把 `p29-anchor-drift-audit.sh` **自己报出来的**"可照抄重锚"逐条落盘。

为什么另写一支而不是直接用 `p29-anchor-remap.py`：那一支的映射表只覆盖本轮被改过的
`.swift`（规则一/规则二都是从 `git diff` 的 hunk 表算的），而 P41 这一轮的漂移来自
`tokens.css` 里 `--sidebar-w-min` 那一行由 1 行变 2 行——整张表下游 +1。这一支不做任何
自己的判断，**只吃审计脚本的输出**：

  * 输入 = 审计日志里 `doc=PATH:L  move=SRC:OLD -> SRC:NEW` 这种行（`reason=唯一命中原文`）。
  * 动作 = 在 `PATH` 的第 `L` 行上，把 token `SRC:OLD` 换成 `SRC:NEW`（同一行多次命中全换）。
  * 该 token 在那一行找不到 / 新旧相同 / 目标行号越界 → 原样不动，打进 `SKIP` 交人工。
  * 默认只打印。`--write` 才落盘，落盘前逐条打印改前/改后。

安全边界照旧：只改 `docs/**.md`，永不碰源码，永不碰 `docs/verification/`（那是历史读数，
改了就是把证据毁了）。审计脚本本身仍然只量不改。

用法：
  ./Scripts/p41-tokens-remap.py docs/verification/p41-anchor-drift/audit-precommit.log          # 看
  ./Scripts/p41-tokens-remap.py ... --write                                                     # 改
退出码：有 SKIP 也返回 0（这是量尺），只有输入读不出或写盘失败才是 1。
"""

import re
import sys
from pathlib import Path

MOVE_RE = re.compile(
    r"doc=(?P<doc>[^:\s]+):(?P<line>\d+)\s+move=(?P<src>[^\s:]+):(?P<old>\d+)\s*->\s*"
    r"(?P<src2>[^\s:]+):(?P<new>\d+)"
)


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--write"]
    write = "--write" in sys.argv[1:]
    if len(args) != 1:
        print("用法: p41-tokens-remap.py <审计日志> [--write]", file=sys.stderr)
        return 1
    log = Path(args[0])
    if not log.is_file():
        print(f"读不到日志：{log}", file=sys.stderr)
        return 1

    moves: dict[str, list[tuple[int, str, str]]] = {}
    for raw in log.read_text(encoding="utf-8", errors="replace").splitlines():
        m = MOVE_RE.search(raw)
        if not m:
            continue
        if m.group("src") != m.group("src2"):
            print(f"SKIP(源文件不同名) {raw.strip()}")
            continue
        doc = m.group("doc")
        if not doc.endswith(".md") or doc.startswith("docs/verification/"):
            continue
        token = f"{Path(m.group('src')).name}:{m.group('old')}"
        repl = f"{Path(m.group('src2')).name}:{m.group('new')}"
        moves.setdefault(doc, []).append((int(m.group("line")), token, repl))

    changed: dict[str, list[str]] = {}
    skips = 0
    for doc, items in sorted(moves.items()):
        path = Path(doc)
        if not path.is_file():
            print(f"SKIP(文档不存在) {doc}")
            skips += 1
            continue
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        for lineno, token, repl in sorted(items, key=lambda x: -x[0]):
            if lineno > len(lines):
                print(f"SKIP(行越界) {doc}:{lineno} {token}")
                skips += 1
                continue
            cur = lines[lineno - 1]
            if token not in cur:
                print(f"SKIP(token 不在该行) {doc}:{lineno} {token}")
                skips += 1
                continue
            # 区间写法 `:A-B` 只报了一个端点，机械 +1 会把 `:66-67` 改成 `:67-67`——
            # 这种行交人工，两端一起挪才有意义。
            if re.search(re.escape(token) + r"-[0-9]", cur):
                print(f"SKIP(区间端点) {doc}:{lineno} {token}")
                skips += 1
                continue
            new = cur.replace(token, repl)
            lines[lineno - 1] = new
            print(f"{'改' if write else '拟'} {doc}:{lineno}  {token} -> {repl}")
        changed[doc] = lines
    if write:
        for doc, lines in changed.items():
            Path(doc).write_text("".join(lines), encoding="utf-8")
    print(f"# 合计条目 {sum(len(v) for v in moves.values())}，跳过 {skips}，"
          f"文档 {len(changed)} 个，落盘 {'是' if write else '否'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
