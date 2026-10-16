#!/usr/bin/env python3
# P52b：文档裸行段引用的 HEAD→工作树 内容核对。
# 每一对 (old_start, old_end, new_start) 由偏移表给出，这里逐行断言文本相等；
# 不相等就打印两边的原文，交给判断，不自动改数。
import subprocess
import sys

REPO = "/Users/lee/Desktop/MacMaster"


def lines(relpath, rev=None):
    if rev is None:
        with open(f"{REPO}/{relpath}", encoding="utf-8") as f:
            return f.read().splitlines()
    out = subprocess.run(["git", "-C", REPO, "show", f"{rev}:{relpath}"],
                         capture_output=True, text=True, check=True).stdout
    return out.splitlines()


UNINSTALLER = "Packages/MMUninstaller/Sources/MMUninstaller/MMUninstaller.swift"
MODEL = "Packages/MMUninstaller/Sources/MMUninstaller/UninstallerModel.swift"

# (文件, 旧起, 旧止, 新起)
PAIRS = [
    (UNINSTALLER, 717, 725, 727),
    (UNINSTALLER, 730, 736, 740),
    (UNINSTALLER, 761, 771, 771),
    (UNINSTALLER, 780, 792, 790),
    (UNINSTALLER, 1290, 1290, 1300),
    (UNINSTALLER, 1346, 1348, 1356),
    (UNINSTALLER, 1349, 1355, 1359),
    (UNINSTALLER, 1441, 1441, 1451),
    (UNINSTALLER, 1472, 1472, 1482),
    (UNINSTALLER, 1541, 1541, 1551),
    (UNINSTALLER, 1574, 1574, 1584),
    (UNINSTALLER, 1641, 1706, 1651),
    (UNINSTALLER, 1657, 1676, 1667),
    (UNINSTALLER, 1689, 1691, 1699),
    (UNINSTALLER, 1849, 1849, 1859),
    (UNINSTALLER, 1862, 1868, 1875),
    (UNINSTALLER, 1887, 1896, 1903),
    (MODEL, 85, 85, 95),
    (MODEL, 91, 93, 101),
    (MODEL, 384, 388, 400),
    (MODEL, 458, 458, 474),
]

bad = 0
for path, os_, oe, ns in PAIRS:
    head = lines(path, "HEAD")
    work = lines(path)
    span = oe - os_ + 1
    diffs = []
    for i in range(span):
        h = head[os_ - 1 + i]
        w = work[ns - 1 + i] if ns - 1 + i < len(work) else "<越界>"
        if h.strip() != w.strip():
            diffs.append((os_ + i, ns + i, h.strip(), w.strip()))
    tag = "OK  " if not diffs else "DIFF"
    print(f"{tag} {path.split('/')[-1]} :{os_}-{oe} -> :{ns}-{ns + span - 1}")
    for d in diffs[:6]:
        bad += 1
        print(f"       HEAD {d[0]}: {d[2][:110]}")
        print(f"       WORK {d[1]}: {d[3][:110]}")
print(f"\n不一致的行数（只打印每对前六条）：{bad}")
sys.exit(0)
