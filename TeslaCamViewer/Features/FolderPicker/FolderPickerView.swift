import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FolderPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        vc.allowsMultipleSelection = false
        vc.delegate = context.coordinator
        // Start at the root so USB drives are immediately visible.
        vc.directoryURL = URL(filePath: "/", directoryHint: .isDirectory)
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coord { Coord(onPick: onPick) }

    final class Coord: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let u = urls.first { onPick(u) }
        }
    }
}
