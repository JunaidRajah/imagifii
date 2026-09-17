import Foundation

/// The current stage of a captured image in the upload queue.
enum UploadState: String, CaseIterable, Codable {
    case pending
    case uploading
    case uploaded
    case failed

    /// Returns a localized display name for the state.
    var title: String {
        switch self {
        case .pending: L10n.statePending
        case .uploading: L10n.stateUploading
        case .uploaded: L10n.stateUploaded
        case .failed: L10n.stateFailed
        }
    }
}

/// Errors that can occur while preparing a captured image.
enum CaptureError: LocalizedError {
    case invalidImage
    case missingFile

    /// Provides a short message suitable for showing in the UI.
    var errorDescription: String? {
        switch self {
        case .invalidImage: return L10n.errorInvalidImage
        case .missingFile: return L10n.errorMissingFile
        }
    }
}
