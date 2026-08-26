import UIKit

extension UIImage {
    /// Уменьшает картинку до maxDimension по большей стороне и сжимает в JPEG,
    /// чтобы не раздувать базу данных.
    func downscaledJPEG(maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let largestSide = max(size.width, size.height)
        let scale = min(1, maxDimension / largestSide)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
