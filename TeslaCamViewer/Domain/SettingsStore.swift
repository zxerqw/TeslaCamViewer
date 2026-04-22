import Foundation
import Observation

@Observable
public final class SettingsStore {
    private static let storageKey = "TeslaCamViewer.AppSettings.v1"
    private let defaults: UserDefaults

    public var settings: AppSettings {
        didSet {
            // Re-clamp in case the UI assigned an out-of-range value directly.
            let clamped = AppSettings(
                recentGapThresholdSeconds: settings.recentGapThresholdSeconds,
                defaultWatermarkPosition: settings.defaultWatermarkPosition
            )
            if clamped != settings {
                settings = clamped
                return   // didSet will run again; it'll hit the guard and persist there.
            }
            persist()
            version &+= 1
        }
    }

    /// Monotonically increasing counter bumped on every mutation, for
    /// consumers (e.g. `LibraryStore`) that want a cheap "something changed" trigger.
    public private(set) var version: Int = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
