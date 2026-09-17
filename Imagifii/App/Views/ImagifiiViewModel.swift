import Foundation
import Observation
import OSLog
import SwiftData
import UIKit

/// Owns the queue screen state and capture/upload workflow.
@MainActor
@Observable
final class ImagifiiViewModel {
    /// Logs lifecycle and queue-resume events.
    private let logger = Logger(subsystem: "com.imagifii.app", category: "queue")
    /// Whether the photo library is visible.
    var showLibrary = false
    /// Whether the capture source dialog is visible.
    var showSourceDialog = false
    /// Whether the camera sheet is visible.
    var showCamera = false
    /// The image returned by the camera.
    var cameraImage: UIImage?
    /// A user-facing workflow error.
    var errorMessage: String?
    /// IDs hidden while their local deletion completes.
    private(set) var deletingItemIDs = Set<UUID>()

    /// The network monitor used to resume uploads after reconnection.
    let networkMonitor = NetworkMonitor()
    private var repository: CaptureRepository?
    private var uploadManager: UploadManager?
    private var hasBootstrapped = false

    /// Creates the view model and configures reconnection handling.
    init() {
        networkMonitor.onReconnection = { [weak self] in
            await self?.resumeQueue()
        }
        networkMonitor.onDisconnection = { [weak self] in
            self?.uploadManager?.pauseUploadsForDisconnection()
        }
    }

    /// Creates services, repairs interrupted records, and starts processing.
    func bootstrap(context: ModelContext) async {
        logger.info("Queue bootstrap started")
        guard !hasBootstrapped else {
            logger.info("Queue already bootstrapped; resuming existing queue")
            await resumeQueue()
            return
        }
        do {
            let repository = try CaptureRepository(context: context)
            try repository.recoverInterruptedUploads()
            self.repository = repository
            uploadManager = UploadManager(repository: repository, networkMonitor: networkMonitor)
            hasBootstrapped = true
            networkMonitor.start()
            logger.info("Queue bootstrap complete; starting initial resume")
            await resumeQueue()
        } catch {
            logger.error("Queue bootstrap failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Starts monitoring connectivity when the screen appears.
    func startMonitoring() {
        networkMonitor.start()
    }

    /// Stops monitoring connectivity when the screen disappears.
    func stopMonitoring() {
        networkMonitor.stop()
    }

    /// Processes the durable queue when the app becomes active.
    func appBecameActive() async {
        logger.info("App became active; resuming queue")
        await resumeQueue()
    }

    /// Converts, persists, and uploads selected photo data.
    func importImageData(_ data: Data) async {
        do {
            guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else {
                throw CaptureError.invalidImage
            }
            try enqueue(jpeg)
            await processQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Imports and durably queues a camera image.
    func importCameraImage(_ image: UIImage) async {
        do {
            guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
                throw CaptureError.invalidImage
            }
            try enqueue(jpeg)
            await processQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Retries the selected failed item.
    func retry(_ item: Item) async {
        await uploadManager?.retry(item)
    }

    /// Hides an item immediately, then deletes it from local storage and SwiftData.
    func delete(_ item: Item) async {
        let itemID = item.id
        deletingItemIDs.insert(itemID)
        await Task.yield()
        do {
            try repository?.delete(item)
        } catch {
            deletingItemIDs.remove(itemID)
            errorMessage = error.localizedDescription
        }
    }

    /// Starts processing the durable queue.
    private func processQueue() async {
        await uploadManager?.processQueue()
    }

    /// Recovers interrupted uploads before processing pending work.
    private func resumeQueue() async {
        guard let repository, uploadManager != nil else {
            logger.warning("Queue resume skipped: services are not ready")
            return
        }
        logger.info("Queue resume started")
        do {
            try repository.clearUploadedErrors()
            try repository.clearAwaitingConnectionMessages()
            try repository.recoverInterruptedUploads()
            await processQueue()
            logger.info("Queue resume finished")
        } catch {
            logger.error("Queue resume failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Persists image bytes before allowing upload processing to begin.
    private func enqueue(_ jpeg: Data) throws {
        guard let repository else { throw CaptureError.invalidImage }
        _ = try repository.enqueue(imageData: jpeg, isConnected: networkMonitor.isConnected)
    }
}
