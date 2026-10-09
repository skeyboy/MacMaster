# MacMaster 1.0.0（构建 1）

发布日：2026-10-08。这一页是**对外那一页**：每一句都对着当前代码或入库的取证日志现读写过，
量不到的直接写"没有"。核验轮次、判据与全部出处在 `docs/analysis/release-readiness.md`。

## 这是什么

MacMaster 是一款 macOS 原生的系统清理与诊断工具，Swift/SwiftUI 写的，**只在本机跑**：
它读本机的缓存、废纸篓、已装应用、磁盘占用、CPU/内存/温度、摄像头与麦克风的占用状态，
把你**逐项勾选**过的东西移进废纸篓（可撤回），磁盘页另有一条需要额外勾选确认的永久删除路径。

- 零网络代码，零遥测（自证见文末）。
- 界面只有简体中文。
- 要求 macOS 14.0 或更高。

## 这一档是什么形态的发布

**自编译 / 私有源码分发档**，不是给陌生人的安装包。

- 产物是 **ad-hoc 签名、未公证**：`codesign` 那行是 `flags=0x2(adhoc) Signature=adhoc TeamIdentifier=not set`，
  Gatekeeper 当场 `spctl ... rejected`。别人下载后首次打开需要自己在「系统设置 › 隐私与安全性」里放行。
- **尚未选择许可证**，也没有确定著作权人与签名身份（产物 plist 里 `NSHumanReadableCopyright` 现在是占位值
  `MacMaster`）。这三项在 `docs/analysis/release-readiness.md` §10 第 4 步列成等人拍的决策。
- 附件由 GitHub Actions 打出（`.github/workflows/release.yml`），与本地跑同一条命令链：
  `make-app.sh` → `package-app.sh`。打包当场会验 plist 版本键、zip 解回来验可执行位与签名、
  dmg 挂回来验 `/Applications` 替身，任一项不过就**不会**上传。
- 附件带 `*-SHA256SUMS.txt`，下载后可以自己比。
- ad-hoc 签名还有一个实际后果：**登录项注册可能被 macOS 拒绝**（界面上会写失败原因，不会假装成功）。

## 八屏

侧边栏七行 + 设置窗，另有一个菜单栏项目。逐屏能力都是本轮从代码里读的：

| 屏 | 里面有什么 |
| --- | --- |
| 概览 | 卷占用与"可释放"实测值、CPU/内存/磁盘实时读数、底部状态条（卷数、文件系统、上次清理时间） |
| 系统清理 | 四页：缓存清理 / 用户文件夹 / 系统分析 / 开发产物；缓存页顶部可按 全部·缓存·日志·临时 过滤 |
| 应用卸载 | 两页：已装应用 / 卸载后遗症（孤儿残留）。brew 装的应用在列表里带 `brew` 或「疑似 brew」标记，详情标题旁是完整来源徽章；「查不到来源」不做成徽章 |
| 磁盘分析 | treemap 真实扫描 + 标记删除；触达深度上限 20 层的目录只量字节不列名字 |
| 系统监控 | 六卡：概览 / 每核 CPU / 磁盘 / 内存 / 进程 / 温度与风扇（SMC，读不到就写读不到的原因）；页头有菜单栏开关 |
| 隐私守护 | 四卡：摄像头与麦克风当前占用（手动测量，非实时监听）/ TCC 授权只读视图 / 登录项管理 / 密钥与自启配置的改动时间 |
| 系统优化 | 四页：重复文件 / 浏览器缓存 / 系统状态 / 开发工具（开发工具页只读，没有删除入口） |
| 设置 | 四页：通用 / 监控 / 清理 / 关于 |
| 菜单栏 | 系统监控项常驻，展开有每核 CPU 与「打开 MacMaster」 |

## 用的时候要知道的四件事

1. **系统清理**：可释放数字是扫描瞬时值，不是承诺值。
2. **磁盘分析**：treemap 需要真实扫描，大目录下扫描时间与内存都要留意；
   触达深度封顶（20 层）的那一档只量字节、不列子项名字，界面上写的是「子项 未枚举」——那不是坏了。
3. **隐私守护**：①TCC 授权视图读不到时需要你手动授「完全磁盘访问」，界面对此有横幅；
   ②那张卡现在叫「密钥与自启配置的改动时间」，**只有 mtime，不报"最近访问"**，
   所以它只能看出密钥目录最近有没有被写过，不能用来判断有没有人访问过你的密钥；
   ③统一日志那一档已经整族撤下，这一模块不再起子进程读系统日志；
   ④页头副标题是四段清单，窗口很窄时会被中间截断（悬停有全文）；
   ⑤`launchctl list` 这一路有 10 秒时限，超时不会给你一个偏小的数，而是整卡换成「没能和 launchd 对表」那句。
4. **系统优化 › 重复文件**：要你人工核对分组。勾选是逐项手动、默认一个都不勾；
   一组里其余文件都勾完之后，最后一份的勾选框会禁用（每组至少留一份）；
   真勾到删除闸门保护的路径时，服务层直接拒绝并给出 PROTECTED 回执，不会静默删掉。

## 隐私：读什么、写什么、不做什么

**读**（全在本机）：`~/Library/Caches`、`~/Library/Logs`、`~/Library/Containers/*/Data/Library/Caches`、
darwin 用户缓存目录、系统级 `/Library/Caches` 与 `/Library/Logs`；iOS 备份目录只读列体积、分类为只读、
不给删除入口；浏览器只看**缓存目录**（不读 History、不读 Cookies、不读密码库）；
重复文件会读文件内容算 SHA-256（先头尾各采样，命中候选才整文件哈希，任何读失败都计入"读不了"，宁可漏报不误报）；
`/var/db/receipts` 安装包收据与 Homebrew 账本只读；
`TCC.db` 以 `SQLITE_OPEN_READONLY` 打开、只跑 prepared SELECT，读五档授权状态
（麦克风、摄像头、屏幕录制、辅助功能、输入监听）。

**写**（你机器上会长期留下的东西）：

1. `~/Library/Preferences/com.macmaster.app`：17 把 `settings.*` 键，加 `mmcleaner.exclusions.v1`
   与 `mmcleaner.exclusions.schema` 两把排除名单键。
2. `~/Library/Application Support/MacMaster/trash-history.json`：**这是唯一一份记录了你的文件路径的磁盘文件**，
   原子写，为的是跨启动撤回。不想要可以删，删了就撤不回那次的删除。
3. 系统登录项的注册/注销（`SMAppService.mainApp`），只在你在设置里打开「登录时启动」时发生。
4. 删除本身：默认 `FileManager.trashItem`（进废纸篓），磁盘页那条永久删除路径需要你额外勾选确认，
   且**不写台账**（删掉就是删掉）。

**不做**：零网络代码（生产源码的 import 清单里没有网络框架，`URLSession`/`socket` 全仓 0 命中）、
无任何遥测或统计上报；通知是唯一会弹系统授权的入口；摄像头与麦克风只做枚举、不建采集会话，
所以不会触发 TCC 弹窗。

## 明确没有的

Mac App Store 版（沙盒会把已测的七行能力砍掉）；多语言（语言开关是禁用的，切换不会改变界面）；
自动更新（没有更新服务器）；helper 与 widget 扩展（仓库根那两个目录各只有一个空的 `Sources/`，
git 里根本没有文件）；许可证文件（尚未选择）。

## 已知限制

- 壳层（导航、窗口、设置页绑定）**零自动化测试**：根 `Package.swift` 只有一个 `.executableTarget`、
  没有测试目标，下面那些测试一条都不覆盖壳层——这一层靠 `docs/verification/` 下的实机照片，不靠断言。
- 清理页删除失败后的「重试失败项 / 复制诊断」补救按钮组件已经写好了，但**全仓 11 个调用点一个都没接**
  （本轮现读：`Sources` 与 `Packages` 里除组件自身定义外，`onRetry`、`onCopyDiagnostics` 0 命中），
  所以现在统计行与页脚是死代码路径；撤回开关只在缓存页的 sheet 里，另两页走系统 alert；
  页签叫「缓存清理」而页头叫「系统清理」，两名不同源。
- 磁盘页详情头部图标与设计稿不同、时间显示用相对时间而不是绝对日期。
- 监控页的网络速率只在菜单栏显示，页面里不用。
- 优化页失败面板的形态（通栏条 vs 带边框卡）与设计稿不一致。
- 温度与风扇那一卡依赖本机 SMC，换机型/换系统要重验（`docs/analysis/release-readiness.md` §8 有这条单列档）。
- **设置页这一版有四处够得着的缺陷**（2026-10-09 逐行核对，四处都在本构建的源码那一棵 `5e3b2ca` 上现读确认；
  下面那两处行号是**那一棵**上的，工作区这一棵已经改过，别照当前文件去对）：
  深链 `x-apple.systempreferences:` 被拼了两遍（`MMDesign.swift:516-517` 加一次、调用点传的字符串里已有一次），
  点开不会有任何反应；没有 ⌘,，系统菜单栏里也没有「设置…」，只能从标题栏那枚齿轮进；
  通知那一节不读系统的授权状态，脚注无论本机是什么档都写"已开启"；设置窗口高 400 pt
  （`SettingsView.swift:54`），第二个页签以下的内容在画面之外。**这四处已在源码中修复**
  （`docs/analysis/release-readiness.md` §7.21、取证照片 `docs/verification/p29-before/` 与 `p29-after/`），
  但**不在本构建里**——它们会随下一版发出。
- 壳层测试那一格要说得更准：本轮之后 MMCore 多了 4 条钉深链拼接的测试、MMMonitor 多了 4 条钉通知文案的测试，
  它们钉的都是包里的纯函数；上面那句"一条都不覆盖壳层"仍然成立，根 `Package.swift` 里没有测试目标。

## 测试与规模（本轮现读）

九包 **633** 个测试、**0** 个失败、**1** 个跳过（跳过原因见 `docs/analysis/release-readiness.md` §1）。
逐包：MMCore 73、MMUI 17、MMFileScanner 117、MMCleaner 25、MMUninstaller 121、MMDisk 77、
MMMonitor 53、MMGuardian 96、MMOptimizer 54。结论行入库在
`docs/verification/p27-citations/run-all-tests.log`。
**这一格量的是"本构建"，不是仓库当前那一棵**：设置页修复之后同一支脚本现读 **641 / 0 / 1**
（MMCore 73→77、MMMonitor 53→57，其余七格逐字相同；日志 `docs/verification/p29-citations/run-all-tests.log`），
那 8 条判据对应的改动**不在这一版产物里**。

## 拿到源码的人怎么自证

```
git clone --no-local <本仓库> /tmp/mm-clone && cd /tmp/mm-clone
VERSION=1.0.0 BUILD=1 ./Scripts/make-app.sh          # 产物 build/MacMaster.app
./Scripts/package-app.sh                              # zip + dmg + SHA256SUMS，并当场验一遍
./Scripts/run-all-tests.sh                            # 期望：633 个测试，0 个失败，1 个跳过
./Scripts/p7-release-check.sh build/MacMaster.app /tmp/evidence   # 三张实机照片 + 签名/plist/Gatekeeper
```

产物 Info.plist 里有 `MMGitCommit` 与 `MMSourceDigest` 两把键：后者是「这次编译真正吃进去的那些文件的
内容指纹」，取证脚本会在拍照片之前当场比这一个数，不等就直接拒拍。所以「照片里的界面」和
「你手上这个二进制」是不是同一棵树，是可以查的，不用相信任何人说的话。
