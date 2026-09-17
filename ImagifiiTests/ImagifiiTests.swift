//
//  ImagifiiTests.swift
//  ImagifiiTests
//
//  Created by Junaid Rajah on 2026/09/16.
//

import Foundation
import SwiftData
import Testing
@testable import Imagifii

@MainActor
/// Tests the durable queue and its upload state transitions.
struct ImagifiiTests {
    /// Creates an isolated in-memory repository for one test.
    private func makeRepository() throws -> (CaptureRepository, ModelContainer) {
        let container = try ModelContainer(for: Item.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = try ImageFileStore(fileManager: .default)
        return (try CaptureRepository(context: ModelContext(container), fileStore: store), container)
    }

    /// Verifies that enqueue creates both metadata and an image file.
    @Test func enqueuePersistsPendingItemAndFile() throws {
        let (repository, _) = try makeRepository()
        let item = try repository.enqueue(imageData: Data([1, 2, 3]))
        #expect(item.state == .pending)
        #expect(repository.fileStore.exists(item.fileName))
    }

    /// Verifies that an interrupted upload resumes in the uploading state.
    @Test func interruptedUploadingItemReturnsToPending() throws {
        let (repository, _) = try makeRepository()
        let item = try repository.enqueue(imageData: Data([1]))
        item.state = .uploading
        try repository.save()
        try repository.recoverInterruptedUploads()
        #expect(item.state == .uploading)
    }

    /// Verifies that successful processing records uploaded state and time.
    @Test func successfulUploadMarksUploaded() async throws {
        let (repository, _) = try makeRepository()
        let item = try repository.enqueue(imageData: Data([1]))
        let manager = UploadManager(repository: repository)
        await manager.processQueue()
        #expect(item.state == .uploaded)
        #expect(item.uploadedAt != nil)
    }

    /// Verifies that a failed attempt remains visible and increments retries.
    @Test func failedUploadCanBeRetried() async throws {
        let (repository, _) = try makeRepository()
        let item = try repository.enqueue(imageData: Data([1]))
        let failing = MockImageUploader(delayNanoseconds: 1, shouldFail: { true })
        let manager = UploadManager(repository: repository, uploader: failing)
        await manager.processQueue()
        #expect(item.state == .failed)
        #expect(item.retryCount == 1)

        // Retry with a succeeding uploader
        let succeeding = MockImageUploader(delayNanoseconds: 1, shouldFail: { false })
        let retryManager = UploadManager(repository: repository, uploader: succeeding)
        await retryManager.retry(item)
        #expect(item.state == .uploaded)
        #expect(item.lastError == nil)
    }

    /// Verifies that disconnection pauses the queue and marks items awaiting connection.
    @Test func disconnectionPausesQueueAndSetsAwaitingConnection() throws {
        let (repository, _) = try makeRepository()
        let item = try repository.enqueue(imageData: Data([1]), isConnected: false)
        #expect(item.state == .pending)
        #expect(item.lastError == L10n.pendingAwaitingConnection)

        try repository.pauseForDisconnection()
        #expect(item.state == .pending)
        #expect(item.lastError == L10n.pendingAwaitingConnection)
    }

    /// Verifies that reconnection clears awaiting messages and completes the upload.
    @Test func reconnectionClearsMessagesAndUploads() async throws {
        let (repository, _) = try makeRepository()
        let item = try repository.enqueue(imageData: Data([1]), isConnected: false)
        #expect(item.lastError == L10n.pendingAwaitingConnection)

        let mockUploader = MockImageUploader(delayNanoseconds: 1, shouldFail: { false })
        let manager = UploadManager(repository: repository, uploader: mockUploader)
        await manager.processQueue()
        #expect(item.state == .uploaded)
        #expect(item.lastError == nil)
    }

    /// Verifies that deleting an item deletes both the image file on disk and the SwiftData record.
    @Test func deleteRemovesFileAndDatabaseRecord() throws {
        let (repository, container) = try makeRepository()
        let item = try repository.enqueue(imageData: Data([1, 2, 3]))
        let fileName = item.fileName
        #expect(repository.fileStore.exists(fileName))

        try repository.delete(item)
        #expect(!repository.fileStore.exists(fileName))

        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<Item>())
        #expect(items.isEmpty)
    }
}
