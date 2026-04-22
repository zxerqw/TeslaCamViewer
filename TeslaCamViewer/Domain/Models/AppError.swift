import Foundation

public enum AppError: LocalizedError, Equatable {
    case notTeslaCamFolder
    case bookmarkStale
    case photoLibraryDenied
    case diskSpaceInsufficient(neededBytes: Int64, availableBytes: Int64)
    case eventCorrupted(id: String, underlying: Error)
    case exportFailed(underlying: Error)
    case memoryPressure

    public var errorDescription: String? {
        switch self {
        case .notTeslaCamFolder:
            return "在选中的文件夹里没找到 TeslaCam 结构（RecentClips / SavedClips / SentryClips）。请重新选择 U 盘根目录或 TeslaCam 文件夹。"
        case .bookmarkStale:
            return "上次选中的文件夹已不可用，请重新选择 TeslaCam 文件夹。"
        case .photoLibraryDenied:
            return "相册权限未授予。导出文件将仅通过分享面板保存。"
        case .diskSpaceInsufficient(let need, let have):
            let gbNeed = Double(need) / 1_000_000_000
            let gbHave = Double(have) / 1_000_000_000
            return String(format: "磁盘空间不足：需要约 %.1f GB，可用 %.1f GB。", gbNeed, gbHave)
        case .eventCorrupted(let id, let err):
            return "事件 \(id) 已损坏，已跳过：\(err.localizedDescription)"
        case .exportFailed(let err):
            return "导出失败：\(err.localizedDescription)"
        case .memoryPressure:
            return "内存不足，已暂停播放。"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notTeslaCamFolder, .bookmarkStale:
            return "点击下方按钮重新选择 TeslaCam 文件夹。"
        case .photoLibraryDenied:
            return "前往「设置 → 隐私 → 照片」授予 TeslaCamViewer 访问权限。"
        default:
            return nil
        }
    }

    public static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.notTeslaCamFolder, .notTeslaCamFolder),
             (.bookmarkStale, .bookmarkStale),
             (.photoLibraryDenied, .photoLibraryDenied),
             (.memoryPressure, .memoryPressure):
            return true
        case let (.diskSpaceInsufficient(a, b), .diskSpaceInsufficient(c, d)):
            return a == c && b == d
        case let (.eventCorrupted(a, _), .eventCorrupted(b, _)):
            return a == b
        case (.exportFailed, .exportFailed):
            return true
        default:
            return false
        }
    }
}
