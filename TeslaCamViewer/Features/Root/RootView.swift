import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    let deps: AppDependencies

    @State private var scopedRoot: URL?
    @State private var isPickingFolder = false
    @State private var error: AppError?
    @State private var selected: TeslaEvent?
    @State private var gridVM: GridPlayerViewModel?
    @State private var exportVM: ExportSheetViewModel?
    @State private var showSettings = false
    @State private var showGridConfig = false

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "gear") }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView(settingsStore: deps.settings, onReselectFolder: reselectFolder)
                    }
                }
                .fileImporter(
                    isPresented: $isPickingFolder,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        Task { await onPickedFolder(url) }
                    }
                }
                .navigationDestination(item: $selected) { event in
                    gridScreen(event: event)
                }
        }
        .task { await bootstrap() }
    }

    @ViewBuilder
    private var content: some View {
        if let err = error {
            VStack {
                ErrorBanner(error: err)
                Button("选择 TeslaCam 文件夹") { isPickingFolder = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if scopedRoot == nil {
            VStack(spacing: 16) {
                Image(systemName: "externaldrive.badge.plus").font(.largeTitle)
                Text("请选择 TeslaCam 文件夹开始").font(.title3)
                Button("选择文件夹") { isPickingFolder = true }
                    .buttonStyle(.borderedProminent)
            }.padding()
        } else {
            let vm = EventListViewModel(library: deps.library)
            EventListView(viewModel: vm, onSelect: { selected = $0 })
                .navigationTitle("TeslaCam")
        }
    }

    @ViewBuilder
    private func gridScreen(event: TeslaEvent) -> some View {
        VStack {
            if let gvm = gridVM {
                GridPlayerView(viewModel: gvm, onExportTap: {
                    exportVM = ExportSheetViewModel(
                        event: event,
                        gridAngles: gvm.gridAngles,
                        trim: gvm.playback.trim,
                        defaultWatermark: gvm.watermarkPosition,
                        exportJob: deps.exportJob,
                        telemetry: gvm.telemetry
                    )
                })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showGridConfig = true } label: { Image(systemName: "square.grid.2x2") }
                    }
                }
                .sheet(isPresented: $showGridConfig) {
                    GridConfigSheet(
                        available: event.availableAngles,
                        current: Binding(get: { gvm.gridAngles }, set: { gvm.gridAngles = $0 }),
                        onDismiss: { showGridConfig = false }
                    )
                }
                .sheet(item: $exportVM) { evm in
                    ExportSheetView(viewModel: evm, onDismiss: { exportVM = nil })
                }
            } else {
                ProgressView().task {
                    gridVM = GridPlayerViewModel(
                        event: event,
                        playback: deps.playback,
                        defaultWatermark: deps.settings.settings.defaultWatermarkPosition
                    )
                }
            }
        }
    }

    // MARK: - actions

    private func bootstrap() async {
        guard deps.bookmarks.hasBookmark else { return }
        do {
            let url = try deps.bookmarks.resolve()
            await onPickedFolder(url, alreadyBookmarked: true)
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .bookmarkStale
        }
    }

    private func onPickedFolder(_ url: URL, alreadyBookmarked: Bool = false) async {
        _ = url.startAccessingSecurityScopedResource()
        do {
            if !alreadyBookmarked { try deps.bookmarks.save(url: url) }
            try await deps.library.load(root: url)
            scopedRoot = url
            error = nil
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .notTeslaCamFolder
        }
    }

    private func reselectFolder() {
        deps.bookmarks.clear()
        scopedRoot = nil
        showSettings = false
        isPickingFolder = true
    }
}
