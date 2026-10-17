import SwiftUI
import Vision
import VisionKit

/// The document camera, for receipts: edge detection, perspective
/// correction, several pages.
struct ReceiptScanner: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: ([UIImage]) -> Void
        init(completion: @escaping ([UIImage]) -> Void) { self.completion = completion }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completion((0..<scan.pageCount).map(scan.imageOfPage(at:)))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            completion([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            completion([])
        }
    }
}

/// Live text scanning: point at the odometer or the VIN plate and tap the
/// number when it's highlighted.
struct LiveTextScanner: UIViewControllerRepresentable {
    enum Mode { case meter, vin, invite }

    let mode: Mode
    let completion: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        var types: Set<DataScannerViewController.RecognizedDataType> = []
        switch mode {
        case .meter: types.insert(.text(textContentType: nil))
        case .vin:
            types.insert(.text(textContentType: nil))
            types.insert(.barcode(symbologies: [.code39, .dataMatrix, .qr, .code128]))
        case .invite:
            types.insert(.barcode(symbologies: [.qr]))
        }
        let controller = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(mode: mode, completion: completion) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let mode: Mode
        let completion: (String) -> Void
        private var finished = false

        init(mode: Mode, completion: @escaping (String) -> Void) {
            self.mode = mode
            self.completion = completion
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            accept(item, requireMatch: false)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            // A VIN or an invite code is unambiguous, so take it on sight.
            guard mode != .meter else { return }
            for item in addedItems { accept(item, requireMatch: true) }
        }

        private func accept(_ item: RecognizedItem, requireMatch: Bool) {
            guard !finished else { return }
            let raw: String
            switch item {
            case let .text(text): raw = text.transcript
            case let .barcode(code): raw = code.payloadStringValue ?? ""
            @unknown default: return
            }
            switch mode {
            case .invite:
                guard ShareInvite.url(in: raw) != nil else { return }
                finished = true
                completion(raw)
            case .vin:
                let candidates = raw.uppercased().components(separatedBy: .whitespacesAndNewlines) + [raw]
                guard let vin = candidates.compactMap(NHTSAClient.normalizedVIN).first else { return }
                finished = true
                completion(vin)
            case .meter:
                let digits = raw.filter(\.isNumber)
                guard digits.count >= 2 || !requireMatch else { return }
                guard !digits.isEmpty else { return }
                finished = true
                completion(digits)
            }
        }
    }
}

/// Reads the odometer or hour meter off the dash.
struct MeterScanner: View {
    let completion: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { LiveTextScanner.isAvailable }

    var body: some View {
        NavigationStack {
            LiveTextScanner(mode: .meter) { text in
                if let value = Double(text) { completion(value) } else { dismiss() }
            }
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text("Tap the number on the dash")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Theme.md).padding(.vertical, Theme.sm)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, Theme.xl)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Reads the VIN off the windshield plate, the door sticker or its barcode.
struct VINScanner: View {
    let completion: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LiveTextScanner(mode: .vin, completion: completion)
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    Text("Point at the VIN on the windshield or door jamb")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.md).padding(.vertical, Theme.sm)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, Theme.xl)
                        .padding(.horizontal, Theme.margin)
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
