import UIKit

/// The Service Record: one vehicle's whole history as a printable PDF, for a
/// buyer, a shop, an insurer or the glovebox. Letter size, black on white so
/// it prints well on any office printer.
///
/// Amazon links never appear here; Associates rules bar affiliate links from
/// anything offline, and a record for a buyer has no business selling.
struct ServiceRecord {
    struct Row {
        var date: Date?
        var reading: Double?
        var title: String
        var detail: String
        var shop: String
        var cost: Double
        var receipts: [UIImage]
    }

    struct ScheduleRow {
        var name: String
        var interval: String
        var last: String
        var next: String
        var status: DueStatus
    }

    var vehicleName: String
    var descriptor: String
    var kind: VehicleKind
    var identifiers: [(label: String, value: String)]
    var meter: MeterUnit
    var reading: Double
    var photo: UIImage?
    var schedule: [ScheduleRow]
    var rows: [Row]
    var showCosts: Bool
    var includeReceipts: Bool
    var preparedBy: String?
    var generated: Date = .now

    var totalCost: Double { rows.reduce(0) { $0 + $1.cost } }

    var firstDate: Date? { rows.compactMap(\.date).min() }
}

enum ServiceRecordPDF {
    static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 48
    private static var contentWidth: CGFloat { pageSize.width - margin * 2 }

    private enum Font {
        static let title = UIFont(descriptor: UIFont.systemFont(ofSize: 24, weight: .semibold).fontDescriptor.withDesign(.serif)!, size: 24)
        static let subtitle = UIFont.systemFont(ofSize: 11, weight: .regular)
        static let label = UIFont.systemFont(ofSize: 7.5, weight: .semibold)
        static let value = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        static let stat = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        static let section = UIFont(descriptor: UIFont.systemFont(ofSize: 13, weight: .semibold).fontDescriptor.withDesign(.serif)!, size: 13)
        static let header = UIFont.systemFont(ofSize: 7.5, weight: .semibold)
        static let cell = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        static let cellStrong = UIFont.systemFont(ofSize: 9, weight: .semibold)
        static let note = UIFont.systemFont(ofSize: 8, weight: .regular)
    }

    private enum Ink {
        static let primary = UIColor(white: 0.1, alpha: 1)
        static let secondary = UIColor(white: 0.4, alpha: 1)
        static let rule = UIColor(white: 0.84, alpha: 1)
        static let band = UIColor(white: 0.965, alpha: 1)
        static let brass = UIColor(red: 0.66, green: 0.47, blue: 0.12, alpha: 1)
        static let overdue = UIColor(red: 0.72, green: 0.22, blue: 0.1, alpha: 1)
    }

    static func render(_ record: ServiceRecord) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(record.vehicleName) service record",
            kCGPDFContextCreator as String: "Vehicle Maintenance Log",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            var page = 0
            func newPage() -> CGFloat {
                context.beginPage()
                page += 1
                drawFooter(record, page: page)
                return margin
            }
            var y = newPage()
            y = drawHeader(record, at: y)
            y = drawStats(record, at: y + 16)

            if !record.schedule.isEmpty {
                y = section("Maintenance schedule", at: y + 22)
                let columns = scheduleColumns
                y = drawColumnHeaders(columns, at: y)
                for row in record.schedule {
                    let cells = [row.name, row.interval, row.last, row.next]
                    let height = rowHeight(cells, columns)
                    if y + height > pageSize.height - margin - 24 {
                        y = newPage()
                        y = drawColumnHeaders(columns, at: y)
                    }
                    drawRow(cells, columns, at: y, strongFirst: true, emphasis: row.status == .overdue ? 3 : nil)
                    y += height
                }
            }

            y = section("Service history", at: y + 22)
            if record.rows.isEmpty {
                y = drawText("No service logged yet.", font: Font.cell, color: Ink.secondary, at: CGPoint(x: margin, y: y), width: contentWidth)
            } else {
                let columns = historyColumns(showCosts: record.showCosts, meter: record.meter)
                y = drawColumnHeaders(columns, at: y)
                for (index, row) in record.rows.enumerated() {
                    var cells = [
                        row.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "",
                        row.reading.map { Format.reading($0, record.meter) } ?? "",
                        row.detail.isEmpty ? row.title : "\(row.title)\n\(row.detail)",
                        row.shop,
                    ]
                    if record.showCosts { cells.append(row.cost > 0 ? Format.money(row.cost) : "") }
                    let height = rowHeight(cells, columns)
                    if y + height > pageSize.height - margin - 24 {
                        y = newPage()
                        y = drawColumnHeaders(columns, at: y)
                    }
                    if index.isMultiple(of: 2) {
                        Ink.band.setFill()
                        UIRectFill(CGRect(x: margin, y: y - 2, width: contentWidth, height: height))
                    }
                    drawRow(cells, columns, at: y, strongFirst: false, emphasis: nil)
                    y += height
                }
            }

            if record.includeReceipts {
                let receipts = record.rows.flatMap { row in row.receipts.map { (row, $0) } }
                if !receipts.isEmpty {
                    y = newPage()
                    y = section("Receipts", at: y)
                    let columnsCount: CGFloat = 2
                    let gap: CGFloat = 16
                    let width = (contentWidth - gap) / columnsCount
                    var column: CGFloat = 0
                    var rowHeight: CGFloat = 0
                    for (row, image) in receipts {
                        let aspect = image.size.height / max(image.size.width, 1)
                        let height = min(width * aspect, 300)
                        if column == 0, y + height + 30 > pageSize.height - margin - 24 {
                            y = newPage()
                        }
                        let x = margin + column * (width + gap)
                        let fitted = CGRect(x: x, y: y, width: height / max(aspect, 0.01), height: height)
                        image.draw(in: fitted)
                        Ink.rule.setStroke()
                        UIBezierPath(rect: fitted).stroke()
                        let caption = [row.date?.formatted(date: .abbreviated, time: .omitted), row.title].compactMap { $0 }.joined(separator: " · ")
                        _ = drawText(caption, font: Font.note, color: Ink.secondary, at: CGPoint(x: x, y: y + height + 4), width: width)
                        rowHeight = max(rowHeight, height + 24)
                        column += 1
                        if column >= columnsCount {
                            column = 0
                            y += rowHeight
                            rowHeight = 0
                        }
                    }
                }
            }
        }
    }

    static func url(for record: ServiceRecord) throws -> URL {
        let safe = record.vehicleName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "Vehicle" : safe)-Service-Record.pdf")
        try render(record).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Pieces

    private static func drawHeader(_ record: ServiceRecord, at top: CGFloat) -> CGFloat {
        var y = top
        let photoSize = CGSize(width: 132, height: 92)
        let textWidth = record.photo == nil ? contentWidth : contentWidth - photoSize.width - 16
        _ = drawText("SERVICE RECORD", font: Font.label, color: Ink.brass, at: CGPoint(x: margin, y: y), width: textWidth, kern: 1.2)
        y += 14
        y = drawText(record.vehicleName, font: Font.title, color: Ink.primary, at: CGPoint(x: margin, y: y), width: textWidth)
        if !record.descriptor.isEmpty, record.descriptor != record.vehicleName {
            y = drawText(record.descriptor, font: Font.subtitle, color: Ink.secondary, at: CGPoint(x: margin, y: y + 2), width: textWidth)
        }
        y += 10
        var x = margin
        for (label, value) in record.identifiers where !value.isEmpty {
            let width = max(70, min(200, (value as NSString).size(withAttributes: [.font: Font.value]).width + 8))
            if x + width > margin + textWidth { x = margin; y += 28 }
            _ = drawText(label.uppercased(), font: Font.label, color: Ink.secondary, at: CGPoint(x: x, y: y), width: width, kern: 0.6)
            _ = drawText(value, font: Font.value, color: Ink.primary, at: CGPoint(x: x, y: y + 10), width: width)
            x += width + 18
        }
        y += 28
        if let photo = record.photo {
            let frame = CGRect(x: pageSize.width - margin - photoSize.width, y: top, width: photoSize.width, height: photoSize.height)
            UIBezierPath(roundedRect: frame, cornerRadius: 8).addClip()
            let aspect = photo.size.width / max(photo.size.height, 1)
            var drawRect = frame
            if aspect > frame.width / frame.height {
                drawRect.size.width = frame.height * aspect
                drawRect.origin.x -= (drawRect.width - frame.width) / 2
            } else {
                drawRect.size.height = frame.width / aspect
                drawRect.origin.y -= (drawRect.height - frame.height) / 2
            }
            photo.draw(in: drawRect)
            UIGraphicsGetCurrentContext()?.resetClip()
            y = max(y, frame.maxY + 8)
        }
        Ink.rule.setFill()
        UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: 0.5))
        return y
    }

    private static func drawStats(_ record: ServiceRecord, at top: CGFloat) -> CGFloat {
        var stats: [(String, String)] = []
        if record.meter.hasReading { stats.append((record.meter.meterName, Format.reading(record.reading, record.meter))) }
        stats.append(("Services logged", "\(record.rows.count)"))
        if let first = record.firstDate { stats.append(("Records since", first.formatted(.dateTime.month(.abbreviated).year()))) }
        if record.showCosts { stats.append(("Total spent", Format.money(record.totalCost))) }
        let width = contentWidth / CGFloat(max(stats.count, 1))
        for (index, stat) in stats.enumerated() {
            let x = margin + CGFloat(index) * width
            _ = drawText(stat.1, font: Font.stat, color: Ink.primary, at: CGPoint(x: x, y: top), width: width - 8)
            _ = drawText(stat.0.uppercased(), font: Font.label, color: Ink.secondary, at: CGPoint(x: x, y: top + 22), width: width - 8, kern: 0.6)
        }
        return top + 36
    }

    private static func section(_ title: String, at y: CGFloat) -> CGFloat {
        drawText(title, font: Font.section, color: Ink.primary, at: CGPoint(x: margin, y: y), width: contentWidth) + 6
    }

    private struct Column {
        let title: String
        let fraction: CGFloat
        var alignRight = false
    }

    private static let scheduleColumns = [
        Column(title: "JOB", fraction: 0.34),
        Column(title: "EVERY", fraction: 0.22),
        Column(title: "LAST DONE", fraction: 0.22),
        Column(title: "NEXT", fraction: 0.22),
    ]

    private static func historyColumns(showCosts: Bool, meter: MeterUnit) -> [Column] {
        var columns = [
            Column(title: "DATE", fraction: 0.14),
            Column(title: meter.hasReading ? meter.meterName.uppercased() : "", fraction: 0.13),
            Column(title: "WORK", fraction: showCosts ? 0.43 : 0.53),
            Column(title: "BY", fraction: 0.20),
        ]
        if showCosts { columns.append(Column(title: "COST", fraction: 0.10, alignRight: true)) }
        return columns
    }

    private static func drawColumnHeaders(_ columns: [Column], at y: CGFloat) -> CGFloat {
        var x = margin
        for column in columns {
            let width = contentWidth * column.fraction
            _ = drawText(column.title, font: Font.header, color: Ink.secondary, at: CGPoint(x: x, y: y), width: width - 6, alignRight: column.alignRight, kern: 0.6)
            x += width
        }
        Ink.rule.setFill()
        UIRectFill(CGRect(x: margin, y: y + 12, width: contentWidth, height: 0.5))
        return y + 17
    }

    private static func rowHeight(_ cells: [String], _ columns: [Column]) -> CGFloat {
        zip(cells, columns).map { cell, column in
            measure(cell, font: Font.cell, width: contentWidth * column.fraction - 6)
        }.max().map { $0 + 8 } ?? 16
    }

    private static func drawRow(_ cells: [String], _ columns: [Column], at y: CGFloat, strongFirst: Bool, emphasis: Int?) {
        var x = margin
        for (index, (cell, column)) in zip(cells, columns).enumerated() {
            let width = contentWidth * column.fraction
            let font = (strongFirst && index == 0) ? Font.cellStrong : Font.cell
            let color = emphasis == index ? Ink.overdue : Ink.primary
            _ = drawText(cell, font: font, color: color, at: CGPoint(x: x, y: y + 2), width: width - 6, alignRight: column.alignRight)
            x += width
        }
    }

    private static func drawFooter(_ record: ServiceRecord, page: Int) {
        var left = "Prepared \(record.generated.formatted(date: .long, time: .omitted))"
        if let by = record.preparedBy { left += " by \(by)" }
        left += " with Vehicle Maintenance Log. Entries are kept by the owner."
        let y = pageSize.height - margin + 14
        _ = drawText(left, font: Font.note, color: Ink.secondary, at: CGPoint(x: margin, y: y), width: contentWidth - 60)
        _ = drawText("Page \(page)", font: Font.note, color: Ink.secondary, at: CGPoint(x: margin, y: y), width: contentWidth, alignRight: true)
    }

    // MARK: - Text

    private static func attributes(_ font: UIFont, _ color: UIColor, alignRight: Bool, kern: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignRight ? .right : .left
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern]
    }

    private static func measure(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return font.lineHeight }
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(font, .black, alignRight: false, kern: 0),
            context: nil
        ).height)
    }

    @discardableResult
    private static func drawText(_ text: String, font: UIFont, color: UIColor, at point: CGPoint, width: CGFloat, alignRight: Bool = false, kern: CGFloat = 0) -> CGFloat {
        let height = measure(text, font: font, width: width)
        (text as NSString).draw(
            with: CGRect(x: point.x, y: point.y, width: width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(font, color, alignRight: alignRight, kern: kern),
            context: nil
        )
        return point.y + height
    }
}
