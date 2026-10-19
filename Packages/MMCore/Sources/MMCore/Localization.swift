import Foundation
import SwiftUI

// MARK: - 界面文案的多语言表
//
// P56 之前这张表是死的：`L(_:)` 在全站零调用点，设置页那个语言开关只能禁用并配一句实话
// （现读 `SettingsView.swift` 那段脚注）。本轮从壳层与概览页开始接消费者，
// 接进来的句子一律走 `L`/`LF`，没接的页面还是中文——所以现在是"按页推进"，
// 缺口与推进顺序记在 `docs/analysis/localization-coverage.md`。
public final class Localization: ObservableObject {
    public static let shared = Localization()

    public enum Language: String, CaseIterable, Sendable {
        case chinese = "zh-Hans"
        case english = "en"
    }

    /// 存进 UserDefaults 的那把 key。P56 起不再用 `@AppStorage`：
    /// 那个包装器是给 View 用的动态属性，放在 `ObservableObject` 里既不发布变化，
    /// 视图也就永远不会因为切语言而重画——开关拨了画面不动，正是那张表当初死掉的原因。
    private static let storageKey = "app.language"

    public var currentLanguage: Language {
        get { Language(rawValue: UserDefaults.standard.string(forKey: Self.storageKey) ?? "") ?? .chinese }
        set {
            guard newValue != currentLanguage else { return }
            objectWillChange.send()
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.storageKey)
        }
    }

    /// `MM_LANGUAGE` 覆盖启动档：取证脚本要拍双语，而原生界面的切换只能靠点击，
    /// 这一条路径上不允许合成点击，所以做成启动钩子（解析与留痕见 `MMLaunchHook`）。
    /// 覆盖是**写回 UserDefaults** 的：只在本进程生效一次的设想会让每一屏都得带同一个变量，
    /// 而拍到第 6 张照片时忘了带，那一张就悄悄回到中文档——这是钩子留痕门禁要防的那类假通过。
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let resolution = MMLaunchHook.resolveLanguage(raw: environment["MM_LANGUAGE"])
        if let rejected = resolution.rejected {
            MMHookValue.emit("MM_LANGUAGE 含非法取值（\(rejected)），只接受 zh|zh-hans|en，已沿用当前档位")
        }
        if let language = resolution.selected {
            // 留痕在被采纳这一支也要打：双语取证的机械判据是照片旁那一行日志，
            // 只有非法值才吭声的话，"这张到底是哪一档"就只剩人眼读像素。
            MMHookValue.emit(Self.appliedNote(language))
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    /// 采纳档的留痕文案。单独一个函数是为了能被单测**逐字**断言：
    /// P6.7 查过的那一族假通过是 `\(rawValue)` 写成 `\(rawValue` ——stderr 上仍有一行"已生效"，
    /// 但那一行说不出用的是哪一档，于是判据和没有这一行等价。
    static func appliedNote(_ language: Language) -> String {
        "MM_LANGUAGE=\(language.rawValue) 已生效：界面按这一档取文案（已写入 UserDefaults 的 \(storageKey)）"
    }

    public var locale: Locale {
        currentLanguage == .english ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
    }

    public func localized(_ key: String) -> String {
        let table = currentLanguage == .english ? Self.english : Self.chinese
        return table[key] ?? Self.chinese[key] ?? key
    }

    /// 带参文案走这一条：语序在两种语言里不一样，所以句子整条进表，不在调用处拼接。
    ///
    /// 表里的占位符一律 `%@`，调用方传**字符串**（数字先过 `MMFormat.count`）。
    /// 这不是风格问题：`%@` 拿到 Swift `Int` 会按对象去解一个整数寄存器，
    /// 现场是崩溃或一坨指针，而它只在文案切到那一条时才走到——单测最容易被漏掉的一类。
    public func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), arguments)
    }

    /// 表里没有这个 key 时回落调用方给的原话，而不是把 key 印到屏幕上。
    /// 用于"数据层带来的名字"这类没法穷举的文案（卷名、分类名）。
    public func localized(_ key: String, or fallback: String) -> String {
        let value = localized(key)
        return value == key ? fallback : value
    }

    // MARK: 中文

    static let chinese: [String: String] = [
        // App
        "app.name": "MacMaster",
        "app.tagline": "您的 Mac 优化专家",

        // Modules
        "module.cleaner": "系统清理",
        "module.uninstaller": "应用卸载",
        "module.disk": "磁盘分析",
        "module.monitor": "系统监控",
        "module.guardian": "隐私守护",
        "module.optimizer": "系统优化",

        // Common actions
        "action.scan": "扫描",
        "action.clean": "立即清理",
        "action.undo": "撤回",
        "action.refresh": "刷新",
        "action.cancel": "取消",
        "action.confirm": "确认",
        "action.delete": "删除",
        "action.optimize": "优化",

        // Cleaner
        "cleaner.title": "系统清理",
        "cleaner.subtitle": "扫描系统缓存、日志、临时文件等可安全清理的垃圾文件",
        "cleaner.scanning": "正在扫描系统文件...",
        "cleaner.empty": "点击「扫描」开始分析系统垃圾文件",
        "cleaner.rescan": "重新扫描",
        "cleaner.cleanable": "可清理",

        // Uninstaller
        "uninstaller.title": "应用卸载",
        "uninstaller.subtitle": "完全卸载应用及其残留文件",
        "uninstaller.scanning": "正在扫描已安装应用...",
        "uninstaller.residuals": "个残留文件",
        "uninstaller.uninstall": "卸载",

        // Disk
        "disk.title": "磁盘分析",
        "disk.subtitle": "分析磁盘空间使用情况",
        "disk.treemap": "Treemap",
        "disk.largeFiles": "大文件",
        "disk.used": "已用",
        "disk.free": "可用",

        // Monitor
        "monitor.title": "系统监控",
        "monitor.subtitle": "实时监控系统资源使用情况",
        "monitor.cpu": "CPU",
        "monitor.memory": "内存",
        "monitor.disk": "磁盘",
        "monitor.network": "网络",
        "monitor.processes": "进程",
        "monitor.menuBar": "菜单栏监控",

        // Guardian
        "guardian.title": "隐私守护",
        "guardian.subtitle": "管理登录项，监控系统活动",
        "guardian.loginItems": "登录项",
        "guardian.activity": "系统活动",
        "guardian.permissions": "应用权限",

        // Optimizer
        "optimizer.title": "系统优化",
        "optimizer.subtitle": "重复文件检测、浏览器清理、系统优化",
        "optimizer.tools": "系统优化",
        "optimizer.duplicates": "重复文件",
        "optimizer.browser": "浏览器清理",
        "optimizer.scanDuplicates": "扫描重复文件",
        "optimizer.duplicateGroups": "组重复文件",
        "optimizer.wasted": "可节省",

        // Settings
        "settings.title": "设置",
        "settings.general": "通用",
        "settings.language": "语言",
        "settings.monitor": "监控",
        "settings.cleaner": "清理",
        "settings.about": "关于",

        // Status
        "status.safe": "安全",
        "status.warning": "警告",
        "status.danger": "危险",
        "status.normal": "正常",
        "status.optimized": "已优化",
        "status.needsOptimization": "需优化",

        // P56：壳层（侧边栏 + 概览页）
        "nav.dashboard": "概览",
        "sidebar.modules": "功能模块",
        "sidebar.settings": "设置",
        "sidebar.volume.unavailable": "未能读取启动卷容量",

        "format.measuring": "测量中",
        "format.bytes": "%@ 字节",
        "format.justNow": "刚刚",

        "risk.safe": "安全",
        "risk.caution": "谨慎",
        "risk.readOnly": "只读",

        // P56：分类名来自 CacheScanner 的中文原话（id 全集见该文件里的类别清单）。
        // 概览页「可释放空间」按大小取前三，所以这些名字是壳层会显示的——
        // 新类别忘记补键时 L(key, or:) 回落中文原话，界面不会缺字，只是那一格没切。
        "category.system_cache": "系统缓存",
        "category.thumbnail_cache": "缩略图与预览缓存",
        "category.trash": "废纸篓",
        "category.var_metal_cache": "GPU 与 Metal 着色器缓存",
        "category.var_icon_preview_cache": "QuickLook 与图标服务缓存",
        "category.var_geo_cache": "地图瓦片缓存",
        "category.var_photo_analysis_cache": "照片分析与视觉搜索缓存",
        "category.logs": "应用日志",
        "category.crash_reports": "崩溃与诊断报告",
        "category.temp_files": "临时文件",
        "category.browser_cache": "浏览器缓存",
        "category.dev_cache": "开发工具缓存",
        "category.sandbox_container_cache": "沙盒容器缓存",
        "category.mail_cache": "邮件缓存",
        "category.privileged_cache": "系统级缓存（需管理员权限）",
        "category.system_logs": "系统日志",

        "storage.used": "已用",
        "storage.available": "可用",
        "storage.reclaimable": "可清理",
        "storage.trash": "废纸篓",
        "storage.otherUsed": "其他已用",
        "memory.active": "前台",
        "memory.wired": "联动",
        "memory.compressed": "压缩",
        "memory.free": "未占用",

        "dashboard.card.storage": "存储",
        "dashboard.card.load": "系统负载",
        "dashboard.card.reclaimable": "可释放空间",
        "dashboard.card.recent": "最近操作",
        "dashboard.header.remeasure": "重新测量",
        "dashboard.header.sampling": "正在读取系统状态…",
        "dashboard.header.subtitle": "上次采样 %@ · CPU/内存/磁盘均为本机实时读数",

        "dashboard.status.volumes": "%@ 个卷",
        "dashboard.status.volumesUnknown": "%@ 个卷",
        "dashboard.status.volumesHelp": "未能读取卷列表，这里不猜数字",
        "dashboard.status.filesystem": "文件系统 %@",
        "dashboard.status.lastCleanup": "上次清理 %@",
        "dashboard.status.noCleanup": "尚无清理记录",
        "dashboard.status.updatedAt": "数据更新于 %@",

        "dashboard.storage.lowSpace": "可用空间偏低",
        "dashboard.storage.availableOf": "%1$@ 可用 · 共 %2$@",
        "dashboard.storage.availableUnknown": "%@ 可用",
        "dashboard.storage.usedPercent": "%1$@ · 已用 %2$@",
        "dashboard.storage.noVolume": "未能读取启动卷容量（volumeTotalCapacity / 重要用途可用容量均未返回），这里不猜数字。",
        "dashboard.storage.diskRank": "查看占用排行",
        "dashboard.storage.releasable": "可立即释放",
        "dashboard.storage.releasableDetail": "（可清理 %1$@ + 废纸篓 %2$@）",
        "dashboard.storage.releasableTrashUnknown": "（可清理 %@ · 废纸篓未读到）",
        "dashboard.storage.goScan": "去扫描",
        "dashboard.storage.cleanNow": "清理 %@",

        "dashboard.load.verdictCalm": "运行平稳",
        "dashboard.load.verdictBusy": "负载偏高",
        "dashboard.load.memory": "内存",
        "dashboard.load.network": "网络",
        "dashboard.load.cpuHelp": "口径：host_statistics 两次采样差分，跨所有核的总占用率（非每核）；首次差分出结果前显示 —。",
        "dashboard.load.memoryHelp": "口径：(active + wired + compressed) × pageSize，不含可即时回收的 inactive。",
        "dashboard.load.cpuCaliber": "总占用 · %@ 核",
        "dashboard.load.cpuCores": "%1$@ 性能 + %2$@ 能效",
        "dashboard.load.cpuCoresUnknown": "跨所有核总占用",
        "dashboard.load.memoryComposition": "内存构成",
        "dashboard.load.memoryCompositionHidden": "三项没读全就不画构成：缺的那段并进“未占用”会画出一条骗人的绿条。",
        "dashboard.load.swapUnknown": "交换空间 %@",
        "dashboard.load.swapZero": "交换空间 0 字节",
        "dashboard.load.swap": "交换 %1$@ / %2$@",
        "dashboard.load.diskIO": "磁盘 I/O",
        "dashboard.load.read": "读 %@/s",
        "dashboard.load.write": "写 %@/s",
        "dashboard.load.allPhysical": "%@ · 全部物理接口",
        "dashboard.load.upload": "上传 %@",
        "dashboard.load.allDiskDrivers": "%@ · 全部磁盘驱动",
        "dashboard.load.writeAwaitingDiff": "写 %@ · 等待差分",
        "dashboard.load.writeNoStats": "写 %@ · IOKit 未返回统计",
        "dashboard.load.diskIOHelp": "口径：IOKit IOBlockStorageDriver 累计字节两次采样差分，含全部磁盘驱动。",

        "dashboard.reclaim.all": "全部",
        "dashboard.reclaim.itemsRisk": "%1$@ 项 · %2$@",
        "dashboard.reclaim.trash": "废纸篓",
        "dashboard.reclaim.trashSubtitle": "移入后可撤回",
        "dashboard.reclaim.notMeasured": "未扫描 · 去清理",
        "dashboard.reclaim.measuring": "扫描中…",
        "dashboard.reclaim.noCategorySelected": "未勾选类别",
        "dashboard.reclaim.failed": "测量失败（%@）",
        "dashboard.reclaim.detailNotMeasured": "数字来自真实扫描，扫描前不预估。",
        "dashboard.reclaim.detailMeasuring": "正在统计各类缓存、日志与临时文件…",
        "dashboard.reclaim.detailNoCategory": "清理页四个类别都关着，这一轮没东西可扫；勾上任一个再点「重新测量」。",
        "dashboard.reclaim.detailMeasured": "来自 %@ 个分类的真实扫描求和",
        "dashboard.reclaim.scanNoResult": "扫描没有返回结果",

        "dashboard.recent.hint": "只有移入废纸篓的动作可以撤回",
        "dashboard.recent.empty": "还没有清理记录。",
        "dashboard.recent.startCleaning": "开始清理",
        "dashboard.recent.rowTitle": "移入废纸篓 %@",
        "dashboard.recent.undo": "撤回",
        "dashboard.recent.badge.undone": "已撤回",
        "dashboard.recent.badge.volumeDetached": "盘已取下",
        "dashboard.recent.badge.volumeDetachedHelp": "落点所在那块卷已不在当前挂载集合里（比对删除当时记下的卷 UUID）：文件还在那块盘上，只是这台机器现在够不着它，没有人倒过垃圾。",
        "dashboard.recent.badge.trashEmptied": "废纸篓已清空",
        "dashboard.recent.badge.unknown": "无法撤回",
        "dashboard.recent.subtitle": "%1$@ · %2$@ 项",
        "dashboard.recent.subtitleWithFailures": "%1$@ · %2$@ 项 · %3$@ 项失败",
        "dashboard.undo.panelSummary": "撤回未完成，文件仍在废纸篓",

        // P56：MMUI 的共享组件——失败面板在概览页也会出现，页面切了英文而它没切就是半英半中。
        "panel.failuresCount": "%@ 项失败",
        "panel.dismiss": "忽略",
        "panel.moreFailures": "另有 %@ 项失败",
        "panel.copyDiagnostics": "复制诊断信息",
        "panel.retryFailed": "重试失败项",
        "panel.statPlanned": "计划",
        "panel.statSucceeded": "成功",
        "panel.statFailed": "失败",
        "panel.statSkipped": "跳过",
    ]

    // MARK: 英文

    static let english: [String: String] = [
        // App
        "app.name": "MacMaster",
        "app.tagline": "Your Mac Optimization Expert",

        // Modules
        "module.cleaner": "System Cleaner",
        "module.uninstaller": "Uninstaller",
        "module.disk": "Disk Analyzer",
        "module.monitor": "System Monitor",
        "module.guardian": "Privacy Guardian",
        "module.optimizer": "Optimizer",

        // Common actions
        "action.scan": "Scan",
        "action.clean": "Clean Now",
        "action.undo": "Undo",
        "action.refresh": "Refresh",
        "action.cancel": "Cancel",
        "action.confirm": "Confirm",
        "action.delete": "Delete",
        "action.optimize": "Optimize",

        // Cleaner
        "cleaner.title": "System Cleaner",
        "cleaner.subtitle": "Scan system caches, logs, and temporary files",
        "cleaner.scanning": "Scanning system files...",
        "cleaner.empty": "Click 'Scan' to analyze junk files",
        "cleaner.rescan": "Rescan",
        "cleaner.cleanable": "Cleanable",

        // Uninstaller
        "uninstaller.title": "Uninstaller",
        "uninstaller.subtitle": "Completely uninstall apps and their residuals",
        "uninstaller.scanning": "Scanning installed apps...",
        "uninstaller.residuals": "residual files",
        "uninstaller.uninstall": "Uninstall",

        // Disk
        "disk.title": "Disk Analyzer",
        "disk.subtitle": "Analyze disk space usage",
        "disk.treemap": "Treemap",
        "disk.largeFiles": "Large Files",
        "disk.used": "Used",
        "disk.free": "Free",

        // Monitor
        "monitor.title": "System Monitor",
        "monitor.subtitle": "Real-time system resource monitoring",
        "monitor.cpu": "CPU",
        "monitor.memory": "Memory",
        "monitor.disk": "Disk",
        "monitor.network": "Network",
        "monitor.processes": "Processes",
        "monitor.menuBar": "Menu Bar Monitor",

        // Guardian
        "guardian.title": "Privacy Guardian",
        "guardian.subtitle": "Manage login items and monitor system activity",
        "guardian.loginItems": "Login Items",
        "guardian.activity": "System Activity",
        "guardian.permissions": "App Permissions",

        // Optimizer
        "optimizer.title": "Optimizer",
        "optimizer.subtitle": "Duplicate detection, browser cleanup, system optimization",
        "optimizer.tools": "System Tools",
        "optimizer.duplicates": "Duplicates",
        "optimizer.browser": "Browser Cleanup",
        "optimizer.scanDuplicates": "Scan Duplicates",
        "optimizer.duplicateGroups": "duplicate groups",
        "optimizer.wasted": "wasted",

        // Settings
        "settings.title": "Settings",
        "settings.general": "General",
        "settings.language": "Language",
        "settings.monitor": "Monitor",
        "settings.cleaner": "Cleaner",
        "settings.about": "About",

        // Status
        "status.safe": "Safe",
        "status.warning": "Warning",
        "status.danger": "Danger",
        "status.normal": "Normal",
        "status.optimized": "Optimized",
        "status.needsOptimization": "Needs Optimization",

        // P56: shell (sidebar + dashboard)
        "nav.dashboard": "Overview",
        "sidebar.modules": "Modules",
        "sidebar.settings": "Settings",
        "sidebar.volume.unavailable": "Startup volume capacity unavailable",

        "format.measuring": "Measuring",
        "format.bytes": "%@ bytes",
        "format.justNow": "just now",

        "risk.safe": "Safe",
        "risk.caution": "Caution",
        "risk.readOnly": "Read-only",

        "category.system_cache": "System Caches",
        "category.thumbnail_cache": "Thumbnail & Preview Caches",
        "category.trash": "Trash",
        "category.var_metal_cache": "GPU & Metal Shader Caches",
        "category.var_icon_preview_cache": "QuickLook & Icon Service Caches",
        "category.var_geo_cache": "Map Tile Caches",
        "category.var_photo_analysis_cache": "Photo Analysis & Visual Search Caches",
        "category.logs": "App Logs",
        "category.crash_reports": "Crash & Diagnostic Reports",
        "category.temp_files": "Temporary Files",
        "category.browser_cache": "Browser Caches",
        "category.dev_cache": "Developer Tool Caches",
        "category.sandbox_container_cache": "Sandbox Container Caches",
        "category.mail_cache": "Mail Cache",
        "category.privileged_cache": "System-Level Caches (Requires Admin)",
        "category.system_logs": "System Logs",

        "storage.used": "Used",
        "storage.available": "Free",
        "storage.reclaimable": "Cleanable",
        "storage.trash": "Trash",
        "storage.otherUsed": "Other used",
        "memory.active": "Active",
        "memory.wired": "Wired",
        "memory.compressed": "Compressed",
        "memory.free": "Unused",

        "dashboard.card.storage": "Storage",
        "dashboard.card.load": "System Load",
        "dashboard.card.reclaimable": "Reclaimable Space",
        "dashboard.card.recent": "Recent Activity",
        "dashboard.header.remeasure": "Remeasure",
        "dashboard.header.sampling": "Reading system state…",
        "dashboard.header.subtitle": "Last sample %@ · CPU, memory and disk are live readings",

        "dashboard.status.volumes": "%@ volumes",
        "dashboard.status.volumesUnknown": "%@ volumes",
        "dashboard.status.volumesHelp": "Volume list unavailable — no guessing",
        "dashboard.status.filesystem": "File system %@",
        "dashboard.status.lastCleanup": "Last cleanup %@",
        "dashboard.status.noCleanup": "No cleanup yet",
        "dashboard.status.updatedAt": "Updated %@",

        "dashboard.storage.lowSpace": "Low free space",
        "dashboard.storage.availableOf": "%1$@ free of %2$@",
        "dashboard.storage.availableUnknown": "%@ free",
        "dashboard.storage.usedPercent": "%1$@ · %2$@ used",
        "dashboard.storage.noVolume": "Startup volume capacity unavailable (neither volumeTotalCapacity nor important-usage free space returned); no guessing here.",
        "dashboard.storage.diskRank": "Usage Ranking",
        "dashboard.storage.releasable": "Releasable now",
        "dashboard.storage.releasableDetail": "(cleanable %1$@ + trash %2$@)",
        "dashboard.storage.releasableTrashUnknown": "(cleanable %@ · trash unreadable)",
        "dashboard.storage.goScan": "Scan",
        "dashboard.storage.cleanNow": "Clean %@",

        "dashboard.load.verdictCalm": "Steady",
        "dashboard.load.verdictBusy": "Busy",
        "dashboard.load.memory": "Memory",
        "dashboard.load.network": "Network",
        "dashboard.load.cpuHelp": "Method: host_statistics sampled twice, total utilization across all cores (not per core); shows — before the first diff.",
        "dashboard.load.memoryHelp": "Method: (active + wired + compressed) × pageSize, excluding instantly reclaimable inactive memory.",
        "dashboard.load.cpuCaliber": "Total · %@ cores",
        "dashboard.load.cpuCores": "%1$@ performance + %2$@ efficiency",
        "dashboard.load.cpuCoresUnknown": "Total across all cores",
        "dashboard.load.memoryComposition": "Memory breakdown",
        "dashboard.load.memoryCompositionHidden": "Shown only when all three parts were read: folding a missing part into “Unused” would draw a green bar that lies.",
        "dashboard.load.swapUnknown": "Swap %@",
        "dashboard.load.swapZero": "Swap 0 bytes",
        "dashboard.load.swap": "Swap %1$@ / %2$@",
        "dashboard.load.diskIO": "Disk I/O",
        "dashboard.load.read": "Read %@/s",
        "dashboard.load.write": "Write %@/s",
        "dashboard.load.allPhysical": "%@ · all physical interfaces",
        "dashboard.load.upload": "Up %@",
        "dashboard.load.allDiskDrivers": "%@ · all disk drivers",
        "dashboard.load.writeAwaitingDiff": "Write %@ · awaiting diff",
        "dashboard.load.writeNoStats": "Write %@ · IOKit returned no statistics",
        "dashboard.load.diskIOHelp": "Method: IOKit IOBlockStorageDriver cumulative bytes, sampled twice, across all disk drivers.",

        "dashboard.reclaim.all": "All",
        "dashboard.reclaim.itemsRisk": "%1$@ items · %2$@",
        "dashboard.reclaim.trash": "Trash",
        "dashboard.reclaim.trashSubtitle": "Undoable after moving",
        "dashboard.reclaim.notMeasured": "Not scanned · Clean up",
        "dashboard.reclaim.measuring": "Scanning…",
        "dashboard.reclaim.noCategorySelected": "No category selected",
        "dashboard.reclaim.failed": "Measurement failed (%@)",
        "dashboard.reclaim.detailNotMeasured": "The number comes from a real scan; nothing is estimated beforehand.",
        "dashboard.reclaim.detailMeasuring": "Counting caches, logs and temporary files…",
        "dashboard.reclaim.detailNoCategory": "All four categories on the Cleaner page are off, so there was nothing to scan. Turn one on and press “Remeasure”.",
        "dashboard.reclaim.detailMeasured": "Sum of real scans across %@ categories",
        "dashboard.reclaim.scanNoResult": "The scan returned no result",

        "dashboard.recent.hint": "Only actions moved to the Trash can be undone",
        "dashboard.recent.empty": "No cleanup records yet.",
        "dashboard.recent.startCleaning": "Start Cleaning",
        "dashboard.recent.rowTitle": "Moved to Trash %@",
        "dashboard.recent.undo": "Undo",
        "dashboard.recent.badge.undone": "Undone",
        "dashboard.recent.badge.volumeDetached": "Disk Removed",
        "dashboard.recent.badge.volumeDetachedHelp": "The volume that holds the landing point is no longer mounted (compared against the volume UUID recorded at deletion). The files are still on that disk — nothing was able to reach it, and nobody emptied Trash.",
        "dashboard.recent.badge.trashEmptied": "Trash Emptied",
        "dashboard.recent.badge.unknown": "Can’t Undo",
        "dashboard.recent.subtitle": "%1$@ · %2$@ items",
        "dashboard.recent.subtitleWithFailures": "%1$@ · %2$@ items · %3$@ failed",
        "dashboard.undo.panelSummary": "Undo incomplete — files are still in Trash",

        "panel.failuresCount": "%@ failed",
        "panel.dismiss": "Dismiss",
        "panel.moreFailures": "%@ more failures",
        "panel.copyDiagnostics": "Copy Diagnostics",
        "panel.retryFailed": "Retry Failed Items",
        "panel.statPlanned": "Planned",
        "panel.statSucceeded": "Succeeded",
        "panel.statFailed": "Failed",
        "panel.statSkipped": "Skipped",
    ]
}

public func L(_ key: String) -> String {
    Localization.shared.localized(key)
}

/// 整句带参：语序由表里的格式串决定，不在视图里拼接。
public func LF(_ key: String, _ arguments: CVarArg...) -> String {
    Localization.shared.formatted(key, arguments)
}

/// 表里没有就退回调用方给的原话（用于数据层带来的名字）。
public func L(_ key: String, or fallback: String) -> String {
    Localization.shared.localized(key, or: fallback)
}
