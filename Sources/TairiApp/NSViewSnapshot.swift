import AppKit

extension NSView {
    func tairiSnapshotImage() -> NSImage? {
        guard bounds.width > 0.5,
            bounds.height > 0.5,
            let bitmap = bitmapImageRepForCachingDisplay(in: bounds)
        else {
            return nil
        }

        cacheDisplay(in: bounds, to: bitmap)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}
