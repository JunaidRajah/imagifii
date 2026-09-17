//
//  ImagifiiView.swift
//  Imagifii
//
//  Created by Junaid Rajah on 2026/09/16.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Displays captures and starts the durable upload workflow.
struct ImagifiiView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var viewModel = ImagifiiViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(L10n.queueEmptyTitle, systemImage: "tray", description: Text(L10n.queueEmptyDescription))
                } else {
                    List {
                            ForEach(items.filter { !viewModel.deletingItemIDs.contains($0.id) }) { item in
                            NavigationLink {
                                ImageDetailsView(itemID: item.id)
                            } label: {
                                QueueRow(item: item) {
                                    Task { await viewModel.retry(item) }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await viewModel.delete(item) }
                                } label: {
                                    Label(L10n.delete, systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.myImages)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("imagifiiLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132, height: 38)
                        .accessibilityLabel(L10n.queueTitle)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.showSourceDialog = true } label: {
                        Label(L10n.captureButton, systemImage: "camera.fill")
                    }
                    .accessibilityIdentifier("captureButton")
                }
            }
            .confirmationDialog(L10n.captureDialogTitle, isPresented: $viewModel.showSourceDialog, titleVisibility: .visible) {
                Button(L10n.captureTakePhoto) { viewModel.showCamera = true }
                Button(L10n.captureChooseLibrary) { viewModel.showLibrary = true }
                Button(L10n.cancel, role: .cancel) { }
            }
            .sheet(isPresented: $viewModel.showCamera) {
                CameraPicker(image: $viewModel.cameraImage).ignoresSafeArea()
            }
            .overlay {
                if let errorMessage = viewModel.errorMessage {
                    VStack {
                        Spacer()
                        Text(errorMessage).font(.footnote).padding().background(.thinMaterial).clipShape(.capsule)
                    }
                    .padding()
                }
            }
        }
        .task { await viewModel.bootstrap(context: modelContext) }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                do {
                    guard let data = try await newValue.loadTransferable(type: Data.self) else {
                        throw CaptureError.invalidImage
                    }
                    await viewModel.importImageData(data)
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
                selectedPhoto = nil
            }
        }
        .photosPicker(isPresented: $viewModel.showLibrary, selection: $selectedPhoto, matching: .images)
        .onChange(of: viewModel.cameraImage) { _, image in
            guard let image else { return }
            Task { await viewModel.importCameraImage(image) }
            viewModel.cameraImage = nil
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.appBecameActive() }
        }
        .onAppear { viewModel.startMonitoring() }
    }
}

/// Renders one queue item and its current upload action.
private struct QueueRow: View {
    let item: Item
    /// Action supplied by the parent for a failed item.
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let data = item.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary).frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                Label(item.state.title, systemImage: icon).font(.subheadline.weight(.medium)).foregroundStyle(color)
                if let lastError = item.lastError { Text(lastError).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if item.state == .failed || (item.state == .pending && item.lastError != nil) {
                Button(L10n.retry, action: retry).buttonStyle(.bordered)
            } else if item.state == .uploading {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Chooses an icon that matches the item's upload state.
    private var icon: String {
        switch item.state {
        case .pending: "clock"
        case .uploading: "arrow.up.circle"
        case .uploaded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    /// Chooses a color that matches the item's upload state.
    private var color: Color {
        switch item.state {
        case .pending: .orange
        case .uploading: .blue
        case .uploaded: .green
        case .failed: .red
        }
    }
}

#Preview {
    ImagifiiView().modelContainer(for: Item.self, inMemory: true)
}
