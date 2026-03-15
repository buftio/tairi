import AppKit

enum WorkspaceTileChromeMetrics {
    static let cornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 8
    static let compactCornerRadiusThreshold: CGFloat = 260

    // Glass background
    static let backgroundMaterial: NSVisualEffectView.Material = .underWindowBackground

    // Border
    static let activeBorderWidth: CGFloat = 5
    static let inactiveBorderWidth: CGFloat = 1
    static let activeBorderColor = NSColor(
        calibratedRed: 0.54,
        green: 0.86,
        blue: 0.62,
        alpha: 0.96
    )
    static let inactiveBorderColor = NSColor(calibratedWhite: 1, alpha: 0.18)

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
