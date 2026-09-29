# P4.3 开发工具缓存：走 owner 命令，还是走目录删除

参考：Mole `lib/clean/dev.sh:72-447`、`845-1000`（Go 段）、`1070-1082`（`resolve_tool_home`）。
本轮结论：**MacMaster 只报位置和 owner 命令，不执行任何第三方二进制。**

## 为什么停在"只报"

这条能力的本体是"跑 `go clean -modcache` / `brew cleanup` / `npm cache verify`"，
也就是让一个清理工具去执行用户机器上任意版本的第三方程序。Mole 为此付出的代价可以直接读出来：
`_run_go_cache_clean_bound()` 在真正执行前的最后一步还要再查一次符号链接位（注释原话：
入口检查只证明"调用方看的那一刻"根目录不是链接；之后被换成链接，`go clean -modcache`
就会顺着链接删到别处），外加进程状态探针、词法/物理双路径身份快照、超时、
"process state unknown / cache path changed / owner cleanup failed" 三类停机原因。

这套判据是对的，但它保护的是"我们真的删了"这个动作。MacMaster 不执行，就把这一整层
风险面消掉了：

- 不 spawn 用户机器上的任意版本 `go`/`brew`/`npm`，也就没有 argv 注入、PATH 劫持、
  工具版本行为差异这一类问题；
- 不需要"进程状态未知时拒绝执行"这条判据——**没有执行，就没有需要拒绝的执行**；
- 用户拿到的是可以自己核对的命令，跑不跑由他决定。

代价：这一屏回收不了空间，只是把"该由 owner 清的缓存"从"我们 rm 掉"里摘出来。
这比多回收几个 GB 但踩一次误删要划算。

## 明确不做

- **`brew autoremove`**：它卸载的是 formula 本身，不是缓存。 roadmap 里把它列进 4.3 是个
  归类错误，这里改口：清理工具不该给"卸载你正在用的软件"的入口。
- **执行任何 owner 命令**（含带 `-n` 的预览形式）：预览也要 spawn，收益不抵风险。
- **`go env` / `npm config get cache` 求根**：这两个是只读查询，但仍然是 spawn。
  改成读环境变量 + 文档默认值，并把"根是从哪来的"标在界面上（见下）。

## 根位置怎么定（不 spawn 的前提下）

优先级：环境变量 → 文档默认值。环境变量必须过校验：绝对路径、不含 `..`、不含换行，
否则视为无效并回落到默认值——照 Mole `resolve_tool_home` 的判据抄。

| 缓存 | 环境变量 | 默认值 |
|---|---|---|
| Go 模块 | `GOMODCACHE` | `~/go/pkg/mod` |
| Go 构建 | `GOCACHE` | `~/Library/Caches/go-build` |
| Cargo registry | `CARGO_HOME`（拼 `/registry`） | `~/.cargo/registry` |
| Homebrew 下载 | `HOMEBREW_CACHE` | `~/Library/Caches/Homebrew` |
| npm | 无（`npm config get cache` 要 spawn，不做） | `~/.npm/_cacache` |
| pip | 无 | `~/Library/Caches/pip` |

界面上每条都要写明来源档位：「按 GOMODCACHE 定位」/「按默认位置，未向 go 求证」。
后者是"没问过工具"，不能让用户读成"这就是工具实际用的那个"。

## 测量诚实档位

三条独立的事实，绝不合并成一条"可清理 X"：

1. **装没装**：`PATH` 里能不能解析到可执行文件（这一步只是 `stat`，不执行）。
2. **在不在**：解析出的根目录是否存在。不存在要写成"这个位置不存在，本机没拉过模块"，
   不能写成 0 字节——`absent ≠ 空`，`空 ≠ 干净`。
3. **多大**：`SystemSampler.directoryBytes` 的量数；`nil` 渲染成 `—` + "没量到"，
   不折成 0。

## owner 命令与"为什么不能 rm 目录"

| 缓存 | 命令（只给文本） | 为什么目录级 rm 不够好 |
|---|---|---|
| Go 模块 | `go clean -modcache` | modcache 内文件是只读且共享硬链接；删完 go 自己的视图不会同步。另外这条命令删的是**根目录本身**，所以根被换成符号链接时会顺着链接删到别处，跑之前必须确认它不是链接。 |
| Go 构建 | `go clean -cache` | 构建缓存有 owner 的 trim 逻辑（`-trim` 按时间保留），rm 会连"最近用过的那部分"一起清掉，下次全量重编。 |
| Homebrew | 先 `brew cleanup -n` 预览，再 `brew cleanup` | `Library/Caches/Homebrew` 只是下载瓶子的缓存，rm 安全；但真正占空间的多是旧版本 formula，只有 brew 自己知道哪些还在依赖链上。 |
| Cargo registry | `cargo cache -O`（第三方 `cargo-cache`，默认没装） | cargo 自带**没有**清缓存子命令；没装 cargo-cache 时这条要如实写"没有 owner 命令，删目录是可接受的降级"。 |
| npm | `npm cache verify` | verify 会校验内容寻址存储并回收失效项，比 rm 准；rm 之后首次安装要全量重下。 |
| pip | 无 | pip 没有清理子命令，直接删目录是安全的。 |

## 本机实测（写这份文档时跑的只读命令）

- 在：`go` `/opt/homebrew/bin/go`、`cargo`、`brew`、`npm`、`uv`、`pip3`；不在：`gh`。
- `go env GOMODCACHE` = `~/go/pkg/mod`，`go env GOCACHE` = `~/Library/Caches/go-build`，
  两个目录**都不存在**（`go` 装了但从没拉过模块/构建过）。
- `brew --cache` = `~/Library/Caches/Homebrew`，**不存在**。
- `~/.cargo/registry` 存在，75 MB。
- `~/Library/Developer/Xcode/DerivedData` 存在，336 MB。

也就是说本机这一屏大部分行会落在"不存在"档——这正是实现要画对的状态，
不是可以跳过的边界。

## 落地边界

- 新增 `MMOptimizer/DevToolCacheAudit.swift`：纯函数，输入环境字典 + 文件存在性探针 +
  大小探针，输出条目数组。不 spawn、不写文件。
- UI 挂在「系统优化」页新增的「开发工具缓存」卡：每条显示 名称 / 位置来源 / 状态 / 大小 /
  「拷贝命令」/「在访达中显示」。**没有删除按钮。**
- 未覆盖：owner 命令的**执行**、`mise`/`rustup` 之类二次重定位根的处理（Mole 为此写了
  issue #1378 的专门回归）、非默认 `CARGO_HOME` 下的物理路径身份复核。
