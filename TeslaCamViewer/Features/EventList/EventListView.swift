import SwiftUI

struct EventListView: View {
    @Bindable var viewModel: EventListViewModel
    let onSelect: (TeslaEvent) -> Void

    @State private var selectedTab: EventType = .saved

    var body: some View {
        TabView(selection: $selectedTab) {
            tabContent(.saved)
                .tabItem { Label("主动保存", systemImage: "square.and.arrow.down") }
                .tag(EventType.saved)
            tabContent(.sentry)
                .tabItem { Label("哨兵", systemImage: "eye") }
                .tag(EventType.sentry)
            tabContent(.recent)
                .tabItem { Label("最近", systemImage: "clock") }
                .tag(EventType.recent)
        }
    }

    @ViewBuilder
    private func tabContent(_ type: EventType) -> some View {
        let events = viewModel.events(for: type)
        if events.isEmpty {
            ContentUnavailableView("暂无事件", systemImage: "tray", description: Text(emptyHint(type)))
        } else {
            List(events) { e in
                Button { onSelect(e) } label: { EventRowView(event: e) }
                    .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func emptyHint(_ t: EventType) -> String {
        switch t {
        case .saved:  return "按喇叭可主动保存片段。"
        case .sentry: return "哨兵模式触发的片段将出现在这里。"
        case .recent: return "行车时的滚动缓冲会显示在这里。"
        }
    }
}
