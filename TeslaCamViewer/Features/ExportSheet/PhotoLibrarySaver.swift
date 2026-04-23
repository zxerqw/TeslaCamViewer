import Foundation
import Photos

enum PhotoLibrarySaver {
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.photoLibraryDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset()
                .addResource(with: .video, fileURL: url, options: nil)
        }
    }
}
