import Dependencies
import Foundation

/// Where preferences are stored: UserDefaults in the app, a throwaway suite
/// in tests. UserDefaults is documented as thread-safe but not marked
/// Sendable, hence the wrapper.
private enum SettingsStorageKey: DependencyKey {
    static let liveValue = UncheckedSendable(UserDefaults.standard)
}

extension DependencyValues {
    var settingsStorage: UserDefaults {
        get { self[SettingsStorageKey.self].wrappedValue }
        set { self[SettingsStorageKey.self] = UncheckedSendable(newValue) }
    }
}
