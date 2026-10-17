import PDFKit
import SwiftUI

/// The Service Record, previewed before it's printed or sent.
struct ServiceRecordView: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    @State private var showCosts = !AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts)
    @State private var includeReceipts = true
    @State private var pdf: Data?
    @State private var file: SharedFile?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let pdf {
                    PDFPreview(data: pdf)
                        .background(Theme.raised)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack(spacing: Theme.sm) {
                    Toggle("Show costs", isOn: $showCosts)
                    Toggle("Attach receipts", isOn: $includeReceipts)
                    HStack(spacing: Theme.sm) {
                        Button {
                            print()
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Button {
                            share()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .font(.subheadline)
                .padding(Theme.margin)
                .background(Theme.surface)
            }
            .navigationTitle("Service Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task(id: "\(showCosts)\(includeReceipts)") { render() }
            .sheet(item: $file) { file in ShareSheet(items: [file.url]) }
        }
    }

    private func render() {
        let record = RecordBuilder.record(for: vehicle, store: garage, showCosts: showCosts, includeReceipts: includeReceipts)
        pdf = ServiceRecordPDF.render(record)
    }

    private func share() {
        let record = RecordBuilder.record(for: vehicle, store: garage, showCosts: showCosts, includeReceipts: includeReceipts)
        if let url = try? ServiceRecordPDF.url(for: record) { file = SharedFile(url: url) }
    }

    private func print() {
        guard let pdf else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "\(vehicle.displayName) service record"
        controller.printInfo = info
        controller.printingItem = pdf
        controller.present(animated: true)
    }
}

struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(data: data)
    }
}
