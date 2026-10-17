import PDFKit
import SwiftUI

/// The Service Record, previewed before it's printed or sent.
struct ServiceRecordView: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    @State private var showCosts = !AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts)
    @State private var includeReceipts = true
    @State private var includeSchedule = true
    @State private var includeNotes = true
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
                // Side by side until large text would split the words, then stacked.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.sm) { recordButtons }
                    VStack(spacing: Theme.sm) { recordButtons }
                }
                .font(.subheadline)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(Theme.margin)
                .background(Theme.surface)
            }
            .navigationTitle("Service Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Costs", isOn: $showCosts)
                        Toggle("Receipts", isOn: $includeReceipts)
                        Toggle("Notes", isOn: $includeNotes)
                        Toggle("What's due next", isOn: $includeSchedule)
                    } label: {
                        Label("Include", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("record.include")
                }
            }
            .task(id: "\(showCosts)\(includeReceipts)\(includeSchedule)\(includeNotes)") { render() }
            .sheet(item: $file) { file in ShareSheet(items: [file.url]) }
        }
    }

    private func render() {
        let record = RecordBuilder.record(for: vehicle, store: garage, showCosts: showCosts, includeReceipts: includeReceipts, includeSchedule: includeSchedule, includeNotes: includeNotes)
        pdf = ServiceRecordPDF.render(record)
    }

    private func share() {
        let record = RecordBuilder.record(for: vehicle, store: garage, showCosts: showCosts, includeReceipts: includeReceipts, includeSchedule: includeSchedule, includeNotes: includeNotes)
        if let url = try? ServiceRecordPDF.url(for: record) { file = SharedFile(url: url) }
    }

    @ViewBuilder private var recordButtons: some View {
        Button {
            print()
        } label: {
            Label("Print", systemImage: "printer").lineLimit(1)
        }
        .buttonStyle(SecondaryButtonStyle())
        Button {
            share()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up").lineLimit(1)
        }
        .buttonStyle(PrimaryButtonStyle())
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
