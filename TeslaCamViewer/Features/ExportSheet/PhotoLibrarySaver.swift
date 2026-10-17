import Foundation
import Photos

enum PhotoLibrarySaver {
    /// Saves a video file to the user's photo library.
    /// Requests authorization first, then performs the save.
    static func save(_ url: URL) async throws {
        // Request add-only authorization
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.photoLibraryDenied
        }

        // Verify the file exists before trying to save
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.exportFailed(underlying: NSError(
                domain: "PhotoLibrarySaver", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "导出文件不存在：\(url.lastPathComponent)"]
            ))
        }

        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false  // Copy instead of move so the temp file stays for sharing
            PHAssetCreationRequest.forAsset()
                .addResource(with: .video, fileURL: url, options: options)
        }
    }
}
