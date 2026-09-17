import Foundation
import CoreGraphics
import ImageIO
import Observation

/// Loads the original locally persisted image for the details screen.
@MainActor
@Observable
final class ImageDetailsViewModel {
    /// The decoded original image loaded from Application Support.
    private(set) var image: CGImage?
    /// A user-facing error when the original image cannot be loaded.
    private(set) var errorMessage: String?

    /// Loads the image belonging to a SwiftData queue record.
    func loadImage(fileName: String) {
        do {
            let store = try ImageFileStore()
            let data = try Data(contentsOf: store.url(for: fileName))
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CaptureError.invalidImage
            }
            self.image = image
            errorMessage = nil
        } catch {
            image = nil
            errorMessage = error.localizedDescription
        }
    }
}
