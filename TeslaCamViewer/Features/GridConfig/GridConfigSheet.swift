import SwiftUI

struct GridConfigSheet: View {
    let available: Set<CameraAngle>
    @Binding var current: [CameraAngle]
    let onDismiss: () -> Void

    private let allAngles = CameraAngle.allCases

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<current.count, id: \.self) { idx in
                    Section(header: Text("格 \(idx + 1)")) {
                        ForEach(allAngles, id: \.self) { angle in
                            HStack {
                                Text(label(angle))
                                    .foregroundStyle(available.contains(angle) ? .primary : .secondary)
                                Spacer()
                                if current.indices.contains(idx), current[idx] == angle {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard current.indices.contains(idx) else { return }
                                current[idx] = angle
                            }
                        }
                    }
                }
            }
            .navigationTitle("网格配置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: onDismiss) } }
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
}
