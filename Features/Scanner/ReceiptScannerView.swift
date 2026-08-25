import SwiftUI
import Vision
import PhotosUI
import AVFoundation

// MARK: - Models

struct ReceiptLine: Identifiable {
    let id = UUID()
    let rawText: String
    var productName: String?
    var matchedProductID: UUID?
    var price: Decimal?
    var isIncluded: Bool
}

struct ParsedReceipt {
    var inferredStoreName: String?
    var observedDate: Date
    var lines: [ReceiptLine]
}

// MARK: - Receipt Parser

enum ReceiptParser {
    // Norwegian price pattern: digits, comma or period, exactly 2 decimal digits at end of token
    private static let pricePattern = /(\d{1,5}[,\.]\d{2})$/
    private static let knownChains = [
        "kiwi", "rema 1000", "rema", "coop extra", "extra", "coop mega", "mega",
        "coop prix", "prix", "meny", "joker", "bunnpris", "spar", "europris"
    ]

    static func parse(rawLines: [String], knownProducts: [Product] = []) -> ParsedReceipt {
        var receiptLines: [ReceiptLine] = []
        let inferredStoreName = inferStoreName(from: rawLines)

        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            var price: Decimal?
            var productName: String?
            var matchedProductID: UUID?

            if let match = trimmed.firstMatch(of: pricePattern) {
                let priceString = String(match.output.1).replacingOccurrences(of: ",", with: ".")
                price = Decimal(string: priceString)
                // Everything before the price token is the product name
                let nameCandidate = trimmed
                    .dropLast(match.output.1.count)
                    .trimmingCharacters(in: .whitespaces)
                if !nameCandidate.isEmpty {
                    if let matched = bestProductMatch(for: nameCandidate, in: knownProducts) {
                        productName = matched.name
                        matchedProductID = matched.id
                    } else {
                        productName = nameCandidate
                    }
                }
            }

            // Skip lines that look like totals, headers, or store metadata
            let lower = trimmed.lowercased()
            let isNoise = lower.hasPrefix("sum") || lower.hasPrefix("total") ||
                          lower.hasPrefix("mva") || lower.hasPrefix("kvittering") ||
                          lower.hasPrefix("tlf") || lower.hasPrefix("org")

            let line = ReceiptLine(
                rawText: raw,
                productName: productName,
                matchedProductID: matchedProductID,
                price: price,
                isIncluded: price != nil && productName != nil && !isNoise
            )
            receiptLines.append(line)
        }

        return ParsedReceipt(inferredStoreName: inferredStoreName, observedDate: Date(), lines: receiptLines)
    }

    static func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["nb-NO", "en-US"]
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private static func inferStoreName(from rawLines: [String]) -> String? {
        let headerLines = rawLines.prefix(8).map { $0.lowercased() }
        for chain in knownChains {
            if headerLines.contains(where: { $0.contains(chain) }) {
                return displayName(for: chain)
            }
        }
        return nil
    }

    private static func displayName(for chain: String) -> String {
        switch chain {
        case "kiwi": return "Kiwi"
        case "rema", "rema 1000": return "Rema 1000"
        case "coop extra", "extra": return "Coop Extra"
        case "coop mega", "mega": return "Coop Mega"
        case "coop prix", "prix": return "Coop Prix"
        case "meny": return "Meny"
        case "joker": return "Joker"
        case "bunnpris": return "Bunnpris"
        case "spar": return "Spar"
        case "europris": return "Europris"
        default: return chain.capitalized
        }
    }

    private static func bestProductMatch(for scannedName: String, in products: [Product]) -> Product? {
        let scanned = normalisedWords(scannedName)
        guard !scanned.isEmpty else { return nil }

        if let exact = products.first(where: { normalisedWords($0.name).joined(separator: " ") == scanned.joined(separator: " ") }) {
            return exact
        }

        let scannedText = scanned.joined(separator: " ")
        if let substring = products.first(where: { product in
            let productText = normalisedWords(product.name).joined(separator: " ")
            return scannedText.contains(productText) || productText.contains(scannedText)
        }) {
            return substring
        }

        return products
            .map { product -> (product: Product, score: Double) in
                let productWords = Set(normalisedWords(product.name))
                let scannedWords = Set(scanned)
                let overlap = productWords.intersection(scannedWords).count
                let denominator = max(productWords.union(scannedWords).count, 1)
                return (product, Double(overlap) / Double(denominator))
            }
            .filter { $0.score >= 0.5 }
            .max { $0.score < $1.score }?
            .product
    }

    private static func normalisedWords(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
    }
}

// MARK: - Camera Image Picker

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraImagePicker

        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Receipt Scanner View

struct ReceiptScannerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var phase: ScanPhase = .idle
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var parsedReceipt: ParsedReceipt?
    @State private var rawReceiptLines: [String] = []
    @State private var showCameraUnavailable = false
    @State private var cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private enum ScanPhase {
        case idle, processing, review
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    idleView
                case .processing:
                    processingView
                case .review:
                    if let receipt = parsedReceipt {
                        ReceiptImportView(receipt: receipt, rawLines: rawReceiptLines) { committed, branchID in
                            commitLines(committed, branchID: branchID)
                            dismiss()
                        }
                        .environment(store)
                    }
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(isPresented: $showCamera) { image in
                processImage(image)
            }
        }
        .alert("Camera unavailable", isPresented: $showCameraUnavailable) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cameraUnavailableMessage)
        }
        .task {
            if cameraAuthStatus == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                cameraAuthStatus = granted ? .authorized : .denied
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                processImage(image)
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "doc.viewfinder")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Scan a Receipt")
                    .font(.title2.weight(.bold))
                Text("Take a photo of your receipt or import one from your photo library. PrisPilot will extract prices automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 14) {
                Button {
                    if canUseCameraCapture {
                        showCamera = true
                    } else {
                        showCameraUnavailable = true
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private var canUseCameraCapture: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera) &&
        cameraAuthStatus != .denied &&
        cameraAuthStatus != .restricted
    }

    private var cameraUnavailableMessage: String {
        if cameraAuthStatus == .denied || cameraAuthStatus == .restricted {
            return "Allow camera access in iOS Settings to take photos of receipts."
        }
        return "Camera capture is not available on this device. Choose a receipt image from your photo library instead."
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Reading receipt…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func processImage(_ image: UIImage) {
        phase = .processing
        Task {
            let rawLines = await ReceiptParser.recognizeText(in: image)
            let receipt = ReceiptParser.parse(rawLines: rawLines, knownProducts: store.products)
            await MainActor.run {
                rawReceiptLines = rawLines
                parsedReceipt = receipt
                phase = .review
            }
        }
    }

    private func commitLines(_ lines: [ReceiptLine], branchID: UUID) {
        guard let branch = store.branches.first(where: { $0.id == branchID }) else { return }

        let date = parsedReceipt?.observedDate ?? Date()

        for line in lines {
            guard let name = line.productName, let price = line.price else { continue }

            // Match or create product
            let product: Product
            if let matchedID = line.matchedProductID,
               let existing = store.products.first(where: { $0.id == matchedID }) {
                product = existing
            } else if let existing = store.products.first(where: { $0.name.lowercased() == name.lowercased() }) {
                product = existing
            } else {
                let newProduct = Product(name: name)
                store.products.append(newProduct)
                product = newProduct
            }

            let obs = PriceObservation(
                productID: product.id,
                productName: product.name,
                storeBranchID: branchID,
                storeBranchName: branch.displayName,
                price: price,
                observedDate: date,
                source: .receiptScan
            )
            store.priceObservations.append(obs)
            store.queueCommunityContributionIfNeeded(for: obs)
        }
        store.persistNow()
    }
}

// MARK: - Receipt Import Review View

struct ReceiptImportView: View {
    @Environment(AppStore.self) private var store
    @State var receipt: ParsedReceipt
    let rawLines: [String]
    @State private var selectedBranchID: UUID?
    @State private var showAIConsent = false
    @State private var isParsingWithAI = false
    @State private var hasUsedAIParsing = false
    @State private var aiParsingError: String?
    let onCommit: ([ReceiptLine], UUID) -> Void

    var includedLines: [ReceiptLine] { receipt.lines.filter { $0.isIncluded } }
    var canCommit: Bool { !includedLines.isEmpty && selectedBranchID != nil }
    var canUseAIParsing: Bool {
        store.isUsingLiveAI && !rawLines.isEmpty && !hasUsedAIParsing && !isParsingWithAI
    }

    var body: some View {
        List {
            if let storeName = receipt.inferredStoreName {
                Section("Store") {
                    LabeledContent("Detected store", value: storeName)
                }
            }

            Section {
                if store.enabledBranches.isEmpty {
                    Text("No enabled branches. Add a store in Settings before saving receipt prices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Branch", selection: $selectedBranchID) {
                        Text("Select branch").tag(Optional<UUID>.none)
                        ForEach(store.enabledBranches) { branch in
                            Text(branch.displayName).tag(Optional(branch.id))
                        }
                    }
                }
                LabeledContent("Date", value: receipt.observedDate.formatted(date: .abbreviated, time: .omitted))
                aiParsingControls
            } header: {
                Text("Receipt Info")
            }

            Section {
                ForEach($receipt.lines) { $line in
                    if line.price != nil && line.productName != nil {
                        Toggle(isOn: $line.isIncluded) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.productName ?? line.rawText)
                                    .font(.subheadline)
                                if let price = line.price {
                                    Text("kr \(NSDecimalNumber(decimal: price).stringValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Detected Items (\(includedLines.count) selected)")
            } footer: {
                Text("Toggle off items you don't want to save as price observations.")
            }

            if receipt.lines.filter({ $0.price == nil || $0.productName == nil }).count > 0 {
                Section {
                    ForEach(receipt.lines.filter { $0.price == nil || $0.productName == nil }) { line in
                        Text(line.rawText)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Unrecognised Lines")
                }
            }
        }
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save \(includedLines.count)") {
                    guard let selectedBranchID else { return }
                    onCommit(includedLines, selectedBranchID)
                }
                .disabled(!canCommit)
            }
        }
        .onAppear {
            if selectedBranchID == nil {
                selectedBranchID = inferredBranchID() ?? store.enabledBranches.first?.id
            }
        }
        .confirmationDialog(
            "Send receipt text to AI?",
            isPresented: $showAIConsent,
            titleVisibility: .visible
        ) {
            Button("Send OCR text") {
                parseWithAI()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PrisPilot will send the recognised receipt text, not the image, to Gemini for better item matching.")
        }
    }

    @ViewBuilder
    private var aiParsingControls: some View {
        if store.isUsingLiveAI {
            Button {
                showAIConsent = true
            } label: {
                if isParsingWithAI {
                    Label("Improving with AI…", systemImage: "sparkles")
                } else {
                    Label("Improve matches with AI", systemImage: "sparkles")
                }
            }
            .disabled(!canUseAIParsing)

            if let aiParsingError {
                Text(aiParsingError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if hasUsedAIParsing {
                Text("AI parsing applied for this receipt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func parseWithAI() {
        guard let parser = store.currentAIService as? any ReceiptParsingAIService else {
            aiParsingError = "AI receipt parsing is unavailable with the current provider."
            return
        }

        isParsingWithAI = true
        aiParsingError = nil
        Task {
            do {
                let improvedReceipt = try await parser.parseReceiptLines(rawLines: rawLines, knownProducts: store.products)
                await MainActor.run {
                    receipt = improvedReceipt
                    selectedBranchID = inferredBranchID() ?? selectedBranchID ?? store.enabledBranches.first?.id
                    hasUsedAIParsing = true
                    isParsingWithAI = false
                }
            } catch let error as AIServiceError {
                await MainActor.run {
                    aiParsingError = error.localizedDescription
                    hasUsedAIParsing = true
                    isParsingWithAI = false
                }
            } catch {
                await MainActor.run {
                    aiParsingError = "AI receipt parsing failed. The local OCR result is still available."
                    hasUsedAIParsing = true
                    isParsingWithAI = false
                }
            }
        }
    }

    private func inferredBranchID() -> UUID? {
        guard let storeName = receipt.inferredStoreName?.lowercased() else { return nil }
        return store.enabledBranches.first { branch in
            branch.chainName.lowercased().contains(storeName) ||
            branch.displayName.lowercased().contains(storeName)
        }?.id
    }
}
