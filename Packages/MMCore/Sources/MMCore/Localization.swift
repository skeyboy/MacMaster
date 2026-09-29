import Foundation
import SwiftUI

public final class Localization: ObservableObject {
    public static let shared = Localization()

    public enum Language: String {
        case chinese = "zh-Hans"
        case english = "en"
    }

    @AppStorage("app.language") private var languageRaw: String = Language.chinese.rawValue

    public var currentLanguage: Language {
        get { Language(rawValue: languageRaw) ?? .chinese }
        set { languageRaw = newValue.rawValue }
    }

    private init() {}

    private var strings: [String: [String: String]] = [
        Language.chinese.rawValue: [
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
        ],
        Language.english.rawValue: [
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
        ],
    ]

    public func localized(_ key: String) -> String {
        let lang = currentLanguage.rawValue
        return strings[lang]?[key] ?? strings[Language.chinese.rawValue]?[key] ?? key
    }
}

public func L(_ key: String) -> String {
    Localization.shared.localized(key)
}
