import Foundation

public protocol BookmarkStoreProtocol {
    var hasBookmark: Bool { get }
    func save(url: URL) throws
    func resolve() throws -> URL
    func clear()
}
