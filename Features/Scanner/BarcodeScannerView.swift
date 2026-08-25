import SwiftUI
import VisionKit
import AVFoundation

// MARK: - Mode

enum BarcodeScannerMode {
    case priceEntry
    case addToList(UUID)
}

// MARK: - Main Scanner View

struct BarcodeScannerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let mode: BarcodeScannerMode
    @State private var scannedBarcode: String?
    @State private var scanResult: BarcodeScanResult = .idle
    @State private var showManualEntry = false
    @State private var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            ZStack {
                if canShowScanner {
                    DataScannerRepresentable(scannedBarcode: $scannedBarcode)
                        .ignoresSafeArea()
                } else {
                    scannerUnavailableView
                }

                VStack {
                    Spacer()
                    scanOverlay
                        .padding(.bottom, 48)
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: scannedBarcode) { _, barcode in
                guard let barcode else { return }
                handleScannedBarcode(barcode)
            }
            .sheet(isPresented: $showManualEntry) {
                manualEntrySheet
            }
            .task {
                await requestCameraAccessIfNeeded()
            }
        }
    }

    private var canShowScanner: Bool {
        cameraAuthorizationStatus == .authorized &&
        Self.canUseDataScanner
    }

    private static var canUseDataScanner: Bool {
        DataScannerViewController.isSupported &&
        DataScannerViewController.isAvailable
    }

    private func requestCameraAccessIfNeeded() async {
        guard cameraAuthorizationStatus == .notDetermined else { return }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraAuthorizationStatus = granted ? .authorized : .denied
    }

    @ViewBuilder
    private var scanOverlay: some View {
        switch scanResult {
        case .idle:
            HStack(spacing: 8) {
                Image(systemName: "barcode.viewfinder")
                Text("Point at a barcode")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())

        case .found(let product):
            BarcodeResultView(product: product, mode: mode, onDone: { dismiss() })
                .padding(.horizontal, 16)

        case .multiple(let products, let barcode):
            MultipleBarcodeResultsView(products: products, barcode: barcode, mode: mode, onDone: { dismiss() })
                .padding(.horizontal, 16)

        case .unknown(let barcode):
            VStack(spacing: 12) {
                Text("Unknown barcode")
                    .font(.headline)
                Text(barcode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Add manually") { showManualEntry = true }
                        .buttonStyle(.borderedProminent)
                    Button("Dismiss") { scanResult = .idle }
                        .buttonStyle(.bordered)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
        }
    }

    private var scannerUnavailableView: some View {
        ContentUnavailableView(
            scannerUnavailableTitle,
            systemImage: "camera.viewfinder",
            description: Text(scannerUnavailableDescription)
        )
        .safeAreaInset(edge: .bottom) {
            Button {
                showManualEntry = true
            } label: {
                Label("Enter price manually", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private var scannerUnavailableTitle: String {
        if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
            return "Camera Access Needed"
        }
        return "Camera Scanner Unavailable"
    }

    private var scannerUnavailableDescription: String {
        if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
            return "Allow camera access in iOS Settings to scan barcodes."
        }
        if !DataScannerViewController.isSupported {
            return "Live barcode scanning requires a supported physical device."
        }
        return "Barcode scanning is not available in previews, simulators, or while camera access is unavailable."
    }

    @ViewBuilder
    private var manualEntrySheet: some View {
        switch mode {
        case .priceEntry:
            AddPriceObservationSheet(prefilledBarcode: scannedBarcode)
                .environment(store)
        case .addToList(let listID):
            AddShoppingListItemSheet(listID: listID)
                .environment(store)
        }
    }

    private func handleScannedBarcode(_ barcode: String) {
        let matches = store.products.filter { $0.barcode == barcode }
        if matches.count == 1, let product = matches.first {
            scanResult = .found(product)
        } else if matches.count > 1 {
            scanResult = .multiple(matches, barcode: barcode)
        } else {
            scanResult = .unknown(barcode)
        }
    }
}

private enum BarcodeScanResult {
    case idle
    case found(Product)
    case multiple([Product], barcode: String)
    case unknown(String)
}

// MARK: - Result View

private struct MultipleBarcodeResultsView: View {
    let products: [Product]
    let barcode: String
    let mode: BarcodeScannerMode
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Multiple matches")
                    .font(.headline)
                Spacer()
            }

            Text(barcode)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(products) { product in
                    BarcodeProductChoiceRow(product: product, mode: mode, onDone: onDone)
                }
            }

            Button("Cancel") { onDone() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}

private struct BarcodeProductChoiceRow: View {
    @Environment(AppStore.self) private var store

    let product: Product
    let mode: BarcodeScannerMode
    let onDone: () -> Void

    @State private var showPriceEntry = false
    @State private var addedToList = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.subheadline.weight(.medium))
                Text(productDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch mode {
            case .priceEntry:
                Button("Use") { showPriceEntry = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            case .addToList:
                if addedToList {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Add") { addProductToList() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showPriceEntry) {
            AddPriceObservationSheet(prefilledProductName: product.name, prefilledBarcode: product.barcode)
                .environment(store)
        }
    }

    private var productDetail: String {
        if let category = product.category, let unit = product.defaultUnit {
            return "\(category) · \(unit.rawValue)"
        }
        if let category = product.category {
            return category
        }
        if let unit = product.defaultUnit {
            return "Default unit: \(unit.rawValue)"
        }
        return "No package details saved"
    }

    private func addProductToList() {
        guard case .addToList(let listID) = mode,
              let idx = store.shoppingLists.firstIndex(where: { $0.id == listID }) else { return }
        var item = ShoppingListItem(listID: listID, productName: product.name)
        item.productID = product.id
        store.shoppingLists[idx].items.append(item)
        store.persistNow()
        addedToList = true
    }
}

private struct BarcodeResultView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let product: Product
    let mode: BarcodeScannerMode
    let onDone: () -> Void

    @State private var showPriceEntry = false
    @State private var addedToList = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(product.name)
                    .font(.headline)
                Spacer()
            }

            if let category = product.category {
                Text(category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                switch mode {
                case .priceEntry:
                    Button("Record Price") { showPriceEntry = true }
                        .buttonStyle(.borderedProminent)
                case .addToList:
                    if addedToList {
                        Label("Added", systemImage: "checkmark")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)
                    } else {
                        Button("Add to List") { addProductToList() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Button("Done") { onDone() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .sheet(isPresented: $showPriceEntry) {
            AddPriceObservationSheet(prefilledProductName: product.name, prefilledBarcode: product.barcode)
                .environment(store)
        }
    }

    private func addProductToList() {
        guard case .addToList(let listID) = mode,
              let idx = store.shoppingLists.firstIndex(where: { $0.id == listID }) else { return }
        var item = ShoppingListItem(listID: listID, productName: product.name)
        item.productID = product.id
        store.shoppingLists[idx].items.append(item)
        store.persistNow()
        addedToList = true
    }
}

// MARK: - DataScanner Representable

struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var scannedBarcode: String?

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: DataScannerRepresentable
        private var lastScanned: String?

        init(_ parent: DataScannerRepresentable) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let item = addedItems.first,
                  case .barcode(let barcode) = item,
                  let value = barcode.payloadStringValue,
                  value != lastScanned else { return }
            lastScanned = value
            Task { @MainActor in
                self.parent.scannedBarcode = value
            }
        }
    }
}
