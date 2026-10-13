# P36 第二笔在册债：漂移量尺的目标面补上「本轮被改的非 `.swift`」

一支量尺、三跑读数。过程与判据在 `docs/analysis/release-readiness.md` §7.26。

```
./Scripts/p29-anchor-drift-audit.sh docs/verification/p36-anchor-drift            # base=HEAD
./Scripts/p29-anchor-drift-audit.sh docs/verification/p36-anchor-drift HEAD~1     # 复看上一轮
```

## 三份日志是哪三跑

| 文件 | 跑法 | 读数 |
| --- | --- | --- |
| `audit-injection.log` | 受控注入：在 `feature-roadmap.md` 顶部插两行再跑 | 14 条 `DRIFT` / 3 条 `UNRESOLVED`，其中 13 条是别的文档指向本文行号的活锚点、位移全是 +2 |
| `audit-after-repoint.log` | 注入还原、五条锚点重指之后再跑一次 | 1 条 `DRIFT` / 2 条 `UNRESOLVED`，三条全指向本轮未提交的 `Scripts/p29-anchor-drift-audit.sh` 自己 |
| `audit-prev-round.log` | `BASE=HEAD~1`，复看第十五遍那一轮 | 目标面 13 个被改的非 `.swift` 文件，报出的三条仍全是本轮那一份，**上一轮那 11 条一条都不再出现** |

注入那两行（一句 `<!-- P36 受控注入… -->` 与一个空行）跑完即还原，没有进提交，也没有进任何文档。

## 为什么只有 `audit-after-repoint.log` 这一族指向脚本

它拿 `BASE` 那一版的同一行当"应然文本"，**本轮新写进行号引用的锚点必然被报成漂**——
base 那一版还没有这一行。所以第二跑的那三条不是"又漂了"，是"新写的锚点在 base 里无对应行"，
其中两条给的 reason 就是 `base 那行是空行`。**真值只在"这一轮第一次跑"那一次**（P35b 归档里第 2 类同一件事，现在两族都适用）。

## TSV

`drift.tsv`（`.swift` 目标那一族）本轮 0 行——九包之外的 `.swift` 一个没改。
`drift-nonswift.tsv` 是**最后一跑**（`HEAD~1` 那一次）落的 3 行，前两跑的 TSV 被同一目录的后续跑覆盖，
逐条明细以三份 `.log` 里的 `#   doc=…` 行为准。
