import Dependencies

/// The one registry of system-wide shortcuts, shared by every feature.
private enum GlobalShortcutsKey: DependencyKey {
    static let liveValue = GlobalShortcuts()
}

extension DependencyValues {
    var globalShortcuts: GlobalShortcuts {
        get { self[GlobalShortcutsKey.self] }
        set { self[GlobalShortcutsKey.self] = newValue }
    }
}
