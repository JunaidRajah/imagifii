//
//  Item.swift
//  Imagifii
//
//  Created by Junaid Rajah on 2026/09/16.
//

import Foundation
import SwiftData

@Model
/// A persisted queue record for one captured image.
final class Item {
    /// Stable identifier used to name the image file.
    var id: UUID
    /// The image filename stored in Application Support.
    var fileName: String
    /// A small preview used to render the queue without reading the full image.
    var thumbnailData: Data?
    /// The time the capture entered the queue.
    var createdAt: Date
    /// The raw string SwiftData stores for the upload state.
    var stateRaw: String
    /// Number of upload attempts made for this item.
    var retryCount: Int
    /// The most recent upload error, if one occurred.
    var lastError: String?
    /// The time the backend confirmed the upload.
    var uploadedAt: Date?

    /// Creates a new queue item, initially pending upload.
    init(id: UUID = UUID(), fileName: String, thumbnailData: Data? = nil, state: UploadState = .pending) {
        self.id = id
        self.fileName = fileName
        self.thumbnailData = thumbnailData
        self.createdAt = Date()
        self.stateRaw = state.rawValue
        self.retryCount = 0
        self.lastError = nil
        self.uploadedAt = nil
    }

    /// Converts the stored string into the app's typed upload state.
    var state: UploadState {
        get { UploadState(rawValue: stateRaw) ?? .failed }
        set { stateRaw = newValue.rawValue }
    }
}
