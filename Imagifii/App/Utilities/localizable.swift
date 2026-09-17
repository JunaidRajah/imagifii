import Foundation

/// Typed access to the app's localized strings.
enum L10n {
    /// Delete action title.
    static let delete = String(localized: "Delete")
    /// My Images navigation title.
    static let myImages = String(localized: "My Images")
    /// Imagifii Queue
    static let queueTitle = String(localized: "Imagifii Queue")
    /// No captures yet
    static let queueEmptyTitle = String(localized: "You have no Imagifii captures yet.")
    /// Choose an image to add it to the durable upload queue.
    static let queueEmptyDescription = String(localized: "Choose an image from you gallery or take a photo to secure it with iMagifii")
    /// Retry
    static let retry = String(localized: "Retry")

    /// Capture
    static let captureButton = String(localized: "Capture")
    /// Add an image
    static let captureDialogTitle = String(localized: "Add an Image")
    /// Take Photo
    static let captureTakePhoto = String(localized: "Take Photo")
    /// Choose from Library
    static let captureChooseLibrary = String(localized: "Choose from Library")
    /// Cancel
    static let cancel = String(localized: "Cancel")

    /// Pending
    static let statePending = String(localized: "Pending")
    /// Pending, awaiting connection
    static let pendingAwaitingConnection = String(localized: "Pending, awaiting connection")
    /// Uploading
    static let stateUploading = String(localized: "Uploading")
    /// Uploaded
    static let stateUploaded = String(localized: "Uploaded")
    /// Uploading
    static let stateFailed = String(localized: "Failed")

    /// The image could not be encoded.
    static let errorInvalidImage = String(localized: "The image could not be encoded.")
    /// The local image file is missing.
    static let errorMissingFile = String(localized: "The local image file is missing.")
    /// Upload interrupted; queued again.
    static let errorUploadInterrupted = String(localized: "Upload interrupted; queued again.")
    /// The upload failed.
    static let errorUploadFailed = String(localized: "The upload failed.")
    /// The server rejected the upload.
    static let errorServerRejected = String(localized: "The server rejected the upload.")
    /// Simulated upload failure.
    static let errorSimulatedFailure = String(localized: "Simulated upload failure.")

    /// Image details title.
    static let detailsTitle = String(localized: "Image Details")
    /// Metadata section title.
    static let detailsMetadata = String(localized: "Metadata")
    /// Missing queue record message.
    static let detailsUnavailable = String(localized: "Image record unavailable")
    /// Missing original image message.
    static let detailsImageUnavailable = String(localized: "Image unavailable")
    /// Metadata labels.
    static let detailsID = String(localized: "ID")
    static let detailsFileName = String(localized: "File Name")
    static let detailsCreated = String(localized: "Created")
    static let detailsState = String(localized: "Upload State")
    static let detailsRetryCount = String(localized: "Retry Count")
    static let detailsUploaded = String(localized: "Uploaded At")
    static let detailsNotUploaded = String(localized: "Not uploaded")
    static let detailsLastError = String(localized: "Last Error")
}
