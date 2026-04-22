import Foundation

@MainActor
final class AppDependencies {
    let settings: SettingsStore
    let bookmarks: BookmarkStoreProtocol
    let scanner: ScannerProtocol
    let library: LibraryStore
    let playback: PlaybackController
    let exportJob: ExportJob

    init() {
        self.settings = SettingsStore()
        self.bookmarks = BookmarkStore()
        self.scanner = TeslaCamScanner()
        self.library = LibraryStore(scanner: scanner, settings: settings)
        self.playback = PlaybackController(player: MultiAVPlayer())
        self.exportJob = ExportJob(composer: AVComposer())
    }
}
