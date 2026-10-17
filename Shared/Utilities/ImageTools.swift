import UIKit

/// Photos go to iCloud with every family member's copy, so they are sized
/// for a phone screen and a printout, not for a billboard.
enum ImageTools {
    static func jpeg(_ data: Data, maxDimension: CGFloat = 2000, quality: CGFloat = 0.75) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(image, maxDimension: maxDimension, quality: quality)
    }

    static func jpeg(_ image: UIImage, maxDimension: CGFloat = 2000, quality: CGFloat = 0.75) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// A small square-ish thumbnail for lists and the PDF.
    static func thumbnail(_ data: Data?, maxDimension: CGFloat = 600) -> UIImage? {
        guard let data, let image = UIImage(data: data) else { return nil }
        guard let jpeg = jpeg(image, maxDimension: maxDimension, quality: 0.8) else { return image }
        return UIImage(data: jpeg)
    }
}
