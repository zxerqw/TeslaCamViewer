import Observation
import Foundation

@Observable
@MainActor
final class EventListViewModel {
    let library: LibraryStore
    init(library: LibraryStore) { self.library = library }

    func events(for type: EventType) -> [TeslaEvent] {
        switch type {
        case .saved:  return library.savedEvents
        case .sentry: return library.sentryEvents
        case .recent: return library.recentEvents
        }
    }
}
