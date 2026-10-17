import PhotosUI
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
    enum Mode: Equatable { case meter, vin, invite, field(FieldScan) }

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
        case .field:
            types.insert(.text(textContentType: nil))
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
            guard mode == .vin || mode == .invite || mode == .field(.vin) else { return }
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
            case let .field(kind):
                guard let value = FieldReader.tapped(raw, for: kind) else { return }
                finished = true
                completion(value)
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

/// One photo from the camera, for the pump display or the dash.
struct CameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}

/// A camera button for a typed field. Point and tap where Live Text runs;
/// elsewhere, choose a photo and Vision reads it.
struct ScanFieldButton: View {
    let kind: FieldScan
    let onScan: (String) -> Void

    @State private var scanning = false
    @State private var item: PhotosPickerItem?
    @State private var lines: [String] = []
    @State private var choosing = false
    @State private var failed = false

    var body: some View {
        Group {
            if LiveTextScanner.isAvailable {
                Button { scanning = true } label: { ScanIcon() }
            } else {
                PhotosPicker(selection: $item, matching: .images) { ScanIcon() }
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Fill in from a photo")
        .sheet(isPresented: $scanning) {
            FieldScanner(kind: kind) { value in
                scanning = false
                Haptics.success()
                onScan(value)
            }
        }
        .sheet(isPresented: $choosing) {
            LineChooser(lines: lines) { value in
                choosing = false
                onScan(value)
            }
        }
        .alert("Nothing to fill in", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't read that photo. Try one closer up, or type it in.")
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            item = nil
            Task { await read(newItem) }
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)?.cgImage else { failed = true; return }
        let found = await PumpReader.recognize(in: image)
        if let value = FieldReader.best(in: found, for: kind) {
            Haptics.success()
            onScan(value)
            return
        }
        let texts = found.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Only free text has nothing to guess; for the rest an empty read is a miss.
        guard kind == .text, !texts.isEmpty else { failed = true; return }
        lines = texts
        choosing = true
    }
}

private struct ScanIcon: View {
    var body: some View {
        Image(systemName: "camera.viewfinder")
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.brass)
            .frame(minWidth: 32, minHeight: 32)
            .contentShape(Rectangle())
    }
}

/// The live camera for one field.
private struct FieldScanner: View {
    let kind: FieldScan
    let completion: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LiveTextScanner(mode: .field(kind), completion: completion)
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    Text(kind.hint)
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

/// Every line Vision found in the photo; tap the ones to use.
private struct LineChooser: View {
    let lines: [String]
    let completion: (String) -> Void
    @State private var picked: Set<Int> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Button {
                            if picked.contains(index) { picked.remove(index) } else { picked.insert(index) }
                        } label: {
                            HStack {
                                Text(line).foregroundStyle(Theme.ink)
                                Spacer()
                                if picked.contains(index) { Image(systemName: "checkmark").foregroundStyle(Theme.brass) }
                            }
                        }
                    }
                } footer: {
                    Text("Pick one line or several, in order.")
                }
            }
            .navigationTitle("Text in the photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { completion(picked.sorted().map { lines[$0] }.joined(separator: " ")) }
                        .disabled(picked.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
