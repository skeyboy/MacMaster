# 双层闸门语义复核（disk I6 · 集成阶段落地结论）

> 对应 `fidelity-disk.md` §提请协调者 第 6 条。本文档只下结论、不改代码。

## 结论先行

`DiskRemoval.plan` 与 `MMCore.DeletionGuard` 是**两层互补、各司其职、无冲突**的闸门，
不是"两套清单打架"。防御纵深成立，无需合并，也无需改任何裁决逻辑。

## 两层各自是什么

| 层 | 位置 | 职责 | 时机 | 失败后果 |
| --- | --- | --- | --- | --- |
| 展示裁决 | `MMDisk/DiskRemoval.plan` | 把"用户标了什么"裁决成"能删/不能删/为什么"，供确认面板列清单、合计字节、投影剩余空间 | 标记 → 弹出确认面板前 | 只是面板显示不完整，不碰磁盘 |
| 执行闸口 | `MMCore/DeletionGuard.rejection` | 全站唯一删除出口的硬保护：系统目录、凭证子树、六目录本身、废纸篓目录 | `FileTrashService.moveToTrash` 逐条执行时 | 拒绝执行并作为 `TrashFailure(code:"PROTECTED")` 上报 |

## 关键事实链

1. `trashMarked(plan:)` 只取 `plan.targets`（`MMDisk.swift:1339`），被 `DiskRemoval` 拦下的
   `blocked` 项**根本进不了删除清单**——第一层已经挡掉"整卷根/系统树/主目录/消失项"。
2. `targets` 仍会**再**走 `FileTrashService.shared.moveToTrash`（`MMDisk.swift:1347`），
   其内部对每条路径调 `DeletionGuard.rejection(for:)`（`FileTrashService.swift:96`，P47 现读重指，此前写 `:47`），
   命中即拒绝并进 `failures`。这是第二道、也是最后一道闸。
3. 两层的判据集合有重叠但不矛盾：
   - `DiskRemoval.systemFirstComponents`（`System/usr/bin/sbin/private/dev/Library`）用于
     **展示侧**标"系统目录树"——写作当时它比 `DeletionGuard.systemRoots` 更宽（多含 `dev`、`private`）。
     **P21 把这两条补进了闸门**（`DeletionGuard.swift:32`，理由见 `deletion-guard.md` §7.1），
     两边现在在这三条上口径一致；剩下的差异只在"宽严方向"上：第一层按**名字**匹配根目录的子女，
     第二层按**整棵子树 + 符号链接解析**判，后者仍多得多（凭证子树、六目录本身、`/var/db` 等）。
     漏过第一层的路径一律由 `DeletionGuard` 兜住。
   - `DeletionGuard` 独有的凭证子树（`.ssh/.gnupg/.aws/Keychains/…`）与"六目录本身挡、内容放"
     是 `DiskRemoval` 没有的维度——这是**刻意的分工**：disk 的扫描根通常是用户主动选的目录，
     不该由模块自己再硬编码一套凭证清单；真正的拒绝权收敛在 MMCore 唯一出口。

## 结论

- **无"该拦没拦"的漏判**：任何从第一层漏过的路径，执行时都会被第二层挡住并如实上报。
- **无"该放被误拦"**：`DiskRemoval` 宽口径只影响确认面板的"是否显示为可删"，不影响最终能否删；
  用户能看到的可删项，执行侧仍以 `DeletionGuard` 为准，误报只会让面板少列一项，不会误删。
- **无需合并**：合并会把"展示裁决"和"执行拒绝"两种语义捆死，反而让 disk 模块被迫依赖 MMCore
  的完整凭证清单（当前刻意解耦）。

## 遗留（不属本次范围）

- ~~`DeletionGuard.systemRoots` 未显式收 `/dev`、`/private` 作为独立前缀（`/private` 经
  `privateAliases` 归一、`/dev` 靠 `physicalPath` 兜底）~~ —— **P21 已收**（`DeletionGuard.swift:32`）。
  顺带把这一条当时说错的地方记下来：`physicalPath` 只是把符号链接解析成物理路径，
  它**不会**给清单增加任何条目，所以"`/dev` 靠 `physicalPath` 兜底"不成立 ——
  `/dev` 不是链接，`/dev/null` 在两遍口径下都落在当时的清单之外，第一道（`DiskRemoval` 按名字）
  之外确实没有人挡。写文档时把"解析"当成"保护"，是这一类缺口最容易的来法。
