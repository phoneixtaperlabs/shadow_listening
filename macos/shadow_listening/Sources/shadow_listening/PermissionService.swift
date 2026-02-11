import Foundation
import AppKit

enum PermissionType {
    case mic
    case sysAudio
    case screenRecording
}

final class PermissionService {
    static let shared = PermissionService()

    private let micProvider = MicPermissionProvider()
    private let sysAudioProvider = SystemAudioPermissionProvider()
    private let screenProvider = ScreenRecordingPermissionProvider()

    private init() {}

    // MARK: - Public API

    func checkStatus(for type: PermissionType) -> Bool {
        switch type {
        case .mic:
            return micProvider.checkStatus()
        case .sysAudio:
            return sysAudioProvider.checkStatus()
        case .screenRecording:
            return screenProvider.checkStatus()
        }
    }

    func requestAccess(for type: PermissionType, completion: @escaping (Bool) -> Void) {
        switch type {
        case .mic:
            micProvider.requestAccess(completion: completion)
        case .sysAudio:
            sysAudioProvider.requestAccess(completion: completion)
        case .screenRecording:
            screenProvider.requestAccess(completion: completion)
        }
    }

    // MARK: - System Settings Helper

    static func openSystemSettings(for type: String) {
        let urlString: String
        switch type {
        case "microphone":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case "screen":
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        default:
            return
        }

        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
