# P4 浅色档全站核对（fidelity-light-dark）

> 覆盖 9 屏 × 明暗两档。配套证据：`docs/verification/p4-light-dark/`（16 张实机图 + 2 张磁盘夹具图）。
> 单屏逐元素对照在 `fidelity-<模块>.md` 里，本文只管**跨屏共性问题**：色档、层次、对比度。

## 0. 结论先行

1. **此前所有"色档一致"的结论都是拿浅色稿比深色照片得出的**，从来没在同一档上对照过。
   本轮补了 `MM_APPEARANCE` 钩子（只改本进程 `NSApp.appearance`，不动用户系统设置），
   才第一次把 9 屏拍成浅色实机图。
2. 浅色档一量就露馅：**卡片面和页面面在同档里挤成一团**。概览卡实测 #E9E9E9（稿要 #FFFFFF），
   监控指标卡实测 #959595（稿要 #E4E4E4），底部操作栏 #959595（稿要 #F7F7F7）。
   根因是共享层把三个不同语义的面都接到了 AppKit 语义色上，而语义色的浅色档值并不等于稿里钉的那三个十六进制。
3. 修法是在 `MMColor` 里按 `tokens.css` 的明暗两档钉死三个面色（`cardSurface` / `recessedSurface` /
   `underPageSurface`），并把被误命名为 `cardBackground` 的那个令牌拆开——它其实一直是"次级面"，
   名字把 8 个模块带偏了。修后两档全部对上（见 §2）。
4. 深色档没有为了迁就浅色档而改动：修后深色实测值与此前已验收的截图一致（±2 内）。
5. 顺带修掉两个会让证据变假的工具问题：`p4-sweep.sh` 的尺寸钩子被覆盖（§4.1）、
   `make-app.sh` 签名失败静默退出（§4.2）。

## 1. 哪些数字是量出来的

- 取色：`swift Scripts/pixel-probe.swift <png> scan <x|y> <fixed> <from> [to]`（色带）与
  `<png> x,y ...`（定点）。截图一律 `screencapture -o -x -l<windowid>`，窗口 id 由
  `Scripts/window-ids.swift --pid <自己起的 pid>` 得到。**全程零合成点击。**
- 复现命令：
  ```zsh
  ./Scripts/make-app.sh -o /tmp/mmapp-p5 -s /tmp/mmscratch-p5
  ./Scripts/p4-sweep.sh /tmp/mmapp-p5/MacMaster.app /tmp/p4-final light
  ./Scripts/p4-sweep.sh /tmp/mmapp-p5/MacMaster.app /tmp/p4-final-dark dark
  ```
- **不要用 NSColor 在命令行里查语义色的值。** 本轮踩过：脱离真实绘制上下文解析动态色，
  `windowBackgroundColor` 在 Aqua 下报 #FFFFFF，实机渲染其实是 #E9E9E9；
  写进 `NSBitmapImageRep` + `performAsCurrentDrawingAppearance` 也一样。
  判断"卡片比页面亮还是暗"只能量截图本身——这条已写进 `pixel-probe.swift` 文件头。
- 误差：`screencapture` 对中性灰有 **±2…±5** 的系统性偏移（明档偏亮、暗档偏暗）。
  下文 Δ 超过这个区间的才算真差异。

## 2. 三个面的对照表（修前 → 修后）

采样点固定在 png 像素坐标（窗口内容区 2214×1762 @2x），两档同一坐标，布局一致才可比。

| 面 | 令牌 | tokens.css | 采样点 | 修前实测 | 修后实测（浅/深） | 判定 |
| --- | --- | --- | --- | --- | --- | --- |
| 卡片面 | `MMColor.cardSurface` | `--c-card-bg` #FFFFFF / #2A2A2A | `dashboard` 1100,250 | 浅 #E9E9E9(233) | **255 / 37** | 浅档对上；深档 37 vs 42 在噪声内 |
| 次级面 | `MMColor.recessedSurface` | `--c-card-bg-alt` #F7F7F7 / #232323 | `cleaner` 1100,1680（底部操作栏） | 浅 #959595(149) | **246 / 32** | 对上（247/35，噪声内） |
| 页面底 | `MMColor.underPageSurface` | `--c-under-page` #E4E4E4 / #161616 | `monitor` 1900,280（指标卡） | 浅 #959595(149) | **224 / 22** | 对上（228/22，噪声内） |
| 内容底 | `MMColor.contentBackground` | `--c-content-bg` #FFFFFF / #282828 | `dashboard` 1100,1400 | 未改 | **255 / 28** | 浅档对上；**深档 28 vs 40 是真差异**，见 §3.2 |
| 窗口底 | `MMColor.controlBackground` | `--c-window-bg` #ECECEC / #1E1E1E | `disk` 1100,1400（未扫描占位） | 未改 | **237 / 42** | 浅档对上；深档 42 vs 30 见 §3.2 |

逐屏修后实测（同一批截图，定点取色，单位 0-255 灰阶）：

| 屏 | 浅 1100,250 | 浅 1100,1400 | 浅 底部条 | 深 1100,250 | 深 1100,1400 | 深 底部条 |
| --- | --- | --- | --- | --- | --- | --- |
| dashboard | 255 | 255 | 246 | 37 | 28 | 32 |
| cleaner | 255 | 196* | 246 | 28 | 95* | 32 |
| uninstaller | 237* | 255 | 246 | 70* | 28 | 32 |
| disk（未扫描） | 237 | 237 | 237 | 42 | 42 | 42 |
| monitor | 224 | 237 | 224 | 22 | 42 | 22 |
| guardian | 255 | 237 | 246 | 37 | 42 | 32 |
| optimizer | 255 | 255 | 246 | 94* | 28 | 32 |

`*` 落在彩色风险条/进度条上，不是面色，不参与判定。
`disk` 这一轮没带 `MM_DISK_SCAN`，整屏是未扫描占位态，所以三处都是窗口底 237/42——
带夹具的那张另见 `light-disk-fixture.jpg`。

## 3. 差异归属

### 3.1 已修（实现该改）

- **三面钉档**：`MMDesign.swift` 新增 `surface(lightHex:darkHex:)`，用
  `NSColor(name: nil) { appearance in … }` 按 `.aqua/.darkAqua` 取两档十六进制。
  代价写在注释里：**增强对比度模式不再自动跟随**，真需要时在 `surface` 里补分支。
- **拆掉误导令牌**：`MMColor.cardBackground`（实为 `underPageBackgroundColor`）删除，
  20 处调用点按语义分流到 `recessedSurface`（MMCleaner 4 / MMDisk 4 / MMUninstaller 7 / MMGuardian 若干）。
  名字里带 "card" 却指向"沉底面"，是监控页整页灰卡的直接原因。
- **同一次改动里挡住一个回归**：隐私守护的卡改白后，卡内 `contentBackground`（也是白）的行会隐形，
  所以 LoginItemRow / DeviceUsageRow / TCCAuthorizationRow 三处行底同时换成 `recessedSurface`。
- **壳状态栏**：`MainWindow.swift` 状态栏由 `controlBackground` 换成 `recessedSurface`
  （稿 `.statusbar` = #F7F7F7，实测 246）。
- **磁盘扫描口径**：扫描层整目录跳过 `Library`/`.Trash` 等受保护项，页面上却看不出来。
  夹具 175 MB 只显示 77.8 MB，差的就是被跳过的 `Library/`（101 MB）。
  现在 `ScanOutput.skippedProtected` 把名单带出来，面包屑条挂一枚 `🔒 未纳入 N 个受保护目录` 徽标，
  hover 给出具体名字。判据：`DiskScannerHierarchyTests` 两条新用例。
  没有改扫描语义——删除安全另有 `DeletionGuard`/`DiskRemoval` 两道闸，这里要补的只是"没看"和"是空的"的区别。

### 3.2 记为已知偏差（本轮不改）

- **深色档的 `contentBackground`/`controlBackground` 与 tokens.css 不等**：
  28 vs 40、42 vs 30。这两个仍走 AppKit 语义色，是**故意的**：列表/表格底跟平台走，
  高对比度和"提高对比度"开关才能自动生效。要改的是稿——`--c-content-bg` 深色档该写"≈平台值"而不是钉死十六进制。
- **概览副标题会被中间截断**：`MMPageHeader` 的 subtitle 是 `lineLimit(1) + truncationMode(.middle)`，
  磁盘页头部右侧控件多（分段控件 + 筛选框 + 两个按钮），~1100pt 宽度下
  "N 个文件"这一项会被吃掉，保留的是路径头和"占用/用时"尾。
  这也是为什么受保护目录的披露放徽标而不是塞副标题——塞进去会把占用和用时一起挤没。
  归到 #55（最小窗口核对）一起处理。

## 4. 工具侧修的两处"假证据"

### 4.1 `p4-sweep.sh` 的尺寸钩子被覆盖

`extra=(MM_WINDOW_SIZE=…)` 后面又 `extra=(MM_APPEARANCE=…)`，第二次赋值把第一次清了，
于是"最小窗口"那轮其实只换了外观，照片上的窄窗是假的。改成 `extra+=(…)`，并加第 5 个参数只跑指定屏。

### 4.2 `make-app.sh` 签名失败静默退出

脚本 `set -e`，`codesign --force --deep` 失败时直接退出 1 且不打印，
而 SwiftPM 已经输出过 "Build complete!"，看上去像构建成功。
实测踩到的一次：`-o` 传成 `…/MacMaster.app`，里面套了一层同名 bundle，`--deep` 失败。
`-o` 要传**目录**。现在签名失败会把原始错误转到 stderr 并写明是哪个产物。

## 5. 没能验证到的部分

- **辅助功能档**：增强对比度 / 大字号 / 减少透明度都没截图。三个面钉死十六进制后，
  高对比度这一档**已知不会自动跟随**（§3.1 第一条），需要单独设计。
- **真实权限档**：`MM_DISK_SCAN` 只认 `/tmp`，所以完整用户目录（含 `~/Library` 真实内容）
  的扫描结果没有截图；受保护目录徽标在真机上会列出更多名字，宽度是否够没测。
- **摄像头/麦克风"正在使用"肯定分支**：仍只有否定与降级档。
- **磁盘夹具的深色档**：只拍了浅色（`light-disk-fixture.jpg`）。
- **多显示器 / 非 @2x 屏**：取色全部在这块 Retina 屏上，sRGB 值不能直接搬到非 P3 普通屏。

## 6. 提请协调者

1. `tokens.css` 深色档的 `--c-content-bg`/`--c-window-bg` 与平台语义色不一致（§3.2），
   要么改稿注明"近似值"，要么实现侧一并钉死——但钉死会牺牲高对比度跟随，需要产品决策。
2. `MMPageHeader` 副标题在窄窗/多控件页会被中间截断（§3.2）。若要保住"文件数"，
   建议给 header 右侧控件区设最小宽度并让副标题优先，属于共享层改动，影响 8 屏，等 #55 结论一起定。
3. 三个面现在有了唯一真源，**新代码不应再直接写 `contentBackground` 当卡底**；
   下一轮全站一致性检查可以把 `grep -n "background(MMColor.contentBackground)"` 作为入口。
