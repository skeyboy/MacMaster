import Foundation

// MARK: - Module Descriptor

public struct ModuleDescriptor: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let iconName: String
    public let priority: Int
    public let viewBuilder: () -> AnyView

    public init(
        id: String,
        name: String,
        iconName: String,
        priority: Int = 100,
        viewBuilder: @escaping () -> AnyView
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.priority = priority
        self.viewBuilder = viewBuilder
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: ModuleDescriptor, rhs: ModuleDescriptor) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Module Registrable Protocol

public protocol ModuleRegistrable {
    var moduleID: String { get }
    var moduleName: String { get }
    var moduleIcon: String { get }
    var modulePriority: Int { get }
    func createView() -> AnyView
}

public extension ModuleRegistrable {
    var modulePriority: Int { 100 }

    func descriptor() -> ModuleDescriptor {
        ModuleDescriptor(
            id: moduleID,
            name: moduleName,
            iconName: moduleIcon,
            priority: modulePriority,
            viewBuilder: { createView() }
        )
    }
}

// MARK: - Module Registry

@MainActor
public final class ModuleRegistry: ObservableObject {
    public static let shared = ModuleRegistry()

    @Published public private(set) var modules: [ModuleDescriptor] = []

    private var registeredIDs: Set<String> = []

    private init() {}

    public func register(_ descriptor: ModuleDescriptor) {
        guard !registeredIDs.contains(descriptor.id) else {
            return
        }
        registeredIDs.insert(descriptor.id)
        modules.append(descriptor)
        modules.sort { $0.priority < $1.priority }
    }

    public func register(_ module: any ModuleRegistrable) {
        register(module.descriptor())
    }

    public func module(for id: String) -> ModuleDescriptor? {
        modules.first { $0.id == id }
    }

    public func unregister(_ id: String) {
        registeredIDs.remove(id)
        modules.removeAll { $0.id == id }
    }
}

// MARK: - AnyView Import

import SwiftUI

public typealias AnyView = SwiftUI.AnyView

// MARK: - App Preferences

public struct AppPreferences {
    public static let appGroupID = "group.com.macmaster.app"
    public static let bundleID = "com.macmaster.app"
}
