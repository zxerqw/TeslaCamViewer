import SwiftUI
import UIKit

struct ExportSheetView: View {
    @Bindable var viewModel: ExportSheetViewModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                    if viewModel.hasTelemetry {
                        Section("叠加") {
                            Toggle("车速 / G 值写入视频", isOn: $viewModel.burnTelemetry)
                        }
                    }
                    if viewModel.isRunning {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("导出中… \(Int(viewModel.progress * 100))%")
                                ProgressView(value: viewModel.progress, total: 1.0)
                                    .progressViewStyle(.linear)
                            }
                        }
                    }
                    if !viewModel.resultURLs.isEmpty {
                        Section("完成") {
                            if viewModel.savedToLibrary {
                                Label("已保存到相册", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if viewModel.error == .photoLibraryDenied {
                                Label("保存到相册失败，请在设置中允许访问相册", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        }
                    }
                    if let err = viewModel.error, err != .photoLibraryDenied {
                        Section { Text(err.errorDescription ?? "导出失败").foregroundStyle(.red) }
                    }
                }

                // Bottom action button area
                VStack(spacing: 12) {
                    Divider()
                    bottomButton
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("导出")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭", action: onDismiss) }
            }
        }
    }

    @ViewBuilder
    private var bottomButton: some View {
        if !viewModel.resultURLs.isEmpty {
            // Export succeeded → share button
            Button {
                present(urls: viewModel.resultURLs)
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            // Not yet exported, or failed → export / retry button
            Button {
                Task { await viewModel.run() }
            } label: {
                Group {
                    if viewModel.isRunning {
                        Label("导出中…", systemImage: "arrow.triangle.2.circlepath")
                    } else if viewModel.error != nil {
                        Label("重新导出", systemImage: "arrow.clockwise")
                    } else {
                        Label("开始导出", systemImage: "square.and.arrow.down")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isRunning)
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
