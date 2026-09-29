# P3.2 调研：TCC 授权只读视图（guardian-tcc）

> 结论先行：**本机（macOS 27.0 beta / Build 26A428，ad-hoc 签名、非沙盒、无 FDA）
> 两个 TCC.db 都读不到。**
> 用户级库连目录都对当前进程不可见（ENOENT，被系统隐藏而非 EPERM 拒绝），
> 系统级库在 `open(2)` 层就被挡（EPERM），sqlite 报 `authorization denied`（rc=23）。
> 因此这一屏在"未授权完全磁盘访问"的常态下必须走**"读不到 · 原因"降级档**，
> 绝不显示空列表（空列表会被读成"没有应用持有权限"）。
> 证据命令与报错原文全部本机实测，逐条列在下面。

## 1. 本机实测（2026-09-30）

### 1.1 探针方法

- 与路线图指向的 Pearcleaner 同一入口：`sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, NULL)`
  （`docs/github-references/Pearcleaner/Pearcleaner/Logic/TCC/TCCQueryHelper.swift:31-40`）。
- 额外用裸 `open(2, O_RDONLY)` 先探一次，把 sqlite 吞掉的 POSIX errno 原文抓出来
  （sqlite 的 `unable to open database file` 不区分"不存在/被隐藏/被拒"，这三个语义对用户不同）。
- 探针程序：`cc probe.c -lsqlite3`，SELECT 列取实现要用的
  `service, client, auth_value, last_modified`。

### 1.2 用户级 `~/Library/Application Support/com.apple.TCC/TCC.db`

```
ls: /Users/lee/Library/Application Support/com.apple.TCC: No such file or directory
open(O_RDONLY)                errno=2 (No such file or directory)
sqlite3_open_v2(READONLY)     rc=14 (unable to open database file)
```

- **注意 ENOENT ≠ 文件真的不存在**：同机对照实验——同样需要 FDA 的
  `~/Library/Mail` 报的是 `Operation not permitted`（EPERM），而 `com.apple.TCC`
  目录报的是 ENOENT。macOS 对 TCC 自己的数据做了**隐藏**（data vault），
  无权限的进程连"它存在"都无法断言。
- 因此实现里对 ENOENT 的文案是"路径不存在**或被系统隐藏**"，不说死。
- **本机无法验证"授予 FDA 后可读"**：给 ad-hoc 构建的 MacMaster 授 FDA 需要人工
  去系统设置点加，不在自动化验证范围内。按社区共识与 Pearcleaner 源码注释
  （`TCCQueryHelper.swift:118` "System database path (requires Full Disk Access)"），
  用户级库授予 FDA 后通常可读；**此结论标注为未在本机验证**。
  若授予后仍 ENOENT，则本机用户级档就是长期"读不到"，UI 已有对应降级路径。

### 1.3 系统级 `/Library/Application Support/com.apple.TCC/TCC.db`

```
ls -la: -rw-r--r-- 1 root wheel 126976   ← Unix 权限位显示全局可读，但没有用
cat                                      → Operation not permitted
open(O_RDONLY)                           errno=1 (Operation not permitted)
sqlite3 -readonly <db> .tables           → Error: unable to open database …: authorization denied
sqlite3_open_v2(READONLY)                rc=23 (authorization denied)
sqlite3 "file:…?immutable=1" .schema     → 同样 authorization denied（rc=23）
```

- Unix 权限位（`o+r`）与实际可达性完全脱节：拦截发生在 macOS 的 TCC/SIP 数据保护
  层（sqlite rc=23 `SQLITE_AUTH`），**不是文件权限问题，chmod/属主都改不动，
  授予 FDA 也不在其管辖内**。immutable URI 绕不开。
- 未验证"以 root + FDA 读取"的分支：那需要提权，超出本功能红线（只读、绝不提权），
  不做。`kTCCServiceScreenCapture`、`kTCCServiceAccessibility`、`kTCCServiceListenEvent`
  的授权记录主要就存在这个系统级库里——所以即便用户级库可读，**屏幕录制/辅助功能
  两行在本 app 里预期仍是"读不到"**，卡上必须按来源分别标注可读性，不能混在一起。

### 1.4 能读到哪些表/列

两个库都开不了，**没有读到任何行**，`access` 表、`client`/`auth_value`/`last_modified`
列的实际内容在本机未验证。下表列名取自 Pearcleaner 查询与 sqlite3 CLI 对普通库的
schema 约定，实现按"列取不到=查询失败→读不到档"处理，不做任何回退猜测。

| 列 | 用途 | 本机验证 |
|---|---|---|
| `service` | 服务名（`kTCCServiceMicrophone` 等） | ❌ 未读到（库打不开） |
| `client` | bundle id（`client_type=0`）或路径（`=1`） | ❌ 同上 |
| `auth_value` | 0 拒绝 / 2 允许 / 3 有限 / 4 已禁用；**其它值=未知** | ❌ 同上 |
| `last_modified` | unix epoch 秒 | ❌ 同上 |

## 2. auth_value 语义映射（不猜）

任务书口径：0 拒绝 / 2 允许 / 3 有限 / 4 已禁用。
历史注记：Big Sur 之前 1 表示"允许"（Pearcleaner `TCCModels.swift:38-46` 仍按旧表把 1
映射成 Allowed、2 映射成 "Allowed (Limited)"——**在新系统上是过时的映射，不采纳**）。
本项目把 1 和一切不在表内的值统一渲染成"未知值 (N)"徽章（灰色、不表达"允许"），
宁可信息少，不能信息假。单测锁死这条映射。

## 3. UI 呈现三档（测量诚实）

| 档 | 条件 | 呈现 |
|---|---|---|
| 读不到 | 两个库都打不开 | 卡内降级横幅："读不到 · 需要完全磁盘访问" + 每库错误原文（errno/sqlite 码原样保留）+ "打开系统设置"按钮。**不画列表** |
| 部分可读 | 一库可读、一库打不开 | 列表 + 顶部警示条点名读不到的库："清单可能不完整" |
| 可读为空 | 可读库都查了、0 行 | 空态文案明确"这是查到了 0 行"；若有库没读到则并入部分可读档 |

client → 应用名解析：bundle id 用 `NSWorkspace.urlForApplication(withBundleIdentifier:)`
+ `CFBundleDisplayName/Name`；解析不到就显示原始 client 串（法则 2，不编名字）。

## 4. 实现分层（照 P3.1）

- `TCCAuthorization.swift`：auth_value 判定表、服务名映射、三档视图状态机、
  夹具解析 —— 纯逻辑，单测全覆盖。
- `TCCProbe.swift`：真正 `sqlite3_open_v2(..., READONLY)` 的一层，路径可注入；
  与 DeviceUsageProbe 同理**不假测**（用夹具 db 测它只能证明 sqlite 能用，
  不能证明真 TCC 库的可读性，装了就是假绿）。
- 截图钩子 `MM_TCC_FIXTURE`：取值仅 `rows|unreadable|empty`，含非法项整体作废并写
  stderr；`rows` 注入的全是 `com.example.*` 合成行，与真实数据一眼可分。

## 5. 风险声明

- 只读：`SQLITE_OPEN_READONLY` + prepared statement 只 SELECT；任何写 API 不链接调用路径。
- 不提权：不出现 `authorization_execute`/`SMAppService`/sudo；打不开就降级文案。
- schema 漂移：列缺失/prepare 失败一律按"读不到 + 原文"处理（Pearcleaner 同款防御，
  `TCCQueryHelper.swift:44-46` 的显式列名查询思路）。
