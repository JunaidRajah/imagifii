import SwiftUI
import SwiftData

/// Shows the original image and all persisted queue metadata.
struct ImageDetailsView: View {
    private let itemID: UUID
    @Query private var matchingItems: [Item]
    @State private var viewModel = ImageDetailsViewModel()

    /// Creates a details screen filtered to one queue record.
    init(itemID: UUID) {
        self.itemID = itemID
        let predicate = #Predicate<Item> { item in
            item.id == itemID
        }
        _matchingItems = Query(filter: predicate)
    }

    var body: some View {
        ScrollView {
            if let item = matchingItems.first {
                VStack(alignment: .center, spacing: 20) {
                    imageSection
                    metadataSection(for: item)
                }
                .padding()
            } else {
                ContentUnavailableView(L10n.detailsUnavailable, systemImage: "photo.badge.exclamationmark")
            }
        }
        .navigationTitle(L10n.detailsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let item = matchingItems.first {
                viewModel.loadImage(fileName: item.fileName)
            }
        }
        .onChange(of: matchingItems.first?.fileName) { _, fileName in
            guard let fileName else { return }
            viewModel.loadImage(fileName: fileName)
        }
    }

    /// Displays the original image from local FileManager storage.
    @ViewBuilder
    private var imageSection: some View {
        if let image = viewModel.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(radius: 8, y: 4)
        } else {
            ContentUnavailableView(L10n.detailsImageUnavailable, systemImage: "photo")
        }
    }

    /// Displays every stored metadata field for the queue record.
    private func metadataSection(for item: Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.detailsMetadata)
                .font(.headline)

            DetailRow(title: L10n.detailsID, value: item.id.uuidString)
            DetailRow(title: L10n.detailsFileName, value: item.fileName)
            DetailRow(title: L10n.detailsCreated, value: item.createdAt.formatted(date: .abbreviated, time: .standard))
            DetailRow(title: L10n.detailsState, value: item.state.title)
            DetailRow(title: L10n.detailsRetryCount, value: String(item.retryCount))
            DetailRow(title: L10n.detailsUploaded, value: item.uploadedAt?.formatted(date: .abbreviated, time: .standard) ?? L10n.detailsNotUploaded)

            if let lastError = item.lastError {
                DetailRow(title: L10n.detailsLastError, value: lastError)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Displays one metadata label and value.
private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}
