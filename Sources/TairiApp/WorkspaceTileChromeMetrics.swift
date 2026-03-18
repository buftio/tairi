import AppKit

enum WorkspaceTileChromeMetrics {
    static let cornerRadius: CGFloat = 10
    static let compactCornerRadius: CGFloat = 5
    static let compactCornerRadiusThreshold: CGFloat = 260

    // Glass background
    static let backgroundMaterial: NSVisualEffectView.Material = .underWindowBackground

    // Border
    static let activeBorderWidth: CGFloat = 3.5
    static let inactiveBorderWidth: CGFloat = 1

    static func cornerRadius(for size: CGSize) -> CGFloat {
        let compactDimension = min(size.width, size.height)
        return compactDimension < compactCornerRadiusThreshold
            ? compactCornerRadius
            : cornerRadius
    }

    static func clampedCornerRadius(for size: CGSize) -> CGFloat {
        min(cornerRadius(for: size), min(size.width, size.height) / 2)
    }
}
