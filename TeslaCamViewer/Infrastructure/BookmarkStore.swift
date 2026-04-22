import Foundation

public final class BookmarkStore: BookmarkStoreProtocol, @unchecked Sendable {
    private static let key = "TeslaCamViewer.FolderBookmark.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hasBookmark: Bool {
        defaults.data(forKey: Self.key) != nil
    }

    public func save(url: URL) throws {
        #if os(iOS)
        let data = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        defaults.set(data, forKey: Self.key)
    }

    public func resolve() throws -> URL {
        guard let data = defaults.data(forKey: Self.key) else { throw AppError.bookmarkStale }
        var stale = false
        let url: URL
        do {
            #if os(iOS)
            url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            #else
            url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            #endif
        } catch {
            throw AppError.bookmarkStale
        }
        if stale { throw AppError.bookmarkStale }
        return url
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
