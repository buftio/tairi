import AppKit
import GhosttyDyn

enum TerminalPasteboard {
    static func pasteboard(for location: ghostty_clipboard_e) -> NSPasteboard? {
        switch location {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return .general
        case GHOSTTY_CLIPBOARD_SELECTION:
            return NSPasteboard(name: .init("com.mitchellh.ghostty.selection"))
        default:
            return nil
        }
    }

    static func preferredPasteString(from pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
            !urls.isEmpty
        {
            return
                urls
                .map { $0.isFileURL ? shellEscape($0.path) : $0.absoluteString }
                .joined(separator: " ")
        }

        if let string = pasteboard.string(forType: .string) {
            return string
        }

        if let imagePath = materializeImage(from: pasteboard) {
            return shellEscape(imagePath)
        }

        return nil
    }

    private static func shellEscape(_ string: String) -> String {
        let charactersToEscape = "\\ ()[]{}<>\"'`!#$&;|*?\t"
        var escaped = string

        for character in charactersToEscape {
            let needle = String(character)
            escaped = escaped.replacingOccurrences(of: needle, with: "\\\(needle)")
        }

        return escaped
    }

    private static func materializeImage(from pasteboard: NSPasteboard) -> String? {
        guard
            let image = NSImage(pasteboard: pasteboard),
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tairi-clipboard-images", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("paste-\(UUID().uuidString).png")
            try pngData.write(to: url, options: .atomic)
            return url.path(percentEncoded: false)
        } catch {
            TairiLog.write("clipboard image materialization failed error=\(error.localizedDescription)")
            return nil
        }
    }
}
