import Foundation
import Observation

@Observable
@MainActor
public final class LibraryStore {
    public private(set) var savedEvents: [TeslaEvent] = []
    public private(set) var sentryEvents: [TeslaEvent] = []
    public private(set) var recentEvents: [TeslaEvent] = []

    public private(set) var lastError: AppError?
    public private(set) var isLoading = false

    @ObservationIgnored private let scanner: ScannerProtocol
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var cachedRecentSegments: [MinuteSegment] = []
    @ObservationIgnored private var lastSettingsVersion: Int = -1
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    public init(scanner: ScannerProtocol, settings: SettingsStore) {
        self.scanner = scanner
        self.settings = settings
        startObservingSettings()
    }

    deinit { observationTask?.cancel() }

    public func load(root: URL) async throws {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await scanner.scan(root: root)
            savedEvents = result.savedEvents
            sentryEvents = result.sentryEvents
            cachedRecentSegments = result.recentSegments
            rechunkRecent()
        } catch let err as AppError {
            lastError = err
            throw err
        } catch {
            lastError = .eventCorrupted(id: "scan", underlying: error)
            throw error
        }
    }

    // MARK: - Settings reactivity

    private func startObservingSettings() {
        observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let currentVersion = self.settings.version
                if currentVersion != self.lastSettingsVersion {
                    self.lastSettingsVersion = currentVersion
                    self.rechunkRecent()
                }
                try? await Task.sleep(nanoseconds: 50_000_000)   // 50ms poll
            }
        }
    }

    private func rechunkRecent() {
        let chunks = RecentChunker.chunk(
            segments: cachedRecentSegments,
            gapThresholdSeconds: settings.settings.recentGapThresholdSeconds
        )
        recentEvents = chunks.map { segs -> TeslaEvent in
            let first = segs.first!
            let available = Set(segs.flatMap { $0.filesByAngle.keys })
            return TeslaEvent(
                id: "recent-\(ISO8601DateFormatter().string(from: first.timestamp))",
                type: .recent,
                startTime: first.timestamp,
                segments: segs,
                availableAngles: available,
                thumbnailURL: nil,
                eventMetadata: nil
            )
        }.sorted(by: { $0.startTime > $1.startTime })
    }
}
