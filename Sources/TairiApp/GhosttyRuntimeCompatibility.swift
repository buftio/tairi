import Foundation
import GhosttyDyn

struct GhosttyRuntimeMetadata {
    let version: String
    let buildMode: ghostty_build_mode_e
}

enum GhosttyRuntimeCompatibilityError: Error {
    case message(String)

    var message: String {
        switch self {
        case .message(let value):
            value
        }
    }
}

enum GhosttyRuntimeCompatibility {
    private static let supportedHeaderVersions: Set<String> = ["1.3.1"]

    static func validateLoadedRuntime() -> Result<GhosttyRuntimeMetadata, GhosttyRuntimeCompatibilityError> {
        let info = tairi_ghostty_info()
        let version = decodeString(pointer: info.version, length: info.version_len) ?? "unknown"
        let metadata = GhosttyRuntimeMetadata(version: version, buildMode: info.build_mode)

        guard version != "unknown" else {
            return .failure(.message("Ghostty runtime compatibility check failed: runtime did not report a version"))
        }

        switch validate(version: version, vendoredVersion: currentVendoredVersion()) {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }

        return .success(metadata)
    }

    static func validate(version: String, vendoredVersion: String?) -> Result<Void, GhosttyRuntimeCompatibilityError> {
        if let vendoredVersion {
            guard vendoredVersion == version else {
                return .failure(
                    .message(
                        "Ghostty runtime version \(version) does not match vendored headers \(vendoredVersion). "
                            + "Header signature: \(headerSignature)"
                    ))
            }
            return .success(())
        }

        guard supportedHeaderVersions.contains(version) else {
            return .failure(
                .message(
                    "Unsupported Ghostty runtime version \(version). Supported header versions: \(supportedHeaderVersions.sorted().joined(separator: ", ")). "
                        + "Header signature: \(headerSignature)"
                ))
        }

        return .success(())
    }

    static var headerSignature: String {
        [
            "open_url=\(GHOSTTY_ACTION_OPEN_URL.rawValue)",
            "show_child_exited=\(GHOSTTY_ACTION_SHOW_CHILD_EXITED.rawValue)",
            "command_finished=\(GHOSTTY_ACTION_COMMAND_FINISHED.rawValue)",
        ].joined(separator: ", ")
    }

    private static func currentVendoredVersion() -> String? {
        TairiPaths.requiredGhosttyVendorVersion()
    }

    private static func decodeString(pointer: UnsafePointer<CChar>?, length: UInt) -> String? {
        guard let pointer else { return nil }
        let count = Int(length)
        guard count > 0, count <= 128 else { return nil }
        let data = Data(bytes: pointer, count: count)
        return String(data: data, encoding: .utf8)
    }
}
