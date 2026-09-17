import SwiftUI
import UIKit

/// Provides a SwiftUI camera sheet using the native camera controller.
struct CameraPicker: UIViewControllerRepresentable {
    /// The captured image returned to SwiftUI.
    @Binding var image: UIImage?

    /// Creates the delegate coordinator.
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Creates the native camera controller.
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    /// Updates the camera controller when SwiftUI state changes.
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }

    /// Receives camera results and forwards them to SwiftUI.
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        /// The SwiftUI camera bridge.
        let parent: CameraPicker

        /// Creates a coordinator for the camera bridge.
        init(_ parent: CameraPicker) { self.parent = parent }

        /// Sends the selected image back to the bound SwiftUI state.
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
        }

        /// Closes the camera without returning an image.
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
