import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    let onReselectFolder: () -> Void

    var body: some View {
        Form {
            Section(header: Text("Recent 分块间隔"),
                    footer: Text("超过此间隔的分钟文件会被切为新事件。")) {
                HStack {
                    Text("\(settingsStore.settings.recentGapThresholdSeconds / 60) 分钟")
                        .monospacedDigit()
                    Slider(
                        value: Binding(
                            get: { Double(settingsStore.settings.recentGapThresholdSeconds) },
                            set: { settingsStore.settings.recentGapThresholdSeconds = Int($0) }
                        ),
                        in: Double(AppSettings.minRecentGapSeconds) ... Double(AppSettings.maxRecentGapSeconds),
                        step: 60
                    )
                }
            }
            Section("水印默认位置") {
                Picker("默认位置", selection: $settingsStore.settings.defaultWatermarkPosition) {
                    Text("左下").tag(ExportRequest.WatermarkPosition.bottomLeft)
                    Text("右下").tag(ExportRequest.WatermarkPosition.bottomRight)
                    Text("左上").tag(ExportRequest.WatermarkPosition.topLeft)
                    Text("右上").tag(ExportRequest.WatermarkPosition.topRight)
                }
            }
            Section("TeslaCam 文件夹") {
                Button("重新选择文件夹", role: .destructive, action: onReselectFolder)
            }
        }
        .navigationTitle("设置")
    }
}
