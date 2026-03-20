import Foundation
import GhosttyDyn

enum GhosttyExitReason: String {
    case reportedChildExit = "show_child_exited"
}

enum GhosttyRuntimeEvent {
    case createTile(nextToSessionID: UUID)
    case updateTitle(sessionID: UUID, title: String)
    case updatePWD(sessionID: UUID, pwd: String)
    case openURL(URL)
    case childExited(sessionID: UUID, exitCode: Int, reason: GhosttyExitReason)
    case commandFinished(sessionID: UUID, exitCode: Int)
    case ignore
    case unhandled

    var handled: Bool {
        switch self {
        case .unhandled:
            false
        default:
            true
        }
    }
}

struct GhosttyActionAdapter {
    func decode(action: ghostty_action_s, sessionID: UUID?) -> GhosttyRuntimeEvent {
        switch action.tag {
        case GHOSTTY_ACTION_NEW_WINDOW, GHOSTTY_ACTION_NEW_TAB:
            guard let sessionID else { return .ignore }
            return .createTile(nextToSessionID: sessionID)

        case GHOSTTY_ACTION_NEW_SPLIT:
            guard let sessionID else { return .ignore }
            switch action.action.new_split {
            case GHOSTTY_SPLIT_DIRECTION_RIGHT, GHOSTTY_SPLIT_DIRECTION_LEFT:
                return .createTile(nextToSessionID: sessionID)
            default:
                return .ignore
            }

        case GHOSTTY_ACTION_GOTO_SPLIT:
            return .ignore

        case GHOSTTY_ACTION_RESIZE_SPLIT:
            return .ignore

        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            return .ignore

        case GHOSTTY_ACTION_SET_TITLE:
            guard let sessionID, let title = decodeCString(action.action.set_title.title) else {
                return .ignore
            }
            return .updateTitle(sessionID: sessionID, title: title)

        case GHOSTTY_ACTION_PWD:
            guard let sessionID, let pwd = decodeCString(action.action.pwd.pwd) else {
                return .ignore
            }
            return .updatePWD(sessionID: sessionID, pwd: pwd)

        case GHOSTTY_ACTION_OPEN_URL:
            if let url = decodeOpenURL(action.action.open_url) {
                return .openURL(url)
            }
            return .ignore

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            guard let sessionID else { return .ignore }
            return .childExited(
                sessionID: sessionID,
                exitCode: Int(action.action.child_exited.exit_code),
                reason: .reportedChildExit
            )

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            guard let sessionID else { return .ignore }
            return .commandFinished(sessionID: sessionID, exitCode: Int(action.action.command_finished.exit_code))

        case GHOSTTY_ACTION_CLOSE_WINDOW, GHOSTTY_ACTION_CLOSE_TAB, GHOSTTY_ACTION_CLOSE_ALL_WINDOWS, GHOSTTY_ACTION_QUIT:
            return .ignore

        default:
            return .unhandled
        }
    }

    static func actionName(_ tag: ghostty_action_tag_e) -> String {
        switch tag {
        case GHOSTTY_ACTION_QUIT: "quit"
        case GHOSTTY_ACTION_NEW_WINDOW: "new_window"
        case GHOSTTY_ACTION_NEW_TAB: "new_tab"
        case GHOSTTY_ACTION_CLOSE_TAB: "close_tab"
        case GHOSTTY_ACTION_NEW_SPLIT: "new_split"
        case GHOSTTY_ACTION_CLOSE_ALL_WINDOWS: "close_all_windows"
        case GHOSTTY_ACTION_GOTO_SPLIT: "goto_split"
        case GHOSTTY_ACTION_RESIZE_SPLIT: "resize_split"
        case GHOSTTY_ACTION_EQUALIZE_SPLITS: "equalize_splits"
        case GHOSTTY_ACTION_SET_TITLE: "set_title"
        case GHOSTTY_ACTION_PWD: "pwd"
        case GHOSTTY_ACTION_CLOSE_WINDOW: "close_window"
        case GHOSTTY_ACTION_OPEN_URL: "open_url"
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED: "show_child_exited"
        case GHOSTTY_ACTION_COMMAND_FINISHED: "command_finished"
        default: "tag_\(tag.rawValue)"
        }
    }

    private func decodeOpenURL(_ payload: ghostty_action_open_url_s) -> URL? {
        guard let pointer = payload.url else { return nil }

        let length = Int(payload.len)
        let address = UInt(bitPattern: pointer)
        guard length > 0, length <= 8_192, address > 0x100000000 else {
            return nil
        }

        let data = Data(bytes: pointer, count: length)
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        return URL(string: string)
    }

    private func decodeCString(_ pointer: UnsafePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        return String(validatingCString: pointer)
    }
}
