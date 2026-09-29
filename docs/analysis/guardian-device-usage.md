# P3.1 调研：谁在用我的摄像头 / 麦克风（guardian-device-usage）

> 结论先行：**"是否正在被使用"有可信的无特权、进程内路径；"被哪个进程使用"没有。**
> 因此 UI 只渲染状态（含"无法确定"档），永远不编造进程名。本文所有"已验证"条目都在本机
> （Mac mini，macOS 27.0 beta / Build 26A428，**无摄像头、无音频输入设备**）实测过，
> 受硬件限制的分支在"本机验证矩阵"里写明验证到了哪一步。

## 1. 候选检测路径逐条评估

### 1.1 麦克风：CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`（✅ 采用）

- **API**：`AudioHardware.h` 公开常量 `kAudioDevicePropertyDeviceIsRunningSomewhere = 'gone'`，
  与 CoreMediaIO 头文件里 `kCMIODevicePropertyDeviceIsRunningSomewhere` 是同一个 FourCharCode（`'gone'`）。
  进程内 `AudioObjectGetPropertyData`，无子进程、无 TCC 弹窗、单次查询 <1ms。
- **官方语义**（SDK 头文件原文）："A UInt32 where 1 means that the AudioDevice is running in at
  least one process on the system and 0 means that it isn't running at all."
  —— 这正是"此刻有没有进程在驱动这个设备"，而且是**全系统视角**。
- **能拿到**：某个音频设备此刻是否被任一进程驱动（1/0），实时。
- **拿不到**：进程归属。HAL 内部有未公开的客户端 pid 列表属性，没有公开 API；
  公开的 `kAudioDevicePropertyHogMode` 只在**独占（non-mixable）**场景返回 pid，
  本机实测返回 -1（"available to all processes"），常规通话/录音场景恒为 -1，不用于归属。
- **⚠️ 关键坑（本机实测发现）**：`'gone'` 是**整设备**标志，**不区分 scope**。
  本机用 `afplay` 纯播放期间，对唯一的输出设备（Mac mini 扬声器）分别按
  global / input / output scope 读取，三个读数**同时翻 1**。
  这意味着对"麦克风+扬声器一体"的组合设备（外接显示器常带 Audio Loopback 输入），
  仅仅在放音乐就可能把"麦克风侧"读成 running。
  → 判定表里把"有输入通道的组合设备 gone=1"降级为**无法确定**，只把
  **纯输入设备**（内置麦克风、独立 USB 麦）的 gone=1 判为"正在被使用"。
- **输入设备判定**：设备是否算"麦克风"用 `kAudioDevicePropertyStreamConfiguration`（input scope）
  的通道数 >0 判定；`kAudioHardwarePropertyDefaultInputDevice` 为 0 表示系统没有默认输入设备。

### 1.2 摄像头：IOKit 注册表 AppleCamera 节点（❌ 弃用）

- 旧思路：`IOServiceGetMatchingService("AppleCamera…")` + 电源状态 / `ioreg` 解析，
  Intel 时代（2016–2019，OverSight 早期）可用。
- **本机实测**：`ioreg -c AppleCamera` 无匹配；全量 `ioreg -l` 里与 camera 相关的只有
  `SEPCameraDisable` 一个 SEP 键（且本机根本没有摄像头硬件）。
- **版本差异（社区共识 + 本机佐证）**：Apple Silicon 上视频通路换到 AVE/DCP（Apple AV Domain /
  Display Control Processor），不再有独立的 AppleCamera IOService 电源节点；这条路在
  M 系列上**结构性失效**，而且就算在 Intel 上也只能给出"摄像头是否上电"，给不出进程。
  → 放弃。它连"是/否"都不再可信，不存在保留价值。

### 1.3 摄像头：CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere`（✅ 采用）

- **API**：`CMIOHardwareDevice.h` 公开常量，同为 `'gone'`；用 `CMIOObjectGetPropertyData`
  读取。CMIO 系统对象枚举摄像头设备：`kCMIOHardwarePropertyDevices = 'dev#'`
  （`CMIOHardwareSystem.h`，只含视频/采集设备，与 CoreAudio 的 `'dev#'` 同 selector 值、不同系统对象）。
- **本机实测**：`CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject, 'dev#')` 调用成功
  （status 0，size 0——本机无摄像头，列表为空，与 AVCapture 枚举互相印证为 0）。
  **正分支（有摄像头时读 1）受硬件限制无法在本机验证**，此结论来自公开头文件语义 +
  OverSight 在 Apple Silicon 上也改用 CMIO `'gone'`  polling 的先例；实现里把它当作"读数可能失败"
  处理：读不到 ≠ 空闲，落到"无法确定"。
- **摄像头存在性**：用 `AVCaptureDevice.DiscoverySession(mediaType: .video)` 枚举。
  只枚举不建 session、不开采集，**不会触发 TCC 摄像头弹窗**（本机验证：枚举返回 0 个设备，
  无任何弹窗）。CMIO 列表与 AVCapture 列表交叉核对，两者不一致时判"无法确定"而不是"没有摄像头"。
- **拿不到**：进程归属（同 1.1，`'gone'` 不含 pid；摄像头也不走文件描述符，见 1.4）。

### 1.4 进程归属：`lsof` 子进程（❌ 弃用）

- **可行性实测**：`afplay` 播放期间 `lsof -nP` 全表扫描，占用音频的进程只出现在
  `txt`（映射了 CoreAudio.component 框架文件）与 `cwd` 条目里——**没有任何"设备占用"性质的
  fd**。CoreAudio/CMIO 的客户端-音频驱动路径走的是到 coreaudiod / CMIO 守护进程的 mach IPC，
  摄像头也不落在 `/dev`（没有 `/dev/video*` 这类节点）。`lsof` 结构上就看不到这件事，
  拿它筛 "CoreAudio.component" 只能列出"链接过音频框架的进程"（几乎每个 GUI 应用），全是噪声。
- **成本**：本机 0.16s（11,889 行输出）；系统繁忙/NFS 挂载多时到秒级。为一个**给不出答案**的
  信号付这个代价并常驻子进程，不值得。
- **结论**：进程归属走 `lsof` 被否决——不是慢，是**原理上不可达**。

### 1.5 进程归属：统一日志（`log show` / `log stream` TCC 事件）（❌ 弃用，留档）

- 思路（OverSight 的核心信号之一）：tccd/securityd 在应用做摄像头/麦克风**权限签入**时打日志，
  事件里带进程路径与 pid。
- **本机实测**：`log show --last 6h --info --debug --predicate 'process == "tccd" AND
  (eventMessage CONTAINS[c] "kTCCServiceCamera" OR …Microphone)'` 返回空；
  `subsystem == "com.apple.cmio"` 过滤 "running/start" 同样为空。
- 结构性缺陷：① 事件在**授权签入**时打，不在 IO 启停时打——一小时前的会议开始、现在的"是否在用"
  它答不了；② 敏感字段长期被 `<private>` 脱敏（社区反复抱怨的 OverSight 失效主因之一，
  macOS 版本更新一次日志形态变一次）；③ `log show` 每次子进程启动数百 ms–数秒，`log stream`
  要常驻一个子进程。对一个每次点"刷新"就要出结果的面板，这条路的延迟和失真都不可接受。
- **保留价值**：若以后做"过去 24 小时访问历史"（那是另一个问题），这是唯一来源，届时再评估。

### 1.6 其他核对过的路径（全部不采用）

- `AVCaptureDevice.isInUseByAnotherApplication`：头文件（AVCaptureDevice.h:323）标注
  `API_AVAILABLE(macCatalyst(14.0)) API_UNAVAILABLE(ios, …)`，macOS 上 Swift 侧不可直接调用，
  只能 KVC 碰运气，且对"另一进程"的定义与采集框架内部状态绑定，不如 `'gone'` 直给。
- 私有 SFAuthorization/ControlCenter 面板 API（控制中心那个橙色圆点背后的"哪个 app 在用"）：
  未公开、无 entitlement 不可达；这正是 MacMaster 不想赌的兼容性。
- 读 TCC.db（`kTCCServiceCamera` 的 `last_accessed` 列）：需要给 MacMaster 授 FDA，
  为做一个只读面板要求全盘权限，代价和收益不成比例，且 `last_accessed` 仍是签入时间语义。

## 2. 开源同类实现的对照

- **OverSight（Patrick Wardle，已停更/仓库下架）**：统一日志 TCC 事件（能报进程）+ 轮询音频/视频
  设备 running 状态。踩坑记录：macOS 把日志字段私有化后进程名大量丢失；Apple Silicon 视频栈更换
  后早期依赖 AppleCamera 注册表节点的思路全部失效；因逆向私有 API 引发法律争议而停止开发。
  —— 印证了本文两条决策：不依赖日志文本、不依赖 IOService 节点。
- **Micro Snitch（商业，闭源）**：菜单栏指示 + 历史。公开资料同样不做"精确到进程"的承诺口径
  （控制中心式提示依赖系统 UI）。
- 中文社区教程（php.cn 等）推荐的用户级答案是"打开系统设置看摄像头授权列表"——那是**授权列表**
  不是**当前占用**，回答了错误的问题；本面板副标题保留"打开系统设置"作为第二入口即可。

Sources:
- [OverSight – 阻止 macOS 应用偷偷录音录像（apprinn）](https://www.appinn.com/oversight-for-macos/?utm_medium=website&utm_source=gank.io/xiandu)
- [你知道你的Mac摄像头正在偷窥你吗（51CTO，OverSight 原理介绍）](https://www.51cto.com/article/518845.html)
- [Mac 恶意软件的艺术：日志监控（掘金）](https://juejin.cn/post/7533235582262345728)
- [我怎样才能知道相机是否被另一个过程所使用（腾讯云，旧 IOKit 思路讨论）](https://cloud.tencent.com/developer/ask/sof/113279447)
- [Apple 官方：控制 Mac 上相机的取用权限（授权列表 ≠ 当前占用）](https://support.apple.com/zh-cn/guide/mac-help/mchlf6d108da/12.0/mac/12.0)
- [AVCaptureDevice.h（inUseByAnotherApplication 的可用性标注）](https://github.com/theos/sdks/blob/master/iPhoneOS9.3.sdk/System/Library/Frameworks/AVFoundation.framework/Headers/AVCaptureDevice.h)

## 3. 本机验证矩阵（诚实口径）

| 分支 | 本机可验证性 | 结果 |
|---|---|---|
| `'gone'` 读取调用（麦克风侧） | ✅ | status=0，空闲时 value=0 |
| `'gone'` **正分支**（被别的进程驱动时翻 1） | ✅（用扬声器替代验证） | `afplay` 播放期间 global/input/output 三读数同时 1，停止后回 0 |
| `'gone'` 不分 scope（组合设备风险） | ✅ 实测发现 | 无输入通道的设备按 input scope 读也返回 1 |
| 无输入设备判定（`defaultInputDevice==0`） | ✅ | 本机 0 → "无可用麦克风"，是确定事实不是"无法确定" |
| CMIO `'dev#'` 枚举调用 | ✅ | status=0，本机 size=0（无摄像头） |
| 摄像头**存在且空闲/被占用**两个读数 | ❌ 本机无摄像头 | 依据公开头文件语义；实现上读失败一律"无法确定" |
| IOKit AppleCamera 节点 | ❌ 本机不存在（硬件+平台双重） | 弃用该路径的直接佐证 |
| `lsof` 给出占用进程 | ✅（验证了它给不出） | 播放期间无设备类 fd，仅 txt/cwd 噪声 |
| tccd 统一日志近期事件 | ✅（验证了本机 6h 内为空） | 弃用该路径的直接佐证 |
| AVCapture 枚举不触发弹窗 | ✅ | 0 设备，无弹窗 |

## 4. 最终选型

| 行 | 信号 | 状态集 |
|---|---|---|
| 麦克风 | CoreAudio：枚举设备 → 有输入通道的设备读 `'gone'` | 正在被使用（纯输入设备 1）/ 当前空闲（全部 0）/ 无法确定（组合设备歧义、读取失败）/ 无可用麦克风（无输入设备） |
| 摄像头 | CMIO `'dev#'` 枚举 + 读 `'gone'`；AVCapture 枚举做存在性交叉核对 | 同上（无"组合设备"歧义分支）；两个枚举器矛盾 → 无法确定 |
| 进程归属 | **不做**。`'gone'`/`lsof`/日志都给不出可信答案 | 使用中方永远显示"使用方无法确定" |

判定表（含降级规则）抽成纯函数放 `DeviceUsage.swift`，探针层（CoreAudio/CMIO/AVCapture 实际调用）
放 `DeviceUsageProbe.swift`，单测只打判定表与夹具解析，不假装覆盖原生调用。
