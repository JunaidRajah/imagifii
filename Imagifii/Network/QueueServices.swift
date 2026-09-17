import Foundation
import Network
import OSLog
import Observation
import SwiftData
import UIKit

/// Publishes connectivity changes and triggers work after reconnection.
@MainActor
@Observable
final class NetworkMonitor {
    /// Logs connectivity changes in Xcode's console.
    private let logger = Logger(subsystem: "com.imagifii.app", category: "network")
    /// The current network availability reported by the system.
    private(set) var isConnected = true

    /// The callback run when internet transitions from offline to online.
    var onReconnection: (() async -> Void)?
    /// The callback run when internet transitions from online to offline.
    var onDisconnection: (() -> Void)?

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "Imagifii.NetworkMonitor")
    private var isStarted = false
    private var reconnectPollTask: Task<Void, Never>?

    init() {
        start()
    }

    /// Marks the connection disconnected when an upload request fails due to a network outage.
    func markDisconnected() {
        guard isConnected else { return }
        isConnected = false
        logger.notice("Internet disconnected (network request failed). Pausing uploads and moving to pending.")
        startReconnectPolling()
        onDisconnection?()
    }

    /// Starts observing network path changes once.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        let monitor = NWPathMonitor()
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(connected: isConnected)
            }
        }
        monitor.start(queue: queue)
        logger.info("NetworkMonitor started")
    }

    private func handlePathUpdate(connected: Bool) {
        let previous = isConnected
        isConnected = connected
        logger.info("Network path update: connected=\(connected, privacy: .public), previous=\(previous, privacy: .public)")

        if connected {
            stopReconnectPolling()
            if !previous {
                logger.notice("Internet restored (offline -> online). Firing reconnection callback...")
                Task { [weak self] in
                    await self?.onReconnection?()
                }
            }
        } else {
            startReconnectPolling()
            if previous {
                logger.notice("Internet disconnected (online -> offline). Pausing uploads and moving to pending.")
                onDisconnection?()
            }
        }
    }

    /// Polls periodically while offline to detect reconnection promptly on all environments.
    private func startReconnectPolling() {
        guard reconnectPollTask == nil else { return }
        reconnectPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, !self.isConnected else { break }
                if self.monitor?.currentPath.status == .satisfied {
                    self.handlePathUpdate(connected: true)
                    break
                }
            }
        }
    }

    private func stopReconnectPolling() {
        reconnectPollTask?.cancel()
        reconnectPollTask = nil
    }

    /// Stops observing network path changes.
    func stop() {
        logger.info("NetworkMonitor stopped")
        stopReconnectPolling()
        monitor?.cancel()
        monitor = nil
        isStarted = false
    }
}

/// Stores captured image bytes separately from SwiftData metadata.
final class ImageFileStore {
    /// The protected Application Support directory used for images.
    private let directory: URL

    /// Creates the image directory if it does not already exist.
    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = support.appendingPathComponent("ImagifiiCaptureQueue", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Atomically saves image data and returns its filename.
    func save(_ data: Data, id: UUID) throws -> String {
        let name = "\(id.uuidString).jpg"
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }

    /// Returns the local URL for a stored filename.
    func url(for fileName: String) -> URL { directory.appendingPathComponent(fileName) }

    /// Checks whether a stored image still exists.
    func exists(_ fileName: String) -> Bool { FileManager.default.fileExists(atPath: url(for: fileName).path) }

    /// Deletes a stored image when it exists.
    func delete(_ fileName: String) throws {
        let url = url(for: fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

/// Persists queue metadata and coordinates it with image files.
@MainActor
final class CaptureRepository {
    private let context: ModelContext
    /// The file store containing the image bytes.
    let fileStore: ImageFileStore

    /// Creates a repository backed by a SwiftData context.
    init(context: ModelContext, fileStore: ImageFileStore? = nil) throws {
        self.context = context
        self.fileStore = try fileStore ?? ImageFileStore()
    }

    @discardableResult
    /// Writes the image first, then creates its pending SwiftData record.
    func enqueue(imageData: Data, isConnected: Bool = true) throws -> Item {
        let id = UUID()
        let fileName = try fileStore.save(imageData, id: id)
        let thumbnail = UIImage(data: imageData)?.preparingThumbnail(of: CGSize(width: 180, height: 180))?.jpegData(compressionQuality: 0.7)
        let item = Item(id: id, fileName: fileName, thumbnailData: thumbnail)
        if !isConnected {
            item.lastError = L10n.pendingAwaitingConnection
        }
        do {
            context.insert(item)
            try context.save()
        } catch {
            try? fileStore.delete(fileName)
            throw error
        }
        return item
    }

    /// Moves any active uploading or failed items to pending with awaiting connection message.
    func pauseForDisconnection() throws {
        let uploadingDesc = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == "uploading" })
        for item in try context.fetch(uploadingDesc) {
            item.state = .pending
            item.lastError = L10n.pendingAwaitingConnection
        }

        let failedDesc = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == "failed" })
        for item in try context.fetch(failedDesc) {
            item.state = .pending
            item.lastError = L10n.pendingAwaitingConnection
        }

        let pendingDesc = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == "pending" })
        for item in try context.fetch(pendingDesc) {
            item.lastError = L10n.pendingAwaitingConnection
        }

        try context.save()
    }

    /// Keeps interrupted records visibly uploading so the queue can resume them first.
    func recoverInterruptedUploads() throws {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == "uploading" })
        for item in try context.fetch(descriptor) {
            item.state = .uploading
            item.lastError = nil
        }
        try context.save()
    }

    /// Returns records that were interrupted while uploading.
    func uploadingItems() throws -> [Item] {
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.stateRaw == "uploading" },
            sortBy: [SortDescriptor(\Item.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    /// Returns pending items in oldest-first order.
    func pendingItems() throws -> [Item] {
        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.createdAt)])
        return try context.fetch(descriptor).filter { $0.state == .pending }
    }

    /// Saves any state changes made to queue records.
    func save() throws { try context.save() }

    /// Clears stale errors from records already confirmed as uploaded.
    func clearUploadedErrors() throws {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == "uploaded" })
        var changed = false
        for item in try context.fetch(descriptor) where item.lastError != nil {
            item.lastError = nil
            changed = true
        }
        if changed { try context.save() }
    }

    /// Clears "Pending, awaiting connection" messages when internet is connected.
    func clearAwaitingConnectionMessages() throws {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == "pending" })
        var changed = false
        for item in try context.fetch(descriptor) where item.lastError == L10n.pendingAwaitingConnection {
            item.lastError = nil
            changed = true
        }
        if changed { try context.save() }
    }

    /// Deletes an image from FileManager and then removes its SwiftData record.
    func delete(_ item: Item) throws {
        try fileStore.delete(item.fileName)
        context.delete(item)
        try context.save()
    }

    /// Moves the oldest failed item to pending and returns it for immediate retry.
    func requeueOldestFailedItem() throws -> Item? {
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.stateRaw == "failed" },
            sortBy: [SortDescriptor(\Item.createdAt)]
        )
        let failedItems = try context.fetch(descriptor)
        guard let item = failedItems.first else { return nil }
        for failedItem in failedItems {
            failedItem.state = .pending
            failedItem.lastError = nil
        }
        try context.save()
        return item
    }

    /// Moves every failed item back into the pending queue.
    func requeueAllFailedItems() throws {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == "failed" })
        let failedItems = try context.fetch(descriptor)
        guard !failedItems.isEmpty else { return }
        for item in failedItems {
            item.state = .pending
            item.lastError = nil
        }
        try context.save()
    }

    /// Moves every failed item except the selected one to pending.
    func requeueOtherFailedItems(excluding id: UUID) throws {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.stateRaw == "failed" && $0.id != id })
        for item in try context.fetch(descriptor) {
            item.state = .pending
            item.lastError = nil
        }
        try context.save()
    }
}

/// Abstraction for a backend image upload implementation.
protocol ImageUploader: Sendable {
    func upload(itemID: UUID, fileURL: URL) async throws
}

/// Uploads persisted image bytes to a configurable mock HTTP endpoint.
struct URLSessionImageUploader: ImageUploader {
    /// The endpoint that accepts the image body.
    var endpoint: URL = URL(string: "https://httpbin.org/post")!
    /// The URL session used for the request.
    var session: URLSession = .shared
    /// Artificial delay used to make upload state observable.
    var delayNanoseconds: UInt64 = 500_000_000

    /// Posts the image file and requires a successful HTTP response.
    func upload(itemID: UUID, fileURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw CaptureError.missingFile }
        try await Task.sleep(nanoseconds: delayNanoseconds)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(itemID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw MockUploadError.rejected(String(data: data, encoding: .utf8) ?? String(localized: "error.serverRejected"))
        }
    }
}

/// Errors returned by the mock upload service.
enum MockUploadError: LocalizedError {
    case rejected(String)

    var errorDescription: String? {
        if case let .rejected(message) = self { return message }
        return L10n.errorUploadFailed
    }
}

/// A deterministic uploader used by unit tests.
struct MockImageUploader: ImageUploader {
    var delayNanoseconds: UInt64 = 1
    var shouldFail: @Sendable () -> Bool = { false }

    /// Simulates success or failure without making a network request.
    func upload(itemID: UUID, fileURL: URL) async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        if shouldFail() { throw MockUploadError.rejected(L10n.errorSimulatedFailure) }
    }
}

/// Processes durable queue records one at a time.
@MainActor
final class UploadManager {
    /// Logs upload queue activity in Xcode's console.
    private let logger = Logger(subsystem: "com.imagifii.app", category: "upload")
    private let repository: CaptureRepository
    private let uploader: ImageUploader
    private weak var networkMonitor: NetworkMonitor?
    /// Prevents overlapping queue-processing runs.
    private var isProcessing = false

    /// Creates a manager with an injectable uploader.
    init(repository: CaptureRepository, uploader: ImageUploader? = nil, networkMonitor: NetworkMonitor? = nil) {
        self.repository = repository
        self.uploader = uploader ?? URLSessionImageUploader()
        self.networkMonitor = networkMonitor
    }

    /// Pauses any in-flight uploading calls and moves queue items to pending with awaiting connection message.
    func pauseUploadsForDisconnection() {
        logger.notice("Pausing uploads for network disconnection: moving items to pending")
        try? repository.pauseForDisconnection()
    }

    /// Requeues failures and drains every pending item in FIFO order.
    func processQueue() async {
        guard networkMonitor?.isConnected ?? true else {
            logger.info("Upload queue processing skipped: network is disconnected")
            pauseUploadsForDisconnection()
            return
        }
        guard !isProcessing else {
            logger.debug("Upload queue processing skipped: already processing")
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            logger.info("Upload queue processing started")
            try repository.clearAwaitingConnectionMessages()
            try repository.clearUploadedErrors()

            // Resume interrupted work before touching failed or pending records.
            let interruptedItems = try repository.uploadingItems()
            logger.info("Interrupted uploading items found: \(interruptedItems.count, privacy: .public)")
            for item in interruptedItems {
                guard networkMonitor?.isConnected ?? true else {
                    pauseUploadsForDisconnection()
                    return
                }
                await upload(item)
            }

            // Start the oldest failed item directly as uploading, then drain the rest.
            if let failedItem = try repository.requeueOldestFailedItem() {
                guard networkMonitor?.isConnected ?? true else {
                    pauseUploadsForDisconnection()
                    return
                }
                await upload(failedItem)
            }
            await drainPendingItems()
            logger.info("Upload queue processing finished")
        } catch {
            logger.error("Upload queue processing failed: \(error.localizedDescription, privacy: .public)")
            // The durable record remains on disk and will be retried on the next trigger.
        }
    }

    /// Retries the selected item first, then drains the other pending items.
    func retry(_ item: Item) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        // Immediately put into Uploading state and update UI
        item.state = .uploading
        item.lastError = nil
        try? repository.save()
        await Task.yield()

        try? repository.requeueOtherFailedItems(excluding: item.id)
        await upload(item, force: true)
        await drainPendingItems()
    }

    /// Uploads each pending item once in oldest-first order.
    private func drainPendingItems() async {
        do {
            // Fetch a fresh item after each attempt so one failure cannot stop the queue.
            while let item = try repository.pendingItems().first {
                guard networkMonitor?.isConnected ?? true else {
                    logger.info("Draining pending items stopped: network disconnected")
                    pauseUploadsForDisconnection()
                    break
                }
                await upload(item)
            }
        } catch {
            // The durable record remains pending and will be retried on the next trigger.
        }
    }

    /// Uploads one item and records its final result.
    private func upload(_ item: Item, force: Bool = false) async {
        guard item.state != .uploaded else { return }
        if !force {
            guard networkMonitor?.isConnected ?? true else {
                item.state = .pending
                item.lastError = L10n.pendingAwaitingConnection
                try? repository.save()
                return
            }
        }
        logger.info("Item \(item.id.uuidString, privacy: .public) transitioning to uploading")
        item.state = .uploading
        item.lastError = nil
        do {
            try repository.save()
        } catch {
            item.state = .pending
            item.lastError = error.localizedDescription
            return
        }
        // Yield to allow SwiftUI to redraw the Uploading state on the main runloop
        await Task.yield()

        do {
            try await uploader.upload(itemID: item.id, fileURL: repository.fileStore.url(for: item.fileName))
            item.state = .uploaded
            item.uploadedAt = Date()
            item.lastError = nil
        } catch {
            let isNetworkOutage: Bool
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                    isNetworkOutage = true
                default:
                    isNetworkOutage = false
                }
            } else {
                isNetworkOutage = false
            }

            if isNetworkOutage {
                item.state = .pending
                item.lastError = L10n.pendingAwaitingConnection
                try? repository.save()
                networkMonitor?.markDisconnected()
            } else {
                item.state = .failed
                item.retryCount += 1
                item.lastError = error.localizedDescription
                try? repository.save()
            }
            logger.error("Item \(item.id.uuidString, privacy: .public) upload failed: \(error.localizedDescription, privacy: .public)")
        }
        if item.state == .uploaded {
            logger.info("Item \(item.id.uuidString, privacy: .public) upload confirmed")
        }
        try? repository.save()
        await Task.yield()
    }
}
