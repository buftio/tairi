import Foundation

enum GhosttySessionState: Equatable {
    case running
    case exited(exitCode: Int)
}
