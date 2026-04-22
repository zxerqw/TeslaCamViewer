import SwiftUI
import UIKit

struct ExportSheetView: View {
    @Bindable var viewModel: ExportSheetViewModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("布局") {
                    Picker("布局", selection: $viewModel.mode) {
                        ForEach(ExportSheetViewModel.Mode.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                }
                if viewModel.mode == .singles {
                    Section("选择视角") {
                        ForEach(CameraAngle.allCases, id: \.self) { a in
                            Toggle(label(a), isOn: Binding(
                                get: { viewModel.selectedAngles.contains(a) },
                                set: { on in
                                    if on { viewModel.selectedAngles.insert(a) }
                                    else  { viewModel.selectedAngles.remove(a) }
                                })
                            )
                            .disabled(!viewModel.event.availableAngles.contains(a))
                        }
                    }
                }
                Section("水印") {
                    Picker("位置", selection: $viewModel.watermarkPosition) {
                        Text("左下").tag(ExportRequest.WatermarkPosition.bottomLeft)
                        Text("右下").tag(ExportRequest.WatermarkPosition.bottomRight)
                        Text("左上").tag(ExportRequest.WatermarkPosition.topLeft)
                        Text("右上").tag(ExportRequest.WatermarkPosition.topRight)
                    }
                }
                if viewModel.isRunning {
                    ProgressView("导出中…")
                } else if !viewModel.resultURLs.isEmpty {
                    Section("完成") {
                        Text("已保存到相册（若有权限）。点击下方按钮再分享一次。")
                        Button("分享") { present(urls: viewModel.resultURLs) }
                    }
                }
                if let err = viewModel.error {
                    Section { Text(err.errorDescription ?? "导出失败").foregroundStyle(.red) }
                }
            }
            .navigationTitle("导出")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭", action: onDismiss) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始导出") { Task { await viewModel.run() } }
                        .disabled(viewModel.isRunning)
                }
            }
        }
    }

    private func label(_ a: CameraAngle) -> String {
        switch a {
        case .front:         return "前 Front"
        case .back:          return "后 Back"
        case .leftRepeater:  return "左后视镜"
        case .rightRepeater: return "右后视镜"
        case .leftPillar:    return "左 B 柱"
        case .rightPillar:   return "右 B 柱"
        }
    }

    @MainActor
    private func present(urls: [URL]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        var presenter = root
        while let p = presenter.presentedViewController { presenter = p }
        presenter.present(vc, animated: true)
    }
}
