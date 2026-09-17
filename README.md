# Imagifii - Resilient Capture & Upload Proof of Concept

## Overview

**Imagifii** is a native iOS proof-of-concept demonstrating a resilient image capture and upload pipeline. Designed for identity document and selfie verification workflows, the app guarantees that **no completed capture is ever lost**, surviving network dropouts, backgrounding, and full app process restarts.

---

## The Core Invariant

> **The capture is persisted locally on disk before any network operation begins.**

```text
User Captures Image (Camera or Gallery)
           │
           ▼
    Convert to JPEG
           │
           ▼
  [1] Save to FileManager (Protected Application Support)
           │
           ▼
  [2] Save to SwiftData (Status: "Pending")
           │
           ▼
  [3] Safe to Upload (Network is only called now)
           │
           ▼
  [4] Upload via URLSession with Idempotency Key
           │
           ▼
  [5] Confirmed HTTP 2xx Response -> Status: "Uploaded"
```

If the app crashes, is killed, or loses internet at any point after capture, the image file and its metadata remain intact on disk and are recovered automatically on next launch.

---

## How to Run

### Requirements
- macOS with Xcode 15+ installed
- iOS 17.0+ Simulator or Physical Device

### Quick Start
1. Open `Imagifii.xcodeproj` in Xcode.
2. Select the `Imagifii` scheme and target an iPhone simulator (e.g. iPhone 15 Pro) or a connected device.
3. Press **Cmd + R** to Build & Run.
4. Tap the **Camera** button in the top-right toolbar:
   - Choose **Take Photo** to use the device camera (or fallback library in simulator).
   - Choose **Choose from Library** to select photos from the simulator gallery.
5. Tap on any queue item to open its **Image Details** view and view metadata.
6. Swipe left on any row to **Delete** (optimistically removes from UI, then deletes from disk and database).

### Running Unit Tests
- Press **Cmd + U** in Xcode, or select **Product → Test**.
- Tests use Apple's Swift Testing framework (`@Test`, `#expect`) and execute against isolated, in-memory repositories.

---

## Key Features

- **Capture Flexibility**: Full support for device camera (`UIImagePickerController` bridged via `UIViewControllerRepresentable`) and Photo Library (`PhotosPicker`).
- **Durable Persistence First**: Image bytes are written atomically with `.completeFileProtection` to `Application Support/ImagifiiCaptureQueue`, while lightweight metadata and a thumbnail are saved in `SwiftData`.
- **Smart Network Monitoring**: Uses Apple's `NWPathMonitor` with reconnection detection. When connection is lost, active uploads cleanly pause with `"Pending, awaiting connection"`. As soon as internet returns, the queue resumes and uploads automatically in FIFO order.
- **Idempotent Requests**: Each upload request sends an `Idempotency-Key` HTTP header with the capture's unique UUID to prevent duplicate processing on the backend.
- **Detailed Metadata View**: Tap any image in the list to view its UUID, filename, upload state, creation timestamp, retry count, and confirmation timestamp.
- **Optimistic Swipe-to-Delete**: Swipe to delete an image; it disappears immediately from the UI and is cleaned up asynchronously from both disk and database.

---

## State Machine

```text
               ┌──────────────┐
               │   Pending    │ ◄─── Captures start here / Requeued on disconnect
               └──────┬───────┘
                      │
                      ▼
               ┌──────────────┐
               │  Uploading   │ ◄─── Active network transfer
               └──────┬───────┘
                      │
               ┌──────┴──────┐
               │             │
               ▼             ▼
         ┌──────────┐   ┌─────────┐
         │ Uploaded │   │ Failed  │
         └──────────┘   └────┬────┘
                             │
                      Manual │ Retry
                             ▼
                         Uploading
```

### State Transitions
1. **Pending**: Capture saved locally. If offline, annotated with `"Pending, awaiting connection"`.
2. **Uploading**: Actively transferring the JPEG file to the mock server endpoint (`https://httpbin.org/post`).
3. **Uploaded**: The server returned a confirmed HTTP 2xx status code. Errors are cleared and confirmation timestamp is recorded.
4. **Failed**: The server rejected the request or an unexpected error occurred. Can be retried manually by tapping **Retry**.

---

## Concurrency & Architecture

- **100% Native SwiftUI & SwiftData**: Clean view code using Swift Observation (`@Observable`, `@Bindable`, `@Query`).
- **Separation of Concerns**:
  - `ContentViewModel`: Manages queue presentation, camera/photo workflows, and triggers.
  - `CaptureRepository`: Coordinates atomic file writes via `ImageFileStore` and metadata records in `SwiftData`.
  - `UploadManager`: Serializes queue orchestration, prevents concurrent overlapping runs, and manages item upload lifecycle.
  - `NetworkMonitor`: Observes interface path changes and signals reconnection/disconnection transitions.
- **No Heavy Third-Party Dependencies**: Built purely with Foundation, SwiftUI, SwiftData, Network, and OSLog.

---

## Resilience Scenarios Handled

| Scenario | Behavior |
|---|---|
| **App killed immediately after capture** | Image and SwiftData record were saved first. Item safely resumes on next app launch. |
| **Network dropped during upload** | Active upload stops; item transitions to `Pending` with `"Pending, awaiting connection"`. |
| **Internet restored** | `NetworkMonitor` detects restoration and triggers `UploadManager` to resume the queue oldest-first. |
| **App backgrounded / relaunched** | Interrupted uploads are recovered and processing restarts as soon as the app becomes active. |
| **Server error / rejection** | Item transitions to `Failed` and displays the error message. User can tap `Retry` to re-attempt. |

---

## Production Recommendations

For a full production identity verification system, the following enhancements are motivated:
1. **Background URLSession**: Upgrade from standard URLSession to `URLSessionConfiguration.background(withIdentifier:)` with `uploadTask(with:fromFile:)` so transfers continue even if the system suspends or kills the app.
2. **End-to-End Encryption**: Apply hardware-backed Keychain encryption keys or Secure Enclave protection for identity document payloads stored at rest.
3. **Telemetry & Observability**: Incorporate structured logging and metric reporting for upload latency, failure classifications, and retry frequencies.
